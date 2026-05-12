extends Area2D

# Water-stance practice target: a flame the player can extinguish by pouring
# water over it (RMB + LMB in water stance). Burns the player on contact.

const Element := preload("res://scripts/core/element.gd")

@export var max_water_hits: int = 10
@export var contact_damage: int = 8
@export var contact_damage_interval: float = 0.6

var _water_hits: int = 0
var _alive: bool = true
var _damage_cd: float = 0.0

@onready var inner_flame: Polygon2D = $InnerFlame
@onready var outer_flame: Polygon2D = $OuterFlame
@onready var base: Polygon2D = $Base
@onready var flicker_phase: float = randf() * TAU


func _ready() -> void:
	add_to_group("fire_obstacle")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if not _alive:
		return
	_damage_cd = maxf(0.0, _damage_cd - delta)
	flicker_phase += delta * 8.0
	var pulse: float = 0.85 + 0.15 * sin(flicker_phase)
	if outer_flame:
		outer_flame.scale = Vector2(pulse, pulse * 1.05)
	if inner_flame:
		inner_flame.scale = Vector2(pulse * 0.9, pulse * 0.95)


func _on_body_entered(body: Node) -> void:
	if not _alive:
		return
	if body.is_in_group("player") and body.has_method("take_damage") and _damage_cd <= 0.0:
		body.take_damage(contact_damage)
		_damage_cd = contact_damage_interval


# Called by water_drop on overlap.
func on_water_drop(_drop_position: Vector2) -> void:
	if not _alive:
		return
	_water_hits += 1
	_spawn_steam()
	var t := 1.0 - float(_water_hits) / float(max_water_hits)
	if outer_flame:
		outer_flame.modulate.a = clampf(t, 0.2, 1.0)
	if inner_flame:
		inner_flame.modulate.a = clampf(t, 0.2, 1.0)
	if _water_hits >= max_water_hits:
		_extinguish()


func _spawn_steam() -> void:
	var puff := Polygon2D.new()
	puff.color = Color(0.9, 0.95, 1.0, 0.55)
	var n := 12
	var pts := PackedVector2Array()
	for i in range(n):
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cos(a), sin(a)) * 14.0)
	puff.polygon = pts
	puff.position = Vector2(randf_range(-12.0, 12.0), -30.0)
	add_child(puff)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(puff, "position:y", puff.position.y - 50.0, 0.6)
	t.tween_property(puff, "modulate:a", 0.0, 0.6)
	t.finished.connect(puff.queue_free, CONNECT_ONE_SHOT)


func _extinguish() -> void:
	_alive = false
	monitoring = false
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(outer_flame, "modulate:a", 0.0, 0.4)
	t.tween_property(inner_flame, "modulate:a", 0.0, 0.4)
	t.tween_property(base, "modulate", Color(0.25, 0.25, 0.25, 1.0), 0.4)
