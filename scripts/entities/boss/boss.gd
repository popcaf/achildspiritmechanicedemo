extends CharacterBody2D

# Boss with three attacks chosen by weighted random (weights biased by player
# distance). Only acts while the player is inside the boss zone (x-range).
#   1. Dash    — long-distance linear rush. Phases through everything and damages
#                the player on contact. Preferred at medium-to-long range.
#   2. Melee   — wide heavy swing in front. Preferred when player is close.
#   3. Ranged  — three-projectile fan toward the player. Preferred when far.

const GRAVITY := 1500.0
const FRICTION := 1200.0
const Element := preload("res://scripts/core/element.gd")
const DAMAGE_NUMBER := preload("res://scenes/effects/damage_number.tscn")
const PROJECTILE := preload("res://scenes/entities/projectile/projectile.tscn")

const PLAYER_GROUP := "player"

# Boss-zone gate: boss is dormant unless the player's x is within this range.
@export var area_left: float = 3600.0
@export var area_right: float = 4800.0

# Distance buckets used by attack-weighting.
const RANGE_MELEE := 240.0
const RANGE_FAR := 700.0

const MOVE_SPEED := 160.0

# Melee tunables
const MELEE_DAMAGE := 22
const MELEE_WINDUP := 0.55
const MELEE_RECOVERY := 0.55
const MELEE_STRIKE_REACH := 280.0
const MELEE_STRIKE_HEIGHT := 110.0

# Dash tunables
const DASH_DAMAGE := 28
const DASH_WINDUP := 0.55
const DASH_RECOVERY := 0.75
const DASH_SPEED := 1700.0
const DASH_LENGTH := 1500.0          # "wild length" — crosses the arena
const DASH_HIT_RADIUS := 90.0

# Ranged tunables
const RANGED_DAMAGE := 14
const RANGED_WINDUP := 0.70
const RANGED_RECOVERY := 0.55
const RANGED_PROJ_SPEED := 760.0
const RANGED_PROJ_RANGE := 1500.0
const RANGED_SPREAD_DEG := 12.0

const ATTACK_COOLDOWN := 1.30
const STUN_TIME := 0.20
const KNOCKBACK_PER_DAMAGE := 6.0
const KNOCKBACK_LIFT_RATIO := 0.20
const KNOCKBACK_RESIST := 0.25       # bosses brace against knockback

# Boss-arena walls live on physics layer 7 (bit 6) — see project.godot.
# Dash phases through everything *except* this layer.
const WALL_MASK_BIT := 1 << 6

const STATE_IDLE := 0
const STATE_WINDUP := 1
const STATE_DASHING := 2
const STATE_RECOVERY := 3

const ATTACK_NONE := 0
const ATTACK_MELEE := 1
const ATTACK_DASH := 2
const ATTACK_RANGED := 3

@export var max_health: int = 600

var health: int

var _player: Node = null
var _facing: int = 1
var _state: int = STATE_IDLE
var _state_timer: float = 0.0
var _attack_cd: float = 0.0
var _stun_timer: float = 0.0
var _current_attack: int = ATTACK_NONE

var _dash_dir: Vector2 = Vector2.RIGHT
var _dash_distance_left: float = 0.0
var _dash_hit_player: bool = false
var _saved_layer: int = 0
var _saved_mask: int = 0

# Direction locked at windup start (so the warning telegraph matches the strike
# path even if the player moves during windup).
var _attack_dir: Vector2 = Vector2.RIGHT

@onready var body_visual: Polygon2D = $Body
@onready var label: Label = $Label
@onready var name_label: Label = $NameLabel

signal died


func _ready() -> void:
	# Sharing the "dummy" group means player attacks/projectiles already target it.
	add_to_group("dummy")
	add_to_group("boss")
	health = max_health
	_refresh_label()
	for other in get_tree().get_nodes_in_group("dummy"):
		if other == self or not (other is PhysicsBody2D):
			continue
		add_collision_exception_with(other)
		other.add_collision_exception_with(self)


func _physics_process(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_stun_timer = maxf(0.0, _stun_timer - delta)

	if _player == null or not is_instance_valid(_player):
		_player = _find_player()

	# Gravity is suppressed mid-dash so the rush stays a clean horizontal line.
	if _state == STATE_DASHING:
		velocity.y = 0.0
	elif is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += GRAVITY * delta

	if _stun_timer > 0.0 and _state != STATE_DASHING:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		move_and_slide()
		return

	match _state:
		STATE_IDLE:
			_update_idle(delta)
		STATE_WINDUP:
			_update_windup(delta)
		STATE_DASHING:
			_update_dashing(delta)
		STATE_RECOVERY:
			_update_recovery(delta)

	move_and_slide()


func _player_in_area() -> bool:
	if _player == null:
		return false
	var px: float = _player.global_position.x
	return px >= area_left and px <= area_right


func _update_idle(delta: float) -> void:
	if not _player_in_area() or _player == null:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		return

	var to_player: Vector2 = _player.global_position - global_position
	if to_player.x > 4.0:
		_facing = 1
	elif to_player.x < -4.0:
		_facing = -1

	if _attack_cd > 0.0:
		# Slowly creep toward the player between attacks so it doesn't feel static.
		velocity.x = float(_facing) * MOVE_SPEED * 0.5
		return

	_choose_and_start_attack(to_player.length())


func _choose_and_start_attack(distance: float) -> void:
	# Weights bias by distance but every option always has a non-zero chance,
	# so the boss feels unpredictable instead of strictly range-gated.
	var w_melee: float
	var w_dash: float
	var w_ranged: float
	if distance <= RANGE_MELEE:
		w_melee = 4.0
		w_dash = 1.5
		w_ranged = 0.3
	elif distance >= RANGE_FAR:
		w_melee = 0.2
		w_dash = 2.5
		w_ranged = 3.5
	else:
		w_melee = 1.0
		w_dash = 3.0
		w_ranged = 1.2

	var total: float = w_melee + w_dash + w_ranged
	var roll: float = randf() * total
	if roll < w_melee:
		_start_attack(ATTACK_MELEE)
	elif roll < w_melee + w_dash:
		_start_attack(ATTACK_DASH)
	else:
		_start_attack(ATTACK_RANGED)


func _start_attack(attack: int) -> void:
	_current_attack = attack
	_state = STATE_WINDUP
	velocity.x = 0.0

	# Lock the strike direction at windup start so the warning telegraph stays
	# in sync with the actual strike. Player can dodge by leaving the rectangle.
	var to_player: Vector2 = Vector2(float(_facing), 0.0)
	if _player and is_instance_valid(_player):
		var d: Vector2 = _player.global_position - global_position
		if d.length_squared() > 1.0:
			to_player = d
	_attack_dir = to_player.normalized()
	if absf(to_player.x) > 4.0:
		_facing = int(signf(to_player.x))

	match attack:
		ATTACK_MELEE:
			_state_timer = MELEE_WINDUP
			body_visual.modulate = Color(1.8, 0.9, 0.5, 1.0)
			_spawn_warning_local(
				Vector2(float(_facing) * MELEE_STRIKE_REACH * 0.5, -50.0),
				Vector2(MELEE_STRIKE_REACH, MELEE_STRIKE_HEIGHT),
				MELEE_WINDUP)
			if _player and _player.has_method("notify_incoming_attack"):
				_player.notify_incoming_attack(self, MELEE_WINDUP)
		ATTACK_DASH:
			_state_timer = DASH_WINDUP
			# Dash is purely horizontal — bake _dash_dir here so the warning and
			# the actual rush travel the same line.
			_dash_dir = Vector2(float(_facing), 0.0)
			body_visual.modulate = Color(1.8, 0.5, 1.7, 1.0)
			_spawn_warning_local(
				Vector2(_dash_dir.x * DASH_LENGTH * 0.5, -50.0),
				Vector2(DASH_LENGTH, DASH_HIT_RADIUS * 2.0),
				DASH_WINDUP)
			if _player and _player.has_method("notify_incoming_attack"):
				_player.notify_incoming_attack(self, DASH_WINDUP)
		ATTACK_RANGED:
			_state_timer = RANGED_WINDUP
			body_visual.modulate = Color(0.7, 0.85, 2.2, 1.0)
			# Drop a square marker on the player's locked position so the
			# barrage feels telegraphed instead of instant.
			var target: Vector2 = global_position + _attack_dir * 320.0
			if _player and is_instance_valid(_player):
				target = _player.global_position + Vector2(0.0, -40.0)
			_spawn_warning_global(target, Vector2(140.0, 140.0), RANGED_WINDUP)


func _update_windup(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	if _state_timer > 0.0:
		return
	match _current_attack:
		ATTACK_MELEE:
			_perform_melee()
			_state = STATE_RECOVERY
			_state_timer = MELEE_RECOVERY
		ATTACK_DASH:
			_begin_dash()
		ATTACK_RANGED:
			_perform_ranged()
			_state = STATE_RECOVERY
			_state_timer = RANGED_RECOVERY


func _perform_melee() -> void:
	_spawn_swing_visual(MELEE_STRIKE_REACH, MELEE_STRIKE_HEIGHT, Color(1.0, 0.55, 0.55, 0.55))
	body_visual.modulate = Color.WHITE
	if _player == null or not is_instance_valid(_player):
		return
	var to_player: Vector2 = _player.global_position - global_position
	var x_ok: bool = (signf(to_player.x) == float(_facing)) or absf(to_player.x) < 30.0
	if x_ok and absf(to_player.x) <= MELEE_STRIKE_REACH and absf(to_player.y) < MELEE_STRIKE_HEIGHT:
		if _player.has_method("take_damage"):
			_player.take_damage(MELEE_DAMAGE, self)


func _begin_dash() -> void:
	_state = STATE_DASHING
	# _dash_dir was locked at windup start so the rush stays on the telegraphed line.
	_dash_distance_left = DASH_LENGTH
	_dash_hit_player = false
	# Phase through ground/dummies/player but keep the boss-arena walls solid.
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	collision_layer = 0
	collision_mask = WALL_MASK_BIT
	body_visual.modulate = Color(1.5, 0.5, 1.6, 1.0)


func _update_dashing(delta: float) -> void:
	velocity = _dash_dir * DASH_SPEED
	var step: float = DASH_SPEED * delta
	_dash_distance_left -= step

	if not _dash_hit_player and _player and is_instance_valid(_player):
		var diff: Vector2 = _player.global_position - global_position
		if diff.length() <= DASH_HIT_RADIUS and _player.has_method("take_damage"):
			_player.take_damage(DASH_DAMAGE, self)
			_dash_hit_player = true

	# Stop when distance is spent OR a boss-arena wall is hit (is_on_wall picks
	# up the slide collision since the wall layer is the only thing in our mask).
	if _dash_distance_left <= 0.0 or is_on_wall():
		_end_dash()


func _end_dash() -> void:
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	velocity = Vector2.ZERO
	body_visual.modulate = Color.WHITE
	_state = STATE_RECOVERY
	_state_timer = DASH_RECOVERY


func _perform_ranged() -> void:
	body_visual.modulate = Color.WHITE
	var origin: Vector2 = global_position + Vector2(0.0, -40.0)
	# Use the direction locked at windup so projectiles travel toward the
	# warning square, not the player's current position.
	var base_dir: Vector2 = _attack_dir
	if base_dir.length_squared() < 0.01:
		base_dir = Vector2(float(_facing), 0.0)
	for i in range(3):
		var p: Area2D = PROJECTILE.instantiate()
		var offset_deg: float = float(i - 1) * RANGED_SPREAD_DEG
		var dir: Vector2 = base_dir.rotated(deg_to_rad(offset_deg))
		get_tree().current_scene.add_child(p)
		p.global_position = origin + dir * 30.0
		p.configure(RANGED_DAMAGE, Color(0.95, 0.4, 1.0, 1.0), Element.NEUTRAL, RANGED_PROJ_RANGE)
		p.speed = RANGED_PROJ_SPEED
		if "hostile" in p:
			p.hostile = true
		if p.has_method("set_velocity"):
			p.set_velocity(dir)


func _update_recovery(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	if _state_timer > 0.0:
		return
	_state = STATE_IDLE
	_attack_cd = ATTACK_COOLDOWN
	_current_attack = ATTACK_NONE


# Called by the player on a successful parry against our windup.
func on_parried() -> void:
	if _state == STATE_DASHING:
		_end_dash()
	_state = STATE_RECOVERY
	_state_timer = ATTACK_COOLDOWN
	_attack_cd = ATTACK_COOLDOWN
	_current_attack = ATTACK_NONE
	_stun_timer = 1.0
	body_visual.modulate = Color.WHITE
	_flash()
	if _player and is_instance_valid(_player):
		var away: Vector2 = global_position - _player.global_position
		if away.length_squared() < 1.0:
			away = Vector2(float(_facing) * -1.0, 0.0)
		away = away.normalized()
		velocity.x += away.x * 180.0
		velocity.y -= 100.0


func take_damage(amount: int, _element: int = Element.NEUTRAL, from_pos: Vector2 = Vector2.INF) -> void:
	# Boss ignores weakness multipliers — flat damage like the parry dummy.
	health = maxi(0, health - amount)
	_refresh_label()
	_flash()
	_spawn_damage_number(amount)

	if amount > 0 and from_pos.is_finite() and _state != STATE_DASHING:
		var kdir: Vector2 = global_position - from_pos
		if kdir.length_squared() < 0.01:
			kdir = Vector2.RIGHT
		kdir = kdir.normalized()
		var force: float = float(amount) * KNOCKBACK_PER_DAMAGE
		velocity.x += kdir.x * force * KNOCKBACK_RESIST
		velocity.y -= force * KNOCKBACK_LIFT_RATIO * KNOCKBACK_RESIST

	# Hits cancel a melee/ranged windup but never a dash (boss commits to the rush).
	if _state == STATE_WINDUP:
		_stun_timer = STUN_TIME
		_state = STATE_IDLE
		_attack_cd = maxf(_attack_cd, ATTACK_COOLDOWN * 0.4)
		_current_attack = ATTACK_NONE
		body_visual.modulate = Color.WHITE

	if health <= 0:
		died.emit()
		queue_free()


func apply_knockback(impulse: Vector2) -> void:
	if _state == STATE_DASHING:
		return
	velocity += impulse * KNOCKBACK_RESIST


func _spawn_warning_local(local_pos: Vector2, size: Vector2, duration: float) -> Node2D:
	# Red flashing telegraph parented to the boss — moves with it.
	return _build_warning(self, local_pos, size, duration)


func _spawn_warning_global(world_pos: Vector2, size: Vector2, duration: float) -> Node2D:
	# Telegraph fixed in world space — used for ranged where the marker should
	# stay on the target even if the boss shifts during windup.
	var parent: Node = get_tree().current_scene
	var holder: Node2D = _build_warning(parent, Vector2.ZERO, size, duration)
	holder.global_position = world_pos
	return holder


func _build_warning(parent: Node, local_pos: Vector2, size: Vector2, duration: float) -> Node2D:
	var holder := Node2D.new()
	holder.position = local_pos
	holder.z_index = 10
	parent.add_child(holder)

	var hw: float = size.x * 0.5
	var hh: float = size.y * 0.5
	var pts := PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh),
		Vector2(hw, hh), Vector2(-hw, hh),
	])

	var fill := Polygon2D.new()
	fill.color = Color(0.95, 0.2, 0.25, 0.35)
	fill.polygon = pts
	holder.add_child(fill)

	var border := Line2D.new()
	border.width = 3.0
	border.default_color = Color(1.0, 0.3, 0.35, 1.0)
	border.closed = true
	border.points = pts
	holder.add_child(border)

	# Pulse the fill alpha so the warning reads as "incoming!" instead of static.
	var t := create_tween().set_loops()
	t.tween_property(fill, "modulate:a", 1.0, 0.18)
	t.tween_property(fill, "modulate:a", 0.35, 0.18)

	get_tree().create_timer(duration).timeout.connect(holder.queue_free)
	return holder


func _spawn_swing_visual(reach: float, height: float, color: Color) -> void:
	var swing := Polygon2D.new()
	swing.color = color
	swing.polygon = PackedVector2Array([
		Vector2(0.0, -height / 2.0),
		Vector2(reach, -height / 2.0),
		Vector2(reach, height / 2.0),
		Vector2(0.0, height / 2.0),
	])
	add_child(swing)
	swing.position = Vector2(float(_facing) * 30.0, -50.0)
	swing.scale.x = float(_facing)
	var t := create_tween()
	t.tween_property(swing, "modulate:a", 0.0, 0.30)
	t.finished.connect(swing.queue_free, CONNECT_ONE_SHOT)


func _find_player() -> Node:
	var nodes := get_tree().get_nodes_in_group(PLAYER_GROUP)
	if nodes.size() > 0:
		return nodes[0]
	return null


func _refresh_label() -> void:
	if label:
		label.text = str(health) + " / " + str(max_health)


func _flash() -> void:
	body_visual.modulate = Color(2.0, 0.6, 0.6)
	var tween := create_tween()
	tween.tween_property(body_visual, "modulate", Color.WHITE, 0.18)


func _spawn_damage_number(amount: int) -> void:
	var dn := DAMAGE_NUMBER.instantiate()
	get_tree().current_scene.add_child(dn)
	dn.global_position = global_position + Vector2(randf_range(-20.0, 20.0), -120.0)
	dn.setup(amount, 1.0)
