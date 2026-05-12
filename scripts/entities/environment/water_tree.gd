extends StaticBody2D

# Water-stance practice plot. Starts as a seed; each water_drop the player
# pours onto it advances its growth meter. Past PLATFORM_THRESHOLD growth, a
# platform on top becomes solid and the player can jump on it. A FIRE-element
# attack burns the tree to ash; after a short delay it resets to a seed so the
# practice loop can repeat.

const Element := preload("res://scripts/core/element.gd")

@export var max_water_hits: int = 12
@export var platform_threshold: float = 0.25  # solid platform appears at this growth.
@export var burn_reset_delay: float = 1.5

var _water_hits: int = 0
var _is_solid: bool = false
var _alive: bool = true

@onready var trunk: Polygon2D = $Visual/Trunk
@onready var canopy: Polygon2D = $Visual/Canopy
@onready var seed_dot: Polygon2D = $Visual/SeedDot
@onready var plank: Polygon2D = $Visual/Plank
@onready var platform_shape: CollisionShape2D = $PlatformShape


func _ready() -> void:
	add_to_group("dummy")  # treated as a hittable target by player attacks.
	platform_shape.disabled = true
	_update_visual(0.0)


# Called by water_drop on overlap.
func on_water_drop(_drop_position: Vector2) -> void:
	if not _alive:
		return
	if _water_hits >= max_water_hits:
		return
	_water_hits += 1
	var t: float = float(_water_hits) / float(max_water_hits)
	_update_visual(t)
	if t >= platform_threshold and not _is_solid:
		_become_solid()


func take_damage(_amount: int, element: int = Element.NEUTRAL, _from_pos: Vector2 = Vector2.INF) -> void:
	if element == Element.FIRE:
		_burn()


func apply_knockback(_impulse: Vector2) -> void:
	pass


func _update_visual(t: float) -> void:
	# Seed dot visible only when t == 0.
	seed_dot.visible = t < 0.05
	# Trunk grows vertically + thickens.
	var trunk_scale_y: float = lerp(0.05, 1.0, t)
	var trunk_scale_x: float = lerp(0.4, 1.0, t)
	trunk.scale = Vector2(trunk_scale_x, trunk_scale_y)
	# Canopy appears once growth exceeds 30%.
	var canopy_t: float = clampf((t - 0.3) / 0.7, 0.0, 1.0)
	canopy.scale = Vector2.ONE * canopy_t


func _become_solid() -> void:
	_is_solid = true
	# Deferred so the enable happens at a safe point in the physics step.
	platform_shape.set_deferred("disabled", false)
	plank.visible = true
	# Strong color shift on canopy AND trunk so the "landable" state is
	# unmistakable from anywhere on screen.
	canopy.modulate = Color(1.6, 1.6, 0.8, 1.0)
	trunk.modulate = Color(1.2, 1.0, 0.8, 1.0)


func _burn() -> void:
	if not _alive:
		return
	_alive = false
	platform_shape.disabled = true
	_is_solid = false
	plank.visible = false
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(trunk, "modulate", Color(0.2, 0.1, 0.05, 1.0), 0.4)
	t.tween_property(canopy, "modulate", Color(0.2, 0.1, 0.05, 1.0), 0.4)
	t.tween_property(trunk, "scale", trunk.scale * 0.5, 0.5)
	t.tween_property(canopy, "scale", canopy.scale * 0.2, 0.5)
	t.finished.connect(_reset_after_delay, CONNECT_ONE_SHOT)


func _reset_after_delay() -> void:
	await get_tree().create_timer(burn_reset_delay).timeout
	_water_hits = 0
	trunk.modulate = Color.WHITE
	canopy.modulate = Color.WHITE
	plank.visible = false
	_alive = true
	_update_visual(0.0)
