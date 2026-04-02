extends Control

## Loading screen: shows on startup, hides when NetworkManager connects.

@onready var status_label: Label = $StatusLabel
@onready var progress_bar: ProgressBar = $ProgressBar

var _tween: Tween = null


func _ready() -> void:
	visible = true
	NetworkManager.connected.connect(_on_connected)
	_start_progress_animation()


func _start_progress_animation() -> void:
	status_label.text = "Loading..."
	progress_bar.value = 0.0
	_tween = create_tween().set_loops()
	_tween.tween_property(progress_bar, "value", 90.0, 2.0)
	_tween.tween_property(progress_bar, "value", 0.0, 0.5)


func _on_connected() -> void:
	if _tween:
		_tween.kill()
	status_label.text = "Connected!"
	progress_bar.value = 100.0
	var fade_tween := create_tween()
	fade_tween.tween_interval(0.5)
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	fade_tween.tween_callback(_hide_and_cleanup)


func _hide_and_cleanup() -> void:
	visible = false
	modulate.a = 1.0
