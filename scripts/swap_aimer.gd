extends Node2D

signal swap_confirmed(target_pos: Vector2)
signal swap_cancelled

@export var radius: float = 240.0

var _active: bool = false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func start_aiming() -> void:
	visible = true
	_active = true
	queue_redraw()


func stop_aiming() -> void:
	visible = false
	_active = false


func _process(_delta: float) -> void:
	if _active:
		queue_redraw()


func _draw() -> void:
	if not _active:
		return
	# Range disc + outline anchored at the player.
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.85, 0.3, 0.08))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(1.0, 0.85, 0.3, 0.7), 2.0, true)

	var mouse: Vector2 = get_local_mouse_position()
	var target: Vector2 = mouse
	if target.length() > radius:
		target = target.normalized() * radius

	# Line from player to clamped target + target marker.
	draw_line(Vector2.ZERO, target, Color(1.0, 0.85, 0.3, 0.85), 2.5)
	draw_arc(target, 14.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.3, 0.95), 3.0, true)
	draw_circle(target, 4.0, Color(1.0, 0.85, 0.3, 1.0))


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse: Vector2 = get_local_mouse_position()
		var target: Vector2 = mouse
		if target.length() > radius:
			target = target.normalized() * radius
		swap_confirmed.emit(global_position + target)
		return
	if event.is_action_pressed("cancel_skill") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("stance_toggle"):
		swap_cancelled.emit()
