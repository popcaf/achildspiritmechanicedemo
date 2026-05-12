extends "res://scripts/entities/player/stance_player.gd"

const COLOR := Color(0.6, 0.95, 0.7, 1.0)

# Wind's signature: a push skill that knocks enemies away on BOTH the front
# and back of the player (two opposing knockback rectangles). Triggered by
# double-tapping R. The dash itself is universal (handled by player.gd).
const PUSH_COOLDOWN := 3.0
const PUSH_LENGTH := 200.0
const PUSH_WIDTH := 140.0
const PUSH_FORCE := 700.0
const PUSH_DAMAGE := 8

# Wind fly: hold Jump while airborne in wind stance to lift, drains fly_gauge.
const FLY_LIFT := -260.0
const FLY_MAX := 2.0
const FLY_REGEN_RATE := 1.0

const BASIC_CD := 0.25
const RANGED_CD := 0.30  # wind ranged faster than fire
const RANGED_DAMAGE := 10
const RANGED_RANGE := 900.0

var fly_gauge: float = FLY_MAX
var _is_flying: bool = false


func stance_name() -> String: return "Wind"
func stance_color() -> Color: return COLOR
func stance_key() -> String: return "R"
func skill_name() -> String: return "Wind Push"
func skill_cooldown_max() -> float: return PUSH_COOLDOWN
func element_id() -> int: return Element.WIND
func basic_attack_cooldown() -> float: return BASIC_CD
func ranged_attack_cooldown() -> float: return RANGED_CD
func fly_gauge_max() -> float: return FLY_MAX
func fly_gauge_current() -> float: return fly_gauge


func try_push_skill() -> void:
	# Triggered by player.gd on double-tap R. Knocks enemies away on both the
	# front and back of the player, applying damage along with the knockback.
	if not skill_ready():
		return
	start_skill_cooldown()
	_do_push(1)
	_do_push(-1)


# Wind fly: hold Jump while airborne, drains fly_gauge. Active stance only.
func apply_movement_modifier(delta: float) -> void:
	var want_fly: bool = (
		not player.is_on_floor()
		and Input.is_action_pressed("jump")
		and fly_gauge > 0.0
	)
	if want_fly:
		player.velocity.y = FLY_LIFT
		var prev: float = fly_gauge
		fly_gauge = maxf(0.0, fly_gauge - delta)
		if not _is_flying:
			_is_flying = true
		if fly_gauge != prev:
			fly_gauge_changed.emit(fly_gauge, FLY_MAX)
	else:
		if _is_flying:
			_is_flying = false
		if fly_gauge < FLY_MAX:
			var prev: float = fly_gauge
			fly_gauge = minf(FLY_MAX, fly_gauge + FLY_REGEN_RATE * delta)
			if fly_gauge != prev:
				fly_gauge_changed.emit(fly_gauge, FLY_MAX)


func start_ranged_attack() -> void:
	if player.attack_cd > 0.0:
		return
	player.attack_cd = RANGED_CD
	spawn_needle(RANGED_DAMAGE, COLOR, Element.WIND, RANGED_RANGE)


func _do_push(dir_sign: int) -> void:
	# Knockback rectangle extending PUSH_LENGTH in dir_sign (+1 = right, -1 = left).
	# Damages overlapping bodies and shoves them away from the player.
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 32
	area.monitorable = false

	var coll := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(PUSH_LENGTH, PUSH_WIDTH)
	coll.shape = rect
	coll.position = Vector2(PUSH_LENGTH / 2.0, 0.0)
	area.add_child(coll)

	var visual := Polygon2D.new()
	visual.color = Color(COLOR.r, COLOR.g, COLOR.b, 0.45)
	visual.polygon = PackedVector2Array([
		Vector2(0.0, -PUSH_WIDTH / 2.0),
		Vector2(PUSH_LENGTH, -PUSH_WIDTH / 2.0),
		Vector2(PUSH_LENGTH, PUSH_WIDTH / 2.0),
		Vector2(0.0, PUSH_WIDTH / 2.0),
	])
	area.add_child(visual)

	area.global_position = player.global_position
	area.rotation = 0.0 if dir_sign > 0 else PI
	get_tree().current_scene.add_child(area)

	await get_tree().physics_frame
	for body in area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(PUSH_DAMAGE, Element.WIND, player.global_position)
		if body.has_method("apply_knockback"):
			var away: Vector2 = body.global_position - player.global_position
			if away.length_squared() < 1.0:
				away = Vector2(float(dir_sign), 0.0)
			away = away.normalized()
			body.apply_knockback(Vector2(away.x * PUSH_FORCE, -PUSH_FORCE * 0.35))

	var t := area.create_tween()
	t.tween_property(visual, "modulate:a", 0.0, 0.25)
	t.finished.connect(area.queue_free, CONNECT_ONE_SHOT)


func reset_on_respawn() -> void:
	fly_gauge = FLY_MAX
	_is_flying = false
	fly_gauge_changed.emit(fly_gauge, FLY_MAX)


@warning_ignore("unused_parameter")
func _on_state_changed(state: String) -> void:
	# Hook for wind-themed animations.
	pass
