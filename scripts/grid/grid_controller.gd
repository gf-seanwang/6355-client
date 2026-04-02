extends Control
class_name GridController

## Manages the 6x6 symbol grid, animations, and visual state

signal cascade_complete()

const COLS := 6
const ROWS := 6  # default rows; see current_rows for dynamic grid
const MAX_ROWS := 8
const CELL_SIZE := Vector2(150, 150)
const CELL_GAP := 4.0
const GRID_OFFSET := Vector2(500, 80)  # Centered on 1920x1080
const VIEWPORT_HEIGHT := 1080.0
const GRID_BOTTOM_MARGIN := 20.0  # minimum bottom margin

const SPIN_SYMBOLS := [1, 2, 3, 4, 5, 6, 11, 12, 13]
const SPIN_BASE_COUNT := 15        # base reel strip random symbols
const SPIN_COL_EXTRA := 3          # extra random symbols per subsequent column
const SPIN_COL_START_DELAY := 0.06  # stagger between column starts (s)
const SPIN_ANTICIPATION_PX := 15.0  # bounce-up distance before spin
const SPIN_ANTICIPATION_TIME := 0.08
const SPIN_VELOCITY := 3500.0      # px/s during fast scroll
const SPIN_DECEL_RATIO := 0.25     # fraction of scroll distance for deceleration
const SPIN_OVERSHOOT_PX := 16.0    # overshoot past target before snap
const SPIN_SNAPBACK_TIME := 0.1    # bounce-back duration (s)
const WILD_FLOAT_PX := 4.0         # wild float amplitude (px)
const WILD_FLOAT_PERIOD := 2.0     # wild float cycle (s)

const FRAME_PADDING := 8.0
const FRAME_COLOR := Color(0.35, 0.4, 0.5)
const FRAME_BORDER_WIDTH := 3
const GRID_BG_COLOR := Color(0.08, 0.1, 0.14)

const CORNER_FEATURE_NAMES := {21: "Collect", 22: "Double", 23: "Generate", 24: "Unlock"}

static func pos_to_grid(pos: int, rows: int = ROWS) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(pos / rows, pos % rows)

var symbol_scene: PackedScene = preload("res://scenes/grid/symbol.tscn")
var cells: Array = []  # [col][row] -> SymbolController (up to MAX_ROWS rows pre-built)
var current_rows: int = ROWS  # dynamic row count (6-8), updated by set_rows()
var _animating: bool = false
var _spin_cols_done := 0
var _grid_clip: Control  # Clipping container for the grid area
var _frame: Panel  # Border frame behind the grid
var _wild_corner_set: Dictionary = {}  # {Vector2i(col,row): true} — actual Wild corner positions


func _ready() -> void:
	_create_frame()
	_create_grid()
	_set_random_initial_screen()


func _create_frame() -> void:
	var grid_w: float = COLS * CELL_SIZE.x + (COLS - 1) * CELL_GAP
	var grid_h: float = current_rows * CELL_SIZE.y + (current_rows - 1) * CELL_GAP

	# Border frame behind the grid
	_frame = Panel.new()
	_frame.position = GRID_OFFSET - Vector2(FRAME_PADDING, FRAME_PADDING)
	_frame.size = Vector2(grid_w + FRAME_PADDING * 2, grid_h + FRAME_PADDING * 2)
	var style := StyleBoxFlat.new()
	style.bg_color = GRID_BG_COLOR
	style.border_color = FRAME_COLOR
	style.set_border_width_all(FRAME_BORDER_WIDTH)
	style.set_corner_radius_all(4)
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)

	# Clipping container — all cells and spin temp nodes go here
	_grid_clip = Control.new()
	_grid_clip.clip_contents = true
	_grid_clip.position = GRID_OFFSET
	_grid_clip.size = Vector2(grid_w, grid_h)
	add_child(_grid_clip)


func _is_wild_corner(col: int, row: int) -> bool:
	return _wild_corner_set.has(Vector2i(col, row))


## Initialise wild corner set to the four grid corners of current_rows
func _init_wild_corners() -> void:
	_wild_corner_set.clear()
	for pos in [Vector2i(0, 0), Vector2i(COLS - 1, 0),
				Vector2i(0, current_rows - 1), Vector2i(COLS - 1, current_rows - 1)]:
		_wild_corner_set[pos] = true


## Shift all tracked wild corners down by 1 row (called before Unlock set_rows)
func shift_wild_corners_down() -> void:
	var new_set := {}
	for k in _wild_corner_set:
		new_set[Vector2i(k.x, k.y + 1)] = true
	_wild_corner_set = new_set


func _create_grid() -> void:
	_init_wild_corners()
	for col in range(COLS):
		var column := []
		for row in range(MAX_ROWS):
			var cell: SymbolController = symbol_scene.instantiate()
			cell.setup(col, row)
			cell.position = _cell_position(col, row)
			cell.custom_minimum_size = CELL_SIZE
			cell.size = CELL_SIZE
			_grid_clip.add_child(cell)
			column.append(cell)
			# Wild corners are always Wild (based on current_rows)
			if _is_wild_corner(col, row):
				cell.set_symbol(GameManager.WILD_ID)
			# Hide rows beyond current_rows
			if row >= current_rows:
				cell.visible = false
		cells.append(column)


func _set_random_initial_screen() -> void:
	for col in range(COLS):
		for row in range(current_rows):
			if not _is_wild_corner(col, row):
				cells[col][row].set_symbol(_random_spin_symbol())


func _cell_position(col: int, row: int) -> Vector2:
	return Vector2(
		col * (CELL_SIZE.x + CELL_GAP),
		row * (CELL_SIZE.y + CELL_GAP)
	)


## Apply the correct visual to a cell based on symbol id and multiplier
func _apply_cell_symbol(cell: SymbolController, sid: int, mtp: int, bt: int = 0) -> void:
	if sid == GameManager.MTP_ID and mtp <= 0:
		cell.set_empty()
	elif sid == GameManager.MTP_ID and mtp > 0:
		cell.set_multiplier_cell(mtp)
	else:
		cell.set_symbol(sid, bt if sid == GameManager.WILD_ID else 0)


## Set the entire screen from a flat array of {sid, pos} dicts
## Wild cells use bt field as wild_sub_type for display (e.g. W17, W12)
func set_screen(screen_data: Array) -> void:
	for i in range(mini(screen_data.size(), COLS * current_rows)):
		var gr := pos_to_grid(i, current_rows)
		if gr.x < COLS and gr.y < current_rows:
			var sid: int = screen_data[i].get("sid", 0)
			var bt: int = screen_data[i].get("bt", 0)
			cells[gr.x][gr.y].hide_extend_marker()
			if _is_wild_corner(gr.x, gr.y):
				cells[gr.x][gr.y].set_symbol(GameManager.WILD_ID, bt)
			else:
				var mtp: int = screen_data[i].get("mtp", 0)
				_apply_cell_symbol(cells[gr.x][gr.y], sid, mtp, bt)


## Highlight winning clusters
func highlight_clusters(elims: Array) -> void:
	for elim in elims:
		var positions: Array = elim.get("wp", [])
		for pos in positions:
			var gr := pos_to_grid(int(pos), current_rows)
			if gr.x < COLS and gr.y < current_rows:
				cells[gr.x][gr.y].highlight()


## Play elimination animation for winning clusters
func animate_elimination(elims: Array) -> void:
	_animating = true
	var positions_to_eliminate := []
	for elim in elims:
		for pos in elim.get("wp", []):
			var gr := pos_to_grid(int(pos), current_rows)
			if gr.x < COLS and gr.y < current_rows:
				positions_to_eliminate.append(gr)
				cells[gr.x][gr.y].play_eliminate()

	if positions_to_eliminate.size() > 0:
		await get_tree().create_timer(0.4).timeout
	_animating = false
	cascade_complete.emit()


## Respin animation: each non-sticky cell is a mini vertical reel
## All respin cells start and stop together

const RESPIN_DIM_ALPHA := 0.3
const RESPIN_DIM_TIME := 0.2
const RESPIN_REEL_COUNT := 15            # number of random symbols per mini-reel
const RESPIN_REEL_VELOCITY := 2500.0     # px/s for mini-reel scroll

var _respin_cells_done := 0

func animate_drop(sticky_positions: Array, new_screen: Array) -> void:
	_animating = true

	# Build sticky lookup from backend-provided sticky positions
	var sticky_set := {}
	for pos in sticky_positions:
		sticky_set[int(pos)] = true
	# Wild corners are always sticky
	for col in range(COLS):
		for row in range(current_rows):
			if _is_wild_corner(col, row):
				sticky_set[col * current_rows + row] = true

	# If backend sent no sticky positions, fall back to symbol comparison
	if sticky_positions.size() == 0:
		for col in range(COLS):
			for row in range(current_rows):
				var idx: int = col * current_rows + row
				if _is_wild_corner(col, row):
					continue
				if idx < new_screen.size():
					var new_sid: int = new_screen[idx].get("sid", 0)
					if cells[col][row].symbol_id == new_sid:
						sticky_set[idx] = true

	# Classify cells and show wild corner borders in one pass
	var respin_cells: Array = []  # [{col, row, sid}]
	for col in range(COLS):
		for row in range(current_rows):
			var idx: int = col * current_rows + row
			if _is_wild_corner(col, row):
				continue  # Wild 角落不重轉，但不顯示 sticky 框
			if sticky_set.has(idx):
				cells[col][row].highlight()
				cells[col][row].show_sticky_border()
				continue
			var sid: int = 0
			if idx < new_screen.size():
				sid = new_screen[idx].get("sid", 0)
			else:
				sid = _random_spin_symbol()
			respin_cells.append({"col": col, "row": row, "sid": sid})

	if respin_cells.size() == 0:
		set_screen(new_screen)
		_animating = false
		return

	# === Phase 1: The Lock ===
	# Dim respin cells
	var dim_tweens: Array[Tween] = []
	for entry in respin_cells:
		var cell: SymbolController = cells[entry["col"]][entry["row"]]
		var dim_tween := create_tween()
		dim_tween.tween_property(cell, "modulate:a", RESPIN_DIM_ALPHA, RESPIN_DIM_TIME)
		dim_tweens.append(dim_tween)

	await get_tree().create_timer(RESPIN_DIM_TIME + 0.15).timeout

	# Kill dim tweens to avoid race with modulate.a = 1.0 in _respin_cell_reel
	for dt in dim_tweens:
		dt.kill()

	# === Phase 2: All mini-reels spin together ===
	_respin_cells_done = 0
	var total_cells := respin_cells.size()
	for entry in respin_cells:
		_respin_cell_reel(entry["col"], entry["row"], entry["sid"])

	# Wait for all cells to finish
	while _respin_cells_done < total_cells:
		await get_tree().process_frame

	# === Cleanup ===
	for col in range(COLS):
		for row in range(current_rows):
			var idx: int = col * current_rows + row
			if _is_wild_corner(col, row) or sticky_set.has(idx):
				cells[col][row].hide_sticky_border()
	for entry in respin_cells:
		cells[entry["col"]][entry["row"]].restore_modulate()

	set_screen(new_screen)
	_animating = false


## Per-cell mini-reel: create a vertical strip clipped to cell bounds and scroll it
func _respin_cell_reel(col: int, row: int, target_sid: int) -> void:
	var cell: SymbolController = cells[col][row]
	var cell_pos := _cell_position(col, row)

	# Hide the real cell
	cell.visible = false

	# Create a clip at the cell's position (single cell size)
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = cell_pos
	clip.size = CELL_SIZE
	_grid_clip.add_child(clip)
	_grid_clip.move_child(clip, 0)  # behind sticky cells

	# Build mini-reel strip: [target_symbol] + [RESPIN_REEL_COUNT random symbols]
	var total := 1 + RESPIN_REEL_COUNT
	var strip := Control.new()
	clip.add_child(strip)

	# First slot = target (final position after scroll)
	var node := _create_strip_symbol()
	node.position = Vector2.ZERO
	strip.add_child(node)
	_set_strip_symbol(node, target_sid)
	# Rest = random
	for i in range(1, total):
		node = _create_strip_symbol()
		node.position = Vector2(0, i * CELL_SIZE.y)
		strip.add_child(node)
		_set_strip_symbol(node, _random_spin_symbol())

	# Scroll from top (random symbols visible) down to target at position 0
	strip.position.y = -RESPIN_REEL_COUNT * CELL_SIZE.y
	await _scroll_strip_anim(strip, RESPIN_REEL_COUNT, CELL_SIZE.y,
		RESPIN_REEL_VELOCITY, 8.0, 0.06, 10.0, 0.08, 0.3, 0.4)

	# Reveal real cell
	cell.set_symbol(target_sid)
	cell.visible = true
	cell.modulate.a = 1.0

	clip.queue_free()
	_respin_cells_done += 1


## Play wild effect animations — sorted by priority, grouped by sub_type
## scnb: screen before wild effects (Array of SymbolDescription dicts), used as fallback for upgrade animation
func animate_wild_effects(effects: Array, scnb: Array = []) -> void:
	if effects.size() == 0:
		return
	_animating = true

	# Build scnb lookup as fallback: flat position → sid (screen before wild effects)
	var before_sids := {}
	for sd in scnb:
		var bpos: int = sd.get("pos", -1)
		if bpos >= 0:
			before_sids[bpos] = int(sd.get("sid", 0))

	# 保持後端順序，只把 mystery 移到最前
	var sorted_effects: Array = []
	var non_mystery: Array = []
	for e in effects:
		if e.get("effect_type", "") == GameManager.WILD_EFFECT_MYSTERY:
			sorted_effects.append(e)
		else:
			non_mystery.append(e)
	sorted_effects.append_array(non_mystery)

	# 用 effect_type 分組，確保同類效果一起播，mystery 獨立分組
	var groups: Array = []  # Array of Arrays
	var current_group: Array = []
	var current_group_key: String = ""
	for effect in sorted_effects:
		var etype: String = effect.get("effect_type", "")
		var group_key: String = etype
		if group_key != current_group_key and current_group.size() > 0:
			groups.append(current_group)
			current_group = []
		current_group_key = group_key
		current_group.append(effect)
	if current_group.size() > 0:
		groups.append(current_group)

	# Play each group sequentially with 0.6s gap
	for group in groups:
		var is_super: bool = GameManager.is_super_wild(group[0].get("wild_sub_type", 0))
		for effect in group:
			var pos: int = effect.get("pos", 0)
			var gr := pos_to_grid(pos, current_rows)
			var effect_type: String = effect.get("effect_type", GameManager.WILD_EFFECT_EXTEND)
			var value: int = effect.get("value", 0)
			var affected: Array = effect.get("affected", [])
			var changes: Array = effect.get("changes", [])
			var sub_type: int = effect.get("wild_sub_type", 0)

			if gr.x >= COLS or gr.y >= current_rows:
				continue

			# Update Wild cell label to show sub-type code (skip for mystery — play_mystery_reveal handles it)
			if effect_type != GameManager.WILD_EFFECT_MYSTERY:
				cells[gr.x][gr.y].set_symbol(GameManager.WILD_ID, sub_type)

			# Console log
			var super_str := "Super" if is_super else "Normal"
			print("[Wild] W%d (%s %s) pos=(%d,%d) value=%d affected=%s changes=%s" % [
				sub_type, super_str, effect_type, gr.x, gr.y, value, str(affected), str(changes)])

			# Play source Wild animation (mystery handles its own animation via play_mystery_reveal)
			if effect_type != GameManager.WILD_EFFECT_MYSTERY:
				cells[gr.x][gr.y].play_wild_effect(effect_type, is_super)

			# Build changes lookup: flat pos → to_sid
			var changes_map := {}
			for ch in changes:
				changes_map[int(ch.get("pos", -1))] = int(ch.get("to_sid", 0))

			# Dispatch by effect type
			match effect_type:
				GameManager.WILD_EFFECT_MYSTERY:
					var reveal_wst: int = effect.get("wild_sub_type", 0)
					var reveal_super: bool = GameManager.is_super_wild(reveal_wst)
					cells[gr.x][gr.y].play_mystery_reveal(reveal_wst, reveal_super)
					print("  -> Mystery reveal: W%d (%s)" % [reveal_wst, "Super" if reveal_super else "Normal"])
				GameManager.WILD_EFFECT_EXTEND:
					# Show extend count on source Wild
					cells[gr.x][gr.y].show_wild_value_label("W%d\nExt×%d" % [sub_type, affected.size()])
					for apos in affected:
						var agr := pos_to_grid(int(apos), current_rows)
						if agr.x < COLS and agr.y < current_rows:
							var to_sid: int = changes_map.get(int(apos), GameManager.WILD_ID)
							cells[agr.x][agr.y].play_transform_extend(to_sid, is_super)
							var to_name: String = SymbolController.SYMBOL_NAMES.get(to_sid, "?") if to_sid > 0 else "?"
							print("  -> Extend: (%d,%d) → %s" % [agr.x, agr.y, to_name])
				GameManager.WILD_EFFECT_UPGRADE:
					for apos in affected:
						var agr := pos_to_grid(int(apos), current_rows)
						if agr.x < COLS and agr.y < current_rows:
							# Use changes to get the target upgraded symbol
							var to_sid: int = changes_map.get(int(apos), 0)
							# Fallback to scnb if changes not available
							var before_sid: int = before_sids.get(int(apos), 0)
							if before_sid > 0:
								cells[agr.x][agr.y].set_symbol(before_sid)
							cells[agr.x][agr.y].play_upgrade_symbol(to_sid if to_sid > 0 else before_sid, is_super)
							var from_name: String = SymbolController.SYMBOL_NAMES.get(before_sid, "?") if before_sid > 0 else "?"
							var to_name: String = SymbolController.SYMBOL_NAMES.get(to_sid, "?") if to_sid > 0 else "?"
							print("  -> Upgrade: (%d,%d) %s → %s" % [agr.x, agr.y, from_name, to_name])
				GameManager.WILD_EFFECT_MTP:
					cells[gr.x][gr.y].show_wild_value_label("W%d\n×%d" % [sub_type, value])
					print("  -> MTP: ×%d" % value)
				GameManager.WILD_EFFECT_AWARD:
					cells[gr.x][gr.y].show_wild_value_label("W%d\n+%.1f×" % [sub_type, value / 100.0])
					print("  -> Award: +%.1f×" % (value / 100.0))

		await get_tree().create_timer(0.8).timeout

	_animating = false


## Highlight scatter positions
func highlight_scatters() -> void:
	for col in range(COLS):
		for row in range(current_rows):
			if cells[col][row].symbol_id == GameManager.SCATTER_ID:
				cells[col][row].highlight(Color.MAGENTA)


## Highlight sticky positions (clusters + scatters, skip non-cluster Wilds)
func highlight_sticky(positions: Array) -> void:
	for pos in positions:
		var gr := pos_to_grid(pos as int, current_rows)
		if gr.x < COLS and gr.y < current_rows:
			var cell: SymbolController = cells[gr.x][gr.y]
			if cell.symbol_id == GameManager.WILD_ID:
				continue  # Wild 沒加入叢集不亮，加入叢集的已由 highlight_clusters 處理
			if cell.symbol_id == GameManager.SCATTER_ID:
				cell.highlight(Color.MAGENTA)
			else:
				cell.highlight(Color.GOLD)


## Display multiplier overlays at specified positions
## mpi: Array of {pos: int, value: int}
func display_multipliers(mpi: Array) -> void:
	clear_multipliers()
	for m in mpi:
		var pos: int = m.get("pos", -1)
		var value: int = m.get("value", 1)
		if pos < 0 or value <= 0:
			continue
		var gr := pos_to_grid(pos, current_rows)
		if gr.x < COLS and gr.y < current_rows:
			cells[gr.x][gr.y].show_multiplier(value)


## Clear all multiplier overlays
func clear_multipliers() -> void:
	for col in range(COLS):
		for row in range(MAX_ROWS):
			cells[col][row].hide_multiplier()


## Reset all cells to default visual state
func reset_highlights() -> void:
	for col in range(COLS):
		for row in range(MAX_ROWS):
			var cell: SymbolController = cells[col][row]
			cell.is_highlighted = false
			# Skip MTP cells — set_symbol would overwrite "x10" label with "MTP"
			if cell.symbol_id != GameManager.MTP_ID:
				cell.set_symbol(cell.symbol_id, cell.wild_sub_type)
			cell.hide_wild_value_label()
			cell.hide_extend_marker()
			cell.hide_sticky_border()


## Animate spin: reel-style scroll with staggered column stops
func animate_spin(screen_data: Array) -> void:
	_animating = true
	_spin_cols_done = 0
	for col in range(COLS):
		_spin_column(col, screen_data)
	while _spin_cols_done < COLS:
		await get_tree().process_frame
	_animating = false


func _spin_column(col: int, screen_data: Array) -> void:
	# Staggered start
	if col > 0:
		await get_tree().create_timer(col * SPIN_COL_START_DELAY).timeout

	var step_h: float = CELL_SIZE.y + CELL_GAP
	var rows := current_rows

	# Classify rows and gather target SIDs + bt for scrollable rows
	var wild_rows: Array[int] = []
	var wild_tweens: Array = []
	var scroll_rows: Array[int] = []
	var scroll_sids: Array = []
	var scroll_bts: Array = []
	for row in range(rows):
		if _is_wild_corner(col, row):
			wild_rows.append(row)
		else:
			scroll_rows.append(row)
			var idx: int = col * rows + row
			if idx < screen_data.size():
				scroll_sids.append(screen_data[idx].get("sid", 0))
				scroll_bts.append(screen_data[idx].get("bt", 0))
			else:
				scroll_sids.append(_random_spin_symbol())
				scroll_bts.append(0)

	# Wild corners: fixed, float during spin
	for row in wild_rows:
		_grid_clip.move_child(cells[col][row], -1)
		var base_y: float = _cell_position(col, row).y
		var wt := create_tween().set_loops()
		wt.tween_property(cells[col][row], "position:y", base_y - WILD_FLOAT_PX,
			WILD_FLOAT_PERIOD / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		wt.tween_property(cells[col][row], "position:y", base_y + WILD_FLOAT_PX,
			WILD_FLOAT_PERIOD / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		wild_tweens.append(wt)

	var scroll_count: int = scroll_rows.size()
	if scroll_count == 0:
		_finish_wild_float(col, wild_tweens, wild_rows)
		_spin_cols_done += 1
		return

	# Clip covers only the scrollable row range
	var first_row: int = scroll_rows[0]
	var last_row: int = scroll_rows[scroll_count - 1]
	var col_x: float = _cell_position(col, 0).x
	var clip_y: float = _cell_position(0, first_row).y
	var clip_height: float = (last_row - first_row) * step_h + CELL_SIZE.y

	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(col_x, clip_y)
	clip.size = Vector2(CELL_SIZE.x, clip_height)
	_grid_clip.add_child(clip)

	# Hide non-wild cells
	for row in scroll_rows:
		cells[col][row].visible = false

	# --- Build reel strip ---
	# Layout: results (0..scroll_count-1) then randoms (scroll_count..total-1)
	var spin_count: int = SPIN_BASE_COUNT + col * SPIN_COL_EXTRA
	var total: int = scroll_count + spin_count
	var strip := Control.new()
	clip.add_child(strip)

	for i in range(total):
		var node := _create_strip_symbol()
		node.position = Vector2(0, i * step_h)
		strip.add_child(node)
		if i < scroll_count:
			_set_strip_symbol(node, scroll_sids[i])
		else:
			_set_strip_symbol(node, _random_spin_symbol())

	await _scroll_strip(strip, spin_count)

	_finish_wild_float(col, wild_tweens, wild_rows)

	# Update wild corner bt from screen data
	for row in wild_rows:
		var idx: int = col * rows + row
		if idx < screen_data.size():
			var bt: int = screen_data[idx].get("bt", 0)
			cells[col][row].set_symbol(GameManager.WILD_ID, bt)

	# --- Reveal real cells ---
	for i in range(scroll_count):
		var row: int = scroll_rows[i]
		var sid: int = scroll_sids[i]
		var bt: int = scroll_bts[i]
		cells[col][row].set_symbol(sid, bt if sid == GameManager.WILD_ID else 0)
		cells[col][row].visible = true

	clip.queue_free()
	_spin_cols_done += 1


func _finish_wild_float(col: int, wild_tweens: Array, wild_rows: Array[int]) -> void:
	for wt in wild_tweens:
		wt.kill()
	for row in wild_rows:
		cells[col][row].position.y = _cell_position(col, row).y
		cells[col][row].play_spin_flip()


func _random_spin_symbol() -> int:
	return SPIN_SYMBOLS[randi() % SPIN_SYMBOLS.size()]


func _scroll_strip(strip: Control, spin_count: int) -> void:
	var step_h: float = CELL_SIZE.y + CELL_GAP
	strip.position.y = -spin_count * step_h
	await _scroll_strip_anim(strip, spin_count, step_h,
		SPIN_VELOCITY, SPIN_ANTICIPATION_PX, SPIN_ANTICIPATION_TIME,
		SPIN_OVERSHOOT_PX, SPIN_SNAPBACK_TIME, SPIN_DECEL_RATIO, 0.5)


## Shared scroll animation: anticipation → fast → decelerate → overshoot → snapback
func _scroll_strip_anim(strip: Control, count: int, step_h: float,
		velocity: float, antic_px: float, antic_time: float,
		overshoot_px: float, snapback_time: float,
		decel_ratio: float, slow_divisor: float) -> void:
	var start_y: float = -count * step_h
	var target_y: float = 0.0
	var antic_y: float = start_y - antic_px
	var overshoot_y: float = target_y + overshoot_px

	var total_dist: float = target_y - antic_y
	var fast_dist: float = total_dist * (1.0 - decel_ratio)
	var slow_dist: float = total_dist * decel_ratio + overshoot_px
	var fast_time: float = fast_dist / velocity
	var slow_time: float = slow_dist / (velocity * slow_divisor)
	var mid_y: float = antic_y + fast_dist

	var tween := create_tween()
	tween.tween_property(strip, "position:y", antic_y, antic_time) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(strip, "position:y", mid_y, fast_time) \
		.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(strip, "position:y", overshoot_y, slow_time) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(strip, "position:y", target_y, snapback_time) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished


func _create_strip_symbol() -> Control:
	var node := Control.new()
	node.size = CELL_SIZE
	var rect := ColorRect.new()
	rect.size = CELL_SIZE
	node.add_child(rect)
	var lbl := Label.new()
	lbl.size = CELL_SIZE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 42)
	node.add_child(lbl)
	return node


func _set_strip_symbol(node: Control, sid: int) -> void:
	var rect: ColorRect = node.get_child(0)
	var lbl: Label = node.get_child(1)
	rect.color = SymbolController.SYMBOL_COLORS.get(sid, Color.GRAY).darkened(0.5)
	lbl.text = SymbolController.SYMBOL_NAMES.get(sid, "?")


## Set strip node as a multiplier display for Free Game spin animation
var _random_mtp_values: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 25, 50, 100]

func _set_strip_mtp(node: Control, value: int) -> void:
	var rect: ColorRect = node.get_child(0)
	var lbl: Label = node.get_child(1)
	rect.color = SymbolController.SYMBOL_COLORS.get(GameManager.MTP_ID, Color.GRAY).darkened(0.5)
	lbl.text = "x%d" % value


## Animate spin with each cell as an independent mini-reel (used in Free Game)
## Hold 'n' Win: cells with MTP symbol and mtp>0 are held in place, others spin.
## prev_screen: previous screen data — cells with sid=MTP_ID are held.
func animate_spin_cells(screen_data: Array, prev_screen: Array = []) -> void:
	_animating = true
	_respin_cells_done = 0

	# Build set of previously held positions from prev_screen (sid=MTP_ID cells)
	var hold_positions := {}
	for i in range(prev_screen.size()):
		if prev_screen[i].get("sid", 0) == GameManager.MTP_ID and prev_screen[i].get("mtp", 0) > 0:
			hold_positions[i] = true

	# Classify cells: hold (existing MTP from prev_screen) vs spin (everything else)
	var hold_cells: Array = []   # [{col, row}]
	var spin_cells: Array = []   # [{col, row, sid, mtp}] — all non-hold cells
	var rows := current_rows

	for col in range(COLS):
		for row in range(rows):
			var idx: int = col * rows + row
			if idx >= screen_data.size():
				continue
			# Wild corners: update display immediately (show feature text during spin)
			if _is_wild_corner(col, row):
				var bt: int = screen_data[idx].get("bt", 0)
				cells[col][row].set_symbol(GameManager.WILD_ID, bt)
				continue
			var sid: int = screen_data[idx].get("sid", 0)
			var mtp: int = screen_data[idx].get("mtp", 0)
			# Skip Wild cells at shifted positions (after Unlock)
			if sid == GameManager.WILD_ID:
				var bt: int = screen_data[idx].get("bt", 0)
				cells[col][row].set_symbol(GameManager.WILD_ID, bt)
				continue
			# Hold cells: was MTP in prev_screen AND still MTP in current screen_data
			if hold_positions.has(idx) and sid == GameManager.MTP_ID and mtp > 0:
				hold_cells.append({"col": col, "row": row})
			else:
				spin_cells.append({"col": col, "row": row, "sid": sid, "mtp": mtp})

	# Debug: print hold/spin classification
	var hold_str := ""
	for h in hold_cells:
		hold_str += "(%d,%d) " % [h["col"], h["row"]]
	var spin_mtp_str := ""
	for s in spin_cells:
		if s["mtp"] > 0:
			spin_mtp_str += "(%d,%d)=x%d " % [s["col"], s["row"], s["mtp"]]
	var prev_pos_str := ""
	for pos in hold_positions:
		@warning_ignore("integer_division")
		prev_pos_str += "(%d,%d) " % [pos / rows, pos % rows]
	print("[FreeGame] spin_cells: %d cells, rows=%d" % [screen_data.size(), rows])
	print("[FreeGame]   prev_hold pos: %s" % prev_pos_str)
	print("[FreeGame]   hold(%d): %s" % [hold_cells.size(), hold_str])
	if spin_mtp_str.length() > 0:
		print("[FreeGame]   spin has MTP(!): %s" % spin_mtp_str)

	# Phase 1: Hold cells — show sticky border (no highlight to match new MTP cells' brightness)
	for entry in hold_cells:
		cells[entry["col"]][entry["row"]].show_sticky_border()

	# Phase 2: Dim spin cells
	var dim_tweens: Array[Tween] = []
	for entry in spin_cells:
		var dt := create_tween()
		dt.tween_property(cells[entry["col"]][entry["row"]], "modulate:a",
			RESPIN_DIM_ALPHA, RESPIN_DIM_TIME)
		dim_tweens.append(dt)
	await get_tree().create_timer(RESPIN_DIM_TIME + 0.15).timeout
	for dt in dim_tweens:
		dt.kill()

	# Phase 3: Spin all non-hold cells (multiplier reel animation)
	if spin_cells.size() == 0:
		_cleanup_hold(hold_cells)
		_animating = false
		return

	for entry in spin_cells:
		_spin_single_cell(entry["col"], entry["row"], entry["sid"],
			(entry["col"] * rows + entry["row"]) * 0.02, entry["mtp"])

	# Wait for all spin cells to finish
	while _respin_cells_done < spin_cells.size():
		await get_tree().process_frame

	# Pause so player can see the result
	await get_tree().create_timer(0.5).timeout

	# Cleanup
	_cleanup_hold(hold_cells)
	for entry in spin_cells:
		cells[entry["col"]][entry["row"]].restore_modulate()
	_animating = false


func _cleanup_hold(hold_cells: Array) -> void:
	for entry in hold_cells:
		cells[entry["col"]][entry["row"]].hide_sticky_border()


## Single-cell mini-reel for animate_spin_cells — similar to _respin_cell_reel but uses SPIN speed
func _spin_single_cell(col: int, row: int, target_sid: int, delay: float, mtp: int = 0) -> void:
	if delay > 0:
		await get_tree().create_timer(delay).timeout

	var cell: SymbolController = cells[col][row]
	var cell_pos := _cell_position(col, row)
	cell.visible = false

	var clip := Control.new()
	clip.clip_contents = true
	clip.position = cell_pos
	clip.size = CELL_SIZE
	_grid_clip.add_child(clip)
	_grid_clip.move_child(clip, 0)

	var spin_count: int = SPIN_BASE_COUNT + randi() % 6  # random length for visual variety
	var total := 1 + spin_count
	var strip := Control.new()
	clip.add_child(strip)

	var is_free_game: bool = GameManager.is_in_free_game
	var node := _create_strip_symbol()
	node.position = Vector2.ZERO
	strip.add_child(node)
	if is_free_game:
		if mtp > 0:
			_set_strip_mtp(node, mtp)
		else:
			_set_strip_mtp(node, _random_mtp_values[randi() % _random_mtp_values.size()])
	else:
		_set_strip_symbol(node, target_sid)
	for i in range(1, total):
		node = _create_strip_symbol()
		node.position = Vector2(0, i * CELL_SIZE.y)
		strip.add_child(node)
		if is_free_game:
			_set_strip_mtp(node, _random_mtp_values[randi() % _random_mtp_values.size()])
		else:
			_set_strip_symbol(node, _random_spin_symbol())

	strip.position.y = -spin_count * CELL_SIZE.y
	await _scroll_strip_anim(strip, spin_count, CELL_SIZE.y,
		SPIN_VELOCITY, SPIN_ANTICIPATION_PX, SPIN_ANTICIPATION_TIME,
		SPIN_OVERSHOOT_PX, SPIN_SNAPBACK_TIME, SPIN_DECEL_RATIO, 0.5)

	_apply_cell_symbol(cell, target_sid, mtp)
	cell.visible = true
	cell.restore_modulate()
	clip.queue_free()
	_respin_cells_done += 1


## Set visible row count (6-8) for Free Game row expansion
func set_rows(n: int) -> void:
	n = clampi(n, ROWS, MAX_ROWS)
	if n == current_rows:
		return
	var old_rows := current_rows
	current_rows = n
	# Update grid clip and frame sizes
	var grid_w: float = COLS * CELL_SIZE.x + (COLS - 1) * CELL_GAP
	var grid_h: float = current_rows * CELL_SIZE.y + (current_rows - 1) * CELL_GAP
	_grid_clip.size = Vector2(grid_w, grid_h)
	_frame.size = Vector2(grid_w + FRAME_PADDING * 2, grid_h + FRAME_PADDING * 2)
	# Show/hide rows and update wild corners
	for col in range(COLS):
		for row in range(MAX_ROWS):
			if row < current_rows:
				cells[col][row].visible = true
				if row >= old_rows:
					# Free Game: 新行用空格，set_screen 會更新正確內容
					if GameManager.is_in_free_game:
						cells[col][row].set_empty()
					else:
						cells[col][row].set_symbol(_random_spin_symbol())
			else:
				cells[col][row].visible = false
		# Update wild corners (skip in Free Game — corners managed by shift_wild_corners_down)
		if not GameManager.is_in_free_game:
			for row in [0, current_rows - 1]:
				if col == 0 or col == COLS - 1:
					cells[col][row].set_symbol(GameManager.WILD_ID)
	if not GameManager.is_in_free_game:
		_init_wild_corners()
	_fit_grid_to_viewport()
	print("[Grid] Rows changed: %d → %d" % [old_rows, current_rows])


## Shift all grid cell content down by 1 row (for first Unlock: insert row at top)
func _shift_grid_content_down() -> void:
	for col in range(COLS):
		for row in range(current_rows - 1, 0, -1):
			_copy_cell_content(cells[col][row - 1], cells[col][row])
		cells[col][0].set_empty()


## Copy visual content from one cell to another
func _copy_cell_content(src: SymbolController, dst: SymbolController) -> void:
	if src.symbol_id == GameManager.MTP_ID:
		var text: String = src.label.text
		if text.begins_with("x"):
			dst.set_multiplier_cell(text.substr(1).to_int())
		else:
			dst.set_empty()
	elif src.symbol_id > 0:
		dst.set_symbol(src.symbol_id, src.wild_sub_type)
	else:
		dst.set_empty()


## Scale grid down when expanded rows would exceed viewport height
func _fit_grid_to_viewport() -> void:
	var grid_w: float = COLS * CELL_SIZE.x + (COLS - 1) * CELL_GAP
	var grid_h: float = current_rows * CELL_SIZE.y + (current_rows - 1) * CELL_GAP
	var total_h: float = grid_h + FRAME_PADDING * 2
	var available_h: float = VIEWPORT_HEIGHT - GRID_OFFSET.y - GRID_BOTTOM_MARGIN
	var s: float = 1.0
	if total_h > available_h:
		s = available_h / total_h
	# Scale frame and grid clip together, re-centering horizontally
	var scaled_w: float = (grid_w + FRAME_PADDING * 2) * s
	var original_w: float = grid_w + FRAME_PADDING * 2
	var x_offset: float = (original_w - scaled_w) / 2.0
	_frame.scale = Vector2(s, s)
	_frame.position = Vector2(GRID_OFFSET.x - FRAME_PADDING + x_offset, GRID_OFFSET.y - FRAME_PADDING)
	_grid_clip.scale = Vector2(s, s)
	_grid_clip.position = Vector2(GRID_OFFSET.x + x_offset, GRID_OFFSET.y)


## Display corner feature labels on the four wild corners
func display_corner_assignments(assignments: Array) -> void:
	for a in assignments:
		var gr := pos_to_grid(a.get("pos", -1), current_rows)
		if gr.x >= 0 and gr.x < COLS and gr.y >= 0 and gr.y < current_rows:
			if _is_wild_corner(gr.x, gr.y):
				var ft: int = a.get("feature_type", 0)
				cells[gr.x][gr.y].set_symbol(GameManager.WILD_ID, ft)
				print("[FreeGame] Corner (%d,%d) = %s" % [gr.x, gr.y, CORNER_FEATURE_NAMES.get(ft, "?")])


## Animate corner feature activations, sorted by priority
## Priority: Generate(23) > Unlock(24) > Double(22) > Collect(21)
## pre_corner_mpi: multiplier state BEFORE any corner features (for display)
func animate_corner_features(features: Array, pre_corner_screen: Array = []) -> void:
	if features.size() == 0:
		return
	_animating = true

	# Display pre-corner screen state so MTP cells are visible during animation
	if pre_corner_screen.size() > 0:
		set_screen(pre_corner_screen)

	# Sort by feature_type priority
	var priority := {23: 0, 24: 1, 22: 2, 21: 3}
	var sorted_features := features.duplicate()
	sorted_features.sort_custom(func(a, b):
		return priority.get(a.get("feature_type", 0), 99) < priority.get(b.get("feature_type", 0), 99)
	)
	for feat in sorted_features:
		var ftype: int = feat.get("feature_type", 0)
		var pos: int = feat.get("pos", 0)
		var value: int = feat.get("value", 0)
		var feat_rows: int = feat.get("rows", current_rows)
		if feat_rows <= 0:
			feat_rows = current_rows
		var gr := pos_to_grid(pos, feat_rows)
		var fname: String = CORNER_FEATURE_NAMES.get(ftype, "?")
		print("[FreeGame] Corner feature: %s at (%d,%d) value=%d rows=%d" % [fname, gr.x, gr.y, value, feat_rows])

		# Flash the corner cell — await tween completion
		if gr.x < COLS and gr.y < current_rows:
			var corner_tween = cells[gr.x][gr.y].play_wild_effect(GameManager.WILD_EFFECT_EXTEND, true)
			if corner_tween:
				await corner_tween.finished

		match ftype:
			24:  # Unlock — value = 擴展後的總行數
				if value >= ROWS and value <= MAX_ROWS:
					var old_rows := current_rows
					if old_rows == ROWS:  # 6→7: 第一次 Unlock，上方加列
						shift_wild_corners_down()
					set_rows(value)
					if old_rows == ROWS:
						_shift_grid_content_down()
					# 7→8: 第二次 Unlock，底部加列，角落不動（新列在最下方）
				await get_tree().create_timer(0.5).timeout

			23:  # Generate — animate new multiplier positions popping in
				var gen_mpi: Array = feat.get("generated_mpi", [])
				if gen_mpi.size() > 0:
					for m in gen_mpi:
						var mpos: int = m.get("pos", -1)
						var mval: int = m.get("value", 1)
						if mpos < 0 or mval <= 0:
							continue
						var mgr := pos_to_grid(mpos, feat_rows)
						if mgr.x < COLS and mgr.y < current_rows:
							var cell: SymbolController = cells[mgr.x][mgr.y]
							cell.modulate.a = 0.0
							cell.scale = Vector2(0.3, 0.3)
							cell.set_multiplier_cell(mval)
							var tween := create_tween().set_parallel(true)
							tween.tween_property(cell, "scale", Vector2.ONE, 0.35) \
								.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
							tween.tween_property(cell, "modulate:a", 1.0, 0.2)
							await tween.finished
							await get_tree().create_timer(0.15).timeout
				else:
					await get_tree().create_timer(0.5).timeout

			22:  # Double — only highlight and double BFS-adjacent cells from backend
				var affected: Array = feat.get("affected_mpi", [])
				if affected.size() > 0:
					for m in affected:
						var mpos: int = m.get("pos", -1)
						var mgr := pos_to_grid(mpos, feat_rows)
						if mgr.x < COLS and mgr.y < current_rows:
							cells[mgr.x][mgr.y].highlight(Color.YELLOW)
					await get_tree().create_timer(0.8).timeout
					for m in affected:
						var mpos: int = m.get("pos", -1)
						var mval: int = m.get("value", 1)
						var mgr := pos_to_grid(mpos, feat_rows)
						if mgr.x < COLS and mgr.y < current_rows:
							cells[mgr.x][mgr.y].set_multiplier_cell(mval)
					await get_tree().create_timer(0.5).timeout
				else:
					await get_tree().create_timer(0.5).timeout

			21:  # Collect — highlight MTP cells, show total, then clear board
				var collect_cells: Array = []
				for col in range(COLS):
					for row in range(current_rows):
						if cells[col][row].symbol_id == GameManager.MTP_ID:
							cells[col][row].highlight(Color.CYAN)
							collect_cells.append(cells[col][row])
				if collect_cells.size() > 0:
					await get_tree().create_timer(0.8).timeout
					for cell in collect_cells:
						cell.set_empty()
				await get_tree().create_timer(0.5).timeout

	_animating = false


## Display multiplier positions as MTP cells (without clearing existing non-MTP cells)
func _display_mpi_as_cells(mpi: Array) -> void:
	for m in mpi:
		var pos: int = m.get("pos", -1)
		var value: int = m.get("value", 1)
		if pos < 0 or value <= 0:
			continue
		var gr := pos_to_grid(pos, current_rows)
		if gr.x < COLS and gr.y < current_rows:
			cells[gr.x][gr.y].set_multiplier_cell(value)



## Set up Free Game grid: corners with feature from screen Wild bt, others empty
func setup_free_game_grid(fg_screen: Array) -> void:
	_init_wild_corners()
	clear_multipliers()
	for col in range(COLS):
		for row in range(current_rows):
			var idx: int = col * current_rows + row
			if _is_wild_corner(col, row) and idx < fg_screen.size():
				var bt: int = fg_screen[idx].get("bt", 0)
				cells[col][row].set_symbol(GameManager.WILD_ID, bt)
			elif _is_wild_corner(col, row):
				cells[col][row].set_symbol(GameManager.WILD_ID)
			else:
				cells[col][row].set_empty()


## Animate multipliers appearing one by one with a pop-in effect
func animate_multipliers_appear(mpi: Array) -> void:
	_animating = true
	for m in mpi:
		var pos: int = m.get("pos", -1)
		var value: int = m.get("value", 1)
		if pos < 0 or value <= 0:
			continue
		var gr := pos_to_grid(pos, current_rows)
		if gr.x < COLS and gr.y < current_rows:
			var cell: SymbolController = cells[gr.x][gr.y]
			# Start invisible and scaled down
			cell.modulate.a = 0.0
			cell.scale = Vector2(0.3, 0.3)
			cell.set_multiplier_cell(value)
			# Pop-in: scale + fade
			var tween := create_tween().set_parallel(true)
			tween.tween_property(cell, "scale", Vector2.ONE, 0.35) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(cell, "modulate:a", 1.0, 0.2)
			await tween.finished
			await get_tree().create_timer(0.25).timeout
	_animating = false


func is_animating() -> bool:
	return _animating
