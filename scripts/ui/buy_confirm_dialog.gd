extends Panel

## Confirmation dialog for Buy Free Game / Buy Wild feature purchases.

signal confirmed(arena_code: String)
signal cancelled()

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var cost_label: Label = $VBoxContainer/CostLabel
@onready var confirm_button: Button = $VBoxContainer/HBoxContainer/ConfirmButton
@onready var cancel_button: Button = $VBoxContainer/HBoxContainer/CancelButton

var _arena_code: String = ""


func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm)
	cancel_button.pressed.connect(_on_cancel)
	visible = false


## Shows the dialog for the given arena code and cost.
func show_dialog(arena_code: String, cost: float) -> void:
	_arena_code = arena_code
	match arena_code:
		GameManager.ARENA_BUY_FREE_GAME:
			title_label.text = "Buy Free Game?"
			cost_label.text = "Cost: %.2f (%dx bet)" % [cost, GameManager.BUY_FREE_GAME_MULTIPLIER]
		GameManager.ARENA_BUY_WILD:
			title_label.text = "Buy Wild Activation?"
			cost_label.text = "Cost: %.2f (%dx bet)" % [cost, GameManager.BUY_WILD_MULTIPLIER]
		_:
			title_label.text = "Confirm Purchase?"
			cost_label.text = "Cost: %.2f" % cost
	visible = true


func _on_confirm() -> void:
	visible = false
	confirmed.emit(_arena_code)


func _on_cancel() -> void:
	visible = false
	cancelled.emit()
