extends CanvasLayer

signal stance_selected(stance_idx: int, use_skill: bool)
signal stance_aim_requested(stance_idx: int)
signal swap_cancelled

const ICON_RADIUS := 42.0
const WHEEL_RADIUS := 170.0
const RING_THICKNESS := 3
const TITLE_OFFSET := -WHEEL_RADIUS - 70.0
const HINT_OFFSET := WHEEL_RADIUS + 56.0

var _stances: Array = []
var _current_stance: int = 0
var _active: bool = false
var _hover_idx: int = -1

var _root: Control
var _hub: Control
var _title: Label
var _hint: Label
var _icons: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Dim backdrop so the wheel pops while paused.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	_hub = Control.new()
	_hub.anchor_left = 0.5
	_hub.anchor_right = 0.5
	_hub.anchor_top = 0.5
	_hub.anchor_bottom = 0.5
	_hub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hub)

	var ring := Panel.new()
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0, 0, 0, 0)
	ring_style.border_color = Color(1, 1, 1, 0.18)
	ring_style.set_border_width_all(2)
	ring_style.set_corner_radius_all(int(WHEEL_RADIUS) + 6)
	ring.add_theme_stylebox_override("panel", ring_style)
	ring.anchor_left = 0.5
	ring.anchor_right = 0.5
	ring.anchor_top = 0.5
	ring.anchor_bottom = 0.5
	ring.offset_left = -WHEEL_RADIUS - 6.0
	ring.offset_right = WHEEL_RADIUS + 6.0
	ring.offset_top = -WHEEL_RADIUS - 6.0
	ring.offset_bottom = WHEEL_RADIUS + 6.0
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub.add_child(ring)

	_title = Label.new()
	_title.text = "SWAP STANCE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.anchor_left = 0.5
	_title.anchor_right = 0.5
	_title.offset_left = -160.0
	_title.offset_right = 160.0
	_title.offset_top = TITLE_OFFSET
	_title.offset_bottom = TITLE_OFFSET + 22.0
	_title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.7, 1))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_title.add_theme_constant_override("outline_size", 4)
	_title.add_theme_font_size_override("font_size", 16)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub.add_child(_title)

	_hint = Label.new()
	_hint.text = "Hover: switch    Shift+Hover: swap-skill aim    RMB / Esc: cancel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.offset_left = -260.0
	_hint.offset_right = 260.0
	_hint.offset_top = HINT_OFFSET
	_hint.offset_bottom = HINT_OFFSET + 20.0
	_hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 1))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_hint.add_theme_constant_override("outline_size", 3)
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub.add_child(_hint)


func configure(stances: Array, current_stance: int) -> void:
	_stances = stances
	_current_stance = current_stance
	_rebuild_icons()


func start_aiming() -> void:
	visible = true
	_active = true
	_hover_idx = -1
	_refresh_icon_states()


func stop_aiming() -> void:
	visible = false
	_active = false
	_hover_idx = -1


func set_current_stance(stance_idx: int) -> void:
	_current_stance = stance_idx
	if _active:
		_refresh_icon_states()


func _rebuild_icons() -> void:
	for icon in _icons:
		if is_instance_valid(icon):
			icon.queue_free()
	_icons.clear()

	var n: int = _stances.size()
	for i in range(n):
		var data: Dictionary = _stances[i]
		var icon := _make_icon(i, data, n)
		_icons.append(icon)
		_hub.add_child(icon)
	_refresh_icon_states()


func _make_icon(idx: int, data: Dictionary, total: int) -> Button:
	var angle: float = float(idx) * TAU / float(total) - TAU / 4.0
	var ox: float = cos(angle) * WHEEL_RADIUS
	var oy: float = sin(angle) * WHEEL_RADIUS

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_meta("stance_idx", idx)
	btn.anchor_left = 0.5
	btn.anchor_right = 0.5
	btn.anchor_top = 0.5
	btn.anchor_bottom = 0.5
	btn.offset_left = ox - ICON_RADIUS - 4.0
	btn.offset_right = ox + ICON_RADIUS + 4.0
	btn.offset_top = oy - ICON_RADIUS - 4.0
	btn.offset_bottom = oy + ICON_RADIUS + 26.0
	btn.mouse_entered.connect(_on_icon_mouse_entered.bind(idx))
	btn.mouse_exited.connect(_on_icon_mouse_exited.bind(idx))

	var color: Color = data.get("color", Color.WHITE)

	var disc := Panel.new()
	var disc_style := StyleBoxFlat.new()
	disc_style.bg_color = Color(color.r, color.g, color.b, 0.9)
	disc_style.set_corner_radius_all(int(ICON_RADIUS))
	disc.add_theme_stylebox_override("panel", disc_style)
	disc.anchor_left = 0.5
	disc.anchor_right = 0.5
	disc.offset_left = -ICON_RADIUS
	disc.offset_right = ICON_RADIUS
	disc.offset_top = 4.0
	disc.offset_bottom = ICON_RADIUS * 2.0 + 4.0
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.name = "Disc"
	btn.add_child(disc)

	var ring := Panel.new()
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0, 0, 0, 0)
	ring_style.border_color = Color(1, 1, 1, 0.55)
	ring_style.set_border_width_all(RING_THICKNESS)
	ring_style.set_corner_radius_all(int(ICON_RADIUS) + 4)
	ring.add_theme_stylebox_override("panel", ring_style)
	ring.anchor_left = 0.5
	ring.anchor_right = 0.5
	ring.offset_left = -ICON_RADIUS - 4.0
	ring.offset_right = ICON_RADIUS + 4.0
	ring.offset_top = 0.0
	ring.offset_bottom = ICON_RADIUS * 2.0 + 8.0
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.name = "Ring"
	btn.add_child(ring)

	var label := Label.new()
	label.text = String(data.get("name", "?")).to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_top = -22.0
	label.offset_bottom = 0.0
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.name = "Label"
	btn.add_child(label)

	return btn


func _refresh_icon_states() -> void:
	for icon in _icons:
		if not is_instance_valid(icon):
			continue
		var idx: int = int(icon.get_meta("stance_idx", -1))
		var is_current: bool = idx == _current_stance
		icon.disabled = is_current
		icon.mouse_default_cursor_shape = (
			Control.CURSOR_FORBIDDEN if is_current else Control.CURSOR_POINTING_HAND
		)

		var ring: Panel = icon.get_node_or_null("Ring")
		if ring:
			var rs: StyleBoxFlat = ring.get_theme_stylebox("panel")
			if rs:
				rs.border_color = (
					Color(1.0, 0.95, 0.45, 1.0) if is_current else Color(1, 1, 1, 0.55)
				)

		if is_current:
			icon.modulate = Color(0.6, 0.6, 0.65, 0.65)
		else:
			icon.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _on_icon_mouse_entered(idx: int) -> void:
	if not _active:
		return
	if idx == _current_stance:
		return
	_hover_idx = idx
	if Input.is_key_pressed(KEY_SHIFT):
		stance_aim_requested.emit(idx)
	else:
		stance_selected.emit(idx, false)


func _on_icon_mouse_exited(idx: int) -> void:
	if _hover_idx == idx:
		_hover_idx = -1


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("cancel_skill") or event.is_action_pressed("ui_cancel"):
		swap_cancelled.emit()
		return
	if event.is_action_released("stance_toggle"):
		swap_cancelled.emit()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		swap_cancelled.emit()
		return
	# Shift pressed while already hovering an icon → start swap-skill aim for that stance.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SHIFT and _hover_idx != -1 and _hover_idx != _current_stance:
			stance_aim_requested.emit(_hover_idx)
