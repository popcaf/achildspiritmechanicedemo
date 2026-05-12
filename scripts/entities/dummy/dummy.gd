extends CharacterBody2D

const GRAVITY := 1500.0
const FRICTION := 900.0
const KNOCKBACK_PER_DAMAGE := 20.0
const KNOCKBACK_LIFT_RATIO := 0.4
const DAMAGE_NUMBER := preload("res://scenes/effects/damage_number.tscn")
const Element := preload("res://scripts/core/element.gd")

# AI tunables
const PLAYER_GROUP := "player"
const CHASE_RANGE := 700.0       # player must be within this for the dummy to start chasing.
const ATTACK_RANGE := 115.0      # close enough to swing (approach distance).
const STRIKE_RANGE := 145.0      # actual hit reach (slightly longer than approach radius).
const MOVE_SPEED := 220.0
const ATTACK_DAMAGE := 8
const ATTACK_WINDUP := 0.40      # telegraph time before damage actually lands.
const ATTACK_RECOVERY := 0.35
const ATTACK_COOLDOWN := 1.20    # min time between strikes.
const STUN_TIME := 0.20          # brief stagger when hit.

# Jumping (platform pursuit + wall hop). Strong enough to reach mid-height
# platforms; the very highest in the map may need a second hop.
const JUMP_VELOCITY := -900.0
const JUMP_COOLDOWN := 0.65
const PLATFORM_JUMP_X_RANGE := 280.0   # dummy is within this much horizontally of player.
const PLATFORM_JUMP_Y_THRESHOLD := 45.0  # player must be at least this high above to trigger.

const ATTACK_STATE_IDLE := 0
const ATTACK_STATE_WINDUP := 1
const ATTACK_STATE_RECOVERY := 2

@export var max_health: int = 100
@export_enum("None", "Fire", "Water", "Wind") var weakness: int = 0
@export var aggressive: bool = true

var health: int

var _player: Node = null
var _facing: int = 1
var _attack_cd: float = 0.0
var _attack_state: int = ATTACK_STATE_IDLE
var _attack_timer: float = 0.0
var _stun_timer: float = 0.0
var _jump_cd: float = 0.0

signal died

@onready var label: Label = $Label
@onready var body_visual: Polygon2D = $Body
@onready var weakness_label: Label = $WeaknessLabel


func _ready() -> void:
	add_to_group("dummy")
	health = max_health
	_refresh_label()
	_apply_weakness_visuals()
	# Dummies should pass freely through each other — only the world and the
	# player should block them. Add bidirectional collision exceptions with
	# every existing dummy (and they'll add ones for us when they spawn).
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

	_stun_timer = maxf(0.0, _stun_timer - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_jump_cd = maxf(0.0, _jump_cd - delta)

	if _player == null or not is_instance_valid(_player):
		_player = _find_player()

	var can_act: bool = aggressive and _player != null and _stun_timer <= 0.0
	if can_act and _attack_state != ATTACK_STATE_IDLE:
		_tick_attack(delta)
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	elif can_act:
		_ai_chase_or_attack(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	move_and_slide()

	# Climb obstacles when blocked horizontally — uses the same jump as platform pursuit.
	if can_act and is_on_wall() and is_on_floor() and _jump_cd <= 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_cd = JUMP_COOLDOWN


func _ai_chase_or_attack(delta: float) -> void:
	var to_player: Vector2 = _player.global_position - global_position
	var distance: float = to_player.length()

	if distance > CHASE_RANGE:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		return

	if to_player.x > 4.0:
		_facing = 1
	elif to_player.x < -4.0:
		_facing = -1

	if distance <= ATTACK_RANGE and _attack_cd <= 0.0:
		_start_attack()
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	else:
		velocity.x = float(_facing) * MOVE_SPEED
		# Jump up when the player is on a higher platform and within reach.
		if (is_on_floor() and _jump_cd <= 0.0
				and to_player.y < -PLATFORM_JUMP_Y_THRESHOLD
				and absf(to_player.x) < PLATFORM_JUMP_X_RANGE):
			velocity.y = JUMP_VELOCITY
			_jump_cd = JUMP_COOLDOWN


func _start_attack() -> void:
	_attack_state = ATTACK_STATE_WINDUP
	_attack_timer = ATTACK_WINDUP
	body_visual.modulate = Color(1.6, 1.0, 0.55, 1.0)
	# Telegraph the strike so the player can wink-flash and time a parry.
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


# Called by the player when they successfully parry our windup. Long stagger,
# attack canceled, brief flash so the player can capitalize on the opening.
func on_parried() -> void:
	_attack_state = ATTACK_STATE_IDLE
	_attack_cd = ATTACK_COOLDOWN
	_stun_timer = 1.0
	body_visual.modulate = Color.WHITE
	_flash()
	# Knock back away from the player a little.
	if _player and is_instance_valid(_player):
		var away: Vector2 = (global_position - _player.global_position)
		if away.length_squared() < 1.0:
			away = Vector2(float(_facing) * -1.0, 0.0)
		away = away.normalized()
		velocity.x += away.x * 320.0
		velocity.y -= 200.0


func _spawn_swing_visual() -> void:
	var swing := Polygon2D.new()
	swing.color = Color(1.0, 0.5, 0.5, 0.55)
	var w: float = 130.0
	var h: float = 48.0
	swing.polygon = PackedVector2Array([
		Vector2(0.0, -h / 2.0),
		Vector2(w, -h / 2.0),
		Vector2(w, h / 2.0),
		Vector2(0.0, h / 2.0),
	])
	add_child(swing)
	swing.position = Vector2(float(_facing) * 16.0, -18.0)
	swing.scale.x = float(_facing)
	var t := create_tween()
	t.tween_property(swing, "modulate:a", 0.0, 0.25)
	t.finished.connect(swing.queue_free, CONNECT_ONE_SHOT)


func _find_player() -> Node:
	var nodes := get_tree().get_nodes_in_group(PLAYER_GROUP)
	if nodes.size() > 0:
		return nodes[0]
	return null


func apply_knockback(impulse: Vector2) -> void:
	velocity += impulse


func set_weakness(value: int) -> void:
	weakness = value
	if is_node_ready():
		_apply_weakness_visuals()


func take_damage(amount: int, element: int = Element.NEUTRAL, from_pos: Vector2 = Vector2.INF) -> void:
	var mult := _multiplier_for(element)
	var actual: int = maxi(0, roundi(float(amount) * mult))
	health = maxi(0, health - actual)
	_refresh_label()
	_flash()
	_spawn_damage_number(actual, mult)

	# Auto-knockback proportional to the damage actually dealt (so a crit
	# launches harder, a resist barely nudges). Caller passes the hit's source
	# position so direction is "away from the attacker"; if omitted, no knockback.
	if actual > 0 and from_pos.is_finite():
		var kdir: Vector2 = global_position - from_pos
		if kdir.length_squared() < 0.01:
			kdir = Vector2.RIGHT
		kdir = kdir.normalized()
		var force: float = float(actual) * KNOCKBACK_PER_DAMAGE
		velocity.x += kdir.x * force
		velocity.y -= force * KNOCKBACK_LIFT_RATIO

	# Brief stagger + cancel any in-progress windup so the dummy pauses on hit.
	_stun_timer = STUN_TIME
	if _attack_state == ATTACK_STATE_WINDUP:
		_attack_state = ATTACK_STATE_IDLE
		_attack_cd = ATTACK_COOLDOWN * 0.5
		body_visual.modulate = Color.WHITE

	if health <= 0:
		died.emit()
		queue_free()


func _multiplier_for(element: int) -> float:
	# Earth attacks ignore the weakness/resist system entirely — always flat damage.
	if element == Element.EARTH:
		return 1.0
	if weakness == Element.NEUTRAL or element == Element.NEUTRAL:
		return 1.0
	if weakness == element:
		return 2.0
	return 0.5


func _apply_weakness_visuals() -> void:
	match weakness:
		Element.FIRE:
			body_visual.color = Color(0.55, 0.7, 1.0, 1.0)
			weakness_label.text = "WEAK: FIRE"
			weakness_label.modulate = Color(1.0, 0.55, 0.25, 1.0)
			weakness_label.visible = true
		Element.WATER:
			body_visual.color = Color(1.0, 0.5, 0.45, 1.0)
			weakness_label.text = "WEAK: WATER"
			weakness_label.modulate = Color(0.45, 0.78, 1.0, 1.0)
			weakness_label.visible = true
		Element.WIND:
			body_visual.color = Color(0.95, 0.7, 0.45, 1.0)
			weakness_label.text = "WEAK: WIND"
			weakness_label.modulate = Color(0.6, 0.95, 0.7, 1.0)
			weakness_label.visible = true
		_:
			body_visual.color = Color(0.85, 0.85, 0.85, 1.0)
			weakness_label.text = ""
			weakness_label.visible = false


func _refresh_label() -> void:
	label.text = str(health)


func _flash() -> void:
	body_visual.modulate = Color(2.0, 0.6, 0.6)
	var tween := create_tween()
	tween.tween_property(body_visual, "modulate", Color.WHITE, 0.18)


func _spawn_damage_number(amount: int, multiplier: float) -> void:
	var dn := DAMAGE_NUMBER.instantiate()
	get_tree().current_scene.add_child(dn)
	dn.global_position = global_position + Vector2(randf_range(-12.0, 12.0), -28.0)
	dn.setup(amount, multiplier)
