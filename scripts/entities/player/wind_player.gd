extends "res://scripts/entities/player/stance_player.gd"

const COLOR := Color(0.6, 0.95, 0.7, 1.0)

# Gale dash: pure movement. No damage.
const DASH_TIME := 0.18
const DASH_SPEED := 2400.0
const DASH_COOLDOWN := 3.0

# Double-tap bonus: AOE around player on swap-into-wind.
const AOE_RADIUS := 140.0
const AOE_DAMAGE := 8

# Wind fly: hold Jump while airborne in wind stance to lift, drains fly_gauge.
const FLY_LIFT := -260.0
const FLY_MAX := 2.0
const FLY_REGEN_RATE := 1.0

const BASIC_CD := 0.25
const RANGED_CD := 0.30  # wind ranged faster than fire
const RANGED_DAMAGE := 10
const RANGED_RANGE := 900.0

var _dash_time_left: float = 0.0
var fly_gauge: float = FLY_MAX
var _is_flying: bool = false


func stance_name() -> String: return "Wind"
func stance_color() -> Color: return COLOR
func stance_key() -> String: return "⇧"
func skill_name() -> String: return "Gale Dash"
func skill_cooldown_max() -> float: return DASH_COOLDOWN
func element_id() -> int: return Element.WIND
func basic_attack_cooldown() -> float: return BASIC_CD
func ranged_attack_cooldown() -> float: return RANGED_CD
func fly_gauge_max() -> float: return FLY_MAX
func fly_gauge_current() -> float: return fly_gauge


func tick(delta: float) -> void:
	super.tick(delta)
	_dash_time_left = maxf(0.0, _dash_time_left - delta)


func on_stance_key_pressed(is_double_tap: bool) -> void:
	if is_double_tap:
		return
	_try_dash()


func on_swap_in(prev_stance: int) -> void:
	# Swap-INTO-wind from another stance fires an AOE burst around the player.
	if prev_stance != player.STANCE_WIND:
		_do_aoe()


func _try_dash() -> void:
	if not skill_ready():
		return
	start_skill_cooldown()
	_dash_time_left = DASH_TIME
	play_state("dash")


func is_locking_movement() -> bool:
	return _dash_time_left > 0.0


func get_locked_velocity() -> Vector2:
	return Vector2(float(player.facing) * DASH_SPEED, 0.0)


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


func _do_aoe() -> void:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var query_shape := CircleShape2D.new()
	query_shape.radius = AOE_RADIUS
	query.shape = query_shape
	query.transform = Transform2D(0.0, player.global_position)
	query.collision_mask = 32
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hits: Array = space_state.intersect_shape(query, 32)
	for hit in hits:
		var body: Object = hit.get("collider")
		if body and body.has_method("take_damage"):
			body.take_damage(AOE_DAMAGE, Element.WIND, player.global_position)

	var visual := Polygon2D.new()
	visual.color = Color(COLOR.r, COLOR.g, COLOR.b, 0.45)
	var pts := PackedVector2Array()
	var n := 28
	for i in range(n):
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cos(a), sin(a)) * AOE_RADIUS)
	visual.polygon = pts
	visual.scale = Vector2(0.4, 0.4)
	get_tree().current_scene.add_child(visual)
	visual.global_position = player.global_position
	var t := visual.create_tween()
	t.set_parallel(true)
	t.tween_property(visual, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(visual, "modulate:a", 0.0, 0.36)
	t.finished.connect(visual.queue_free, CONNECT_ONE_SHOT)


func reset_on_respawn() -> void:
	_dash_time_left = 0.0
	fly_gauge = FLY_MAX
	_is_flying = false
	fly_gauge_changed.emit(fly_gauge, FLY_MAX)


@warning_ignore("unused_parameter")
func _on_state_changed(state: String) -> void:
	# Hook for wind-themed animations.
	pass
