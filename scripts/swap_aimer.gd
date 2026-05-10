extends CanvasLayer

signal stance_selected(stance_idx: int, use_skill: bool)
signal swap_cancelled

const ICON_RADIUS := 38.0
const ICON_SPACING := 18.0
const PANEL_PADDING := 24.0
const PANEL_TOP_MARGIN := 90.0

var _stances: Array = []
var _current_stance: int = 0
var _active: bool = false

var _root: Control
var _panel: Panel
var _row: HBoxContainer
var _title: Label
var _hint: Label


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

	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.offset_top = PANEL_TOP_MARGIN
	_panel.offset_bottom = PANEL_TOP_MARGIN + ICON_RADIUS * 2.0 + 90.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.06, 0.07, 0.1, 0.92)
	pstyle.border_color = Color(0.4, 0.45, 0.55, 1.0)
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(8)
	pstyle.content_margin_left = PANEL_PADDING
	pstyle.content_margin_right = PANEL_PADDING
	pstyle.content_margin_top = 14.0
	pstyle.content_margin_bottom = 14.0
	_panel.add_theme_stylebox_override("panel", pstyle)
	_root.add_child(_panel)

	_title = Label.new()
	_title.text = "SWAP STANCE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.offset_top = 8.0
	_title.offset_bottom = 30.0
	_title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.7, 1))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_title.add_theme_constant_override("outline_size", 3)
	_title.add_theme_font_size_override("font_size", 14)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_title)

	_row = HBoxContainer.new()
	_row.anchor_left = 0.0
	_row.anchor_right = 1.0
	_row.anchor_top = 0.0
	_row.offset_top = 32.0
	_row.offset_bottom = 32.0 + ICON_RADIUS * 2.0 + 26.0
	_row.add_theme_constant_override("separation", int(ICON_SPACING))
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_child(_row)

	_hint = Label.new()
	_hint.text = "Click: switch    Shift+Click: swap skill    RMB / Esc: cancel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -24.0
	_hint.offset_bottom = -6.0
	_hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 1))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_hint.add_theme_constant_override("outline_size", 3)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_hint)


func configure(stances: Array, current_stance: int) -> void:
	_stances = stances
	_current_stance = current_stance
	_rebuild_icons()
	_resize_panel()


func start_aiming() -> void:
	visible = true
	_active = true
	_refresh_highlight()


func stop_aiming() -> void:
	visible = false
	_active = false


func set_current_stance(stance_idx: int) -> void:
	_current_stance = stance_idx
	if _active:
		_refresh_highlight()


func _resize_panel() -> void:
	var icon_w: float = ICON_RADIUS * 2.0 + 8.0
	var n: int = maxi(1, _stances.size())
	var width: float = float(n) * icon_w + float(n - 1) * ICON_SPACING + PANEL_PADDING * 2.0
	width = maxf(width, 360.0)
	_panel.offset_left = -width / 2.0
	_panel.offset_right = width / 2.0


func _rebuild_icons() -> void:
	for c in _row.get_children():
		c.queue_free()
	for i in range(_stances.size()):
		var data: Dictionary = _stances[i]
		_row.add_child(_make_icon(i, data))


func _make_icon(idx: int, data: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(ICON_RADIUS * 2.0 + 8.0, ICON_RADIUS * 2.0 + 26.0)
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_meta("stance_idx", idx)
	btn.pressed.connect(_on_icon_pressed.bind(idx))

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
	btn.add_child(disc)

	var ring := Panel.new()
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0, 0, 0, 0)
	ring_style.border_color = Color(1, 1, 1, 0.6)
	ring_style.set_border_width_all(3)
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
	btn.add_child(label)

	return btn


func _refresh_highlight() -> void:
	for child in _row.get_children():
		var idx: int = int(child.get_meta("stance_idx", -1))
		var ring: Panel = child.get_node_or_null("Ring")
		if ring == null:
			continue
		var style: StyleBoxFlat = ring.get_theme_stylebox("panel")
		if style == null:
			continue
		if idx == _current_stance:
			style.border_color = Color(1.0, 0.95, 0.45, 1.0)
			child.modulate = Color(1.15, 1.15, 1.15, 1.0)
		else:
			style.border_color = Color(1, 1, 1, 0.55)
			child.modulate = Color(0.85, 0.85, 0.85, 0.95)


func _on_icon_pressed(idx: int) -> void:
	if not _active:
		return
	var use_skill: bool = Input.is_key_pressed(KEY_SHIFT)
	stance_selected.emit(idx, use_skill)


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
