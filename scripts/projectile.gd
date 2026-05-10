extends Area2D

const Element := preload("res://scripts/element.gd")

@export var speed: float = 720.0
@export var damage: int = 8
@export var lifetime: float = 1.2

var direction: int = 1
var element: int = Element.NEUTRAL
var _pending_color: Color = Color(1, 0.92, 0.5, 1)
var _color_set: bool = false

@onready var visual: Polygon2D = $Visual


func _ready() -> void:
	if _color_set:
		visual.color = _pending_color
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position.x += speed * float(direction) * delta


func set_direction(d: int) -> void:
	direction = d
	scale.x = float(d)


func configure(dmg: int, color: Color, elem: int = Element.NEUTRAL) -> void:
	damage = dmg
	_pending_color = color
	_color_set = true
	element = elem
	if is_node_ready():
		visual.color = color


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, element)
	queue_free()
