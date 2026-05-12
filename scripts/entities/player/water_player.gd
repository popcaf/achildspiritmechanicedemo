extends "res://scripts/entities/player/stance_player.gd"

const WATER_DROP_SCENE := preload("res://scenes/entities/water_drop/water_drop.tscn")

const COLOR := Color(0.45, 0.78, 1.0, 1.0)

# Surge push: short cone in front, no damage, knocks enemies back.
const KNOCK_COOLDOWN := 3.0
const KNOCK_LENGTH := 180.0
const KNOCK_WIDTH := 140.0
const KNOCK_FORCE := 600.0

# Pour (RMB hold + LMB hold): spawns gravity-affected droplets at a steady
# rate so the stream looks like physically poured water.
const POUR_INTERVAL := 0.04
const POUR_SPEED := 700.0
const POUR_SPEED_VARIANCE := 60.0
const POUR_SPREAD := 0.12

const BASIC_CD := 0.30

var _pour_cd: float = 0.0


func stance_name() -> String: return "Water"
func stance_color() -> Color: return COLOR
func stance_key() -> String: return "E"
func skill_name() -> String: return "Surge Push"
func skill_cooldown_max() -> float: return KNOCK_COOLDOWN
func element_id() -> int: return Element.WATER
func basic_attack_cooldown() -> float: return BASIC_CD


func on_stance_key_pressed(is_double_tap: bool) -> void:
	if is_double_tap:
		return
	_try_surge_push()


func _try_surge_push() -> void:
	if not skill_ready():
		return
	start_skill_cooldown()
	_do_knockback()


func _do_knockback() -> void:
	# Short rectangle in front. No damage; just push enemies away.
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 32
	area.monitorable = false

	var coll := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(KNOCK_LENGTH, KNOCK_WIDTH)
	coll.shape = rect
	coll.position = Vector2(KNOCK_LENGTH / 2.0, 0.0)
	area.add_child(coll)

	var visual := Polygon2D.new()
	visual.color = Color(COLOR.r, COLOR.g, COLOR.b, 0.4)
	visual.polygon = PackedVector2Array([
		Vector2(0.0, -KNOCK_WIDTH / 2.0),
		Vector2(KNOCK_LENGTH, -KNOCK_WIDTH / 2.0),
		Vector2(KNOCK_LENGTH, KNOCK_WIDTH / 2.0),
		Vector2(0.0, KNOCK_WIDTH / 2.0),
	])
	area.add_child(visual)

	area.global_position = player.global_position
	area.rotation = 0.0 if player.facing > 0 else PI
	get_tree().current_scene.add_child(area)

	await get_tree().physics_frame
	for body in area.get_overlapping_bodies():
		if body.has_method("apply_knockback"):
			var dir: Vector2 = (body.global_position - player.global_position)
			if dir.length_squared() < 1.0:
				dir = Vector2(float(player.facing), 0.0)
			dir = dir.normalized()
			body.apply_knockback(Vector2(dir.x * KNOCK_FORCE, -KNOCK_FORCE * 0.35))

	var t := area.create_tween()
	t.tween_property(visual, "modulate:a", 0.0, 0.25)
	t.finished.connect(area.queue_free, CONNECT_ONE_SHOT)


# Water doesn't use a needle — RMB+LMB pours a continuous stream of drops.
# The first frame resets the pour timer so a drop fires immediately.
func start_ranged_attack() -> void:
	if player.attack_cd > 0.0:
		return
	_pour_cd = 0.0
	_try_pour(0.0)


func continue_ranged_attack(delta: float) -> void:
	_try_pour(delta)


func _try_pour(delta: float) -> void:
	_pour_cd = maxf(0.0, _pour_cd - delta)
	if _pour_cd > 0.0:
		return
	_pour_cd = POUR_INTERVAL
	_spawn_drop()


func _spawn_drop() -> void:
	var spawn_pos: Vector2 = get_projectile_spawn_position()
	var target: Vector2 = player.get_global_mouse_position()
	var dir: Vector2 = target - spawn_pos
	if dir.length_squared() < 1.0:
		dir = Vector2(float(player.facing), 0.0)
	dir = dir.normalized().rotated(randf_range(-POUR_SPREAD, POUR_SPREAD))
	# Face the pour direction so subsequent drops spawn on the correct side.
	if dir.x > 0.1:
		player.set_facing_dir(1)
	elif dir.x < -0.1:
		player.set_facing_dir(-1)
	var speed: float = POUR_SPEED + randf_range(-POUR_SPEED_VARIANCE, POUR_SPEED_VARIANCE)
	var drop: Area2D = WATER_DROP_SCENE.instantiate()
	get_tree().current_scene.add_child(drop)
	drop.global_position = spawn_pos
	drop.launch(dir * speed, COLOR)


@warning_ignore("unused_parameter")
func _on_state_changed(state: String) -> void:
	# Hook for water-themed animations.
	pass
