extends Node

## Singleton: manages game state, balance, bet settings

signal balance_changed(new_balance: float)
signal bet_changed(new_bet: float)
signal game_state_changed(new_state: int)
signal spin_result_received(result: Dictionary)
signal free_game_started(initial_state: Dictionary)
signal free_game_ended(total_win: float)

enum GameState {
	LOADING,
	IDLE,
	SPINNING,
	CASCADING,
	WILD_EFFECTS,
	SCATTER_CHECK,
	RESPIN,
	FREE_GAME_INTRO,
	FREE_GAME_IDLE,
	FREE_GAME_SPINNING,
	FREE_GAME_CASCADING,
	FREE_GAME_RESULT,
	FREE_GAME_END,
	BIG_WIN,
	RESULT,
}

var CHIP_OPTIONS := [0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0]

const ARENA_NORMAL := "11"
const ARENA_BONUS_BET := "12"
const ARENA_BUY_FREE_GAME := "13"
const ARENA_BUY_WILD := "14"

const BONUS_BET_MULTIPLIER := 1.5
const BUY_FREE_GAME_MULTIPLIER := 100
const BUY_WILD_MULTIPLIER := 10

var bonus_bet_active: bool = false

const SCREEN_COLS := 6
const SCREEN_ROWS := 6

const WILD_ID := 91
const SCATTER_ID := 92
const MTP_ID := 21

const WILD_EFFECT_MYSTERY := "mystery"
const WILD_EFFECT_EXTEND := "extend"
const WILD_EFFECT_MTP := "mtp"
const WILD_EFFECT_UPGRADE := "upgrade"
const WILD_EFFECT_AWARD := "award"

const WILD_MYSTERY_BT := 10  # 問號百搭 (BorderType 值)

# Wild sub-type IDs (odd = Normal, even = Super) — 與後端一致
const WILD_SUB_MTP_NORMAL := 11
const WILD_SUB_MTP_SUPER := 12
const WILD_SUB_UPGRADE_NORMAL := 13
const WILD_SUB_UPGRADE_SUPER := 14
const WILD_SUB_AWARD_NORMAL := 15
const WILD_SUB_AWARD_SUPER := 16
const WILD_SUB_EXTEND_NORMAL := 17
const WILD_SUB_EXTEND_SUPER := 18

# Priority order: Super Extend > Extend > Super Upgrade > Upgrade > MTP > Super Award > Award
# Mystery 的最高優先序由排序邏輯中 effect_type 檢查處理
const WILD_EFFECT_PRIORITY := {
	18: 1,  # Extend Super
	17: 2,  # Extend Normal
	14: 3,  # Upgrade Super
	13: 4,  # Upgrade Normal
	12: 5,  # MTP Super
	11: 6,  # MTP Normal
	16: 7,  # Award Super
	15: 8,  # Award Normal
}

static func is_super_wild(sub_type: int) -> bool:
	return sub_type > 0 and sub_type % 2 == 0

const BIG_WIN_THRESHOLD := 10.0
const FREE_GAME_SCATTER_THRESHOLD := 5
const FREE_GAME_ROUNDS := 3

var balance: float = 0.0:
	set(v):
		balance = v
		balance_changed.emit(v)

var chip_index: int = 3:
	set(v):
		chip_index = clampi(v, 0, CHIP_OPTIONS.size() - 1)
		bet_changed.emit(get_bet_amount())

var current_state: GameState = GameState.LOADING:
	set(v):
		current_state = v
		game_state_changed.emit(v)

var current_arena: String = ARENA_NORMAL
var last_spin_response: Dictionary = {}
var is_in_free_game: bool = false
var free_game_left_rounds: int = 0
var free_game_total_rounds: int = 0
var free_game_total_win: float = 0.0


func get_bet_amount() -> float:
	return CHIP_OPTIONS[chip_index]


func get_pay_amount(arena_code: String = "") -> float:
	if arena_code == "":
		arena_code = current_arena
	match arena_code:
		ARENA_BONUS_BET:
			return get_bet_amount() * BONUS_BET_MULTIPLIER
		ARENA_BUY_FREE_GAME:
			return get_bet_amount() * BUY_FREE_GAME_MULTIPLIER
		ARENA_BUY_WILD:
			return get_bet_amount() * BUY_WILD_MULTIPLIER
		_:
			return get_bet_amount()


func parse_chip_setting(setting_str: String) -> void:
	# Format: JSON object like {"11":"[0.2,0.5,1,...]","12":"[...]",...}
	var json := JSON.new()
	if json.parse(setting_str) == OK and json.data is Dictionary:
		var data: Dictionary = json.data
		# Use arena "11" (normal) chip list
		var arena_str = data.get("11", "")
		if arena_str is String and not arena_str.is_empty():
			var inner := JSON.new()
			if inner.parse(arena_str) == OK and inner.data is Array:
				CHIP_OPTIONS = inner.data
				chip_index = clampi(chip_index, 0, CHIP_OPTIONS.size() - 1)
				return
	# Fallback: try comma-separated format
	if setting_str.contains(",") and not setting_str.contains("{"):
		var parts := setting_str.split(",")
		var chips := []
		for p in parts:
			var v := p.strip_edges().to_float()
			if v > 0.0:
				chips.append(v)
		if chips.size() > 0:
			CHIP_OPTIONS = chips
			chip_index = clampi(chip_index, 0, CHIP_OPTIONS.size() - 1)


func can_spin() -> bool:
	return current_state == GameState.IDLE and balance >= get_pay_amount()


func can_buy_free_game() -> bool:
	return current_state == GameState.IDLE and balance >= get_pay_amount(ARENA_BUY_FREE_GAME)


func can_buy_wild() -> bool:
	return current_state == GameState.IDLE and balance >= get_pay_amount(ARENA_BUY_WILD)


func request_spin(arena_code: String = ARENA_NORMAL) -> void:
	if current_state != GameState.IDLE and current_state != GameState.FREE_GAME_IDLE:
		return
	current_arena = arena_code
	if is_in_free_game:
		current_state = GameState.FREE_GAME_SPINNING
	else:
		current_state = GameState.SPINNING
	NetworkManager.send_spin_request(chip_index, arena_code)


func on_spin_response(response: Dictionary) -> void:
	last_spin_response = response
	balance = response.get("balance", balance)
	spin_result_received.emit(response)


func start_free_game(fgis: Dictionary) -> void:
	is_in_free_game = true
	free_game_left_rounds = fgis.get("fgct", 3)
	free_game_total_rounds = free_game_left_rounds
	free_game_total_win = 0.0
	current_state = GameState.FREE_GAME_INTRO
	free_game_started.emit(fgis)


func end_free_game() -> void:
	is_in_free_game = false
	var total_win := free_game_total_win
	free_game_left_rounds = 0
	free_game_total_rounds = 0
	free_game_total_win = 0.0
	current_state = GameState.FREE_GAME_END
	free_game_ended.emit(total_win)


func _ready() -> void:
	current_state = GameState.LOADING
