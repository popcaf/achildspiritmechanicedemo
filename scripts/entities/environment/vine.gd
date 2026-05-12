extends StaticBody2D

# Fire-stance practice target. Only takes damage from FIRE-element attacks;
# every other element bounces off with an "IMMUNE" indicator so the player
# learns to swap to fire stance before engaging.

const Element := preload("res://scripts/core/element.gd")
const DAMAGE_NUMBER := preload("res://scenes/effects/damage_number.tscn")

@export var max_health: int = 60

var health: int

@onready var body_visual: Polygon2D = $Body
@onready var label: Label = $Label


func _ready() -> void:
	# Share the "dummy" group so swing detection / cleanup behaves uniformly.
	add_to_group("dummy")
	health = max_health
	_refresh_label()


func take_damage(amount: int, element: int = Element.NEUTRAL, from_pos: Vector2 = Vector2.INF) -> void:
	if element != Element.FIRE:
		_flash_immune()
		_spawn_immune_indicator()
		return
	health = maxi(0, health - amount)
	_refresh_label()
	_flash_damage()
	_spawn_damage_number(amount, from_pos)
	if health <= 0:
		_wither()


func apply_knockback(_impulse: Vector2) -> void:
	# Vines are rooted; ignore knockback.
	pass


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


func _spawn_immune_indicator() -> void:
	var l := Label.new()
	l.text = "IMMUNE"
	l.modulate = Color(0.6, 0.95, 0.7, 1.0)
	l.add_theme_font_size_override("font_size", 14)
	l.position = Vector2(-30.0, -100.0)
	add_child(l)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position", Vector2(-30.0, -130.0), 0.6)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.finished.connect(l.queue_free, CONNECT_ONE_SHOT)


func _spawn_damage_number(amount: int, from_pos: Vector2) -> void:
	var dn := DAMAGE_NUMBER.instantiate()
	get_tree().current_scene.add_child(dn)
	var x_offset: float = 0.0
	if from_pos.is_finite():
		x_offset = clampf(global_position.x - from_pos.x, -10.0, 10.0)
	dn.global_position = global_position + Vector2(x_offset, -70.0)
	dn.setup(amount, 1.0)


func _wither() -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(body_visual, "scale", Vector2(0.5, 0.1), 0.4)
	t.tween_property(body_visual, "modulate:a", 0.0, 0.4)
	t.finished.connect(queue_free, CONNECT_ONE_SHOT)
