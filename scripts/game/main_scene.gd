extends Control

## Root scene: manages game state transitions and sub-scenes

@onready var grid: GridController = $Grid
@onready var hud: Control = $HUD
@onready var big_win: Control = $BigWin
@onready var free_game_intro: Control = $FreeGameIntro
@onready var main_game: MainGameController = $MainGameController
@onready var bg_rect: ColorRect = $BgRect
@onready var loading_screen: Control = $Loading


func _ready() -> void:
	# Wire up main game controller references
	main_game.grid = grid
	main_game.hud = hud
	main_game.win_presenter = big_win
	main_game.free_game_intro_handler = _handle_free_game_intro

	# Connect signals
	hud.spin_requested.connect(main_game.request_spin)
	main_game.round_complete.connect(hud.update_win)
	GameManager.free_game_ended.connect(_on_free_game_ended)
	GameManager.game_state_changed.connect(_on_state_changed)
	NetworkManager.connected.connect(_on_network_connected)

	# Set background
	bg_rect.color = Color(0.12, 0.15, 0.2, 1.0)

	# Show loading screen initially, hide game elements
	loading_screen.visible = true
	grid.visible = false
	hud.visible = false


func _on_state_changed(new_state: int) -> void:
	match new_state:
		GameManager.GameState.FREE_GAME_END:
			pass  # HUD handles the display


## Staged Free Game intro: popup → empty grid → animate multipliers
func _handle_free_game_intro(fgis: Dictionary, fg_init_screen: Array = []) -> void:
	var count: int = fgis.get("fgct", 3)
	GameManager.start_free_game(fgis)

	# Stage 1: Congratulations popup with CONTINUE button
	await _show_free_game_popup(count)

	# Stage 2: Show empty Free Game grid with corner features from screen Wild bt
	grid.set_rows(GridController.ROWS)
	grid.setup_free_game_grid(fg_init_screen)

	await get_tree().create_timer(0.8).timeout

	# Stage 3: Animate initial multipliers from fgis.multipliers
	var multipliers: Array = fgis.get("multipliers", [])
	if multipliers.size() > 0:
		await grid.animate_multipliers_appear(multipliers)

	await get_tree().create_timer(0.5).timeout

	GameManager.current_state = GameManager.GameState.FREE_GAME_IDLE


func _show_free_game_popup(rounds: int) -> void:
	free_game_intro.visible = true
	free_game_intro.modulate.a = 0.0
	var count_label: Label = free_game_intro.get_node("CountLabel")
	count_label.text = "%d FREE SPINS" % rounds
	var btn: Button = free_game_intro.get_node("ContinueButton")

	# Fade in
	var tween := create_tween()
	tween.tween_property(free_game_intro, "modulate:a", 1.0, 0.3)
	await tween.finished

	# Wait for CONTINUE button click
	await btn.pressed

	# Fade out
	var tween2 := create_tween()
	tween2.tween_property(free_game_intro, "modulate:a", 0.0, 0.3)
	await tween2.finished
	free_game_intro.visible = false


func _on_network_connected() -> void:
	# Loading screen handles its own fade-out via NetworkManager.connected
	grid.visible = true
	hud.visible = true


func _on_free_game_ended(_total_win: float) -> void:
	await get_tree().create_timer(2.0).timeout
	GameManager.current_state = GameManager.GameState.IDLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		# Space bar = spin
		if GameManager.current_state == GameManager.GameState.IDLE:
			main_game.request_spin()
		elif GameManager.current_state == GameManager.GameState.FREE_GAME_IDLE:
			main_game.request_spin(GameManager.current_arena)
