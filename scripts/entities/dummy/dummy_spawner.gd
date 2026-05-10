extends Node2D

const DUMMY_SCENE := preload("res://scenes/entities/dummy/dummy.tscn")

# Weakness values to randomize between when respawning. Defaults to fire+water
# (1, 2) so every respawn is elemental. Add 0 for the chance of a neutral dummy.
@export var weakness_pool: Array[int] = [1, 2]

var _spawn_points: Array[Marker2D] = []


func _ready() -> void:
	for child in get_children():
		if child is Marker2D:
			_spawn_points.append(child)
		elif child.has_signal("died"):
			child.died.connect(_on_dummy_died)


func _on_dummy_died() -> void:
	_spawn_random_dummy()


func _spawn_random_dummy() -> void:
	var d: Node = DUMMY_SCENE.instantiate()
	if weakness_pool.size() > 0:
		d.weakness = weakness_pool[randi() % weakness_pool.size()]
	add_child(d)
	if _spawn_points.size() > 0:
		var marker: Marker2D = _spawn_points[randi() % _spawn_points.size()]
		d.global_position = marker.global_position
	if d.has_signal("died"):
		d.died.connect(_on_dummy_died)
