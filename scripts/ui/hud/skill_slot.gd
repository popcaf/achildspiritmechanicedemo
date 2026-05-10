extends Control

@export var hotkey_text: String = "1"
@export var icon_color: Color = Color.WHITE
@export var skill_name_text: String = "Skill"
@export var mana_cost: int = 0

var _affordable: bool = true
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
	_apply_cost(mana_cost)
	set_cooldown(0.0, 0.0)
	_refresh_state()


func configure(name_str: String, hotkey_str: String, color: Color, cost: int) -> void:
	skill_name_text = name_str
	hotkey_text = hotkey_str
	icon_color = color
	mana_cost = cost
	if is_node_ready():
		icon.color = color
		hotkey_label.text = hotkey_str
		name_label.text = name_str
		_apply_cost(cost)
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


func set_affordable(affordable: bool) -> void:
	if _affordable == affordable:
		return
	_affordable = affordable
	_refresh_state()


func _apply_cost(cost: int) -> void:
	if cost > 0:
		cost_label.text = str(cost)
		cost_label.visible = true
	else:
		cost_label.text = ""
		cost_label.visible = false


func _refresh_state() -> void:
	if _on_cooldown:
		icon.modulate = Color(0.55, 0.55, 0.6)
		cost_label.modulate = Color(0.7, 0.75, 0.85)
	elif not _affordable and mana_cost > 0:
		icon.modulate = Color(0.5, 0.4, 0.42)
		cost_label.modulate = Color(1.0, 0.4, 0.4)
	else:
		icon.modulate = Color.WHITE
		cost_label.modulate = Color.WHITE
