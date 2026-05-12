extends RigidBody2D

# Heavy rock that doubles as a movable platform. Walk into it to push it left
# or right (CharacterBody2D push is built in to move_and_slide). The high
# linear damping makes it settle quickly when the player stops pushing, so it
# behaves like a slab you nudge rather than something that slides forever.
#
# Earth attacks break it; other elements bounce off.

const Element := preload("res://scripts/core/element.gd")
const DAMAGE_NUMBER := preload("res://scenes/effects/damage_number.tscn")

@export var max_health: int = 80

var health: int

@onready var body_visual: Polygon2D = $Body
@onready var label: Label = $Label


func _ready() -> void:
	add_to_group("dummy")
	health = max_health
	_refresh_label()


func take_damage(amount: int, element: int = Element.NEUTRAL, from_pos: Vector2 = Vector2.INF) -> void:
	if element != Element.EARTH:
		_flash_immune()
		return
	health = maxi(0, health - amount)
	_refresh_label()
	_flash_damage()
	_spawn_damage_number(amount, from_pos)
	if health <= 0:
		queue_free()


func apply_knockback(impulse: Vector2) -> void:
	# Heavy, but does respond to player water-pour / wind knockback.
	apply_impulse(impulse * 0.3)


func _refresh_label() -> void:
	if label:
		label.text = str(health)


func _flash_damage() -> void:
	body_visual.modulate = Color(2.0, 0.6, 0.6)
	var t := create_tween()
	t.tween_property(body_visual, "modulate", Color.WHITE, 0.2)


func _flash_immune() -> void:
	body_visual.modulate = Color(1.3, 1.3, 1.3)
	var t := create_tween()
	t.tween_property(body_visual, "modulate", Color.WHITE, 0.2)


func _spawn_damage_number(amount: int, _from_pos: Vector2) -> void:
	var dn := DAMAGE_NUMBER.instantiate()
	get_tree().current_scene.add_child(dn)
	dn.global_position = global_position + Vector2(0, -55)
	dn.setup(amount, 1.0)
