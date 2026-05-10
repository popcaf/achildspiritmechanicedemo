extends CanvasLayer

const HIT_CIRCLE_SCENE := preload("res://scenes/hit_circle.tscn")
const CAST_DURATION := 4.0
const CIRCLE_COUNT := 3

signal cast_completed(success: bool)

var _circles: Array = []
var _remaining: int = 0
var _expected: int = 0
var _start_time: float = 0.0
var _active: bool = false

@onready var skill_name_label: Label = $Panel/SkillName
@onready var progress_label: Label = $Panel/Progress
@onready var circle_area: Control = $Panel/CircleArea
@onready var result_label: Label = $Panel/Result
@onready var timer_bar: ProgressBar = $Panel/TimerBar


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func start_cast(skill_data: Dictionary) -> void:
	visible = true
	var name_str: String = skill_data.get("name", "Skill")
	skill_name_label.text = name_str.to_upper()
	var color: Color = skill_data.get("color", Color.WHITE)
	skill_name_label.add_theme_color_override("font_color", color)
	result_label.text = ""
	_circles.clear()
	_expected = 0

	for c in circle_area.get_children():
		c.queue_free()

	# Wait one frame so circle_area.size is valid after layout pass.
	await get_tree().process_frame

	var area_size: Vector2 = circle_area.size
	for i in range(CIRCLE_COUNT):
		var hc := HIT_CIRCLE_SCENE.instantiate()
		circle_area.add_child(hc)
		hc.color = color
		hc.set_index(i)
		hc.position = Vector2(
			randf_range(70.0, maxf(70.0, area_size.x - 70.0)),
			randf_range(70.0, maxf(70.0, area_size.y - 70.0))
		)
		_circles.append(hc)

	_refresh_active_highlight()
	_remaining = CIRCLE_COUNT
	_update_progress()
	timer_bar.value = 100.0
	_start_time = Time.get_ticks_msec() / 1000.0
	_active = true
	get_tree().paused = true


func _process(_delta: float) -> void:
	if not _active:
		return
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _start_time
	var remaining: float = CAST_DURATION - elapsed
	if remaining <= 0.0:
		timer_bar.value = 0.0
		_miss("TIME!")
		return
	timer_bar.value = (remaining / CAST_DURATION) * 100.0


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("cancel_skill") or event.is_action_pressed("stance_toggle") or event.is_action_pressed("ui_cancel"):
		_cancel()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_click()


func _try_click() -> void:
	var local_mouse: Vector2 = circle_area.get_local_mouse_position()
	for hc in _circles:
		if not is_instance_valid(hc) or hc.is_clicked():
			continue
		if local_mouse.distance_to(hc.position) <= hc.radius * 1.25:
			if hc.circle_index != _expected:
				hc.flash_wrong()
				_miss("WRONG!")
				return
			hc.mark_clicked()
			_expected += 1
			_remaining -= 1
			_update_progress()
			_refresh_active_highlight()
			if _remaining <= 0:
				_success()
			return


func _refresh_active_highlight() -> void:
	for hc in _circles:
		if not is_instance_valid(hc) or hc.is_clicked():
			continue
		hc.set_active(hc.circle_index == _expected)


func _update_progress() -> void:
	var done: int = CIRCLE_COUNT - _remaining
	progress_label.text = "%d / %d" % [done, CIRCLE_COUNT]


func _success() -> void:
	_active = false
	result_label.text = "READY!"
	result_label.add_theme_color_override("font_color", Color(0.5, 1, 0.6))
	await get_tree().create_timer(0.35).timeout
	_close()
	cast_completed.emit(true)


func _miss(reason: String) -> void:
	_active = false
	result_label.text = reason
	result_label.add_theme_color_override("font_color", Color(1, 0.45, 0.45))
	await get_tree().create_timer(0.5).timeout
	_close()
	cast_completed.emit(false)


func _cancel() -> void:
	_active = false
	_close()
	cast_completed.emit(false)


func _close() -> void:
	get_tree().paused = false
	visible = false
	for c in circle_area.get_children():
		c.queue_free()
	_circles.clear()
	result_label.text = ""
