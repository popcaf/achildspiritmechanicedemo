extends CanvasLayer

@export var player_path: NodePath = ^"../Player"

var player: Node = null

@onready var hp_bar: ProgressBar = $Root/HealthBar
@onready var hp_label: Label = $Root/HealthBar/HPLabel
@onready var mp_bar: ProgressBar = $Root/ManaBar
@onready var mp_label: Label = $Root/ManaBar/MPLabel
@onready var stance_label: Label = $Root/StanceLabel
@onready var dash_slot: Node = $Root/SkillBar/DashSlot
@onready var slots: Array = [
	$Root/SkillBar/Slot1,
	$Root/SkillBar/Slot2,
	$Root/SkillBar/Slot3,
	$Root/SkillBar/Slot4,
]


func _ready() -> void:
	player = get_node_or_null(player_path)
	if player == null:
		push_warning("HUD: player not found at path %s" % player_path)
		return

	dash_slot.configure("Dash", "⇧", Color(0.7, 0.95, 1.0, 1.0), 0)

	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal("mana_changed"):
		player.mana_changed.connect(_on_mana_changed)
	if player.has_signal("stance_changed"):
		player.stance_changed.connect(_on_stance_changed)

	_on_stance_changed(player.current_stance)
	_on_health_changed(player.health, player.max_health)
	_on_mana_changed(player.mana, player.max_mana)


func _process(_delta: float) -> void:
	if player == null:
		return
	dash_slot.set_cooldown(player.get_dash_remaining(), player.get_dash_max())
	for i in range(slots.size()):
		var slot: Node = slots[i]
		slot.set_cooldown(player.get_skill_remaining(i), player.get_skill_max(i))
		slot.set_affordable(player.can_afford_skill(i))


func _on_health_changed(current: int, max_value: int) -> void:
	hp_bar.max_value = float(max_value)
	hp_bar.value = float(current)
	hp_label.text = "%d / %d" % [current, max_value]


func _on_mana_changed(current: float, max_value: int) -> void:
	mp_bar.max_value = float(max_value)
	mp_bar.value = current
	mp_label.text = "%d / %d" % [int(current), max_value]


func _on_stance_changed(stance: int) -> void:
	var data: Dictionary = player.STANCES[stance]
	var name_str: String = data.name
	stance_label.text = "%s STANCE   ·   Q to swap" % name_str.to_upper()
	stance_label.modulate = data.color
	var skills: Array = data.skills
	for i in range(slots.size()):
		var s: Dictionary = skills[i]
		slots[i].configure(s.name, str(i + 1), s.color, s.mana)
