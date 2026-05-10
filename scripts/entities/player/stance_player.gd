extends Node2D

@onready var flip_root: Node2D = $FlipRoot
@onready var body_visual: Polygon2D = $FlipRoot/Body
@onready var attack_area: Area2D = $FlipRoot/AttackArea
@onready var attack_visual: Polygon2D = $FlipRoot/AttackArea/Visual
@onready var projectile_spawn: Marker2D = $FlipRoot/ProjectileSpawn

var _facing: int = 1
var _current_state: String = ""


func _ready() -> void:
	attack_area.monitoring = false
	attack_visual.visible = false


func activate() -> void:
	visible = true


func deactivate() -> void:
	visible = false
	attack_area.monitoring = false
	attack_visual.visible = false


func set_facing(direction: int) -> void:
	_facing = direction
	flip_root.scale.x = float(direction)


func get_facing() -> int:
	return _facing


func get_attack_area() -> Area2D:
	return attack_area


func get_projectile_spawn_position() -> Vector2:
	return projectile_spawn.global_position


func show_attack(color: Color) -> void:
	attack_visual.color = color
	attack_visual.visible = true
	attack_area.monitoring = true


func hide_attack() -> void:
	attack_visual.visible = false
	attack_area.monitoring = false


func flash_damage() -> void:
	body_visual.modulate = Color(2.0, 0.6, 0.6)
	var t := create_tween()
	t.tween_property(body_visual, "modulate", Color.WHITE, 0.2)


# Called every physics frame by the parent player with the current motion state:
# "idle", "run", "jump", "fall", "dash", "attack", "heavy".
# Cheap no-op when state is unchanged; subclasses override _on_state_changed.
func play_state(state: String) -> void:
	if state == _current_state:
		return
	_current_state = state
	_on_state_changed(state)


func _on_state_changed(_state: String) -> void:
	pass
