extends Node2D

const LIFETIME := 0.7
const RISE := 36.0

@onready var label: Label = $Label

var _amount: int = 0
var _multiplier: float = 1.0


func setup(amount: int, multiplier: float = 1.0) -> void:
	_amount = amount
	_multiplier = multiplier
	if is_node_ready():
		_apply_style()


func _ready() -> void:
	_apply_style()
	var start_y: float = position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", start_y - RISE, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME)
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


func _apply_style() -> void:
	if _multiplier >= 2.0:
		label.text = "%d!" % _amount
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2, 1.0))
	elif _multiplier < 1.0:
		label.text = str(_amount)
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.85, 1.0))
	else:
		label.text = str(_amount)
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3, 1.0))
