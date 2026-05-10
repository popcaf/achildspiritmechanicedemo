extends Node2D

signal aim_confirmed(target_pos: Vector2)
signal aim_cancelled

@export var radius: float = 240.0

var _color: Color = Color(1.0, 0.85, 0.3, 1.0)
var _active: bool = false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_process(true)


func start_aiming(stance_color: Color = Color(1.0, 0.85, 0.3, 1.0), aim_radius: float = -1.0) -> void:
	_color = stance_color
	if aim_radius > 0.0:
		radius = aim_radius
	_active = true
	visible = true
	set_process(true)
	queue_redraw()


func stop_aiming() -> void:
	_active = false
	visible = false


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

	var mouse: Vector2 = get_local_mouse_position()
	var target: Vector2 = mouse
	if target.length() > radius:
		target = target.normalized() * radius

	draw_line(Vector2.ZERO, target, Color(_color.r, _color.g, _color.b, 0.85), 2.5)
	draw_arc(target, 14.0, 0.0, TAU, 24, Color(_color.r, _color.g, _color.b, 0.95), 3.0, true)
	draw_circle(target, 4.0, Color(_color.r, _color.g, _color.b, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseMotion:
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse: Vector2 = get_local_mouse_position()
		var target: Vector2 = mouse
		if target.length() > radius:
			target = target.normalized() * radius
		aim_confirmed.emit(global_position + target)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cancel_skill") or event.is_action_pressed("ui_cancel"):
		aim_cancelled.emit()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		aim_cancelled.emit()
		return
	if event.is_action_released("stance_toggle"):
		aim_cancelled.emit()
