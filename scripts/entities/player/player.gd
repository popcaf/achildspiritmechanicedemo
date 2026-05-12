extends CharacterBody2D

const GRAVITY := 2500.0
const MOVE_SPEED := 650.0
const JUMP_VELOCITY := -850.0
const MAX_AIR_JUMPS := 1

const STANCE_FIRE := 0
const STANCE_WATER := 1
const STANCE_EARTH := 2
const STANCE_WIND := 3
const STANCE_COUNT := 4

const DOUBLE_TAP_WINDOW := 1.0
const ATTACK_CD_REDUCTION_PER_HIT := 0.4

# Universal dash: any stance can dash via Shift (the `dash` action).
# Cooldown shared across all stances, separate from each stance's signature.
const UNIVERSAL_DASH_TIME := 0.18
const UNIVERSAL_DASH_SPEED := 2400.0
const UNIVERSAL_DASH_COOLDOWN := 3.0

const StancePlayer := preload("res://scripts/entities/player/stance_player.gd")

@export var max_health: int = 100
@export var attack_damage: int = 15
@export var spawn_position: Vector2 = Vector2(-500, 100)

var health: int
var facing: int = 1
var air_jumps_left: int = MAX_AIR_JUMPS
var attack_cd: float = 0.0
var current_stance: int = STANCE_FIRE
var stance_nodes: Array = []
var active_stance: StancePlayer

# Universal dash state (shared across stances).
var dash_cd: float = 0.0
var dash_time_left: float = 0.0

# Double-tap detection: time since last tap (per stance key). INF means "no recent tap".
var last_tap_time: Array = [INF, INF, INF, INF]

# RMB-hold aim mode.
var aim_mode_active: bool = false

signal health_changed(current: int, max_value: int)
signal stance_changed(stance: int)
signal skill_cd_changed(stance: int, remaining: float, max_cd: float)
signal fly_gauge_changed(current: float, max_value: float)
signal dash_cd_changed(remaining: float, max_value: float)

@onready var fire_stance_node: StancePlayer = $StanceHolder/FirePlayer
@onready var water_stance_node: StancePlayer = $StanceHolder/WaterPlayer
@onready var earth_stance_node: StancePlayer = $StanceHolder/EarthPlayer
@onready var wind_stance_node: StancePlayer = $StanceHolder/WindPlayer
@onready var aim_reticle: Node2D = $AimReticle
@onready var dash_aimer: Node2D = $DashAimer


func _ready() -> void:
	add_to_group("player")
	health = max_health
	stance_nodes = [fire_stance_node, water_stance_node, earth_stance_node, wind_stance_node]
	for i in range(stance_nodes.size()):
		var sn: StancePlayer = stance_nodes[i]
		sn.bind_player(self)
		# Re-emit each stance's cooldown updates with the stance index for the HUD.
		var idx: int = i
		sn.skill_cd_changed.connect(func(remaining: float, max_v: float) -> void:
			skill_cd_changed.emit(idx, remaining, max_v))
	# Wind owns the fly gauge — forward its signal to the HUD.
	wind_stance_node.fly_gauge_changed.connect(func(c: float, m: float) -> void:
		fly_gauge_changed.emit(c, m))
	set_facing_dir(facing)
	_refresh_active_stance(current_stance)
	if aim_reticle:
		aim_reticle.visible = false
	health_changed.emit(health, max_health)
	stance_changed.emit(current_stance)
	fly_gauge_changed.emit(wind_stance_node.fly_gauge_current(), wind_stance_node.fly_gauge_max())


func _process(_delta: float) -> void:
	if aim_reticle:
		if aim_mode_active and _stance_can_aim(current_stance):
			aim_reticle.visible = true
			aim_reticle.global_position = get_global_mouse_position()
		else:
			aim_reticle.visible = false


func _physics_process(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	var prev_dash_cd: float = dash_cd
	dash_cd = maxf(0.0, dash_cd - delta)
	if dash_cd != prev_dash_cd:
		dash_cd_changed.emit(dash_cd, UNIVERSAL_DASH_COOLDOWN)
	dash_time_left = maxf(0.0, dash_time_left - delta)
	for i in range(stance_nodes.size()):
		stance_nodes[i].tick(delta)
		last_tap_time[i] = minf(INF, last_tap_time[i] + delta)

	var input_x := Input.get_axis("move_left", "move_right")
	if input_x > 0.0 and facing != 1:
		set_facing_dir(1)
	elif input_x < 0.0 and facing != -1:
		set_facing_dir(-1)

	# Movement: universal dash overrides everything; otherwise a stance's own
	# dash (fire) can override; otherwise normal control.
	if dash_time_left > 0.0:
		velocity = Vector2(float(facing) * UNIVERSAL_DASH_SPEED, 0.0)
	elif active_stance and active_stance.is_locking_movement():
		velocity = active_stance.get_locked_velocity()
		active_stance.during_locked_movement()
	else:
		velocity.x = input_x * MOVE_SPEED
		# Kill leftover upward momentum from a fire-dash (would otherwise launch
		# the player into the sky for ~0.7s before gravity catches up).
		if velocity.y < JUMP_VELOCITY:
			velocity.y = 0.0
		velocity.y += GRAVITY * delta
		if is_on_floor():
			air_jumps_left = MAX_AIR_JUMPS
			if Input.is_action_just_pressed("jump"):
				velocity.y = JUMP_VELOCITY
		else:
			if Input.is_action_just_pressed("jump") and air_jumps_left > 0:
				velocity.y = JUMP_VELOCITY
				air_jumps_left -= 1
		if Input.is_action_just_released("jump") and velocity.y < JUMP_VELOCITY * 0.4:
			velocity.y = JUMP_VELOCITY * 0.4
		if active_stance:
			active_stance.apply_movement_modifier(delta)

	move_and_slide()
	_update_animation_state()

	# RMB hold = aim mode (suppressed while fire-aim is open).
	aim_mode_active = (not fire_stance_node.is_aiming()
		and Input.is_action_pressed("aim_mode")
		and _stance_can_aim(current_stance))

	if Input.is_action_just_pressed("attack"):
		if fire_stance_node.is_aiming():
			fire_stance_node.confirm_dash()
		elif (attack_cd <= 0.0 and dash_time_left <= 0.0
				and active_stance and not active_stance.is_locking_movement()):
			if aim_mode_active:
				active_stance.start_ranged_attack()
			else:
				active_stance.basic_attack()

	# Continuous ranged hold (used by water-pour while RMB+LMB are held).
	if (aim_mode_active
			and Input.is_action_pressed("attack")
			and not Input.is_action_just_pressed("attack")
			and active_stance):
		active_stance.continue_ranged_attack(delta)

	if Input.is_action_just_pressed("dash"):
		try_universal_dash()

	_handle_stance_key("stance_fire", STANCE_FIRE)
	_handle_stance_key("stance_water", STANCE_WATER)
	_handle_stance_key_earth()
	_handle_stance_key_wind()


func _handle_stance_key(action: String, stance_idx: int) -> void:
	if Input.is_action_just_pressed(action):
		var is_double_tap: bool = last_tap_time[stance_idx] <= DOUBLE_TAP_WINDOW
		# Cross-cutting: any non-fire stance key cancels a pending fire aim.
		if stance_idx != STANCE_FIRE and fire_stance_node.is_aiming():
			fire_stance_node.close_aim()
		stance_nodes[stance_idx].on_stance_key_pressed(is_double_tap)
		if is_double_tap:
			swap_to_stance(stance_idx)
			last_tap_time[stance_idx] = INF
		else:
			last_tap_time[stance_idx] = 0.0
	if Input.is_action_just_released(action):
		stance_nodes[stance_idx].on_stance_key_released()


func _handle_stance_key_wind() -> void:
	# R: single tap = swap to wind. Double tap = swap to wind + push skill
	# (knocks enemies on both the front and back sides of the player).
	if Input.is_action_just_pressed("stance_wind"):
		var is_double_tap: bool = last_tap_time[STANCE_WIND] <= DOUBLE_TAP_WINDOW
		if fire_stance_node.is_aiming():
			fire_stance_node.close_aim()
		swap_to_stance(STANCE_WIND)
		if is_double_tap:
			wind_stance_node.try_push_skill()
			last_tap_time[STANCE_WIND] = INF
		else:
			last_tap_time[STANCE_WIND] = 0.0


func try_universal_dash() -> void:
	if dash_cd > 0.0 or dash_time_left > 0.0:
		return
	if active_stance and active_stance.is_locking_movement():
		return
	dash_cd = UNIVERSAL_DASH_COOLDOWN
	dash_time_left = UNIVERSAL_DASH_TIME
	dash_cd_changed.emit(dash_cd, UNIVERSAL_DASH_COOLDOWN)
	if active_stance:
		active_stance.play_state("dash")


func _handle_stance_key_earth() -> void:
	# Earth has the same dispatch shape as other stances, but ALSO cancels a
	# pending fire aim on single-tap (preserved from the original behavior).
	if Input.is_action_just_pressed("stance_earth"):
		var is_double_tap: bool = last_tap_time[STANCE_EARTH] <= DOUBLE_TAP_WINDOW
		if not is_double_tap and fire_stance_node.is_aiming():
			fire_stance_node.close_aim()
		earth_stance_node.on_stance_key_pressed(is_double_tap)
		if is_double_tap:
			swap_to_stance(STANCE_EARTH)
			last_tap_time[STANCE_EARTH] = INF
		else:
			last_tap_time[STANCE_EARTH] = 0.0
	if Input.is_action_just_released("stance_earth"):
		earth_stance_node.on_stance_key_released()


func swap_to_stance(stance_idx: int) -> void:
	if stance_idx == current_stance:
		return
	var prev: int = current_stance
	current_stance = stance_idx
	_refresh_active_stance(prev)
	stance_changed.emit(current_stance)


func _refresh_active_stance(prev_stance: int) -> void:
	for i in range(stance_nodes.size()):
		var sn: StancePlayer = stance_nodes[i]
		if sn == null:
			continue
		if i == current_stance:
			active_stance = sn
			sn.activate(prev_stance)
		else:
			sn.deactivate()


func set_facing_dir(direction: int) -> void:
	facing = direction
	for sn in stance_nodes:
		if sn:
			sn.set_facing(direction)


func _update_animation_state() -> void:
	if active_stance == null:
		return
	if dash_time_left > 0.0 or active_stance.is_locking_movement():
		active_stance.play_state("dash")
	else:
		active_stance.play_state(active_stance.motion_state(velocity, is_on_floor()))


func _stance_can_aim(stance_idx: int) -> bool:
	if stance_idx < 0 or stance_idx >= stance_nodes.size():
		return false
	return stance_nodes[stance_idx].can_aim()


func reduce_skill_cooldowns(amount: float) -> void:
	if amount <= 0.0:
		return
	for sn in stance_nodes:
		sn.reduce_skill_cooldown(amount)


# ---- Damage entry point ----

func take_damage(amount: int, attacker: Node = null) -> void:
	# Earth handles parry + block + passive reduction, always (not just when
	# active) — a parry primed from another stance still fires.
	var working: float = earth_stance_node.modify_incoming_damage(
		float(amount), attacker, current_stance == STANCE_EARTH)
	if working < 0.0:
		return  # parried — damage fully consumed
	var dmg: int = maxi(0, roundi(working))
	health = maxi(0, health - dmg)
	health_changed.emit(health, max_health)
	if active_stance:
		active_stance.flash_damage()
	if health <= 0:
		_respawn()


func notify_incoming_attack(attacker: Node, time_to_strike: float) -> void:
	earth_stance_node.notify_incoming_attack(attacker, time_to_strike)


func _respawn() -> void:
	health = max_health
	velocity = Vector2.ZERO
	global_position = spawn_position
	dash_cd = 0.0
	dash_time_left = 0.0
	dash_cd_changed.emit(0.0, UNIVERSAL_DASH_COOLDOWN)
	fire_stance_node.reset_on_respawn()
	earth_stance_node.reset_on_respawn()
	wind_stance_node.reset_on_respawn()
	for sn in stance_nodes:
		sn.skill_cd = 0.0
		sn.skill_cd_changed.emit(0.0, sn.skill_cooldown_max())
	health_changed.emit(health, max_health)


# ---- HUD-facing accessors ----

func get_skill_remaining(stance_idx: int) -> float:
	return stance_nodes[stance_idx].skill_cd


func get_skill_max(stance_idx: int) -> float:
	return stance_nodes[stance_idx].skill_cooldown_max()


func get_stance_info(stance_idx: int) -> Dictionary:
	return stance_nodes[stance_idx].stance_info()


func get_fly_remaining() -> float:
	return wind_stance_node.fly_gauge_current()


func get_fly_max() -> float:
	return wind_stance_node.fly_gauge_max()
