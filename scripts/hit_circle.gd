extends Control

@export var radius: float = 32.0
@export var color: Color = Color.WHITE

var circle_index: int = 0
var _clicked: bool = false

@onready var inner: Polygon2D = $Inner
@onready var approach: Line2D = $Approach
@onready var number_label: Label = $Number


func _ready() -> void:
	inner.polygon = _disc(radius, 28)
	inner.color = Color(color.r, color.g, color.b, 0.85)
	approach.points = _ring(radius * 1.25, 32)
	approach.default_color = Color(1, 1, 1, 0.65)
	if number_label:
		number_label.text = str(circle_index + 1)


func set_index(i: int) -> void:
	circle_index = i
	if number_label and is_node_ready():
		number_label.text = str(i + 1)


func is_clicked() -> bool:
	return _clicked


func set_active(active: bool) -> void:
	if _clicked:
		return
	if active:
		modulate.a = 1.0
		approach.default_color = Color(1, 1, 1, 0.95)
		approach.width = 4.0
	else:
		modulate.a = 0.45
		approach.default_color = Color(1, 1, 1, 0.4)
		approach.width = 2.5


func mark_clicked() -> void:
	_clicked = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)


func flash_wrong() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(2.0, 0.5, 0.5, 1.0), 0.05)
	tween.tween_property(self, "modulate", Color.WHITE, 0.18)


func _ring(r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segs + 1):
		var a: float = float(i) * TAU / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


func _disc(r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segs):
		var a: float = float(i) * TAU / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts
