extends Control
class_name SymbolController

## Controls a single symbol cell in the 6x6 grid

signal clicked()

const SYMBOL_NAMES := {
	1: "H1", 2: "H2", 3: "H3", 4: "H4", 5: "H5", 6: "H6",
	11: "N1", 12: "N2", 13: "N3",
	21: "MTP",
	91: "W", 92: "SC",
}

const FONT_SIZE_WILD := 28
const FONT_SIZE_DEFAULT := 48

const CORNER_FEATURE_NAMES := {21: "Collect", 22: "Double", 23: "Generate", 24: "Unlock"}

const WILD_EFFECT_NAMES := {
	10: "?",  # Mystery (問號)
	11: "MTP", 12: "S.MTP",
	13: "Upgrade", 14: "S.Upgrade",
	15: "Award", 16: "S.Award",
	17: "Extend", 18: "S.Extend",
}

const SYMBOL_COLORS := {
	1: Color.CORNFLOWER_BLUE,  # H1 藍
	2: Color.INDIAN_RED,       # H2 紅
	3: Color.DARK_ORANGE,      # H3 橘
	4: Color.PALE_GREEN,       # H4 淺綠
	5: Color.DARK_CYAN,        # H5 青
	6: Color.SANDY_BROWN,      # H6 棕
	11: Color.MEDIUM_PURPLE,   # N1 紫
	12: Color.PERU,            # N2 土黃
	13: Color.ROSY_BROWN,      # N3 灰粉
	21: Color.DARK_VIOLET,
	91: Color.GOLD,
	92: Color.MAGENTA,
}

@onready var bg_rect: ColorRect = $BgRect
@onready var label: Label = $Label
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var symbol_id: int = 0
var wild_sub_type: int = 0
var grid_col: int = 0
var grid_row: int = 0
var is_highlighted: bool = false
var _multiplier_label: Label = null
var _wild_value_label: Label = null
var _sticky_border: Panel = null
var _sticky_border_tween: Tween = null
var _extend_marker: Panel = null
var _extend_marker_tween: Tween = null


func setup(col: int, row: int) -> void:
	grid_col = col
	grid_row = row
	pivot_offset = size / 2.0
	# Create multiplier overlay label (hidden by default)
	_multiplier_label = Label.new()
	_multiplier_label.name = "MultiplierLabel"
	_multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_multiplier_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_multiplier_label.add_theme_font_size_override("font_size", 34)
	_multiplier_label.add_theme_color_override("font_color", Color.YELLOW)
	_multiplier_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_multiplier_label.add_theme_constant_override("outline_size", 3)
	_multiplier_label.size = Vector2(60, 30)
	_multiplier_label.position = Vector2(84, 4)
	_multiplier_label.visible = false
	add_child(_multiplier_label)


func set_symbol(sid: int, wst: int = 0) -> void:
	if sid == 0:
		set_empty()
		return
	symbol_id = sid
	wild_sub_type = wst
	if sid == GameManager.WILD_ID and wst > 0:
		if wst == GameManager.WILD_MYSTERY_BT:
			label.text = "?"
		elif wst in CORNER_FEATURE_NAMES:
			label.text = "W%d\n%s" % [wst, CORNER_FEATURE_NAMES[wst]]
		elif wst in WILD_EFFECT_NAMES:
			label.text = "W%d\n%s" % [wst, WILD_EFFECT_NAMES[wst]]
		else:
			label.text = "W%d" % wst
		label.add_theme_font_size_override("font_size", FONT_SIZE_WILD)
	elif sid == GameManager.WILD_ID:
		label.text = SYMBOL_NAMES.get(sid, "W")
		label.add_theme_font_size_override("font_size", FONT_SIZE_WILD)
	else:
		label.text = SYMBOL_NAMES.get(sid, "?%d" % sid)
		label.add_theme_font_size_override("font_size", FONT_SIZE_DEFAULT)
	bg_rect.color = SYMBOL_COLORS.get(sid, Color.GRAY).darkened(0.5)
	is_highlighted = false


## Set cell as a multiplier position with value displayed (e.g. "x8")
func set_multiplier_cell(mtp: int) -> void:
	symbol_id = GameManager.MTP_ID
	wild_sub_type = 0
	label.text = "x%d" % mtp
	label.add_theme_font_size_override("font_size", FONT_SIZE_DEFAULT)
	bg_rect.color = SYMBOL_COLORS.get(GameManager.MTP_ID, Color.GRAY).darkened(0.5)
	hide_multiplier()
	is_highlighted = false


func show_multiplier(value: int) -> void:
	if _multiplier_label:
		if value <= 0:
			_multiplier_label.visible = false
			return
		# Skip overlay if main label already shows this multiplier (set_multiplier_cell)
		if symbol_id == GameManager.MTP_ID:
			return
		_multiplier_label.text = "%dx" % value
		_multiplier_label.visible = true


func hide_multiplier() -> void:
	if _multiplier_label:
		_multiplier_label.visible = false


func highlight(color: Color = Color.YELLOW) -> void:
	is_highlighted = true
	bg_rect.color = SYMBOL_COLORS.get(symbol_id, Color.GRAY)
	if anim_player.has_animation("highlight"):
		anim_player.play("highlight")


func play_eliminate() -> void:
	if anim_player.has_animation("eliminate"):
		anim_player.play("eliminate")
	else:
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): modulate.a = 1.0)


func play_drop(from_y: float) -> void:
	var target_y := position.y
	position.y = from_y
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(self, "position:y", target_y, 0.4)


func play_spin_flip() -> void:
	var tween := create_tween()
	# scale.x 從 1 → 0 → 1，產生水平翻轉效果
	tween.tween_property(self, "scale:x", 0.0, 0.15).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale:x", 1.0, 0.15).set_ease(Tween.EASE_OUT)


func play_wild_effect(effect_type: String, is_super: bool = false) -> Tween:
	var flash_color := Color.CYAN if is_super else Color.GOLD
	var scale_boost := 1.3 if is_super else 1.2
	var tween: Tween
	match effect_type:
		GameManager.WILD_EFFECT_MYSTERY:
			# Mystery 不在這裡處理動畫，由 play_mystery_reveal 處理
			pass
		GameManager.WILD_EFFECT_EXTEND:
			tween = create_tween()
			tween.tween_property(bg_rect, "color", flash_color, 0.1)
			tween.tween_property(self, "scale", Vector2(scale_boost, scale_boost), 0.15)
			tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)
			tween.tween_property(bg_rect, "color", SYMBOL_COLORS.get(symbol_id, Color.GRAY).darkened(0.5), 0.1)
		GameManager.WILD_EFFECT_MTP:
			tween = create_tween()
			tween.tween_property(bg_rect, "color", flash_color, 0.15)
			tween.tween_property(bg_rect, "color", SYMBOL_COLORS.get(symbol_id, Color.GRAY).darkened(0.5), 0.15)
			tween.set_loops(3)
		GameManager.WILD_EFFECT_UPGRADE:
			tween = create_tween()
			tween.tween_property(bg_rect, "color", flash_color, 0.1)
			tween.tween_property(self, "rotation", TAU, 0.4)
			tween.tween_callback(func(): rotation = 0)
			tween.tween_property(bg_rect, "color", SYMBOL_COLORS.get(symbol_id, Color.GRAY).darkened(0.5), 0.1)
		GameManager.WILD_EFFECT_AWARD:
			tween = create_tween()
			tween.tween_property(self, "modulate", Color(flash_color.r, flash_color.g, flash_color.b, 1), 0.2)
			tween.tween_property(self, "modulate", Color.WHITE, 0.2)
	return tween


## Mystery reveal: flip animation to reveal the actual Wild sub-type
func play_mystery_reveal(reveal_wst: int, is_super: bool = false) -> void:
	var flash_color := Color.CYAN if is_super else Color.GOLD
	var tween := create_tween()
	tween.tween_property(bg_rect, "color", flash_color, 0.1)
	tween.tween_property(self, "scale:x", 0.0, 0.15).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): set_symbol(GameManager.WILD_ID, reveal_wst))
	tween.tween_property(self, "scale:x", 1.0, 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(bg_rect, "color", SYMBOL_COLORS.get(91, Color.GRAY).darkened(0.5), 0.1)


## Extend effect: flash and transform affected cell to Wild, with persistent extend marker
func play_transform_to_wild(is_super: bool = false) -> void:
	play_transform_extend(GameManager.WILD_ID, is_super)


## Play extend transform animation: flash → scale up → change to target symbol → scale down → marker
func play_transform_extend(to_sid: int, is_super: bool = false) -> void:
	var flash_color := Color.CYAN if is_super else Color.GOLD
	var tween := create_tween()
	tween.tween_property(bg_rect, "color", flash_color, 0.1)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.05)
	tween.tween_callback(func(): set_symbol(to_sid))
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)
	tween.tween_callback(func(): _show_extend_marker(is_super))


## Show extend marker — pulsing cyan/gold border to indicate this Wild was extended
func _show_extend_marker(is_super: bool) -> void:
	hide_extend_marker()
	var border_color := Color.CYAN if is_super else Color(1.0, 0.85, 0.0)
	_extend_marker = Panel.new()
	_extend_marker.size = size
	_extend_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = border_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(2)
	_extend_marker.add_theme_stylebox_override("panel", style)
	add_child(_extend_marker)
	# Pulse animation
	_extend_marker_tween = create_tween().set_loops()
	_extend_marker_tween.tween_property(_extend_marker, "modulate:a", 0.3, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_extend_marker_tween.tween_property(_extend_marker, "modulate:a", 1.0, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Hide extend marker
func hide_extend_marker() -> void:
	if _extend_marker_tween:
		_extend_marker_tween.kill()
		_extend_marker_tween = null
	if _extend_marker:
		_extend_marker.queue_free()
		_extend_marker = null


## Upgrade effect: flip animation, change symbol at midpoint
func play_upgrade_symbol(target_sid: int, is_super: bool = false) -> void:
	var flash_color := Color.CYAN if is_super else Color.GOLD
	var tween := create_tween()
	tween.tween_property(bg_rect, "color", flash_color, 0.05)
	tween.tween_property(self, "scale:x", 0.0, 0.15).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): set_symbol(target_sid))
	tween.tween_property(self, "scale:x", 1.0, 0.15).set_ease(Tween.EASE_OUT)


## Show value label on Wild cell (MTP/Award)
func show_wild_value_label(text: String) -> void:
	if not _wild_value_label:
		_wild_value_label = Label.new()
		_wild_value_label.name = "WildValueLabel"
		_wild_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_wild_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_wild_value_label.add_theme_font_size_override("font_size", 32)
		_wild_value_label.add_theme_color_override("font_color", Color.WHITE)
		_wild_value_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_wild_value_label.add_theme_constant_override("outline_size", 3)
		_wild_value_label.size = size
		_wild_value_label.position = Vector2.ZERO
		add_child(_wild_value_label)
	_wild_value_label.text = text
	_wild_value_label.visible = true
	# Hide original label so value text is prominent
	label.visible = false


## Hide Wild value label and restore original label
func hide_wild_value_label() -> void:
	if _wild_value_label:
		_wild_value_label.visible = false
	label.visible = true


## Show gold border around sticky cells during respin
func show_sticky_border() -> void:
	if _sticky_border:
		_sticky_border.visible = true
		return
	_sticky_border = Panel.new()
	_sticky_border.size = size
	_sticky_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color.GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(2)
	_sticky_border.add_theme_stylebox_override("panel", style)
	add_child(_sticky_border)
	# Glow pulse
	_sticky_border_tween = create_tween().set_loops()
	_sticky_border_tween.tween_property(_sticky_border, "modulate:a", 0.5, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sticky_border_tween.tween_property(_sticky_border, "modulate:a", 1.0, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func hide_sticky_border() -> void:
	if _sticky_border_tween:
		_sticky_border_tween.kill()
		_sticky_border_tween = null
	if _sticky_border:
		_sticky_border.visible = false
		_sticky_border.modulate.a = 1.0


## Quick shake effect for sticky lock-in
func play_lock_shake() -> void:
	var base_pos := position
	var tween := create_tween()
	tween.tween_property(self, "position:x", base_pos.x - 3, 0.03)
	tween.tween_property(self, "position:x", base_pos.x + 3, 0.03)
	tween.tween_property(self, "position:x", base_pos.x - 2, 0.03)
	tween.tween_property(self, "position:x", base_pos.x + 2, 0.02)
	tween.tween_property(self, "position:x", base_pos.x, 0.02)
	await tween.finished


## Set cell to empty (no symbol displayed, matches grid background)
func set_empty() -> void:
	symbol_id = 0
	wild_sub_type = 0
	label.text = ""
	bg_rect.color = GridController.GRID_BG_COLOR
	hide_multiplier()
	is_highlighted = false


## Show corner feature label at the bottom of the cell
var _corner_feature_label: Label = null

func show_corner_feature_label(feature_name: String) -> void:
	if not _corner_feature_label:
		_corner_feature_label = Label.new()
		_corner_feature_label.name = "CornerFeatureLabel"
		_corner_feature_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_corner_feature_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_corner_feature_label.add_theme_font_size_override("font_size", 26)
		_corner_feature_label.add_theme_color_override("font_color", Color.WHITE)
		_corner_feature_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_corner_feature_label.add_theme_constant_override("outline_size", 2)
		_corner_feature_label.size = size
		_corner_feature_label.position = Vector2(0, 0)
		add_child(_corner_feature_label)
	_corner_feature_label.text = feature_name
	_corner_feature_label.visible = true


func hide_corner_feature_label() -> void:
	if _corner_feature_label:
		_corner_feature_label.visible = false


## Restore from dim
func restore_modulate() -> void:
	modulate = Color.WHITE
