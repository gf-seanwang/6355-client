extends Node

## Singleton: handles WebSocket connection and protobuf communication

const _ProtoParser = preload("res://scripts/proto/proto_parser.gd")

signal connected()
signal disconnected()
signal game_base_info_received(info: Dictionary)
signal spin_response_received(response: Dictionary)
signal error_received(error_code: int)

var _ws: WebSocketPeer = null
var _connected: bool = false
var _server_url: String = "ws://localhost:8355/game"

## Reconnection state
var _reconnect_attempts: int = 0
var _max_reconnect_attempts: int = 5
var _reconnect_timer: float = 0.0
var _reconnecting: bool = false

## Mock mode: when true, generates local spin results without server
var mock_mode: bool = false


func _ready() -> void:
	game_base_info_received.connect(_on_game_base_info)
	if not mock_mode:
		_connect_to_server()
	else:
		# In mock mode, simulate connection
		call_deferred("_on_mock_connected")


func _on_mock_connected() -> void:
	_connected = true
	connected.emit()
	# Send mock game base info (handler will set balance & state)
	var base_info := {
		"chip_setting": "0.1,0.2,0.5,1,2,5,10,20,50,100",
		"last_screen_info": null
	}
	game_base_info_received.emit(base_info)


func _on_game_base_info(info: Dictionary) -> void:
	print("[NetworkManager] Received GameBaseInfo: chip_setting=%s" % str(info.get("chip_setting", "")))
	var chip_setting = info.get("chip_setting", "")
	if chip_setting is String and not chip_setting.is_empty():
		GameManager.parse_chip_setting(chip_setting)
	GameManager.balance = 999999.0
	GameManager.current_state = GameManager.GameState.IDLE


func _connect_to_server() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 8388608  # 8MB — Buy Free Game can produce 5MB+ responses
	_ws.outbound_buffer_size = 65536   # 64KB — client sends are small
	var err := _ws.connect_to_url(_server_url)
	if err != OK:
		push_error("WebSocket connection failed: %d" % err)
		_start_reconnect()


func _start_reconnect() -> void:
	if mock_mode or _reconnect_attempts >= _max_reconnect_attempts:
		if _reconnect_attempts >= _max_reconnect_attempts:
			push_error("Max reconnect attempts reached (%d)" % _max_reconnect_attempts)
		return
	_reconnect_attempts += 1
	# Exponential backoff: 2s, 4s, 8s, 16s, 32s
	_reconnect_timer = pow(2.0, _reconnect_attempts)
	_reconnecting = true
	print("Reconnecting in %.0fs (attempt %d/%d)..." % [_reconnect_timer, _reconnect_attempts, _max_reconnect_attempts])


func _attempt_reconnect() -> void:
	print("Attempting reconnect #%d..." % _reconnect_attempts)
	_connect_to_server()


func _process(delta: float) -> void:
	# Handle reconnection timer
	if _reconnecting:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_reconnecting = false
			_attempt_reconnect()
		return

	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_reconnect_attempts = 0
				print("[NetworkManager] Connected to %s" % _server_url)
				connected.emit()
			while _ws.get_available_packet_count() > 0:
				var packet := _ws.get_packet()
				_handle_server_message(packet)
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				disconnected.emit()
			_ws = null
			_start_reconnect()


func send_spin_request(chip_idx: int, arena_code: String) -> void:
	if mock_mode:
		_generate_mock_spin(chip_idx, arena_code)
		return
	if not _connected:
		push_error("Not connected to server")
		return
	var data := _ProtoParser.encode_spin_request(chip_idx, arena_code)
	_ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)


func _handle_server_message(packet: PackedByteArray) -> void:
	var updates := _ProtoParser.decode_all_updates(packet)
	if updates.is_empty():
		push_warning("NetworkManager: received empty or unparseable message")
		return

	for parsed in updates:
		match parsed.get("_type", ""):
			"game_base_info":
				game_base_info_received.emit(parsed["data"])
			"spin_response":
				var response: Dictionary = parsed["data"]
				spin_response_received.emit(response)
				GameManager.on_spin_response(response)
			"error":
				var code: int = parsed.get("error_code", -1)
				push_error("Server error code: %d" % code)
				error_received.emit(code)


## Mock spin result generator for testing without server
func _generate_mock_spin(chip_idx: int, arena_code: String) -> void:
	await get_tree().create_timer(0.3).timeout

	var bet_amount: float = GameManager.CHIP_OPTIONS[chip_idx] * GameManager.BET_LEVEL
	var screen := _generate_random_screen()
	# 四個角落永遠是 Wild
	for pos in [0, 5, 30, 35]:
		screen[pos]["sid"] = GameManager.WILD_ID
	var elims := _find_clusters(screen)
	var win_score := 0.0
	for e in elims:
		win_score += e.get("ws", 0.0)

	var screen_info := {
		"screen": screen,
		"elims": elims,
		"ws": win_score,
		"stws": win_score,
		"stg": 1,
		"eostg": true,
		"dsp": [],
		"we": [],
		"fg": null,
		"fgis": null,
		"bala": GameManager.balance - bet_amount + win_score,
	}

	var round_results := [screen_info]

	# Check for scatter (mock: ~5% chance of 3+ scatter)
	var scatter_count := 0
	for sym in screen:
		if sym.get("sid", 0) == GameManager.SCATTER_ID:
			scatter_count += 1

	if scatter_count >= GameManager.FREE_GAME_SCATTER_THRESHOLD and arena_code != GameManager.ARENA_BUY_FREE_GAME:
		# Free game trigger
		var fg_multipliers := _generate_mock_multipliers()
		screen_info["fgis"] = {
			"fgsct": scatter_count,
			"fgct": GameManager.FREE_GAME_ROUNDS,
			"ac": arena_code,
		}
		# Generate free game rounds
		var fg_rounds := _generate_mock_fg_rounds(GameManager.FREE_GAME_ROUNDS, win_score, fg_multipliers)
		if fg_rounds.size() > 0:
			win_score = fg_rounds[-1].get("stws", win_score)
		round_results.append_array(fg_rounds)

	if arena_code == GameManager.ARENA_BUY_FREE_GAME:
		bet_amount = GameManager.get_pay_amount(arena_code)
		var fg_multipliers := _generate_mock_multipliers()
		screen_info["fgis"] = {
			"fgsct": GameManager.FREE_GAME_SCATTER_THRESHOLD,
			"fgct": GameManager.FREE_GAME_ROUNDS,
			"ac": arena_code,
		}
		var buy_fg_rounds := _generate_mock_fg_rounds(GameManager.FREE_GAME_ROUNDS, win_score, fg_multipliers)
		if buy_fg_rounds.size() > 0:
			win_score = buy_fg_rounds[-1].get("stws", win_score)
		round_results.append_array(buy_fg_rounds)

	if arena_code == GameManager.ARENA_BUY_WILD:
		bet_amount = GameManager.get_pay_amount(arena_code)

	var back_to_main: Variant = null
	if GameManager.is_in_free_game:
		# If this was the last free game round, include back_to_main_game
		if GameManager.free_game_left_rounds <= 1:
			back_to_main = {"screen": _generate_random_screen()}

	var response := {
		"round_result_list": round_results,
		"back_to_main_game": back_to_main,
		"bet_amount": bet_amount,
		"pay_amount": win_score,
		"balance": GameManager.balance - bet_amount + win_score,
	}

	spin_response_received.emit(response)
	GameManager.on_spin_response(response)


func _generate_random_screen() -> Array:
	var symbols := [1, 2, 3, 11, 12, 13, 14, 15, 16]
	var screen := []
	for i in range(GameManager.SCREEN_COLS * GameManager.SCREEN_ROWS):
		var sid: int
		if randf() < 0.02:
			sid = GameManager.SCATTER_ID  # Scatter
		else:
			sid = symbols[randi() % symbols.size()]
		screen.append({"sid": sid, "pos": i})
	return screen


func _find_clusters(screen: Array) -> Array:
	# Simplified cluster detection for mock
	# Just check if there are groups of same symbols
	var cols := GameManager.SCREEN_COLS
	var rows := GameManager.SCREEN_ROWS
	var grid := []
	for col in range(cols):
		var column := []
		for row in range(rows):
			column.append(screen[col * rows + row].get("sid", 0))
		grid.append(column)

	var visited := []
	for col in range(cols):
		var row_flags := []
		row_flags.resize(rows)
		row_flags.fill(false)
		visited.append(row_flags)

	var elims := []
	var dx := [0, 1, 0, -1]
	var dy := [1, 0, -1, 0]

	for col in range(cols):
		for row in range(rows):
			if visited[col][row] or grid[col][row] == GameManager.WILD_ID or grid[col][row] == GameManager.SCATTER_ID:
				continue
			# BFS
			var target_id: int = grid[col][row]
			var stack := [[col, row]]
			var cluster := []
			while stack.size() > 0:
				var pos: Array = stack.pop_back()
				var c: int = pos[0]
				var r: int = pos[1]
				if c < 0 or c >= cols or r < 0 or r >= rows:
					continue
				if visited[c][r]:
					continue
				if grid[c][r] != target_id and grid[c][r] != GameManager.WILD_ID:
					continue
				visited[c][r] = true
				cluster.append(c * rows + r)
				for d in range(4):
					stack.append([c + dx[d], r + dy[d]])

			if cluster.size() >= cols:
				# Calculate mock win
				var payout := 0.0
				match target_id:
					1: payout = 1.5
					2: payout = 1.2
					3: payout = 0.8
					11: payout = 0.5
					12: payout = 0.4
					13: payout = 0.3
					14: payout = 0.25
					15: payout = 0.15
					16: payout = 0.15
				var win_score: float = payout * GameManager.get_bet_amount()
				elims.append({
					"sid": target_id,
					"wp": cluster,
					"ws": win_score,
				})

	return elims


func _generate_mock_multipliers() -> Array:
	var multiplier_values := [2, 3, 5]
	var mults := []
	var used := {}
	for _i in range(3):  # FREE_GAME_MULTIPLIER_COUNT = 3
		var pos: int = randi() % (GameManager.SCREEN_COLS * GameManager.SCREEN_ROWS)
		while used.has(pos):
			pos = randi() % (GameManager.SCREEN_COLS * GameManager.SCREEN_ROWS)
		used[pos] = true
		mults.append({"pos": pos, "value": multiplier_values[randi() % multiplier_values.size()]})
	return mults


func _generate_mock_fg_rounds(count: int, base_win: float, multipliers: Array = []) -> Array:
	var rounds := []
	var accumulated_win := base_win
	for i in range(count):
		var fg_screen := _generate_random_screen()
		var fg_elims := _find_clusters(fg_screen)
		var fg_win := 0.0
		for e in fg_elims:
			fg_win += e.get("ws", 0.0)
		# Apply multipliers to wins on matching positions
		for e in fg_elims:
			for m in multipliers:
				if m.get("pos", -1) in e.get("wp", []):
					fg_win += e.get("ws", 0.0) * (m.get("value", 1) - 1)
					break
		accumulated_win += fg_win
		rounds.append({
			"screen": fg_screen,
			"elims": fg_elims,
			"ws": fg_win,
			"stws": accumulated_win,
			"stg": 1,
			"eostg": true,
			"dsp": [],
			"we": [],
			"mpi": multipliers,
			"fg": {"tws": accumulated_win, "lr": count - i - 1, "tr": count, "ar": 0},
		})
	return rounds
