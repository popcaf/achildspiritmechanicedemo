extends Control

@export var hotkey_text: String = "1"
@export var icon_color: Color = Color.WHITE
@export var skill_name_text: String = "Skill"

var _on_cooldown: bool = false

@onready var icon: ColorRect = $Inner
@onready var cooldown_overlay: ColorRect = $Cooldown
@onready var hotkey_label: Label = $Hotkey
@onready var cd_label: Label = $CDLabel
@onready var name_label: Label = $NameLabel
@onready var cost_label: Label = $CostLabel


func _ready() -> void:
	icon.color = icon_color
	hotkey_label.text = hotkey_text
	name_label.text = skill_name_text
	cost_label.visible = false
	set_cooldown(0.0, 0.0)
	_refresh_state()


func configure(name_str: String, hotkey_str: String, color: Color) -> void:
	skill_name_text = name_str
	hotkey_text = hotkey_str
	icon_color = color
	if is_node_ready():
		icon.color = color
		hotkey_label.text = hotkey_str
		name_label.text = name_str
		cost_label.visible = false
		_refresh_state()


func set_cooldown(remaining: float, max_cd: float) -> void:
	if remaining <= 0.0 or max_cd <= 0.0:
		_on_cooldown = false
		cooldown_overlay.visible = false
		cd_label.visible = false
	else:
		_on_cooldown = true
		cooldown_overlay.visible = true
		cd_label.visible = true
		cd_label.text = "%.1f" % remaining
		var ratio: float = clampf(remaining / max_cd, 0.0, 1.0)
		cooldown_overlay.anchor_top = 1.0 - ratio
		cooldown_overlay.anchor_bottom = 1.0
		cooldown_overlay.offset_top = 0.0
		cooldown_overlay.offset_bottom = 0.0
	_refresh_state()


func _refresh_state() -> void:
	if _on_cooldown:
		icon.modulate = Color(0.55, 0.55, 0.6)
	else:
		icon.modulate = Color.WHITE
