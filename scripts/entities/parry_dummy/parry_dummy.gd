extends CharacterBody2D

# Stationary practice target for the Earth stance / parry training. Never
# chases; only stands and telegraphs attacks on a regular cycle so the player
# can practice F-press-just-before-impact parries.

const GRAVITY := 1500.0
const FRICTION := 900.0
const KNOCKBACK_PER_DAMAGE := 10.0
const KNOCKBACK_LIFT_RATIO := 0.25
const KNOCKBACK_RESIST := 0.4  # heavy enemy — incoming knockback is reduced.
const DAMAGE_NUMBER := preload("res://scenes/effects/damage_number.tscn")
const Element := preload("res://scripts/core/element.gd")

const PLAYER_GROUP := "player"
const TRIGGER_RANGE := 320.0      # attack only fires if player is within this radius.
const STRIKE_RANGE := 220.0       # actual hit reach.
const ATTACK_DAMAGE := 14
const ATTACK_WINDUP := 0.65       # generous windup — easy to read and parry.
const ATTACK_RECOVERY := 0.45
const ATTACK_COOLDOWN := 1.30
const STUN_TIME := 0.25

const ATTACK_STATE_IDLE := 0
const ATTACK_STATE_WINDUP := 1
const ATTACK_STATE_RECOVERY := 2

@export var max_health: int = 200

var health: int

var _player: Node = null
var _facing: int = 1
var _attack_cd: float = 0.0
var _attack_state: int = ATTACK_STATE_IDLE
var _attack_timer: float = 0.0
var _stun_timer: float = 0.0

signal died

@onready var label: Label = $Label
@onready var body_visual: Polygon2D = $Body


func _ready() -> void:
	# Sharing the "dummy" group keeps existing collision exceptions, area
	# detection, and player AI lookups working uniformly.
	add_to_group("dummy")
	health = max_health
	_refresh_label()
	for other in get_tree().get_nodes_in_group("dummy"):
		if other == self or not (other is PhysicsBody2D):
			continue
		add_collision_exception_with(other)
		other.add_collision_exception_with(self)


func _physics_process(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += GRAVITY * delta
	# No AI movement — always decelerate horizontally (so knockback fades).
	velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	_stun_timer = maxf(0.0, _stun_timer - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)

	if _player == null or not is_instance_valid(_player):
		_player = _find_player()

	if _player and _stun_timer <= 0.0:
		if _attack_state != ATTACK_STATE_IDLE:
			_tick_attack(delta)
		else:
			_maybe_start_attack()

	move_and_slide()


func _maybe_start_attack() -> void:
	if _attack_cd > 0.0:
		return
	var to_player: Vector2 = _player.global_position - global_position
	if to_player.length() > TRIGGER_RANGE:
		return
	if to_player.x > 4.0:
		_facing = 1
	elif to_player.x < -4.0:
		_facing = -1
	_start_attack()


func _start_attack() -> void:
	_attack_state = ATTACK_STATE_WINDUP
	_attack_timer = ATTACK_WINDUP
	body_visual.modulate = Color(1.6, 1.0, 0.55, 1.0)
	# Telegraph to the player so wink + parry timing works exactly like the dummy.
	if _player and _player.has_method("notify_incoming_attack"):
		_player.notify_incoming_attack(self, ATTACK_WINDUP)


func _tick_attack(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	if _attack_state == ATTACK_STATE_WINDUP:
		_do_strike()
		_attack_state = ATTACK_STATE_RECOVERY
		_attack_timer = ATTACK_RECOVERY
	else:
		_attack_state = ATTACK_STATE_IDLE
		_attack_cd = ATTACK_COOLDOWN
		body_visual.modulate = Color.WHITE


func _do_strike() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_spawn_swing_visual()
	var to_player: Vector2 = _player.global_position - global_position
	if to_player.length() <= STRIKE_RANGE and _player.has_method("take_damage"):
		_player.take_damage(ATTACK_DAMAGE, self)


# Called by the player when they successfully parry our windup.
func on_parried() -> void:
	_attack_state = ATTACK_STATE_IDLE
	_attack_cd = ATTACK_COOLDOWN * 1.5
	_stun_timer = 1.5
	body_visual.modulate = Color.WHITE
	_flash()
	if _player and is_instance_valid(_player):
		var away: Vector2 = global_position - _player.global_position
		if away.length_squared() < 1.0:
			away = Vector2(float(_facing) * -1.0, 0.0)
		away = away.normalized()
		velocity.x += away.x * 220.0
		velocity.y -= 120.0


func _spawn_swing_visual() -> void:
	var swing := Polygon2D.new()
	swing.color = Color(1.0, 0.5, 0.5, 0.55)
	var w: float = 200.0
	var h: float = 70.0
	swing.polygon = PackedVector2Array([
		Vector2(0.0, -h / 2.0),
		Vector2(w, -h / 2.0),
		Vector2(w, h / 2.0),
		Vector2(0.0, h / 2.0),
	])
	add_child(swing)
	swing.position = Vector2(float(_facing) * 24.0, -36.0)
	swing.scale.x = float(_facing)
	var t := create_tween()
	t.tween_property(swing, "modulate:a", 0.0, 0.30)
	t.finished.connect(swing.queue_free, CONNECT_ONE_SHOT)


func _find_player() -> Node:
	var nodes := get_tree().get_nodes_in_group(PLAYER_GROUP)
	if nodes.size() > 0:
		return nodes[0]
	return null


func apply_knockback(impulse: Vector2) -> void:
	# Heavy enemy: incoming knockback is reduced.
	velocity += impulse * KNOCKBACK_RESIST


func take_damage(amount: int, _element: int = Element.NEUTRAL, from_pos: Vector2 = Vector2.INF) -> void:
	# No weakness multiplier — these are parry-practice targets, not damage
	# scaling targets. Use raw damage so the player can focus on parry timing.
	health = maxi(0, health - amount)
	_refresh_label()
	_flash()
	_spawn_damage_number(amount, 1.0)

	if amount > 0 and from_pos.is_finite():
		var kdir: Vector2 = global_position - from_pos
		if kdir.length_squared() < 0.01:
			kdir = Vector2.RIGHT
		kdir = kdir.normalized()
		var force: float = float(amount) * KNOCKBACK_PER_DAMAGE
		velocity.x += kdir.x * force * KNOCKBACK_RESIST
		velocity.y -= force * KNOCKBACK_LIFT_RATIO * KNOCKBACK_RESIST

	_stun_timer = STUN_TIME
	if _attack_state == ATTACK_STATE_WINDUP:
		_attack_state = ATTACK_STATE_IDLE
		_attack_cd = ATTACK_COOLDOWN * 0.5
		body_visual.modulate = Color.WHITE

	if health <= 0:
		died.emit()
		queue_free()


func _refresh_label() -> void:
	label.text = str(health)


func _flash() -> void:
	body_visual.modulate = Color(2.0, 0.6, 0.6)
	var tween := create_tween()
	tween.tween_property(body_visual, "modulate", Color.WHITE, 0.18)


func _spawn_damage_number(amount: int, multiplier: float) -> void:
	var dn := DAMAGE_NUMBER.instantiate()
	get_tree().current_scene.add_child(dn)
	dn.global_position = global_position + Vector2(randf_range(-12.0, 12.0), -75.0)
	dn.setup(amount, multiplier)
