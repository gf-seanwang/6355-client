extends Control

## Big Win presentation with tiered celebration

signal presentation_complete()

const WIN_TIERS := {
	10.0: "JAMMIN!",
	25.0: "SUPER DAZZLING!",
	50.0: "BELLISSIMO!",
	100.0: "GOBLET TIME!",
}

@onready var win_label: Label = $WinLabel
@onready var tier_label: Label = $TierLabel
@onready var _panel: Panel = $Panel


func _ready() -> void:
	visible = false


func show_big_win(win_amount: float, win_ratio: float) -> void:
	visible = true

	var tier_name := "BIG WIN!"
	for threshold in WIN_TIERS.keys():
		if win_ratio >= threshold:
			tier_name = WIN_TIERS[threshold]

	tier_label.text = tier_name

	var duration := clampf(win_ratio * 0.05, 1.0, 5.0)
	var tween := create_tween()

	tween.tween_method(func(v: float):
		win_label.text = "%.2f" % v
	, 0.0, win_amount, duration)

	tween.tween_interval(1.5)
	tween.tween_callback(func():
		visible = false
		presentation_complete.emit()
	)
