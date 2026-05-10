extends Area2D

const Element := preload("res://scripts/element.gd")

@export var speed: float = 720.0
@export var damage: int = 8
@export var lifetime: float = 1.5
@export var max_range: float = 600.0

var velocity_dir: Vector2 = Vector2.RIGHT
var element: int = Element.NEUTRAL
var _pending_color: Color = Color(1, 0.92, 0.5, 1)
var _color_set: bool = false
var _traveled: float = 0.0

@onready var visual: Polygon2D = $Visual


func _ready() -> void:
	if _color_set:
		visual.color = _pending_color
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	var step: Vector2 = velocity_dir * speed * delta
	position += step
	_traveled += step.length()
	if _traveled >= max_range:
		queue_free()


func set_velocity(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	velocity_dir = dir.normalized()
	rotation = velocity_dir.angle()


func set_direction(d: int) -> void:
	set_velocity(Vector2(float(d), 0.0))


func configure(dmg: int, color: Color, elem: int = Element.NEUTRAL, range_limit: float = -1.0) -> void:
	damage = dmg
	_pending_color = color
	_color_set = true
	element = elem
	if range_limit > 0.0:
		max_range = range_limit
	if is_node_ready():
		visual.color = color


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, element, global_position)
	queue_free()
