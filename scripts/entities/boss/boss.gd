extends CharacterBody2D

# Boss with four attacks chosen by weighted random (weights biased by player
# distance + elevation). Only acts while the player is inside the boss zone.
#   1. Dash    — long-distance horizontal linear rush. Phases through everything
#                except the arena walls. Preferred at medium-to-long range.
#   2. Melee   — wide heavy swing in front. Preferred when player is close.
#   3. Ranged  — three-projectile fan toward the player. Preferred when far.
#   4. Jump    — parabolic leap (gravity-driven arc) onto the player's locked
#                position. Preferred when the player is on a platform.
#
# Status: a water-drop hit (Player water "pour" attack) applies SLOW for a few
# seconds — action speeds + movement are scaled down. Any non-water hit (which
# goes through take_damage) or the timeout clears it.

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

# Jump tunables — parabolic leap to the player's locked position. The launch
# velocity is computed from JUMP_FLIGHT_TIME and the locked target so gravity
# arcs the boss right onto the player instead of overshooting.
const JUMP_DAMAGE := 26
const JUMP_WINDUP := 0.60
const JUMP_RECOVERY := 0.70
const JUMP_FLIGHT_TIME := 0.70            # tuned so arc-peak comfortably clears map platforms
const JUMP_MIN_AIRBORNE := 0.10           # ignore landing detection for this long after liftoff
const JUMP_HIT_RADIUS := 95.0
const JUMP_ELEVATION_THRESHOLD := 70.0    # player must be at least this high (y is up-negative)

# Water slow — applied by water_drop.gd via on_water_drop(). Scales all
# action speeds for SLOW_DURATION seconds. Cleared early when the boss takes
# any non-water hit (water uses on_water_drop, not take_damage, so the slow
# doesn't accidentally cancel itself).
const SLOW_DURATION := 4.0
const SLOW_MULT := 0.45

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
const STATE_JUMPING := 4

const ATTACK_NONE := 0
const ATTACK_MELEE := 1
const ATTACK_DASH := 2
const ATTACK_RANGED := 3
const ATTACK_JUMP := 4

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

# Water-slow status.
var _slow_timer: float = 0.0
var _slow_label: Label = null

# Jump bookkeeping — start altitude is used to detect landing without relying
# on is_on_floor() (the jump still phases through everything via mask = walls).
var _jump_start_y: float = 0.0
var _jump_min_air: float = 0.0

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
	# Slow timer always uses real-time delta so the slow can't extend itself.
	if _slow_timer > 0.0:
		_slow_timer = maxf(0.0, _slow_timer - delta)
		if _slow_timer == 0.0:
			_clear_slow_visual()

	# Action timers tick at effective_delta so slow stretches windups + cooldowns.
	var effective_delta: float = delta * _speed_mult()
	_state_timer = maxf(0.0, _state_timer - effective_delta)
	_attack_cd = maxf(0.0, _attack_cd - effective_delta)
	_stun_timer = maxf(0.0, _stun_timer - delta)

	if _player == null or not is_instance_valid(_player):
		_player = _find_player()

	# Dash is a straight horizontal line, so kill vertical velocity. Jump is a
	# proper parabolic arc, so gravity always applies during the leap (even on
	# the takeoff frame when is_on_floor() is still true).
	if _state == STATE_DASHING:
		velocity.y = 0.0
	elif _state == STATE_JUMPING:
		velocity.y += GRAVITY * delta
	elif is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += GRAVITY * delta

	if _stun_timer > 0.0 and _state != STATE_DASHING and _state != STATE_JUMPING:
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
		STATE_JUMPING:
			_update_jumping(delta)
		STATE_RECOVERY:
			_update_recovery(delta)

	move_and_slide()


func _is_slowed() -> bool:
	return _slow_timer > 0.0


func _speed_mult() -> float:
	return SLOW_MULT if _is_slowed() else 1.0


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
		velocity.x = float(_facing) * MOVE_SPEED * 0.5 * _speed_mult()
		return

	_choose_and_start_attack(to_player)


func _choose_and_start_attack(to_player: Vector2) -> void:
	# Weights bias by distance but every option always has a non-zero chance,
	# so the boss feels unpredictable instead of strictly range-gated.
	var distance: float = to_player.length()
	var player_elevated: bool = to_player.y < -JUMP_ELEVATION_THRESHOLD

	var w_melee: float
	var w_dash: float
	var w_ranged: float
	var w_jump: float
	if distance <= RANGE_MELEE:
		w_melee = 4.0
		w_dash = 1.5
		w_ranged = 0.3
		w_jump = 0.4
	elif distance >= RANGE_FAR:
		w_melee = 0.2
		w_dash = 2.5
		w_ranged = 3.5
		w_jump = 0.8
	else:
		w_melee = 1.0
		w_dash = 3.0
		w_ranged = 1.2
		w_jump = 0.8

	# If the player is on a platform above, jump becomes the dominant pick and
	# melee gets de-weighted (it can't reach an elevated target anyway).
	if player_elevated:
		w_jump = 4.5
		w_melee *= 0.25

	var total: float = w_melee + w_dash + w_ranged + w_jump
	var roll: float = randf() * total
	var acc: float = w_melee
	if roll < acc:
		_start_attack(ATTACK_MELEE)
		return
	acc += w_dash
	if roll < acc:
		_start_attack(ATTACK_DASH)
		return
	acc += w_ranged
	if roll < acc:
		_start_attack(ATTACK_RANGED)
		return
	_start_attack(ATTACK_JUMP)


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
			var ranged_target: Vector2 = global_position + _attack_dir * 320.0
			if _player and is_instance_valid(_player):
				ranged_target = _player.global_position + Vector2(0.0, -40.0)
			_spawn_warning_global(ranged_target, Vector2(140.0, 140.0), RANGED_WINDUP)
		ATTACK_JUMP:
			_state_timer = JUMP_WINDUP
			body_visual.modulate = Color(0.5, 1.8, 1.8, 1.0)
			# Square telegraph on the locked landing spot — same warning style as
			# ranged, but bigger and aligned to the player's altitude so the
			# "leap target" is unambiguous.
			var jump_target: Vector2 = global_position + _attack_dir * 320.0
			if _player and is_instance_valid(_player):
				jump_target = _player.global_position
			_spawn_warning_global(jump_target, Vector2(180.0, 180.0), JUMP_WINDUP)
			if _player and _player.has_method("notify_incoming_attack"):
				_player.notify_incoming_attack(self, JUMP_WINDUP)


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
		ATTACK_JUMP:
			_begin_jump()


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
	var speed: float = DASH_SPEED * _speed_mult()
	velocity = _dash_dir * speed
	_dash_distance_left -= speed * delta

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


func _begin_jump() -> void:
	# Parabolic leap to the locked target. v_y is solved so y(T) lands on the
	# player's locked altitude under constant GRAVITY; v_x covers dx in the
	# same time. Slow scales the initial velocity (smaller, shorter arc).
	_state = STATE_JUMPING
	var target: Vector2 = global_position + _attack_dir * 320.0
	if _player and is_instance_valid(_player):
		target = _player.global_position
	var dx: float = target.x - global_position.x
	var dy: float = target.y - global_position.y
	var T: float = JUMP_FLIGHT_TIME
	var v_x: float = dx / T
	var v_y: float = dy / T - 0.5 * GRAVITY * T   # upward initial velocity (y is up-negative)
	var mult: float = _speed_mult()
	velocity = Vector2(v_x, v_y) * mult
	_jump_start_y = global_position.y
	_jump_min_air = JUMP_MIN_AIRBORNE
	_dash_hit_player = false
	# Phase through ground/platforms/dummies/player but stop at boss-arena walls.
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	collision_layer = 0
	collision_mask = WALL_MASK_BIT
	body_visual.modulate = Color(0.5, 1.8, 1.8, 1.0)


func _update_jumping(delta: float) -> void:
	# Gravity is applied by _physics_process; we just track damage + landing.
	_jump_min_air = maxf(0.0, _jump_min_air - delta)

	if not _dash_hit_player and _player and is_instance_valid(_player):
		var diff: Vector2 = _player.global_position - global_position
		if diff.length() <= JUMP_HIT_RADIUS and _player.has_method("take_damage"):
			_player.take_damage(JUMP_DAMAGE, self)
			_dash_hit_player = true

	# Landing = arc has returned to (or below) the starting altitude AND we are
	# on the way down. The min-air grace keeps frame-1 from short-circuiting.
	var landed: bool = velocity.y > 0.0 and global_position.y >= _jump_start_y
	if is_on_wall() or (_jump_min_air <= 0.0 and landed):
		_end_jump()


func _end_jump() -> void:
	# Snap back to start altitude so the arc doesn't leave the boss buried
	# slightly below the ground when collision restores.
	global_position.y = _jump_start_y
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	velocity = Vector2.ZERO
	body_visual.modulate = Color.WHITE
	_state = STATE_RECOVERY
	_state_timer = JUMP_RECOVERY


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
	elif _state == STATE_JUMPING:
		_end_jump()
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

	# A real hit clears the water slow (water uses on_water_drop, not this path,
	# so this only fires for non-water attacks).
	if _slow_timer > 0.0:
		_slow_timer = 0.0
		_clear_slow_visual()

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
	if _state == STATE_DASHING or _state == STATE_JUMPING:
		return
	velocity += impulse * KNOCKBACK_RESIST


# Called by water_drop.gd when a player-poured droplet hits the boss. Each drop
# refreshes the slow timer; non-water hits (via take_damage) clear it early.
func on_water_drop(_pos: Vector2) -> void:
	var was_slowed: bool = _slow_timer > 0.0
	_slow_timer = SLOW_DURATION
	if not was_slowed:
		_show_slow_visual()


func _show_slow_visual() -> void:
	if _slow_label and is_instance_valid(_slow_label):
		return
	_slow_label = Label.new()
	_slow_label.text = "SLOW"
	_slow_label.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0, 1.0))
	_slow_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_slow_label.add_theme_constant_override("outline_size", 4)
	_slow_label.add_theme_font_size_override("font_size", 16)
	_slow_label.offset_left = -40.0
	_slow_label.offset_top = -230.0
	_slow_label.offset_right = 40.0
	_slow_label.offset_bottom = -205.0
	_slow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_slow_label)


func _clear_slow_visual() -> void:
	if _slow_label and is_instance_valid(_slow_label):
		_slow_label.queue_free()
	_slow_label = null


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
