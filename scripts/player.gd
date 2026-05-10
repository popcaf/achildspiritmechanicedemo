extends CharacterBody2D

const GRAVITY := 1500.0
const MOVE_SPEED := 650.0
const JUMP_VELOCITY := -750.0
const MAX_AIR_JUMPS := 1
const DASH_SPEED := 2000.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 0.8
const STANCE_SWAP_COOLDOWN := 0.3
const MANA_PER_HIT := 10
const STANCE_WATER := 0
const STANCE_FIRE := 1

const STANCES := [
	{
		"name": "Water",
		"color": Color(0.45, 0.78, 1.0, 1.0),
		"skills": [
			{"name": "Frost",  "cooldown": 0.6, "mana": 10, "color": Color(0.5, 0.85, 1.0, 1.0)},
			{"name": "Tide",   "cooldown": 2.0, "mana": 30, "color": Color(0.25, 0.6, 1.0, 1.0)},
			{"name": "Mend",   "cooldown": 6.0, "mana": 50, "color": Color(0.5, 1.0, 0.75, 1.0)},
			{"name": "Wave",   "cooldown": 8.0, "mana": 70, "color": Color(0.15, 0.4, 0.95, 1.0)},
		],
	},
	{
		"name": "Fire",
		"color": Color(1.0, 0.55, 0.25, 1.0),
		"skills": [
			{"name": "Bolt",   "cooldown": 0.5, "mana": 12, "color": Color(1.0, 0.65, 0.25, 1.0)},
			{"name": "Flame",  "cooldown": 1.5, "mana": 30, "color": Color(1.0, 0.4, 0.15, 1.0)},
			{"name": "Ignite", "cooldown": 3.0, "mana": 35, "color": Color(1.0, 0.85, 0.35, 1.0)},
			{"name": "Meteor", "cooldown": 8.0, "mana": 70, "color": Color(0.95, 0.25, 0.1, 1.0)},
		],
	},
]

const NEEDLE_SCENE := preload("res://scenes/projectile.tscn")
const StancePlayer := preload("res://scripts/stance_player.gd")
const Element := preload("res://scripts/element.gd")

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
var stance_swap_cd: float = 0.0
var current_stance: int = STANCE_WATER
var skill_cd: Array = [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
var active_stance: StancePlayer
var pending_skill: int = -1
var aiming_active: bool = false

signal health_changed(current: int, max_value: int)
signal mana_changed(current: float, max_value: int)
signal stance_changed(stance: int)

@onready var water_stance: StancePlayer = $StanceHolder/WaterPlayer
@onready var fire_stance: StancePlayer = $StanceHolder/FirePlayer
@onready var aim_reticle: Node2D = $AimReticle
@onready var cast_page: Node = get_node_or_null(cast_page_path)


func _ready() -> void:
	add_to_group("player")
	health = max_health
	mana = float(max_mana)
	_set_facing(facing)
	_refresh_active_stance()
	if aim_reticle:
		aim_reticle.visible = false
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
		elif attack_cd <= 0.0 and dash_time_left <= 0.0:
			_basic_attack()

	if Input.is_action_just_pressed("ui_cancel") and aiming_active:
		_cancel_aim()

	if Input.is_action_just_pressed("dash") and dash_cd <= 0.0 and dash_time_left <= 0.0:
		_do_dash()

	if Input.is_action_just_pressed("stance_toggle") and stance_swap_cd <= 0.0:
		_toggle_stance()

	if Input.is_action_just_pressed("skill_1"):
		_trigger_skill(0)
	if Input.is_action_just_pressed("skill_2"):
		_trigger_skill(1)
	if Input.is_action_just_pressed("skill_3"):
		_trigger_skill(2)
	if Input.is_action_just_pressed("skill_4"):
		_trigger_skill(3)


func _tick_timers(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	dash_time_left = maxf(0.0, dash_time_left - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	stance_swap_cd = maxf(0.0, stance_swap_cd - delta)
	for stance_idx in range(skill_cd.size()):
		var arr: Array = skill_cd[stance_idx]
		for i in range(arr.size()):
			arr[i] = maxf(0.0, arr[i] - delta)


func _set_facing(direction: int) -> void:
	facing = direction
	if water_stance:
		water_stance.set_facing(direction)
	if fire_stance:
		fire_stance.set_facing(direction)


func _refresh_active_stance() -> void:
	if current_stance == STANCE_WATER:
		active_stance = water_stance
		water_stance.activate()
		fire_stance.deactivate()
	else:
		active_stance = fire_stance
		fire_stance.activate()
		water_stance.deactivate()


func _update_animation_state() -> void:
	if active_stance == null:
		return
	if dash_time_left > 0.0:
		active_stance.play_state("dash")
	elif not is_on_floor():
		active_stance.play_state("jump" if velocity.y < 0.0 else "fall")
	elif absf(velocity.x) > 1.0:
		active_stance.play_state("run")
	else:
		active_stance.play_state("idle")


func _trigger_skill(slot: int) -> void:
	if pending_skill != -1 or aiming_active:
		return
	if skill_cd[current_stance][slot] > 0.0:
		return
	var data: Dictionary = _get_skill_data(slot)
	if mana < float(data.mana):
		return
	pending_skill = slot
	if cast_page == null:
		# No cast page available: skip rhythm and go straight to aiming.
		aiming_active = true
		return
	cast_page.cast_completed.connect(_on_cast_completed, CONNECT_ONE_SHOT)
	cast_page.start_cast(data)


func _on_cast_completed(success: bool) -> void:
	if not success:
		pending_skill = -1
		aiming_active = false
		return
	aiming_active = true


func _cancel_aim() -> void:
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
	var cost: float = float(data.mana)
	if mana < cost:
		return
	mana -= cost
	mana_changed.emit(mana, max_mana)
	skill_cd[current_stance][slot] = float(data.cooldown)

	var dx := target_pos.x - global_position.x
	if dx > 1.0:
		_set_facing(1)
	elif dx < -1.0:
		_set_facing(-1)

	if current_stance == STANCE_WATER:
		match slot:
			0: _spawn_projectile(8, Color(0.5, 0.85, 1.0))
			1: _heavy_swing(28, Color(0.4, 0.7, 1.0))
			2: _heal(mend_amount)
			3: _heavy_swing(50, Color(0.2, 0.5, 1.0))
	else:
		match slot:
			0: _spawn_projectile(12, Color(1.0, 0.6, 0.2))
			1: _heavy_swing(35, Color(1.0, 0.45, 0.2))
			2: _aoe_blast_at(target_pos, 22, Color(1.0, 0.85, 0.3), 90.0)
			3: _heavy_swing(70, Color(1.0, 0.3, 0.1))


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
			body.take_damage(attack_damage, elem)
			hits += 1
	if hits > 0:
		_add_mana(MANA_PER_HIT * hits)
	await get_tree().create_timer(0.08).timeout
	stance.hide_attack()


func _heavy_swing(damage: int, color: Color) -> void:
	var stance := active_stance
	var elem := _stance_element()
	attack_cd = attack_cooldown
	stance.show_attack(color)
	stance.play_state("heavy")
	await get_tree().physics_frame
	for body in stance.get_attack_area().get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage, elem)
	await get_tree().create_timer(0.08).timeout
	stance.hide_attack()


func _spawn_projectile(damage: int, color: Color) -> void:
	var p: Area2D = NEEDLE_SCENE.instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = active_stance.get_projectile_spawn_position()
	p.set_direction(facing)
	p.configure(damage, color, _stance_element())


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
			body.take_damage(damage, elem)

	var t := area.create_tween()
	t.tween_property(visual, "modulate:a", 0.0, 0.3)
	t.finished.connect(area.queue_free, CONNECT_ONE_SHOT)


func _stance_element() -> int:
	return Element.WATER if current_stance == STANCE_WATER else Element.FIRE


func _do_dash() -> void:
	dash_time_left = DASH_TIME
	dash_cd = DASH_COOLDOWN


func _heal(amount: int) -> void:
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)


func _toggle_stance() -> void:
	current_stance = STANCE_FIRE if current_stance == STANCE_WATER else STANCE_WATER
	stance_swap_cd = STANCE_SWAP_COOLDOWN
	_refresh_active_stance()
	stance_changed.emit(current_stance)


func _stance_color() -> Color:
	return STANCES[current_stance].color


func _add_mana(amount: float) -> void:
	if amount <= 0.0:
		return
	mana = minf(float(max_mana), mana + amount)
	mana_changed.emit(mana, max_mana)


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
		aiming_active = false
		health_changed.emit(health, max_health)
		mana_changed.emit(mana, max_mana)
