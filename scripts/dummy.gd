extends CharacterBody2D

const GRAVITY := 1500.0
const DAMAGE_NUMBER := preload("res://scenes/damage_number.tscn")
const Element := preload("res://scripts/element.gd")

@export var max_health: int = 50
@export_enum("None", "Fire", "Water") var weakness: int = 0

var health: int

signal died

@onready var label: Label = $Label
@onready var body_visual: Polygon2D = $Body
@onready var weakness_label: Label = $WeaknessLabel


func _ready() -> void:
	health = max_health
	_refresh_label()
	_apply_weakness_visuals()


func _physics_process(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += GRAVITY * delta
	move_and_slide()


func set_weakness(value: int) -> void:
	weakness = value
	if is_node_ready():
		_apply_weakness_visuals()


func take_damage(amount: int, element: int = Element.NEUTRAL) -> void:
	var mult := _multiplier_for(element)
	var actual: int = maxi(0, roundi(float(amount) * mult))
	health = maxi(0, health - actual)
	_refresh_label()
	_flash()
	_spawn_damage_number(actual, mult)
	if health <= 0:
		died.emit()
		queue_free()


func _multiplier_for(element: int) -> float:
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
