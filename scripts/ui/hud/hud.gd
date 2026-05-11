extends CanvasLayer

@export var player_path: NodePath = ^"../Player"

var player: Node = null

@onready var hp_bar: ProgressBar = $Root/HealthBar
@onready var hp_label: Label = $Root/HealthBar/HPLabel
@onready var fly_bar: ProgressBar = $Root/FlyBar
@onready var fly_label: Label = $Root/FlyBar/FlyLabel
@onready var fly_caption: Label = $Root/FlyCaption
@onready var stance_label: Label = $Root/StanceLabel
@onready var slots: Array = [
	$Root/SkillBar/FireSlot,
	$Root/SkillBar/WaterSlot,
	$Root/SkillBar/EarthSlot,
	$Root/SkillBar/WindSlot,
]


func _ready() -> void:
	player = get_node_or_null(player_path)
	if player == null:
		push_warning("HUD: player not found at path %s" % player_path)
		return

	for i in range(slots.size()):
		var info: Dictionary = player.get_stance_info(i)
		slots[i].configure(info.skill_name, info.key, info.color)

	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal("stance_changed"):
		player.stance_changed.connect(_on_stance_changed)
	if player.has_signal("fly_gauge_changed"):
		player.fly_gauge_changed.connect(_on_fly_changed)

	_on_stance_changed(player.current_stance)
	_on_health_changed(player.health, player.max_health)
	_on_fly_changed(player.get_fly_remaining(), player.get_fly_max())


func _process(_delta: float) -> void:
	if player == null:
		return
	for i in range(slots.size()):
		slots[i].set_cooldown(player.get_skill_remaining(i), player.get_skill_max(i))


func _on_health_changed(current: int, max_value: int) -> void:
	hp_bar.max_value = float(max_value)
	hp_bar.value = float(current)
	hp_label.text = "%d / %d" % [current, max_value]


func _on_stance_changed(stance: int) -> void:
	var info: Dictionary = player.get_stance_info(stance)
	var name_str: String = info.name
	stance_label.text = "%s STANCE   ·   tap key for skill, double-tap to swap" % name_str.to_upper()
	stance_label.modulate = info.color
	# Fly gauge is only usable in wind stance — dim when irrelevant.
	var wind_active: bool = stance == 3
	var alpha: float = 1.0 if wind_active else 0.4
	fly_bar.modulate.a = alpha
	fly_label.modulate.a = alpha
	fly_caption.modulate.a = alpha


func _on_fly_changed(current: float, max_value: float) -> void:
	fly_bar.max_value = max_value
	fly_bar.value = current
	fly_label.text = "%.1f / %.1f" % [current, max_value]
