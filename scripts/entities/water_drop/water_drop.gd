extends Area2D

# A water droplet thrown out by the Water stance "pour" attack.
# Has w_gravity so the stream arcs and falls realistically. Deals no damage,
# only applies a small knockback on contact.

const Element := preload("res://scripts/core/element.gd")

@export var w_gravity: float = 1400.0
@export var lifetime: float = 1.6
@export var knockback_force: float = 280.0

var velocity: Vector2 = Vector2.ZERO

@onready var visual: Polygon2D = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_safe_free)


func _physics_process(delta: float) -> void:
	velocity.y += w_gravity * delta
	position += velocity * delta
	if velocity.length_squared() > 1.0:
		rotation = velocity.angle()


func launch(initial_velocity: Vector2, color: Color = Color(0.5, 0.85, 1.0, 1.0)) -> void:
	velocity = initial_velocity
	if is_node_ready() and visual:
		visual.color = color


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return
	if body.has_method("apply_knockback"):
		var dir: Vector2 = velocity.normalized() if velocity.length_squared() > 0.0 else Vector2.RIGHT
		body.apply_knockback(Vector2(dir.x * knockback_force, -knockback_force * 0.25))
	queue_free()


func _safe_free() -> void:
	if is_inside_tree():
		queue_free()
