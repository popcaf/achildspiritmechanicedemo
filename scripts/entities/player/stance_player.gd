extends Node2D

const Element := preload("res://scripts/core/element.gd")
const NEEDLE_SCENE := preload("res://scenes/entities/projectile/projectile.tscn")

# Bound by player.gd in _ready(). Stances reach back through this for shared
# physics state (position, velocity, attack_cd, helpers).
var player: Node = null

# Signature-skill cooldown. Each stance ticks its own value down every frame
# (even when inactive — single-tap skills fire from any current stance).
var skill_cd: float = 0.0

var _facing: int = 1
var _current_state: String = ""

signal skill_cd_changed(remaining: float, max_value: float)
# Only the wind stance emits this; declared here so the base type advertises it.
@warning_ignore("unused_signal")
signal fly_gauge_changed(current: float, max_value: float)

@onready var flip_root: Node2D = $FlipRoot
@onready var body_visual: Polygon2D = $FlipRoot/Body
@onready var attack_area: Area2D = $FlipRoot/AttackArea
@onready var attack_visual: Polygon2D = $FlipRoot/AttackArea/Visual
@onready var projectile_spawn: Marker2D = $FlipRoot/ProjectileSpawn


func _ready() -> void:
	attack_area.monitoring = false
	attack_visual.visible = false


func bind_player(p: Node) -> void:
	player = p


# ---- Metadata (subclasses override) ----

func stance_name() -> String:
	return ""


func stance_color() -> Color:
	return Color.WHITE


func stance_key() -> String:
	return ""


func skill_name() -> String:
	return ""


func skill_cooldown_max() -> float:
	return 0.0


func element_id() -> int:
	return Element.NEUTRAL


func basic_attack_cooldown() -> float:
	return 0.3


func ranged_attack_cooldown() -> float:
	return 0.4


# Only the wind stance overrides this — used by the HUD's fly-gauge display.
func fly_gauge_max() -> float:
	return 0.0


func fly_gauge_current() -> float:
	return 0.0


# ---- Stance-specific public hooks the manager may call on any stance ----
# Default no-ops; the relevant stance overrides.

func is_aiming() -> bool:
	return false


func close_aim() -> void:
	pass


func confirm_dash() -> void:
	pass


func notify_incoming_attack(_attacker: Node, _time_to_strike: float) -> void:
	pass


func reset_on_respawn() -> void:
	pass


func stance_info() -> Dictionary:
	return {
		"name": stance_name(),
		"color": stance_color(),
		"key": stance_key(),
		"skill_name": skill_name(),
		"skill_cd": skill_cooldown_max(),
	}


# ---- Lifecycle ----

func activate(prev_stance: int) -> void:
	visible = true
	on_swap_in(prev_stance)


func deactivate() -> void:
	visible = false
	attack_area.monitoring = false
	attack_visual.visible = false
	on_swap_out()


func on_swap_in(_prev_stance: int) -> void:
	pass


func on_swap_out() -> void:
	pass


# ---- Per-frame ----
# Called for ALL stances every physics frame, even inactive ones, so a stance's
# single-tap skill can fire from any current stance (e.g. tapping Q while in
# water stance still opens fire-aim).

func tick(delta: float) -> void:
	if skill_cd > 0.0:
		var prev := skill_cd
		skill_cd = maxf(0.0, skill_cd - delta)
		if skill_cd != prev:
			skill_cd_changed.emit(skill_cd, skill_cooldown_max())


# ---- Input hooks ----
# Routed by player.gd. is_double_tap=true means the player double-tapped this
# stance's key (a swap will follow this call).

func on_stance_key_pressed(_is_double_tap: bool) -> void:
	pass


func on_stance_key_released() -> void:
	pass


# Called when this stance is the active one and LMB is pressed without aim.
func basic_attack() -> void:
	if player.attack_cd > 0.0:
		return
	player.attack_cd = basic_attack_cooldown()
	show_attack(stance_color())
	play_state("attack")
	await get_tree().physics_frame
	var hits := 0
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(player.attack_damage, element_id(), player.global_position)
			hits += 1
	if hits > 0:
		player.reduce_skill_cooldowns(player.ATTACK_CD_REDUCTION_PER_HIT * float(hits))
	await get_tree().create_timer(0.08).timeout
	hide_attack()


# Called when this stance is active, aim mode is on, and LMB is first pressed.
func start_ranged_attack() -> void:
	pass


# Called every frame while LMB is held in aim mode (after the initial press).
func continue_ranged_attack(_delta: float) -> void:
	pass


func can_aim() -> bool:
	return true


# ---- Movement ----
# is_locking_movement() = true overrides the player's normal velocity each
# frame with get_locked_velocity(). during_locked_movement() runs sweeping
# hit-checks for dashes that damage along the path.

func is_locking_movement() -> bool:
	return false


func get_locked_velocity() -> Vector2:
	return Vector2.ZERO


func during_locked_movement() -> void:
	pass


# Called on the active stance during normal (non-locked) movement so stances
# can layer effects on top of standard physics (wind fly uses this).
func apply_movement_modifier(_delta: float) -> void:
	pass


func motion_state(velocity: Vector2, on_floor: bool) -> String:
	if not on_floor:
		return "jump" if velocity.y < 0.0 else "fall"
	if absf(velocity.x) > 1.0:
		return "run"
	return "idle"


# ---- Damage modification ----
# Called by player.take_damage() — return -1.0 to mark the hit as fully
# consumed (used by earth-parry). is_active is true when this stance is the
# active one, allowing earth's passive reduction to be conditional.

func modify_incoming_damage(amount: float, _attacker: Node, _is_active: bool) -> float:
	return amount


# ---- Visual helpers ----

func set_facing(direction: int) -> void:
	_facing = direction
	flip_root.scale.x = float(direction)


func get_facing() -> int:
	return _facing


func get_attack_area() -> Area2D:
	return attack_area


func get_projectile_spawn_position() -> Vector2:
	return projectile_spawn.global_position


func show_attack(color: Color) -> void:
	attack_visual.color = color
	attack_visual.visible = true
	attack_area.monitoring = true


func hide_attack() -> void:
	attack_visual.visible = false
	attack_area.monitoring = false


func flash_damage() -> void:
	body_visual.modulate = Color(2.0, 0.6, 0.6)
	var t := create_tween()
	t.tween_property(body_visual, "modulate", Color.WHITE, 0.2)


func play_state(state: String) -> void:
	if state == _current_state:
		return
	_current_state = state
	_on_state_changed(state)


func _on_state_changed(_state: String) -> void:
	pass


# ---- Skill cooldown helpers ----

func start_skill_cooldown() -> void:
	skill_cd = skill_cooldown_max()
	skill_cd_changed.emit(skill_cd, skill_cooldown_max())


func skill_ready() -> bool:
	return skill_cd <= 0.0


func reduce_skill_cooldown(amount: float) -> void:
	if amount <= 0.0 or skill_cd <= 0.0:
		return
	skill_cd = maxf(0.0, skill_cd - amount)
	skill_cd_changed.emit(skill_cd, skill_cooldown_max())


# ---- Shared ranged needle helper (fire/wind) ----

func spawn_needle(damage: int, color: Color, element: int, range_val: float) -> void:
	var target_pos: Vector2 = player.get_global_mouse_position()
	var dx: float = target_pos.x - player.global_position.x
	if dx > 1.0:
		player.set_facing_dir(1)
	elif dx < -1.0:
		player.set_facing_dir(-1)
	var p: Area2D = NEEDLE_SCENE.instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = get_projectile_spawn_position()
	var dir: Vector2 = target_pos - p.global_position
	if dir.length_squared() < 1.0:
		dir = Vector2(float(_facing), 0.0)
	p.set_velocity(dir.normalized())
	p.configure(damage, color, element, range_val)
