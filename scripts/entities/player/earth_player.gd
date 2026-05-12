extends "res://scripts/entities/player/stance_player.gd"


const COLOR := Color(0.8, 0.6, 0.3, 1.0)

# Hold F to soak hits at 35% of full damage (65% reduction). A press timed
# just before an incoming strike (PARRY_GRACE window) becomes a PARRY — full
# negation + the attacker is staggered. Release to drop the block.
const PASSIVE_REDUCTION := 0.5
const BLOCK_REDUCTION := 0.65
const PARRY_GRACE := 0.30
const WINK_LEAD := 0.40
const WINK_FREQUENCY := 9.0
const PARRY_STAGGER_SECONDS := 1.0
const BASIC_CD := 0.55  # slow earth


var _blocking: bool = false
var _block_dome: Polygon2D = null
# Time since last F press — used by modify_incoming_damage() to detect a
# parry. INF = consumed/none.
var _parry_press_time: float = INF
# List of {attacker, time_left} — pending strikes telegraphed by enemies.
var _incoming_attacks: Array = []
var _wink_phase: float = 0.0


func stance_name() -> String: return "Earth"
func stance_color() -> Color: return COLOR
func stance_key() -> String: return "F"
func skill_name() -> String: return "Bulwark"
func skill_cooldown_max() -> float: return 0.0
func element_id() -> int: return Element.EARTH
func basic_attack_cooldown() -> float: return BASIC_CD


func can_aim() -> bool:
	# Earth has no ranged mode.
	return false


func tick(delta: float) -> void:
	super.tick(delta)
	_update_incoming_attacks(delta)
	_update_wink(delta)
	if _parry_press_time != INF:
		_parry_press_time += delta


# F has its own rules: hold = block (35% damage taken). A press timed within
# PARRY_GRACE seconds before a hit becomes a PARRY (no damage + stagger).
# Double-tap is handled by player.gd (swap); this hook fires on every press.
func on_stance_key_pressed(is_double_tap: bool) -> void:
	# Arm the parry window on every press, including the second tap of a swap.
	_parry_press_time = 0.0
	if is_double_tap:
		end_block()
		return
	start_block()


func on_stance_key_released() -> void:
	end_block()


func start_block() -> void:
	if _blocking:
		return
	_blocking = true
	# Persistent dome visual that follows the player until released.
	_block_dome = Polygon2D.new()
	_block_dome.color = Color(COLOR.r, COLOR.g, COLOR.b, 0.35)
	var pts := PackedVector2Array()
	var n := 32
	var radius := 60.0
	for i in range(n):
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	_block_dome.polygon = pts
	player.add_child(_block_dome)


func end_block() -> void:
	if not _blocking:
		return
	_blocking = false
	if _block_dome and is_instance_valid(_block_dome):
		var dome: Polygon2D = _block_dome
		_block_dome = null
		var t := dome.create_tween()
		t.tween_property(dome, "modulate:a", 0.0, 0.15)
		t.finished.connect(dome.queue_free, CONNECT_ONE_SHOT)


# Called by enemies via player.notify_incoming_attack().
func notify_incoming_attack(attacker: Node, time_to_strike: float) -> void:
	_incoming_attacks.append({"attacker": attacker, "time_left": time_to_strike})


func _update_incoming_attacks(delta: float) -> void:
	if _incoming_attacks.is_empty():
		return
	var still: Array = []
	for atk in _incoming_attacks:
		atk.time_left -= delta
		if atk.time_left > 0.0 and is_instance_valid(atk.attacker):
			still.append(atk)
	_incoming_attacks = still


func _update_wink(delta: float) -> void:
	# Find the soonest incoming strike; if it's within WINK_LEAD, pulse the
	# active stance so the player has a clear visual cue to time their parry.
	var soonest: float = INF
	for atk in _incoming_attacks:
		soonest = minf(soonest, atk.time_left)
	var target: Node2D = player.active_stance
	if target == null:
		return
	if soonest <= WINK_LEAD:
		_wink_phase += delta * WINK_FREQUENCY * TAU
		var t: float = 0.5 + 0.5 * sin(_wink_phase)
		target.modulate = Color.WHITE.lerp(Color(1.8, 1.6, 0.4, 1.0), t)
	elif target.modulate != Color.WHITE:
		_wink_phase = 0.0
		target.modulate = Color.WHITE


# Called from player.take_damage() — always (not just when active), so a
# parry primed from another stance still fires.
func modify_incoming_damage(amount: float, attacker: Node, is_active: bool) -> float:
	# PARRY: F was pressed within the grace window before this hit.
	if _parry_press_time <= PARRY_GRACE:
		_parry_press_time = INF
		_do_parry_visual()
		end_block()
		_resolve_incoming(attacker)
		if attacker and attacker.has_method("on_parried"):
			attacker.on_parried()
		return -1.0
	var working := amount
	if _blocking:
		working *= (1.0 - BLOCK_REDUCTION)
	if is_active:
		working *= (1.0 - PASSIVE_REDUCTION)
	return working


func _do_parry_visual() -> void:
	# A bright yellow ring that briefly flashes around the player.
	var ring := Polygon2D.new()
	ring.color = Color(1.0, 0.95, 0.4, 0.85)
	var pts := PackedVector2Array()
	var n := 32
	var radius := 70.0
	for i in range(n):
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	ring.polygon = pts
	player.add_child(ring)
	var t := ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector2(1.6, 1.6), 0.30) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.35)
	t.finished.connect(ring.queue_free, CONNECT_ONE_SHOT)


func _resolve_incoming(attacker: Node) -> void:
	# Drop any pending strike from this attacker since they were parried.
	if attacker == null:
		return
	var still: Array = []
	for atk in _incoming_attacks:
		if atk.attacker != attacker:
			still.append(atk)
	_incoming_attacks = still


func reset_on_respawn() -> void:
	end_block()
	_parry_press_time = INF
	_incoming_attacks.clear()


@warning_ignore("unused_parameter")
func _on_state_changed(state: String) -> void:
	# Hook for earth-themed animations.
	pass
