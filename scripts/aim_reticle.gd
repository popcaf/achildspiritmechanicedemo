extends Node2D


func _ready() -> void:
	var ring: Line2D = $Ring
	var dot: Polygon2D = $Dot
	var ring_pts := PackedVector2Array()
	var segs := 28
	for i in range(segs + 1):
		var a: float = float(i) * TAU / float(segs)
		ring_pts.append(Vector2(cos(a), sin(a)) * 18.0)
	ring.points = ring_pts
	var dot_pts := PackedVector2Array()
	for i in range(12):
		var a: float = float(i) * TAU / 12.0
		dot_pts.append(Vector2(cos(a), sin(a)) * 3.0)
	dot.polygon = dot_pts
