extends Control

## HUD: displays balance, bet amount, win amount, free game info

signal spin_requested(arena_code: String)

@onready var balance_label: Label = $BalanceLabel
@onready var bet_label: Label = $BetLabel
@onready var win_label: Label = $WinLabel
@onready var free_game_label: Label = $FreeGameLabel
@onready var spin_button: Button = $SpinButton
@onready var bet_up_button: Button = $BetUpButton
@onready var bet_down_button: Button = $BetDownButton
@onready var bonus_bet_button: Button = $BonusBetButton
@onready var buy_fg_button: Button = $BuyFGButton
@onready var buy_wild_button: Button = $BuyWildButton
@onready var buy_confirm_dialog: Panel = $BuyConfirmDialog
@onready var rules_button: Button = $RulesButton
@onready var game_rules: Panel = $GameRules

var _conn_label: Label = null


func _ready() -> void:
	GameManager.balance_changed.connect(_on_balance_changed)
	GameManager.bet_changed.connect(_on_bet_changed)
	GameManager.game_state_changed.connect(_on_state_changed)
	GameManager.free_game_started.connect(_on_free_game_started)
	GameManager.free_game_ended.connect(_on_free_game_ended)
	NetworkManager.connected.connect(_on_network_connected)
	NetworkManager.disconnected.connect(_on_network_disconnected)

	spin_button.pressed.connect(_on_spin_pressed)
	bet_up_button.pressed.connect(_on_bet_up)
	bet_down_button.pressed.connect(_on_bet_down)
	bonus_bet_button.toggled.connect(_on_bonus_bet_toggled)
	buy_fg_button.pressed.connect(_on_buy_fg)
	buy_wild_button.pressed.connect(_on_buy_wild)
	buy_confirm_dialog.confirmed.connect(_on_buy_confirmed)
	rules_button.pressed.connect(_on_rules_pressed)

	# Connection status indicator
	_conn_label = Label.new()
	_conn_label.name = "ConnLabel"
	_conn_label.position = Vector2(1750, 20)
	_conn_label.size = Vector2(150, 30)
	_conn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_conn_label.add_theme_font_size_override("font_size", 14)
	_conn_label.visible = false
	add_child(_conn_label)

	_update_display()


func _on_balance_changed(new_balance: float) -> void:
	balance_label.text = "Balance: %.2f" % new_balance


func _on_bet_changed(_new_bet: float) -> void:
	_update_bet_display()
	_update_buttons()


func _on_state_changed(new_state: int) -> void:
	_update_buttons()
	match new_state:
		GameManager.GameState.IDLE:
			free_game_label.visible = false
		GameManager.GameState.SPINNING:
			win_label.text = "Win: --"
		GameManager.GameState.FREE_GAME_IDLE:
			free_game_label.visible = true
			free_game_label.text = "FREE SPINS: %d" % GameManager.free_game_left_rounds


func update_free_game_info(left_rounds: int, reset: bool = false) -> void:
	free_game_label.visible = true
	if reset:
		free_game_label.text = "SPINS RESET! FREE SPINS: %d" % left_rounds
	else:
		free_game_label.text = "FREE SPINS: %d" % left_rounds


func update_free_game_multipliers(board_sum: int, collect_total: int) -> void:
	var text := "Board: x%d" % board_sum
	if collect_total > 0:
		text += "  Collect: x%d" % collect_total
	win_label.text = text


func update_win(total_win: float) -> void:
	if total_win > 0:
		win_label.text = "Win: %.2f" % total_win
	else:
		win_label.text = "Win: 0.00"


func _on_free_game_started(_fgis: Dictionary) -> void:
	free_game_label.visible = true
	free_game_label.text = "FREE GAME START!"


func _on_free_game_ended(total_win: float) -> void:
	free_game_label.text = "FREE GAME END - Total: %.2f" % total_win
	await get_tree().create_timer(2.0).timeout
	free_game_label.visible = false


func _on_network_connected() -> void:
	if _conn_label:
		_conn_label.text = "Connected"
		_conn_label.add_theme_color_override("font_color", Color.GREEN)
		_conn_label.visible = true
		await get_tree().create_timer(2.0).timeout
		if _conn_label:
			_conn_label.visible = false


func _on_network_disconnected() -> void:
	if _conn_label:
		_conn_label.text = "Disconnected"
		_conn_label.add_theme_color_override("font_color", Color.RED)
		_conn_label.visible = true


func _on_spin_pressed() -> void:
	if GameManager.is_in_free_game:
		spin_requested.emit(GameManager.current_arena)
	elif GameManager.bonus_bet_active:
		spin_requested.emit(GameManager.ARENA_BONUS_BET)
	else:
		spin_requested.emit(GameManager.ARENA_NORMAL)


func _on_bet_up() -> void:
	GameManager.chip_index += 1


func _on_bet_down() -> void:
	GameManager.chip_index -= 1


func _on_bonus_bet_toggled(toggled_on: bool) -> void:
	GameManager.bonus_bet_active = toggled_on
	_update_bet_display()


func _on_buy_fg() -> void:
	if GameManager.can_buy_free_game():
		var cost := GameManager.get_pay_amount(GameManager.ARENA_BUY_FREE_GAME)
		buy_confirm_dialog.show_dialog(GameManager.ARENA_BUY_FREE_GAME, cost)


func _on_buy_wild() -> void:
	if GameManager.can_buy_wild():
		var cost := GameManager.get_pay_amount(GameManager.ARENA_BUY_WILD)
		buy_confirm_dialog.show_dialog(GameManager.ARENA_BUY_WILD, cost)


func _on_buy_confirmed(arena_code: String) -> void:
	spin_requested.emit(arena_code)


func _on_rules_pressed() -> void:
	if game_rules:
		game_rules.show_rules()


func _update_buttons() -> void:
	var is_idle: bool = GameManager.current_state == GameManager.GameState.IDLE
	var is_fg_idle: bool = GameManager.current_state == GameManager.GameState.FREE_GAME_IDLE
	spin_button.disabled = not (is_idle or is_fg_idle)
	bet_up_button.disabled = not is_idle
	bet_down_button.disabled = not is_idle
	bonus_bet_button.disabled = not is_idle
	bonus_bet_button.visible = not GameManager.is_in_free_game
	buy_fg_button.disabled = not GameManager.can_buy_free_game()
	buy_wild_button.disabled = not GameManager.can_buy_wild()
	buy_fg_button.visible = not GameManager.is_in_free_game
	buy_wild_button.visible = not GameManager.is_in_free_game


func _update_bet_display() -> void:
	var base_bet := GameManager.get_bet_amount()
	if GameManager.bonus_bet_active:
		bet_label.text = "Bet: %.2f (x%.1f)" % [base_bet * GameManager.BONUS_BET_MULTIPLIER, GameManager.BONUS_BET_MULTIPLIER]
	else:
		bet_label.text = "Bet: %.2f" % base_bet


func _update_display() -> void:
	balance_label.text = "Balance: %.2f" % GameManager.balance
	_update_bet_display()
	win_label.text = "Win: 0.00"
	free_game_label.visible = false
