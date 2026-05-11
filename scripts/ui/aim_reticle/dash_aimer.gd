extends Node2D

# Real-time radius aim indicator used by the Fire dash-strike skill.
# Drawn in local space around the parent (player) — does not pause the game.

@export var radius: float = 500.0

var _color: Color = Color(1.0, 0.55, 0.25, 1.0)
var _active: bool = false


func _ready() -> void:
	visible = false
	set_process(false)


func start(color: Color = Color.WHITE, aim_radius: float = -1.0) -> void:
	_color = color
	if aim_radius > 0.0:
		radius = aim_radius
	_active = true
	visible = true
	set_process(true)
	queue_redraw()


func stop() -> void:
	_active = false
	visible = false
	set_process(false)


# Returns a target position (in global space) clamped to within `radius` of self.
func get_clamped_target() -> Vector2:
	var local: Vector2 = get_local_mouse_position()
	if local.length() > radius:
		local = local.normalized() * radius
	return global_position + local


func is_active() -> bool:
	return _active


func _process(_delta: float) -> void:
	if _active:
		queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var fill := Color(_color.r, _color.g, _color.b, 0.08)
	var stroke := Color(_color.r, _color.g, _color.b, 0.7)
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, stroke, 2.0, true)

	var local: Vector2 = get_local_mouse_position()
	var target: Vector2 = local
	if target.length() > radius:
		target = target.normalized() * radius

	draw_line(Vector2.ZERO, target, Color(_color.r, _color.g, _color.b, 0.85), 2.5)
	draw_arc(target, 14.0, 0.0, TAU, 24, Color(_color.r, _color.g, _color.b, 0.95), 3.0, true)
	draw_circle(target, 4.0, Color(_color.r, _color.g, _color.b, 1.0))
