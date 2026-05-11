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

# Fire dash-attack: aim with a radius circle, then dash to the clamped target,
# damaging anything along the path. Does NOT pause time.
const FIRE_AIM_RADIUS := 200.0
const FIRE_DASH_SPEED := 2200.0
const FIRE_DASH_MIN_TIME := 0.08
const FIRE_DASH_MAX_TIME := 0.30
const FIRE_DASH_COOLDOWN := 3.0
const FIRE_DASH_DAMAGE := 22
const FIRE_DASH_WIDTH := 80.0

# Water knockback: short cone in front, no damage, knocks enemies back.
const WATER_KNOCK_COOLDOWN := 3.0
const WATER_KNOCK_LENGTH := 180.0
const WATER_KNOCK_WIDTH := 140.0
const WATER_KNOCK_FORCE := 600.0

# Earth shield: 1.5s of full invulnerability.
const EARTH_SHIELD_DURATION := 1.5
const EARTH_SHIELD_COOLDOWN := 6.0
const EARTH_PASSIVE_REDUCTION := 0.5  # take 50% damage in earth stance.

# Wind dash: pure movement. No damage.
const WIND_DASH_TIME := 0.18
const WIND_DASH_SPEED := 2400.0
const WIND_DASH_COOLDOWN := 3.0
# Wind double-tap bonus: AOE around player on swap-into-wind.
const WIND_AOE_RADIUS := 140.0
const WIND_AOE_DAMAGE := 8
# Wind fly: hold Jump while airborne in wind stance to lift, drains fly_gauge.
const WIND_FLY_LIFT := -260.0       # negative = upward velocity while flying.
const WIND_FLY_MAX := 2.0           # seconds of flight from full gauge.
const WIND_FLY_REGEN_RATE := 1.0    # gauge units restored per second when not flying.

# Per-stance basic-attack cooldowns (LMB melee swing).
const BASIC_ATTACK_CD := {
	STANCE_FIRE: 0.30,
	STANCE_WATER: 0.30,
	STANCE_EARTH: 0.55,  # slow earth
	STANCE_WIND: 0.25,
}

# Ranged-mode damage / projectile speed by stance (Earth has none).
const RANGED_DAMAGE := {
	STANCE_FIRE: 12,
	STANCE_WATER: 0,
	STANCE_WIND: 10,
}
const RANGED_PROJECTILE_RANGE := {
	STANCE_FIRE: 820.0,
	STANCE_WATER: 520.0,
	STANCE_WIND: 900.0,
}
const RANGED_ATTACK_CD := {
	STANCE_FIRE: 0.45,
	STANCE_WATER: 0.50,
	STANCE_WIND: 0.30,  # wind ranged faster than fire
}

# Water "pour" (RMB hold + LMB hold while in water stance): spawns gravity-affected
# droplets at a steady rate so the stream looks like physically poured water.
const WATER_POUR_INTERVAL := 0.04   # seconds between droplets while pouring.
const WATER_POUR_SPEED := 700.0     # base launch speed of each droplet.
const WATER_POUR_SPEED_VARIANCE := 60.0
const WATER_POUR_SPREAD := 0.12     # +/- radians of random spray spread.

const STANCE_INFO := [
	{"name": "Fire",  "color": Color(1.0, 0.55, 0.25, 1.0), "key": "Q",   "skill_name": "Dash Strike", "skill_cd": FIRE_DASH_COOLDOWN},
	{"name": "Water", "color": Color(0.45, 0.78, 1.0, 1.0), "key": "E",   "skill_name": "Surge Push", "skill_cd": WATER_KNOCK_COOLDOWN},
	{"name": "Earth", "color": Color(0.8, 0.6, 0.3, 1.0),   "key": "F",   "skill_name": "Bulwark",     "skill_cd": EARTH_SHIELD_COOLDOWN},
	{"name": "Wind",  "color": Color(0.6, 0.95, 0.7, 1.0),  "key": "⇧", "skill_name": "Gale Dash",   "skill_cd": WIND_DASH_COOLDOWN},
]

const NEEDLE_SCENE := preload("res://scenes/entities/projectile/projectile.tscn")
const WATER_DROP_SCENE := preload("res://scenes/entities/water_drop/water_drop.tscn")
const StancePlayer := preload("res://scripts/entities/player/stance_player.gd")
const Element := preload("res://scripts/core/element.gd")

@export var max_health: int = 100
@export var attack_damage: int = 10
@export var spawn_position: Vector2 = Vector2(-500, 100)

var health: int
var facing: int = 1
var air_jumps_left: int = MAX_AIR_JUMPS
var attack_cd: float = 0.0
var current_stance: int = STANCE_FIRE
var stance_nodes: Array = []
var active_stance: StancePlayer

# Per-stance signature-skill cooldowns. Index by STANCE_FIRE..STANCE_WIND.
var skill_cd: Array = [0.0, 0.0, 0.0, 0.0]

# Double-tap detection: time since last tap (per stance key). Inf means "no recent tap".
var last_tap_time: Array = [INF, INF, INF, INF]

# Fire dash-attack state.
var fire_aim_active: bool = false
var fire_dash_time_left: float = 0.0
var fire_dash_velocity: Vector2 = Vector2.ZERO
var fire_dash_hit: Dictionary = {}  # bodies already damaged this dash.

# Wind dash state (no damage).
var wind_dash_time_left: float = 0.0

# Earth shield (full invulnerability while > 0).
var earth_shield_time_left: float = 0.0

# Wind fly gauge: drains while flying, regens otherwise.
var fly_gauge: float = WIND_FLY_MAX
var is_flying: bool = false

# Water-pour droplet timer (counts down between spawned drops while LMB is held in water+aim).
var water_pour_cd: float = 0.0

# RMB-hold aim mode.
var aim_mode_active: bool = false

signal health_changed(current: int, max_value: int)
signal stance_changed(stance: int)
signal skill_cd_changed(stance: int, remaining: float, max_cd: float)
signal fly_gauge_changed(current: float, max_value: float)

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
	_set_facing(facing)
	_refresh_active_stance()
	if aim_reticle:
		aim_reticle.visible = false
	health_changed.emit(health, max_health)
	stance_changed.emit(current_stance)
	fly_gauge_changed.emit(fly_gauge, WIND_FLY_MAX)


func _process(_delta: float) -> void:
	if aim_reticle:
		if aim_mode_active and _stance_can_aim(current_stance):
			aim_reticle.visible = true
			aim_reticle.global_position = get_global_mouse_position()
		else:
			aim_reticle.visible = false


func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	var input_x := Input.get_axis("move_left", "move_right")
	if input_x > 0.0 and facing != 1:
		_set_facing(1)
	elif input_x < 0.0 and facing != -1:
		_set_facing(-1)

	# Movement: dash skills override regular control.
	if fire_dash_time_left > 0.0:
		velocity = fire_dash_velocity
		_fire_dash_check_hits()
	elif wind_dash_time_left > 0.0:
		velocity.x = float(facing) * WIND_DASH_SPEED
		velocity.y = 0.0
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
		# Wind-stance flight: hold Jump while airborne to lift, drains gauge.
		_update_wind_fly(delta)

	move_and_slide()
	_update_animation_state()

	# RMB hold = aim mode (suppressed while fire-aim is open).
	aim_mode_active = (not fire_aim_active) and Input.is_action_pressed("aim_mode") and _stance_can_aim(current_stance)

	if Input.is_action_just_pressed("attack"):
		if fire_aim_active:
			_confirm_fire_dash()
		elif attack_cd <= 0.0 and fire_dash_time_left <= 0.0 and wind_dash_time_left <= 0.0:
			if aim_mode_active:
				if current_stance == STANCE_WATER:
					# Water uses continuous pour while LMB is held — fire first drop now.
					water_pour_cd = 0.0
					_try_water_pour(delta)
				else:
					_ranged_attack()
			else:
				_basic_attack()

	# Continuous water pour while RMB+LMB held in water stance.
	if (current_stance == STANCE_WATER
			and aim_mode_active
			and Input.is_action_pressed("attack")
			and not Input.is_action_just_pressed("attack")):
		_try_water_pour(delta)

	# Stance keys: 1-tap = use that stance's signature skill, 2-tap (within window) = swap.
	_handle_stance_key("stance_fire", STANCE_FIRE)
	_handle_stance_key("stance_water", STANCE_WATER)
	_handle_stance_key("stance_earth", STANCE_EARTH)
	_handle_stance_key("stance_wind", STANCE_WIND)


func _update_wind_fly(delta: float) -> void:
	# Only wind stance can fly. Must be airborne, holding jump, with gauge left.
	var want_fly: bool = (
		current_stance == STANCE_WIND
		and not is_on_floor()
		and Input.is_action_pressed("jump")
		and fly_gauge > 0.0
	)
	if want_fly:
		velocity.y = WIND_FLY_LIFT
		var prev: float = fly_gauge
		fly_gauge = maxf(0.0, fly_gauge - delta)
		if not is_flying:
			is_flying = true
		if fly_gauge != prev:
			fly_gauge_changed.emit(fly_gauge, WIND_FLY_MAX)
	else:
		if is_flying:
			is_flying = false
		if fly_gauge < WIND_FLY_MAX:
			var prev: float = fly_gauge
			fly_gauge = minf(WIND_FLY_MAX, fly_gauge + WIND_FLY_REGEN_RATE * delta)
			if fly_gauge != prev:
				fly_gauge_changed.emit(fly_gauge, WIND_FLY_MAX)


func _tick_timers(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	fire_dash_time_left = maxf(0.0, fire_dash_time_left - delta)
	wind_dash_time_left = maxf(0.0, wind_dash_time_left - delta)
	earth_shield_time_left = maxf(0.0, earth_shield_time_left - delta)
	for i in range(skill_cd.size()):
		var prev: float = skill_cd[i]
		var next: float = maxf(0.0, prev - delta)
		if next != prev:
			skill_cd[i] = next
			skill_cd_changed.emit(i, next, _get_skill_max(i))
		last_tap_time[i] = minf(INF, last_tap_time[i] + delta)


func _set_facing(direction: int) -> void:
	facing = direction
	for sn in stance_nodes:
		if sn:
			sn.set_facing(direction)


func _refresh_active_stance() -> void:
	for i in range(stance_nodes.size()):
		var sn: StancePlayer = stance_nodes[i]
		if sn == null:
			continue
		if i == current_stance:
			active_stance = sn
			sn.activate()
		else:
			sn.deactivate()


func _update_animation_state() -> void:
	if active_stance == null:
		return
	if fire_dash_time_left > 0.0 or wind_dash_time_left > 0.0:
		active_stance.play_state("dash")
	elif not is_on_floor():
		active_stance.play_state("jump" if velocity.y < 0.0 else "fall")
	elif absf(velocity.x) > 1.0:
		active_stance.play_state("run")
	else:
		active_stance.play_state("idle")


func _handle_stance_key(action: String, stance: int) -> void:
	if not Input.is_action_just_pressed(action):
		return
	# Fire: 1-tap toggles the aim, 2-tap (within window) swaps to fire stance.
	if stance == STANCE_FIRE:
		if last_tap_time[STANCE_FIRE] <= DOUBLE_TAP_WINDOW:
			if fire_aim_active:
				_close_fire_aim()
			_swap_to_stance(STANCE_FIRE)
			last_tap_time[STANCE_FIRE] = INF
			return
		last_tap_time[STANCE_FIRE] = 0.0
		_toggle_fire_aim()
		return
	# Pressing any other stance key while aiming Fire cancels the aim first.
	if fire_aim_active:
		_close_fire_aim()
	# Double-tap within window swaps to that stance.
	if last_tap_time[stance] <= DOUBLE_TAP_WINDOW:
		_swap_to_stance(stance)
		last_tap_time[stance] = INF
		return
	# First tap: trigger that stance's signature skill (works from any current stance).
	last_tap_time[stance] = 0.0
	_use_stance_skill(stance)


func _use_stance_skill(stance: int) -> void:
	if skill_cd[stance] > 0.0:
		return
	skill_cd[stance] = _get_skill_max(stance)
	skill_cd_changed.emit(stance, skill_cd[stance], _get_skill_max(stance))
	match stance:
		STANCE_WATER: _do_water_knockback()
		STANCE_EARTH: _do_earth_shield()
		STANCE_WIND:  _do_wind_dash()


func _swap_to_stance(stance: int) -> void:
	# Wind double-tap also fires an AOE around the (new) wind stance position.
	var bonus_aoe: bool = stance == STANCE_WIND and current_stance != STANCE_WIND
	if stance == current_stance:
		# Already in this stance — still treat as a (silent) re-confirmation.
		if bonus_aoe:
			_do_wind_aoe()
		return
	current_stance = stance
	_refresh_active_stance()
	stance_changed.emit(current_stance)
	if bonus_aoe:
		_do_wind_aoe()


# -------- Skills --------

func _toggle_fire_aim() -> void:
	if fire_aim_active:
		_close_fire_aim()
		return
	if skill_cd[STANCE_FIRE] > 0.0:
		return
	if fire_dash_time_left > 0.0:
		return
	_open_fire_aim()


func _open_fire_aim() -> void:
	fire_aim_active = true
	if dash_aimer:
		dash_aimer.start(STANCE_INFO[STANCE_FIRE].color, FIRE_AIM_RADIUS)


func _close_fire_aim() -> void:
	fire_aim_active = false
	if dash_aimer:
		dash_aimer.stop()


func _confirm_fire_dash() -> void:
	if not fire_aim_active:
		return
	var target: Vector2 = global_position
	if dash_aimer:
		target = dash_aimer.get_clamped_target()
	var dir: Vector2 = target - global_position
	var dist: float = dir.length()
	_close_fire_aim()
	if dist < 1.0:
		# Empty click on top of the player — refund (no cooldown, no dash).
		return
	# Lock in the cooldown only after a real confirmation.
	skill_cd[STANCE_FIRE] = _get_skill_max(STANCE_FIRE)
	skill_cd_changed.emit(STANCE_FIRE, skill_cd[STANCE_FIRE], _get_skill_max(STANCE_FIRE))

	var dash_dir: Vector2 = dir / dist
	fire_dash_velocity = dash_dir * FIRE_DASH_SPEED
	fire_dash_time_left = clampf(dist / FIRE_DASH_SPEED, FIRE_DASH_MIN_TIME, FIRE_DASH_MAX_TIME)
	fire_dash_hit.clear()

	if dash_dir.x > 0.1:
		_set_facing(1)
	elif dash_dir.x < -0.1:
		_set_facing(-1)

	# Confirm = swap to fire stance immediately.
	if current_stance != STANCE_FIRE:
		_swap_to_stance(STANCE_FIRE)

	if active_stance:
		active_stance.show_attack(STANCE_INFO[STANCE_FIRE].color)
		active_stance.play_state("dash")
		await get_tree().create_timer(fire_dash_time_left).timeout
		if active_stance:
			active_stance.hide_attack()


func _fire_dash_check_hits() -> void:
	# Sweep a box oriented along the dash direction and damage anything new it touches.
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60.0, FIRE_DASH_WIDTH)
	query.shape = rect
	var dash_angle: float = fire_dash_velocity.angle() if fire_dash_velocity.length_squared() > 0.0 else 0.0
	query.transform = Transform2D(dash_angle, global_position)
	query.collision_mask = 32
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hits: Array = space_state.intersect_shape(query, 8)
	for hit in hits:
		var body: Object = hit.get("collider")
		if body == null or not body.has_method("take_damage"):
			continue
		var id: int = body.get_instance_id()
		if fire_dash_hit.has(id):
			continue
		fire_dash_hit[id] = true
		body.take_damage(FIRE_DASH_DAMAGE, Element.FIRE, global_position)


func _do_water_knockback() -> void:
	# Short rectangle in front. No damage; just push enemies away.
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 32
	area.monitorable = false

	var coll := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(WATER_KNOCK_LENGTH, WATER_KNOCK_WIDTH)
	coll.shape = rect
	coll.position = Vector2(WATER_KNOCK_LENGTH / 2.0, 0.0)
	area.add_child(coll)

	var color: Color = STANCE_INFO[STANCE_WATER].color
	var visual := Polygon2D.new()
	visual.color = Color(color.r, color.g, color.b, 0.4)
	visual.polygon = PackedVector2Array([
		Vector2(0.0, -WATER_KNOCK_WIDTH / 2.0),
		Vector2(WATER_KNOCK_LENGTH, -WATER_KNOCK_WIDTH / 2.0),
		Vector2(WATER_KNOCK_LENGTH, WATER_KNOCK_WIDTH / 2.0),
		Vector2(0.0, WATER_KNOCK_WIDTH / 2.0),
	])
	area.add_child(visual)

	area.global_position = global_position
	area.rotation = 0.0 if facing > 0 else PI
	get_tree().current_scene.add_child(area)

	await get_tree().physics_frame
	for body in area.get_overlapping_bodies():
		if body.has_method("apply_knockback"):
			var dir: Vector2 = (body.global_position - global_position)
			if dir.length_squared() < 1.0:
				dir = Vector2(float(facing), 0.0)
			dir = dir.normalized()
			body.apply_knockback(Vector2(dir.x * WATER_KNOCK_FORCE, -WATER_KNOCK_FORCE * 0.35))

	var t := area.create_tween()
	t.tween_property(visual, "modulate:a", 0.0, 0.25)
	t.finished.connect(area.queue_free, CONNECT_ONE_SHOT)


func _do_earth_shield() -> void:
	earth_shield_time_left = EARTH_SHIELD_DURATION
	if active_stance:
		# Visual cue: a dome flash around the player (independent of stance change).
		var color: Color = STANCE_INFO[STANCE_EARTH].color
		var dome := Polygon2D.new()
		dome.color = Color(color.r, color.g, color.b, 0.35)
		var pts := PackedVector2Array()
		var n := 32
		var radius := 60.0
		for i in range(n):
			var a: float = float(i) * TAU / float(n)
			pts.append(Vector2(cos(a), sin(a)) * radius)
		dome.polygon = pts
		add_child(dome)
		var t := create_tween()
		t.tween_property(dome, "modulate:a", 0.0, EARTH_SHIELD_DURATION)
		t.finished.connect(dome.queue_free, CONNECT_ONE_SHOT)


func _do_wind_dash() -> void:
	wind_dash_time_left = WIND_DASH_TIME
	if active_stance:
		active_stance.play_state("dash")


func _do_wind_aoe() -> void:
	var color: Color = STANCE_INFO[STANCE_WIND].color
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var query_shape := CircleShape2D.new()
	query_shape.radius = WIND_AOE_RADIUS
	query.shape = query_shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 32
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hits: Array = space_state.intersect_shape(query, 32)
	for hit in hits:
		var body: Object = hit.get("collider")
		if body and body.has_method("take_damage"):
			body.take_damage(WIND_AOE_DAMAGE, Element.WIND, global_position)

	var visual := Polygon2D.new()
	visual.color = Color(color.r, color.g, color.b, 0.45)
	var pts := PackedVector2Array()
	var n := 28
	for i in range(n):
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cos(a), sin(a)) * WIND_AOE_RADIUS)
	visual.polygon = pts
	visual.scale = Vector2(0.4, 0.4)
	get_tree().current_scene.add_child(visual)
	visual.global_position = global_position
	var t := visual.create_tween()
	t.set_parallel(true)
	t.tween_property(visual, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(visual, "modulate:a", 0.0, 0.36)
	t.finished.connect(visual.queue_free, CONNECT_ONE_SHOT)


# -------- Basic attacks --------

func _basic_attack() -> void:
	var stance := active_stance
	if stance == null:
		return
	var elem := _stance_element()
	attack_cd = BASIC_ATTACK_CD.get(current_stance, 0.3)
	stance.show_attack(_stance_color())
	stance.play_state("attack")
	await get_tree().physics_frame
	var hits := 0
	for body in stance.get_attack_area().get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(attack_damage, elem, global_position)
			hits += 1
	if hits > 0:
		_reduce_skill_cooldowns(ATTACK_CD_REDUCTION_PER_HIT * float(hits))
	await get_tree().create_timer(0.08).timeout
	if stance == active_stance:
		stance.hide_attack()


func _try_water_pour(delta: float) -> void:
	water_pour_cd = maxf(0.0, water_pour_cd - delta)
	if water_pour_cd > 0.0:
		return
	water_pour_cd = WATER_POUR_INTERVAL
	_spawn_water_drop()


func _spawn_water_drop() -> void:
	if active_stance == null:
		return
	var spawn_pos: Vector2 = active_stance.get_projectile_spawn_position()
	var target: Vector2 = get_global_mouse_position()
	var dir: Vector2 = target - spawn_pos
	if dir.length_squared() < 1.0:
		dir = Vector2(float(facing), 0.0)
	dir = dir.normalized().rotated(randf_range(-WATER_POUR_SPREAD, WATER_POUR_SPREAD))
	# Face the pour direction so subsequent drops spawn on the correct side.
	if dir.x > 0.1:
		_set_facing(1)
	elif dir.x < -0.1:
		_set_facing(-1)
	var speed: float = WATER_POUR_SPEED + randf_range(-WATER_POUR_SPEED_VARIANCE, WATER_POUR_SPEED_VARIANCE)
	var drop: Area2D = WATER_DROP_SCENE.instantiate()
	get_tree().current_scene.add_child(drop)
	drop.global_position = spawn_pos
	drop.launch(dir * speed, _stance_color())


func _ranged_attack() -> void:
	if not _stance_can_aim(current_stance):
		return
	attack_cd = RANGED_ATTACK_CD.get(current_stance, 0.4)
	var damage: int = RANGED_DAMAGE.get(current_stance, 0)
	var range_val: float = RANGED_PROJECTILE_RANGE.get(current_stance, 600.0)
	var color: Color = _stance_color()
	var target_pos: Vector2 = get_global_mouse_position()
	var dx := target_pos.x - global_position.x
	if dx > 1.0:
		_set_facing(1)
	elif dx < -1.0:
		_set_facing(-1)
	var p: Area2D = NEEDLE_SCENE.instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = active_stance.get_projectile_spawn_position()
	var dir: Vector2 = target_pos - p.global_position
	if dir.length_squared() < 1.0:
		dir = Vector2(float(facing), 0.0)
	p.set_velocity(dir.normalized())
	p.configure(damage, color, _stance_element(), range_val)


func _reduce_skill_cooldowns(amount: float) -> void:
	if amount <= 0.0:
		return
	for i in range(skill_cd.size()):
		if skill_cd[i] <= 0.0:
			continue
		skill_cd[i] = maxf(0.0, skill_cd[i] - amount)
		skill_cd_changed.emit(i, skill_cd[i], _get_skill_max(i))


func _stance_can_aim(stance: int) -> bool:
	# Earth has no ranged mode.
	return stance != STANCE_EARTH


func _stance_element() -> int:
	match current_stance:
		STANCE_FIRE:  return Element.FIRE
		STANCE_WATER: return Element.WATER
		STANCE_WIND:  return Element.WIND
		STANCE_EARTH: return Element.EARTH
		_: return Element.NEUTRAL


func _stance_color() -> Color:
	return STANCE_INFO[current_stance].color


func _get_skill_max(stance: int) -> float:
	return float(STANCE_INFO[stance].skill_cd)


# -------- HUD-facing accessors --------

func get_skill_remaining(stance: int) -> float:
	return skill_cd[stance]


func get_skill_max(stance: int) -> float:
	return _get_skill_max(stance)


func get_stance_info(stance: int) -> Dictionary:
	return STANCE_INFO[stance]


func get_fly_remaining() -> float:
	return fly_gauge


func get_fly_max() -> float:
	return WIND_FLY_MAX


# -------- Damage --------

func take_damage(amount: int) -> void:
	if earth_shield_time_left > 0.0:
		# Full block during shield.
		return
	var dmg: int = amount
	if current_stance == STANCE_EARTH:
		dmg = maxi(0, roundi(float(amount) * (1.0 - EARTH_PASSIVE_REDUCTION)))
	health = maxi(0, health - dmg)
	health_changed.emit(health, max_health)
	if active_stance:
		active_stance.flash_damage()
	if health <= 0:
		_respawn()


func _respawn() -> void:
	health = max_health
	velocity = Vector2.ZERO
	global_position = spawn_position
	fire_dash_time_left = 0.0
	wind_dash_time_left = 0.0
	earth_shield_time_left = 0.0
	fly_gauge = WIND_FLY_MAX
	is_flying = false
	fly_gauge_changed.emit(fly_gauge, WIND_FLY_MAX)
	if fire_aim_active:
		_close_fire_aim()
	for i in range(skill_cd.size()):
		skill_cd[i] = 0.0
		skill_cd_changed.emit(i, 0.0, _get_skill_max(i))
	health_changed.emit(health, max_health)
