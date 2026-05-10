extends CharacterBody2D

const GRAVITY := 3000.0
const MOVE_SPEED := 650.0
const JUMP_VELOCITY := -850.0
const MAX_AIR_JUMPS := 1
const DASH_SPEED := 2000.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 0.8
const STANCE_SWAP_COOLDOWN := 2.5
const MANA_PER_HIT := 10
const STANCE_WATER := 0
const STANCE_FIRE := 1
const STANCE_WIND := 2
const STANCE_EARTH := 3

const SWAP_TRAVEL_DISTANCE := 240.0
const SWAP_TRAVEL_TIME := 0.16
const SWAP_DAMAGE := 18
const SWAP_SWEEP_HEIGHT := 80.0
const SWAP_KNOCKBACK_X := 380.0
const SWAP_KNOCKBACK_Y := -200.0
const SWAP_AOE_RADIUS := 110.0
const SWAP_AOE_DAMAGE := 8
const SWAP_AOE_KNOCKBACK := 380.0
const SWAP_AOE_LIFT := -280.0

const STANCES := [
	{
		"name": "Water",
		"color": Color(0.45, 0.78, 1.0, 1.0),
		"skills": [
			{"name": "Frost",  "cooldown": 0.6, "mana": 10, "range": 520.0, "color": Color(0.5, 0.85, 1.0, 1.0)},
			{"name": "Tide",   "cooldown": 2.0, "mana": 30, "range": 130.0, "color": Color(0.25, 0.6, 1.0, 1.0)},
			{"name": "Mend",   "cooldown": 6.0, "mana": 50, "range": 0.0,   "color": Color(0.5, 1.0, 0.75, 1.0)},
			{"name": "Wave",   "cooldown": 8.0, "mana": 70, "range": 220.0, "color": Color(0.15, 0.4, 0.95, 1.0)},
		],
	},
	{
		"name": "Fire",
		"color": Color(1.0, 0.55, 0.25, 1.0),
		"skills": [
			{"name": "Bolt",   "cooldown": 0.5, "mana": 12, "range": 820.0, "color": Color(1.0, 0.65, 0.25, 1.0)},
			{"name": "Flame",  "cooldown": 1.5, "mana": 30, "range": 90.0,  "color": Color(1.0, 0.4, 0.15, 1.0)},
			{"name": "Ignite", "cooldown": 3.0, "mana": 35, "range": 280.0, "color": Color(1.0, 0.85, 0.35, 1.0)},
			{"name": "Meteor", "cooldown": 8.0, "mana": 70, "range": 200.0, "color": Color(0.95, 0.25, 0.1, 1.0)},
		],
	},
	{
		"name": "Wind",
		"color": Color(0.6, 0.95, 0.7, 1.0),
		"skills": [
			{"name": "Gust",    "cooldown": 0.5, "mana": 10, "range": 600.0, "color": Color(0.7, 1.0, 0.8, 1.0)},
			{"name": "Cyclone", "cooldown": 2.0, "mana": 30, "range": 140.0, "color": Color(0.55, 0.95, 0.85, 1.0)},
			{"name": "Glide",   "cooldown": 5.0, "mana": 35, "range": 300.0, "color": Color(0.7, 1.0, 0.65, 1.0)},
			{"name": "Tempest", "cooldown": 8.0, "mana": 70, "range": 220.0, "color": Color(0.4, 0.85, 0.7, 1.0)},
		],
	},
	{
		"name": "Earth",
		"color": Color(0.8, 0.6, 0.3, 1.0),
		"skills": [
			{"name": "Stone",   "cooldown": 0.6, "mana": 12, "range": 480.0, "color": Color(0.85, 0.7, 0.4, 1.0)},
			{"name": "Quake",   "cooldown": 2.5, "mana": 35, "range": 160.0, "color": Color(0.75, 0.55, 0.3, 1.0)},
			{"name": "Bulwark", "cooldown": 6.0, "mana": 45, "range": 0.0,   "color": Color(0.65, 0.5, 0.25, 1.0)},
			{"name": "Rupture", "cooldown": 8.0, "mana": 70, "range": 220.0, "color": Color(0.95, 0.75, 0.3, 1.0)},
		],
	},
]

const NEEDLE_SCENE := preload("res://scenes/entities/projectile/projectile.tscn")
const StancePlayer := preload("res://scripts/entities/player/stance_player.gd")
const Element := preload("res://scripts/core/element.gd")

@export var max_health: int = 100
@export var attack_damage: int = 10
@export var attack_cooldown: float = 0.3
@export var max_mana: int = 100
@export var mend_amount: int = 30
@export var spawn_position: Vector2 = Vector2(-500, 100)
@export var cast_page_path: NodePath = ^"../CastPage"

var health: int
var mana: float
var facing: int = 1
var air_jumps_left: int = MAX_AIR_JUMPS
var attack_cd: float = 0.0
var dash_time_left: float = 0.0
var dash_cd: float = 0.0
var swap_time_left: float = 0.0
var swap_aiming: bool = false
var swap_velocity: Vector2 = Vector2.ZERO
var _swap_phase_active: bool = false
var stance_swap_cd: float = 0.0
var current_stance: int = STANCE_WATER
var skill_cd: Array = []
var active_stance: StancePlayer
var pending_skill: int = -1
var pending_swap_stance: int = -1
var aiming_active: bool = false
var stance_nodes: Array = []

signal health_changed(current: int, max_value: int)
signal mana_changed(current: float, max_value: int)
signal stance_changed(stance: int)

@onready var water_stance: StancePlayer = $StanceHolder/WaterPlayer
@onready var fire_stance: StancePlayer = $StanceHolder/FirePlayer
@onready var wind_stance: StancePlayer = $StanceHolder/WindPlayer
@onready var earth_stance: StancePlayer = $StanceHolder/EarthPlayer
@onready var aim_reticle: Node2D = $AimReticle
@onready var swap_aimer: Node = $SwapAimer
@onready var swap_range_aimer: Node2D = $SwapRangeAimer
@onready var cast_page: Node = get_node_or_null(cast_page_path)


func _ready() -> void:
	add_to_group("player")
	health = max_health
	mana = float(max_mana)
	stance_nodes = [water_stance, fire_stance, wind_stance, earth_stance]
	skill_cd.clear()
	for _i in range(STANCES.size()):
		skill_cd.append([0.0, 0.0, 0.0, 0.0])
	_set_facing(facing)
	_refresh_active_stance()
	if aim_reticle:
		aim_reticle.visible = false
	if swap_aimer:
		swap_aimer.configure(STANCES, current_stance)
		swap_aimer.stance_selected.connect(_on_stance_selected)
		swap_aimer.stance_aim_requested.connect(_on_stance_aim_requested)
		swap_aimer.swap_cancelled.connect(_on_swap_cancelled)
	if swap_range_aimer:
		swap_range_aimer.aim_confirmed.connect(_on_swap_range_confirmed)
		swap_range_aimer.aim_cancelled.connect(_on_swap_range_cancelled)
	health_changed.emit(health, max_health)
	mana_changed.emit(mana, max_mana)
	stance_changed.emit(current_stance)


func _process(_delta: float) -> void:
	if aim_reticle:
		if aiming_active:
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

	if dash_time_left > 0.0:
		velocity.x = float(facing) * DASH_SPEED
		velocity.y = 0.0
	elif swap_time_left > 0.0:
		velocity = swap_velocity
	else:
		velocity.x = input_x * MOVE_SPEED
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

	move_and_slide()
	_update_animation_state()

	if Input.is_action_just_pressed("attack"):
		if aiming_active:
			_execute_pending_skill(get_global_mouse_position())
		elif attack_cd <= 0.0 and dash_time_left <= 0.0 and swap_time_left <= 0.0:
			_basic_attack()

	if aiming_active and (Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("cancel_skill")):
		_cancel_skill()

	if Input.is_action_just_pressed("dash") and dash_cd <= 0.0 and dash_time_left <= 0.0 and swap_time_left <= 0.0:
		_do_dash()

	if Input.is_action_just_pressed("stance_toggle") and stance_swap_cd <= 0.0 and not swap_aiming:
		if aiming_active or pending_skill != -1:
			_cancel_skill()
		_open_swap_hud()

	if Input.is_action_just_pressed("skill_1"):
		_trigger_skill(0)
	if Input.is_action_just_pressed("skill_2"):
		_trigger_skill(1)
	if Input.is_action_just_pressed("skill_3"):
		_trigger_skill(2)
	if Input.is_action_just_pressed("skill_4"):
		_trigger_skill(3)

	if _swap_phase_active and swap_time_left <= 0.0:
		_end_swap_phase()


func _tick_timers(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	dash_time_left = maxf(0.0, dash_time_left - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	swap_time_left = maxf(0.0, swap_time_left - delta)
	stance_swap_cd = maxf(0.0, stance_swap_cd - delta)
	for stance_idx in range(skill_cd.size()):
		var arr: Array = skill_cd[stance_idx]
		for i in range(arr.size()):
			arr[i] = maxf(0.0, arr[i] - delta)


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
	if dash_time_left > 0.0 or swap_time_left > 0.0:
		active_stance.play_state("dash")
	elif not is_on_floor():
		active_stance.play_state("jump" if velocity.y < 0.0 else "fall")
	elif absf(velocity.x) > 1.0:
		active_stance.play_state("run")
	else:
		active_stance.play_state("idle")


func _trigger_skill(slot: int) -> void:
	if pending_skill != -1 or aiming_active or swap_aiming or pending_swap_stance != -1:
		return
	if skill_cd[current_stance][slot] > 0.0:
		return
	var data: Dictionary = _get_skill_data(slot)
	var cost: float = float(data.mana)
	if mana < cost:
		return
	mana -= cost
	mana_changed.emit(mana, max_mana)
	pending_skill = slot
	aiming_active = true


func _cancel_skill() -> void:
	aiming_active = false
	pending_skill = -1


func _execute_pending_skill(target_pos: Vector2) -> void:
	if pending_skill < 0:
		aiming_active = false
		return
	var slot := pending_skill
	pending_skill = -1
	aiming_active = false

	var data: Dictionary = _get_skill_data(slot)
	skill_cd[current_stance][slot] = float(data.cooldown)
	var range_val: float = float(data.get("range", 100.0))

	var dx := target_pos.x - global_position.x
	if dx > 1.0:
		_set_facing(1)
	elif dx < -1.0:
		_set_facing(-1)

	match current_stance:
		STANCE_WATER:
			match slot:
				0: _spawn_projectile_at(target_pos, 8, Color(0.5, 0.85, 1.0), range_val)
				1: _swing_at(target_pos, 28, Color(0.4, 0.7, 1.0), range_val)
				2: _heal(mend_amount)
				3: _swing_at(target_pos, 50, Color(0.2, 0.5, 1.0), range_val)
		STANCE_FIRE:
			match slot:
				0: _spawn_projectile_at(target_pos, 12, Color(1.0, 0.6, 0.2), range_val)
				1: _swing_at(target_pos, 35, Color(1.0, 0.45, 0.2), range_val)
				2: _aoe_blast_at(_clamp_target(target_pos, range_val), 22, Color(1.0, 0.85, 0.3), 90.0)
				3: _swing_at(target_pos, 70, Color(1.0, 0.3, 0.1), range_val)
		STANCE_WIND:
			match slot:
				0: _spawn_projectile_at(target_pos, 9, Color(0.7, 1.0, 0.8), range_val)
				1: _swing_at(target_pos, 26, Color(0.55, 0.95, 0.85), range_val, 90.0)
				2: _aoe_blast_at(_clamp_target(target_pos, range_val), 18, Color(0.75, 1.0, 0.85), 110.0)
				3: _swing_at(target_pos, 55, Color(0.4, 0.85, 0.7), range_val, 90.0)
		STANCE_EARTH:
			match slot:
				0: _spawn_projectile_at(target_pos, 11, Color(0.85, 0.7, 0.4), range_val)
				1: _aoe_blast_at(global_position, 24, Color(0.75, 0.55, 0.3), 120.0)
				2: _heal(int(float(mend_amount) * 0.6))
				3: _swing_at(target_pos, 65, Color(0.95, 0.75, 0.3), range_val, 80.0)


func _get_skill_data(slot: int) -> Dictionary:
	return STANCES[current_stance].skills[slot]


func _basic_attack() -> void:
	var stance := active_stance
	var elem := _stance_element()
	attack_cd = attack_cooldown
	stance.show_attack(_stance_color())
	stance.play_state("attack")
	await get_tree().physics_frame
	var hits := 0
	for body in stance.get_attack_area().get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(attack_damage, elem, global_position)
			hits += 1
	if hits > 0:
		_add_mana(MANA_PER_HIT * hits)
	await get_tree().create_timer(0.08).timeout
	stance.hide_attack()


func _swing_at(target_pos: Vector2, damage: int, color: Color, length: float, width: float = 70.0) -> void:
	var elem := _stance_element()
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 32
	area.monitorable = false

	var coll := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, width)
	coll.shape = rect
	coll.position = Vector2(length / 2.0, 0.0)
	area.add_child(coll)

	var visual := Polygon2D.new()
	visual.color = Color(color.r, color.g, color.b, 0.45)
	visual.polygon = PackedVector2Array([
		Vector2(0.0, -width / 2.0),
		Vector2(length, -width / 2.0),
		Vector2(length, width / 2.0),
		Vector2(0.0, width / 2.0),
	])
	area.add_child(visual)

	area.global_position = global_position
	var dir: Vector2 = target_pos - global_position
	if dir.length_squared() < 1.0:
		dir = Vector2(float(facing), 0.0)
	area.rotation = dir.angle()

	get_tree().current_scene.add_child(area)

	await get_tree().physics_frame
	for body in area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage, elem, global_position)

	var t := area.create_tween()
	t.tween_property(visual, "modulate:a", 0.0, 0.2)
	t.finished.connect(area.queue_free, CONNECT_ONE_SHOT)


func _spawn_projectile_at(target_pos: Vector2, damage: int, color: Color, range_limit: float) -> void:
	var p: Area2D = NEEDLE_SCENE.instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = active_stance.get_projectile_spawn_position()
	var dir: Vector2 = target_pos - p.global_position
	if dir.length_squared() < 1.0:
		dir = Vector2(float(facing), 0.0)
	p.set_velocity(dir.normalized())
	p.configure(damage, color, _stance_element(), range_limit)


func _aoe_blast_at(at_pos: Vector2, damage: int, color: Color, radius: float) -> void:
	var elem := _stance_element()
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 32
	area.monitorable = false

	var coll := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = radius
	coll.shape = circ
	area.add_child(coll)

	var visual := Polygon2D.new()
	visual.color = Color(color.r, color.g, color.b, 0.45)
	var pts := PackedVector2Array()
	var n := 24
	for i in range(n):
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	visual.polygon = pts
	area.add_child(visual)

	area.global_position = at_pos
	get_tree().current_scene.add_child(area)

	await get_tree().physics_frame
	for body in area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage, elem, at_pos)

	var t := area.create_tween()
	t.tween_property(visual, "modulate:a", 0.0, 0.3)
	t.finished.connect(area.queue_free, CONNECT_ONE_SHOT)


func _stance_element() -> int:
	match current_stance:
		STANCE_WATER: return Element.WATER
		STANCE_FIRE:  return Element.FIRE
		STANCE_WIND:  return Element.WIND
		STANCE_EARTH: return Element.EARTH
		_: return Element.NEUTRAL


func _do_dash() -> void:
	dash_time_left = DASH_TIME
	dash_cd = DASH_COOLDOWN


func _begin_swap_phase() -> void:
	# During the swap dash, ignore collisions with dummies so the player can
	# pass through them. Walls (not in the "dummy" group) still block normally.
	if _swap_phase_active:
		return
	_swap_phase_active = true
	for d in get_tree().get_nodes_in_group("dummy"):
		if d is PhysicsBody2D:
			add_collision_exception_with(d)


func _end_swap_phase() -> void:
	if not _swap_phase_active:
		return
	_swap_phase_active = false
	for d in get_tree().get_nodes_in_group("dummy"):
		if d is PhysicsBody2D and is_instance_valid(d):
			remove_collision_exception_with(d)


func _heal(amount: int) -> void:
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)


func _open_swap_hud() -> void:
	if swap_aiming:
		return
	pending_swap_stance = -1
	swap_aiming = true
	if swap_aimer:
		swap_aimer.configure(STANCES, current_stance)
		swap_aimer.start_aiming()
	get_tree().paused = true


func _close_swap_hud() -> void:
	if not swap_aiming:
		return
	swap_aiming = false
	if swap_aimer:
		swap_aimer.stop_aiming()
	get_tree().paused = false


func _on_stance_selected(stance_idx: int, _use_skill: bool) -> void:
	# Hover-to-switch: stay in the wheel so the player can keep browsing stances.
	if stance_idx == current_stance:
		return
	_switch_stance(stance_idx)
	if swap_aimer:
		swap_aimer.set_current_stance(current_stance)


func _on_stance_aim_requested(stance_idx: int) -> void:
	# Hide wheel but stay paused — range-aimer takes over while paused.
	swap_aiming = false
	if swap_aimer:
		swap_aimer.stop_aiming()
	pending_swap_stance = stance_idx
	if swap_range_aimer:
		var stance_color: Color = STANCES[stance_idx].color
		swap_range_aimer.start_aiming(stance_color, SWAP_TRAVEL_DISTANCE)


func _on_swap_range_confirmed(target_pos: Vector2) -> void:
	var stance := pending_swap_stance
	pending_swap_stance = -1
	if swap_range_aimer:
		swap_range_aimer.stop_aiming()
	get_tree().paused = false
	if stance >= 0:
		_execute_swap_skill_at(target_pos, stance)


func _on_swap_range_cancelled() -> void:
	pending_swap_stance = -1
	if swap_range_aimer:
		swap_range_aimer.stop_aiming()
	get_tree().paused = false


func _on_swap_cancelled() -> void:
	_close_swap_hud()


func _switch_stance(stance_idx: int) -> void:
	if stance_idx == current_stance:
		return
	current_stance = stance_idx
	_refresh_active_stance()
	stance_changed.emit(current_stance)


func _execute_swap_skill_at(target_pos: Vector2, target_stance: int) -> void:
	var dir: Vector2 = target_pos - global_position
	var dist: float = dir.length()
	if dist > SWAP_TRAVEL_DISTANCE:
		dist = SWAP_TRAVEL_DISTANCE
	var travel_dir: Vector2 = Vector2(float(facing), 0.0)
	if dir.length_squared() > 1.0:
		travel_dir = dir.normalized()

	if travel_dir.x > 0.1:
		_set_facing(1)
	elif travel_dir.x < -0.1:
		_set_facing(-1)

	swap_velocity = travel_dir * (dist / SWAP_TRAVEL_TIME)
	swap_time_left = SWAP_TRAVEL_TIME
	stance_swap_cd = STANCE_SWAP_COOLDOWN
	_begin_swap_phase()
	# Flip stance FIRST so both swap effects use the destination element/color.
	current_stance = target_stance
	_refresh_active_stance()
	stance_changed.emit(current_stance)
	_do_swap_attack(travel_dir, dist)
	_do_swap_aoe(global_position + travel_dir * dist)


func _do_swap_attack(travel_dir: Vector2, length: float) -> void:
	# Stance has already been flipped by _execute_swap_skill, so this reads the NEW
	# element/color — the one the player is swapping INTO.
	var elem := _stance_element()
	var color := _stance_color()
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 32
	area.monitorable = false

	var height := SWAP_SWEEP_HEIGHT

	var coll := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, height)
	coll.shape = rect
	coll.position = Vector2(length / 2.0, 0.0)
	area.add_child(coll)

	var visual := Polygon2D.new()
	visual.color = Color(color.r, color.g, color.b, 0.5)
	visual.polygon = PackedVector2Array([
		Vector2(0.0, -height / 2.0),
		Vector2(length, -height / 2.0),
		Vector2(length, height / 2.0),
		Vector2(0.0, height / 2.0),
	])
	area.add_child(visual)

	area.global_position = global_position
	area.rotation = travel_dir.angle()

	get_tree().current_scene.add_child(area)

	await get_tree().physics_frame
	for body in area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(SWAP_DAMAGE, elem, global_position)

	var t := area.create_tween()
	t.tween_property(visual, "modulate:a", 0.0, 0.25)
	t.finished.connect(area.queue_free, CONNECT_ONE_SHOT)


func _do_swap_aoe(at_pos: Vector2) -> void:
	# Circular shockwave at the landing point. Damages a little, knocks dummies
	# radially outward and up. Uses a synchronous physics query so damage
	# resolves immediately rather than depending on a deferred Area2D update.
	var elem := _stance_element()
	var color := _stance_color()

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var query_shape := CircleShape2D.new()
	query_shape.radius = SWAP_AOE_RADIUS
	query.shape = query_shape
	query.transform = Transform2D(0.0, at_pos)
	query.collision_mask = 32
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hits: Array = space_state.intersect_shape(query, 32)
	for hit in hits:
		var body: Object = hit.get("collider")
		if body == null:
			continue
		if body.has_method("take_damage"):
			body.take_damage(SWAP_AOE_DAMAGE, elem, at_pos)

	# Visual-only shockwave (collision was handled by the query above).
	var visual := Polygon2D.new()
	visual.color = Color(color.r, color.g, color.b, 0.5)
	var pts := PackedVector2Array()
	var n := 28
	for i in range(n):
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cos(a), sin(a)) * SWAP_AOE_RADIUS)
	visual.polygon = pts
	visual.scale = Vector2(0.4, 0.4)

	get_tree().current_scene.add_child(visual)
	visual.global_position = at_pos

	var t := visual.create_tween()
	t.set_parallel(true)
	t.tween_property(visual, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(visual, "modulate:a", 0.0, 0.36)
	t.finished.connect(visual.queue_free, CONNECT_ONE_SHOT)


func _stance_color() -> Color:
	return STANCES[current_stance].color


func _add_mana(amount: float) -> void:
	if amount <= 0.0:
		return
	mana = minf(float(max_mana), mana + amount)
	mana_changed.emit(mana, max_mana)


func _clamp_target(target_pos: Vector2, max_range: float) -> Vector2:
	if max_range <= 0.0:
		return target_pos
	var to_target: Vector2 = target_pos - global_position
	if to_target.length() <= max_range:
		return target_pos
	return global_position + to_target.normalized() * max_range


func get_skill_remaining(slot: int) -> float:
	return skill_cd[current_stance][slot]


func get_skill_max(slot: int) -> float:
	return float(_get_skill_data(slot).cooldown)


func get_skill_cost(slot: int) -> int:
	return int(_get_skill_data(slot).mana)


func can_afford_skill(slot: int) -> bool:
	return mana >= float(_get_skill_data(slot).mana)


func get_dash_remaining() -> float:
	return dash_cd


func get_dash_max() -> float:
	return DASH_COOLDOWN


func get_swap_remaining() -> float:
	return stance_swap_cd


func get_swap_max() -> float:
	return STANCE_SWAP_COOLDOWN


func take_damage(amount: int) -> void:
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	if active_stance:
		active_stance.flash_damage()
	if health <= 0:
		health = max_health
		mana = float(max_mana)
		velocity = Vector2.ZERO
		global_position = spawn_position
		pending_skill = -1
		pending_swap_stance = -1
		aiming_active = false
		swap_aiming = false
		swap_velocity = Vector2.ZERO
		swap_time_left = 0.0
		_end_swap_phase()
		if swap_aimer:
			swap_aimer.stop_aiming()
		if swap_range_aimer:
			swap_range_aimer.stop_aiming()
		get_tree().paused = false
		health_changed.emit(health, max_health)
		mana_changed.emit(mana, max_mana)
