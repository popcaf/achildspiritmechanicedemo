extends "res://scripts/entities/player/stance_player.gd"

const COLOR := Color(1.0, 0.55, 0.25, 1.0)

# Aim a radius circle, then dash to the clamped target, damaging anything
# along the path. Does NOT pause time.
const AIM_RADIUS := 200.0
const DASH_SPEED := 2200.0
const DASH_MIN_TIME := 0.08
const DASH_MAX_TIME := 0.30
const DASH_COOLDOWN := 3.0
const DASH_DAMAGE := 22
const DASH_WIDTH := 80.0
const BASIC_CD := 0.30
const RANGED_CD := 0.45
const RANGED_DAMAGE := 12
const RANGED_RANGE := 820.0

var _aim_active: bool = false
var _dash_time_left: float = 0.0
var _dash_velocity: Vector2 = Vector2.ZERO
var _dash_hit: Dictionary = {}


func stance_name() -> String: return "Fire"
func stance_color() -> Color: return COLOR
func stance_key() -> String: return "Q"
func skill_name() -> String: return "Dash Strike"
func skill_cooldown_max() -> float: return DASH_COOLDOWN
func element_id() -> int: return Element.FIRE
func basic_attack_cooldown() -> float: return BASIC_CD
func ranged_attack_cooldown() -> float: return RANGED_CD


func tick(delta: float) -> void:
	super.tick(delta)
	_dash_time_left = maxf(0.0, _dash_time_left - delta)


func on_stance_key_pressed(is_double_tap: bool) -> void:
	if is_double_tap:
		if _aim_active:
			close_aim()
		return
	_toggle_aim()


func on_swap_out() -> void:
	if _aim_active:
		close_aim()


func is_aiming() -> bool:
	return _aim_active


func _toggle_aim() -> void:
	if _aim_active:
		close_aim()
		return
	if not skill_ready():
		return
	if _dash_time_left > 0.0:
		return
	_open_aim()


func _open_aim() -> void:
	_aim_active = true
	if player and player.dash_aimer:
		player.dash_aimer.start(COLOR, AIM_RADIUS)


func close_aim() -> void:
	_aim_active = false
	if player and player.dash_aimer:
		player.dash_aimer.stop()


# Player.gd calls this when attack is pressed while we're aiming.
func confirm_dash() -> void:
	if not _aim_active:
		return
	var target: Vector2 = player.global_position
	if player.dash_aimer:
		target = player.dash_aimer.get_clamped_target()
	var dir: Vector2 = target - player.global_position
	var dist: float = dir.length()
	close_aim()
	if dist < 1.0:
		# Empty click on top of the player — refund (no cooldown, no dash).
		return
	start_skill_cooldown()
	var dash_dir: Vector2 = dir / dist
	_dash_velocity = dash_dir * DASH_SPEED
	_dash_time_left = clampf(dist / DASH_SPEED, DASH_MIN_TIME, DASH_MAX_TIME)
	_dash_hit.clear()
	if dash_dir.x > 0.1:
		player.set_facing_dir(1)
	elif dash_dir.x < -0.1:
		player.set_facing_dir(-1)
	# Confirm = swap to fire stance immediately.
	if player.current_stance != player.STANCE_FIRE:
		player.swap_to_stance(player.STANCE_FIRE)
	show_attack(COLOR)
	play_state("dash")
	await get_tree().create_timer(_dash_time_left).timeout
	hide_attack()


func reset_on_respawn() -> void:
	_dash_time_left = 0.0
	_dash_hit.clear()
	if _aim_active:
		close_aim()


func is_locking_movement() -> bool:
	return _dash_time_left > 0.0


func get_locked_velocity() -> Vector2:
	return _dash_velocity


func during_locked_movement() -> void:
	# Sweep a box along the dash direction; damage anything new it touches.
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60.0, DASH_WIDTH)
	query.shape = rect
	var dash_angle: float = _dash_velocity.angle() if _dash_velocity.length_squared() > 0.0 else 0.0
	query.transform = Transform2D(dash_angle, player.global_position)
	query.collision_mask = 32
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hits: Array = space_state.intersect_shape(query, 8)
	for hit in hits:
		var body: Object = hit.get("collider")
		if body == null or not body.has_method("take_damage"):
			continue
		var id: int = body.get_instance_id()
		if _dash_hit.has(id):
			continue
		_dash_hit[id] = true
		body.take_damage(DASH_DAMAGE, Element.FIRE, player.global_position)


func start_ranged_attack() -> void:
	if player.attack_cd > 0.0:
		return
	player.attack_cd = RANGED_CD
	spawn_needle(RANGED_DAMAGE, COLOR, Element.FIRE, RANGED_RANGE)


@warning_ignore("unused_parameter")
func _on_state_changed(state: String) -> void:
	# Hook for fire-themed animations.
	# Add an AnimationPlayer/AnimatedSprite2D as a sibling of FlipRoot and drive it here.
	pass
