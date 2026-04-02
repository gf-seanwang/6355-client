extends Node
class_name MainGameController

## Orchestrates the main game flow: spin -> cascade -> wild effects -> scatter -> result

signal round_complete(total_win: float)
signal free_game_trigger(fgis: Dictionary)

@export var grid: GridController
@export var hud: Control  # HUD node
@export var win_presenter: Control

var free_game_intro_handler: Callable  # set by main_scene for staged intro

var _processing_results: bool = false
var _current_round_win: float = 0.0
var _current_response: Dictionary = {}
var _prev_screen: Array = []  # previous screen data for hold detection in Free Game
var _score_label: RichTextLabel = null  # score formula display on left side
var _fg_collect_total: int = 0  # Free Game: accumulated collect multiplier total


func _ready() -> void:
	NetworkManager.spin_response_received.connect(_on_spin_response)


func request_spin(arena_code: String = GameManager.ARENA_NORMAL) -> void:
	if _processing_results:
		return
	# Clear separation in output panel
	for _i in range(50):
		print("")
	print("================== NEW SPIN ==================")
	GameManager.request_spin(arena_code)


func _on_spin_response(response: Dictionary) -> void:
	_current_response = response
	var round_results: Array = response.get("round_result_list", [])
	if round_results.size() == 0:
		GameManager.current_state = GameManager.GameState.IDLE
		return
	# Print header — individual screens are printed step-by-step in _process_round_results
	var bet: float = response.get("bet_amount", 0.0)
	var pay: float = response.get("pay_amount", 0.0)
	var bal: float = response.get("balance", 0.0)
	print("")
	print("╔══════════════════════════════════════════════════════╗")
	print("║  SPIN RESULT  bet=%.2f  pay=%.2f  bal=%.2f" % [bet, pay, bal])
	print("╚══════════════════════════════════════════════════════╝")
	await _process_round_results(round_results)
	_display_score_formula(round_results)
	print("────────────────────────────────────────────────────────")
	print("")
	# Handle back_to_main_game: restore main game screen after free game ends
	var btmg: Variant = response.get("back_to_main_game", null)
	if btmg != null and btmg is Dictionary:
		# Reset grid to default 6 rows and clear corner labels
		grid.set_rows(GridController.ROWS)
		var main_screen: Array = btmg.get("screen", [])
		if main_screen.size() > 0:
			grid.set_screen(main_screen)
		grid.clear_multipliers()
		_prev_screen = []
		# Clear corner feature labels
		for col in range(GridController.COLS):
			for row in [0, grid.current_rows - 1]:
				if grid._is_wild_corner(col, row):
					grid.cells[col][row].hide_corner_feature_label()
		if GameManager.is_in_free_game:
			# end_free_game may already be called by _process_round_results,
			# but guard with is_in_free_game check
			GameManager.end_free_game()


func _process_round_results(results: Array) -> void:
	_processing_results = true
	_current_round_win = 0.0

	var free_game_started := false
	var prev_sticky_pos: Array = []  # previous stage's sticky positions (from bt==3 or Wild)

	for i in range(results.size()):
		var screen_info: Dictionary = results[i]
		var stage: int = screen_info.get("stg", 1)

		# Debug: print this screen's info right before its animation
		_debug_print_screen_info(i, results.size(), screen_info)

		# Set screen — use scnb (before wild effects) if available, so wild animation can show the transition
		var screen: Array = screen_info.get("screen", [])
		var wild_effects: Array = screen_info.get("we", [])
		var scnb: Array = screen_info.get("scnb", [])
		# Extract sticky positions from screen (bt==3 or Wild)
		var sticky_pos_list: Array = _extract_sticky_from_screen(screen)
		var display_screen: Array = scnb if scnb.size() > 0 and (wild_effects.size() > 0 or GameManager.is_in_free_game) else screen
		if display_screen.size() > 0:
			if stage > 1:
				# Cascade: use PREVIOUS stage's sticky (not current — current includes new matches)
				await grid.animate_drop(prev_sticky_pos, display_screen)
			else:
				if GameManager.is_in_free_game:
					# 轉動開始 → 剩餘次數立刻 -1
					var fg_before: Variant = screen_info.get("fg", null)
					if fg_before != null and fg_before is Dictionary:
						var lrb: int = fg_before.get("lrb", 0)
						if hud and hud.has_method("update_free_game_info"):
							hud.update_free_game_info(lrb - 1, false)
					await grid.animate_spin_cells(display_screen, _prev_screen)
				else:
					await grid.animate_spin(display_screen)

		# Track this stage's sticky positions for the NEXT stage's animation
		prev_sticky_pos = sticky_pos_list

		var elims: Array = screen_info.get("elims", [])

		# 停轉後停頓，讓玩家看清原本的圖標
		if stage == 1 and (elims.size() > 0 or wild_effects.size() > 0):
			await get_tree().create_timer(0.8).timeout

		# 後端送 oelims = 原始叢集（Wild 效果前），elims = 最終叢集（Wild 效果後）
		var oelims: Array = screen_info.get("oelims", [])
		var initial_elims: Array = oelims if oelims.size() > 0 else elims

		# 1. 原始叢集亮起
		if initial_elims.size() > 0:
			GameManager.current_state = GameManager.GameState.CASCADING
			if stage > 1:
				await get_tree().create_timer(0.5).timeout
			grid.highlight_clusters(initial_elims)
			await get_tree().create_timer(0.5).timeout

		# 2. Wild 效果
		if wild_effects.size() > 0:
			GameManager.current_state = GameManager.GameState.WILD_EFFECTS
			await grid.animate_wild_effects(wild_effects, scnb)
			if screen.size() > 0:
				grid.set_screen(screen)
			# Wild 效果後，highlight 完整叢集（包含 extend/upgrade 擴展的位置）
			if elims.size() > 0 and oelims.size() > 0:
				grid.highlight_clusters(elims)
				await get_tree().create_timer(0.5).timeout

		# 3. 消除動畫
		if elims.size() > 0:
			await grid.animate_elimination(elims)
			var ws: float = screen_info.get("ws", 0.0)
			_current_round_win += ws

		# Corner features animation (Free Game)
		var fg_info: Variant = screen_info.get("fg", null)
		var corner_features: Array = fg_info.get("corner_features", []) if fg_info is Dictionary else []
		if corner_features.size() > 0:
			var pre_corner_screen: Array = scnb if scnb.size() > 0 else _prev_screen
			await grid.animate_corner_features(corner_features, pre_corner_screen)

		# Update rows from rsct
		var rsct: Array = screen_info.get("rsct", [])
		if rsct.size() > 0:
			var cr: int = rsct[0] as int
			if cr >= 6 and cr <= 8:
				grid.set_rows(cr)

		# Check for respin (sticky symbols present = respin)
		if sticky_pos_list.size() > 0 and stage == 1:
			GameManager.current_state = GameManager.GameState.RESPIN
			grid.highlight_sticky(sticky_pos_list)
			await get_tree().create_timer(1.0).timeout
			grid.reset_highlights()

		# Track screen for next step's hold detection
		if screen.size() > 0:
			_prev_screen = screen

		# Check for free game initial state
		var fgis: Variant = screen_info.get("fgis", null)
		if fgis != null and fgis is Dictionary:
			free_game_started = true
			_fg_collect_total = 0
			# 顯示初始盤面倍數 (from fgis.multipliers)
			var init_mpi: Array = fgis.get("multipliers", [])
			var init_board_sum: int = 0
			for m in init_mpi:
				init_board_sum += m.get("value", 0)
			if hud and hud.has_method("update_free_game_multipliers"):
				hud.update_free_game_multipliers(init_board_sum, 0)
			GameManager.current_state = GameManager.GameState.FREE_GAME_INTRO
			grid.highlight_scatters()
			await get_tree().create_timer(1.5).timeout
			grid.reset_highlights()
			# Peek next result's screen for corner Wild bt (feature types)
			var fg_init_screen: Array = []
			if i + 1 < results.size():
				fg_init_screen = results[i + 1].get("screen", [])
			# Staged intro: popup → empty grid → animate multipliers
			free_game_trigger.emit(fgis)
			if free_game_intro_handler.is_valid():
				await free_game_intro_handler.call(fgis, fg_init_screen)
			# Build synthetic _prev_screen so first FG spin holds initial MTP
			var init_rows_fg: int = fgis.get("initial_rows", GameManager.SCREEN_ROWS)
			var synth_screen: Array = []
			synth_screen.resize(GridController.COLS * init_rows_fg)
			for si_idx in range(synth_screen.size()):
				synth_screen[si_idx] = {"sid": 0, "mtp": 0}
			for m in init_mpi:
				var mpos: int = m.get("pos", -1)
				if mpos >= 0 and mpos < synth_screen.size():
					synth_screen[mpos] = {"sid": GameManager.MTP_ID, "mtp": m.get("value", 1)}
			_prev_screen = synth_screen

		# Free Game: accumulate collect from corner features
		if GameManager.is_in_free_game:
			for cf in corner_features:
				if cf.get("feature_type", 0) == 21:  # FG_COLLECT
					_fg_collect_total += cf.get("value", 0)
			# Compute board sum from screen symbols
			var board_sum: int = _sum_mtp_from_screen(screen)
			if hud and hud.has_method("update_free_game_multipliers"):
				hud.update_free_game_multipliers(board_sum, _fg_collect_total)

		# Free game round info
		var fg: Variant = screen_info.get("fg", null)
		if fg != null and fg is Dictionary:
			GameManager.free_game_left_rounds = fg.get("lr", 0)
			GameManager.free_game_total_win = fg.get("tws", 0.0)
			var add_round: int = fg.get("ar", 0)
			if add_round > 0:
				GameManager.free_game_total_rounds += add_round
				print("[FreeGame] Spins reset! +%d rounds, now %d left" % [add_round, GameManager.free_game_left_rounds])
				if hud and hud.has_method("update_free_game_info"):
					hud.update_free_game_info(GameManager.free_game_left_rounds, true)

		# Update balance
		var bala: Variant = screen_info.get("bala", null)
		if bala != null:
			GameManager.balance = float(bala)

		# End of stage
		if screen_info.get("eostg", false):
			grid.reset_highlights()

		# Delay between stages — Free Game respin needs longer pause
		if GameManager.is_in_free_game:
			await get_tree().create_timer(0.5).timeout
		else:
			await get_tree().create_timer(0.2).timeout

	_processing_results = false

	# Check for big win
	if _current_round_win > 0:
		var bet := GameManager.get_bet_amount()
		var win_ratio: float = (_current_round_win / bet) if bet > 0 else 0.0
		if win_ratio >= GameManager.BIG_WIN_THRESHOLD and win_presenter != null:
			GameManager.current_state = GameManager.GameState.BIG_WIN
			win_presenter.show_big_win(_current_round_win, win_ratio)
			await win_presenter.presentation_complete
		round_complete.emit(_current_round_win)

	# Return to idle
	if not free_game_started:
		if GameManager.is_in_free_game:
			if GameManager.free_game_left_rounds <= 0:
				grid.clear_multipliers()
				GameManager.end_free_game()
			else:
				GameManager.current_state = GameManager.GameState.FREE_GAME_IDLE
		else:
			GameManager.current_state = GameManager.GameState.IDLE


# ── Debug: text-based screen dump ────────────────────────────────────────────

const _SYM_NAMES := {
	0: "0",
	1: "H1", 2: "H2", 3: "H3", 4: "H4", 5: "H5", 6: "H6",
	11: "N1", 12: "N2", 13: "N3",
	21: "MT",
	91: "WD", 92: "SC",
}

const _FG_CORNER_NAMES := {
	21: "CL",   # Collect
	22: "DB",   # Double
	23: "GN",   # Generate/Prizes
	24: "UL",   # Unlock
}

func _sym_name(sid: int) -> String:
	return _SYM_NAMES.get(sid, "?%d" % sid)


func _extract_sticky_from_screen(scr: Array) -> Array:
	var positions: Array = []
	for i in range(scr.size()):
		if scr[i].get("ih", 0) == 1:
			positions.append(i)
	return positions


func _sum_mtp_from_screen(scr: Array) -> int:
	var total: int = 0
	for s in scr:
		if s.get("sid", 0) == GameManager.MTP_ID and s.get("mtp", 0) > 0:
			total += s.get("mtp", 0)
	return total


func _debug_print_screen(label: String, screen: Array, elims: Array, dsp: Array, rows: int = 6) -> void:
	# Build set of winning positions and sticky positions
	var win_pos := {}
	for e in elims:
		for p in e.get("wp", []):
			win_pos[p] = e.get("sid", 0)
	var sticky_pos := {}
	for p in dsp:
		sticky_pos[p] = true

	var cols := GameManager.SCREEN_COLS

	print("┌─── %s ───┐" % label)
	# Header
	var header := "     "
	for col in range(cols):
		header += "C%-5d" % col
	print(header)
	# Rows
	for row in range(rows):
		var line := "R%d │ " % row
		for col in range(cols):
			var idx: int = col * rows + row
			if idx < screen.size():
				var sid: int = screen[idx].get("sid", 0)
				var bt: int = screen[idx].get("bt", 0)
				var mtp: int = screen[idx].get("mtp", 0)
				var name: String
				if sid == GameManager.MTP_ID and mtp > 0:
					name = "x%d" % mtp
				elif sid == GameManager.MTP_ID:
					name = "--"
				elif sid == GameManager.WILD_ID and bt >= 21 and bt <= 24:
					name = _FG_CORNER_NAMES.get(bt, "W%d" % bt)
				elif sid == GameManager.WILD_ID and bt > 0:
					name = "W%d" % bt
				else:
					name = _sym_name(sid)
				if win_pos.has(idx):
					name = "[%s]" % name  # mark winning
				elif sticky_pos.has(idx):
					name = "<%s>" % name  # mark sticky
				else:
					name = " %s " % name
				line += "%-6s" % name
			else:
				line += " --   "
		print(line)

	# Print cluster info
	if elims.size() > 0:
		var cluster_strs := []
		for e in elims:
			var sid: int = e.get("sid", 0)
			var count: int = e.get("wp", []).size()
			var ws: float = e.get("ws", 0.0)
			cluster_strs.append("%s×%d=%.2f" % [_sym_name(sid), count, ws])
		print("  Clusters: %s" % ", ".join(cluster_strs))
	print("")


func _debug_print_screen_info(i: int, total: int, si: Dictionary) -> void:
	var screen: Array = si.get("screen", [])
	var elims: Array = si.get("elims", [])
	var dsp: Array = si.get("dsp", [])
	var ws: float = si.get("ws", 0.0)
	var stws: float = si.get("stws", 0.0)
	var we: Array = si.get("we", [])
	var scnb: Array = si.get("scnb", [])
	var sticky: Array = _extract_sticky_from_screen(screen)

	var label := "Screen %d/%d" % [i + 1, total]
	if sticky.size() > 0:
		label += " [RESPIN]"
	if ws > 0:
		label += "  ws=%.2f  stws=%.2f" % [ws, stws]

	# Print BEFORE (scnb) and AFTER (screen) grids
	# BEFORE uses rsctb (pre-wild/unlock), AFTER uses rsct (post-wild/unlock)
	var si_rsctb: Array = si.get("rsctb", [])
	var before_rows: int = (si_rsctb[0] as int) if si_rsctb.size() > 0 else (grid.current_rows if grid else GameManager.SCREEN_ROWS)
	var si_rsct: Array = si.get("rsct", [])
	var after_rows: int = (si_rsct[0] as int) if si_rsct.size() > 0 else before_rows
	if after_rows < 6:
		after_rows = before_rows
	if scnb.size() > 0:
		_debug_print_screen("Screen %d/%d [BEFORE Wild]" % [i + 1, total], scnb, [], [], before_rows)
	if screen.size() > 0:
		_debug_print_screen(label + " [AFTER Wild]" if scnb.size() > 0 else label, screen, elims, dsp, after_rows)

	# Wild effects
	if we.size() > 0:
		for w in we:
			var etype: String = w.get("effect_type", "")
			var wpos: int = w.get("pos", 0)
			var val: int = w.get("value", 0)
			var wst: int = w.get("wild_sub_type", 0)
			var affected: Array = w.get("affected", [])
			var changes: Array = w.get("changes", [])
			print("  Wild W%d @%d: %s val=%d affected=%s" % [wst, wpos, etype, val, str(affected)])
			# Print detailed changes for all wild sub_types (11-18)
			if changes.size() > 0:
				for ch in changes:
					var cpos: int = ch.get("pos", 0)
					var to_sid: int = ch.get("to_sid", 0)
					@warning_ignore("integer_division")
					var ccol: int = cpos / GameManager.SCREEN_ROWS
					var crow: int = cpos % GameManager.SCREEN_ROWS
					# Find before symbol from scnb
					var from_name := "?"
					if cpos < scnb.size():
						from_name = _sym_name(scnb[cpos].get("sid", 0))
					print("    change: pos=%d (%d,%d) %s → %s" % [cpos, ccol, crow, from_name, _sym_name(to_sid)])
		print("")

	# Scoring formula when MTP (W11/W12) or Extend (W17/W18) wilds are on screen
	if ws > 0 and elims.size() > 0:
		var has_score_wild := false
		# Check wild effects data
		for w in we:
			if w.get("wild_sub_type", 0) in [
				GameManager.WILD_SUB_MTP_NORMAL, GameManager.WILD_SUB_MTP_SUPER,
				GameManager.WILD_SUB_EXTEND_NORMAL, GameManager.WILD_SUB_EXTEND_SUPER]:
				has_score_wild = true
				break
		# Also check screen symbols for W11/12/17/18
		if not has_score_wild:
			for sym in screen:
				if sym.get("sid", 0) == GameManager.WILD_ID and sym.get("bt", 0) in [
					GameManager.WILD_SUB_MTP_NORMAL, GameManager.WILD_SUB_MTP_SUPER,
					GameManager.WILD_SUB_EXTEND_NORMAL, GameManager.WILD_SUB_EXTEND_SUPER]:
					has_score_wild = true
					break
		if has_score_wild:
			print("  ── Score Breakdown ──")
			var cluster_total := 0.0
			for e in elims:
				var esid: int = e.get("sid", 0)
				var count: int = e.get("wp", []).size()
				var ews: float = e.get("ws", 0.0)
				var bs: float = e.get("bs", 0.0)
				var spo: float = e.get("spo", 0.0)
				var awmtp: float = e.get("awmtp", 0.0)
				var wsbd1: float = e.get("wsbd1", 0.0)
				var wsbd2: float = e.get("wsbd2", 0.0)
				if awmtp > 0 and awmtp != 1.0:
					print("    %s×%d: bs=%.2f × spo=%.2f = wsbd1=%.2f × awmtp=%.1f = ws=%.2f" % [
						_sym_name(esid), count, bs, spo, wsbd1, awmtp, ews])
				else:
					print("    %s×%d: bs=%.2f × spo=%.2f = wsbd1=%.2f → ws=%.2f" % [
						_sym_name(esid), count, bs, spo, wsbd1, ews])
				cluster_total += ews
			print("    Total: %.2f" % cluster_total)
			print("")

	# Free game info
	var fg: Variant = si.get("fg", null)
	if fg != null and fg is Dictionary:
		print("  FreeGame: lr=%d tr=%d tws=%.2f" % [fg.get("lr", 0), fg.get("tr", 0), fg.get("tws", 0.0)])

	# Debug: rsct and corner_features
	var dbg_rsct: Array = si.get("rsct", [])
	if dbg_rsct.size() > 0 and (dbg_rsct[0] as int) != 6:
		print("  rows=%d (from rsct)" % (dbg_rsct[0] as int))
	var dbg_fg: Variant = si.get("fg", null)
	var cf: Array = dbg_fg.get("corner_features", []) if dbg_fg is Dictionary else []
	if cf.size() > 0:
		for c in cf:
			print("  CornerFeature: pos=%d type=%d value=%d" % [c.get("pos", 0), c.get("feature_type", 0), c.get("value", 0)])

	var fgis: Variant = si.get("fgis", null)
	if fgis != null and fgis is Dictionary:
		print("  >>> FREE GAME TRIGGER! scatter=%d rounds=%d" % [fgis.get("fgsct", 0), fgis.get("fgct", 0)])
		_debug_print_free_game_initial_screen(fgis)


func _debug_print_free_game_initial_screen(fgis: Dictionary) -> void:
	var rows: int = GameManager.SCREEN_ROWS
	var cols: int = GameManager.SCREEN_COLS
	var multipliers: Array = fgis.get("multipliers", [])
	var corner_assigns: Array = []  # corner_assignments now in fg, not fgis

	# Build lookup maps: flat_pos → display string
	var mtp_map := {}
	for m in multipliers:
		mtp_map[m.get("pos", -1)] = "x%d" % m.get("value", 0)
	var corner_map := {}
	for a in corner_assigns:
		corner_map[a.get("pos", -1)] = _FG_CORNER_NAMES.get(a.get("feature_type", 0), "??")

	print("  [FreeGame Init] multipliers=%s corners=%s" % [str(multipliers), str(corner_assigns)])
	print("┌─── FreeGame Initial Screen ───┐")
	var header := "     "
	for col in range(cols):
		header += "C%-5d" % col
	print(header)
	for row in range(rows):
		var line := "R%d │ " % row
		for col in range(cols):
			var idx: int = col * rows + row
			var name: String
			if corner_map.has(idx) and mtp_map.has(idx):
				name = "%s%s" % [corner_map[idx], mtp_map[idx]]
			elif corner_map.has(idx):
				name = corner_map[idx]
			elif mtp_map.has(idx):
				name = mtp_map[idx]
			else:
				name = "--"
			line += " %-5s" % name
		print(line)
	print("")


## Create score formula label on the left side of the screen
func _ensure_score_label() -> void:
	if _score_label != null:
		return
	_score_label = RichTextLabel.new()
	_score_label.name = "ScoreFormula"
	_score_label.position = Vector2(10, 120)
	_score_label.size = Vector2(480, 980)
	_score_label.add_theme_font_size_override("normal_font_size", 28)
	_score_label.add_theme_color_override("default_color", Color(0.8, 0.9, 1.0))
	_score_label.bbcode_enabled = false
	_score_label.scroll_active = true
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child.call_deferred(_score_label)


## Append Wild Award/MTP bonus lines to score breakdown
func _append_wild_bonus_lines(lines: Array[String], wild_effects: Array, cluster_total: float, bet: float) -> void:
	for w in wild_effects:
		var etype: String = w.get("effect_type", "")
		var val: int = w.get("value", 0)
		if etype == GameManager.WILD_EFFECT_AWARD and val > 0:
			var award_mult := val / 100.0
			lines.append("  Wild Award: +%.1f× bet = %.2f" % [award_mult, award_mult * bet])
		elif etype == GameManager.WILD_EFFECT_MTP and val > 1:
			var mtp_bonus := cluster_total * (val - 1)
			lines.append("  Wild MTP: x%d → %.2f × %d = %.2f" % [val, cluster_total, val - 1, mtp_bonus])


## Display score formula breakdown after spin completes
func _display_score_formula(results: Array) -> void:
	_ensure_score_label()
	var lines: Array[String] = []
	var bet := GameManager.get_bet_amount()
	var total_win := 0.0

	if GameManager.is_in_free_game:
		lines.append("=== FREE GAME SCORE ===")
		for i in range(results.size()):
			var si: Dictionary = results[i]
			var ws: float = si.get("ws", 0.0)
			var score_fg: Variant = si.get("fg", null)
			var corner_features: Array = score_fg.get("corner_features", []) if score_fg is Dictionary else []
			var elims: Array = si.get("elims", [])
			if ws <= 0 and corner_features.size() == 0 and elims.size() == 0:
				continue
			lines.append("--- Spin %d/%d ---" % [i + 1, results.size()])
			for e in elims:
				var sid: int = e.get("sid", 0)
				var count: int = e.get("wp", []).size()
				var ews: float = e.get("ws", 0.0)
				var bs: float = e.get("bs", 0.0)
				var awmtp: float = e.get("awmtp", 0.0)
				if awmtp > 0 and awmtp != 1.0:
					lines.append("  %s x%d: bs=%.2f x mtp=%.1f = %.2f" % [_sym_name(sid), count, bs, awmtp, ews])
				elif ews > 0:
					lines.append("  %s x%d: bs=%.2f = %.2f" % [_sym_name(sid), count, bs, ews])
			# Wild Award/MTP bonus
			var fg_cluster_total := 0.0
			for e2 in elims:
				fg_cluster_total += e2.get("ws", 0.0)
			_append_wild_bonus_lines(lines, si.get("we", []), fg_cluster_total, bet)
			for cf in corner_features:
				var ft: int = cf.get("feature_type", 0)
				var val: int = cf.get("value", 0)
				match ft:
					23: lines.append("  Generate: +%d MTP" % val)
					24: lines.append("  Unlock: -> %d rows" % val)
					22:
						var affected: Array = cf.get("affected_mpi", [])
						lines.append("  Double: %d cells, delta=%d" % [affected.size(), val])
					21: lines.append("  Collect: sum=%d" % val)
			if ws > 0:
				lines.append("  ws = %.2f" % ws)
		var fg: Variant = results[results.size() - 1].get("fg", null) if results.size() > 0 else null
		if fg != null and fg is Dictionary:
			var tws: float = fg.get("tws", 0.0)
			lines.append("")
			lines.append("Total FG win = %.2f" % tws)
	else:
		lines.append("=== MAIN GAME SCORE ===")
		lines.append("Bet = %.2f" % bet)
		# Only show the final stage that has score (sticky win settles at the end)
		var final_si: Dictionary = {}
		for i in range(results.size() - 1, -1, -1):
			var si: Dictionary = results[i]
			if si.get("ws", 0.0) > 0:
				final_si = si
				break
		if not final_si.is_empty():
			var elims: Array = final_si.get("elims", [])
			var ws: float = final_si.get("ws", 0.0)
			for e in elims:
				var sid: int = e.get("sid", 0)
				var count: int = e.get("wp", []).size()
				var ews: float = e.get("ws", 0.0)
				var bs: float = e.get("bs", 0.0)
				var spo: float = e.get("spo", 0.0)
				var awmtp: float = e.get("awmtp", 0.0)
				var formula := "%s x%d" % [_sym_name(sid), count]
				if bs > 0:
					formula += ": bs=%.2f" % bs
				if spo > 0 and spo != 1.0:
					formula += " x spo=%.1f" % spo
				if awmtp > 0 and awmtp != 1.0:
					formula += " x mtp=%.1f" % awmtp
				formula += " = %.2f" % ews
				lines.append("  " + formula)
			# Wild Award/MTP bonus
			var cluster_total := 0.0
			for e2 in elims:
				cluster_total += e2.get("ws", 0.0)
			_append_wild_bonus_lines(lines, final_si.get("we", []), cluster_total, bet)
			if ws > 0:
				total_win = ws
				lines.append("  stage ws = %.2f" % ws)
		if total_win > 0:
			lines.append("")
			lines.append("Total win = %.2f" % total_win)

	var pay: float = _current_response.get("pay_amount", 0.0)
	var balance: float = _current_response.get("balance", 0.0)
	lines.append("")
	lines.append("pay_amount = %.2f" % pay)
	lines.append("balance = %.2f" % balance)
	_score_label.text = "\n".join(lines)

