class_name MiniMap
extends Control
## Heading-up minimap of the open world: street grid, expressway, water,
## traffic, event markers and the active checkpoint. Drawn with a few dozen
## lines per frame, nothing is rendered to texture.

var world: OpenWorld
var player: Node3D
var traffic: Traffic
var scale_px := 0.42          # pixels per metre
var markers: Array = []       # [{pos: Vector3, color: Color, kind: String}]
var target = null             # Vector3 or null: current checkpoint / destination
var route: PackedVector3Array = []
var _t := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(d: float) -> void:
	_t += d
	queue_redraw()


func _draw() -> void:
	if world == null or player == null:
		return
	var c := size * 0.5
	var r := size.x * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.78))
	var pp := player.global_position
	var yaw := player.rotation.y
	var cs := cos(yaw)
	var sn := sin(yaw)
	var reach := r / scale_px * 1.45
	var to_map := func(w: Vector3) -> Vector2:
		var dx := w.x - pp.x
		var dz := w.z - pp.z
		# rotate so the car's nose points up
		return c + Vector2(dx * cs - dz * sn, dx * sn + dz * cs) * scale_px
	# water
	if pp.z + reach > world.water_z:
		var pts := PackedVector2Array([to_map.call(Vector3(pp.x - reach * 2, 0, world.water_z)), to_map.call(Vector3(pp.x + reach * 2, 0, world.water_z)),
			to_map.call(Vector3(pp.x + reach * 2, 0, world.water_z + reach * 3)), to_map.call(Vector3(pp.x - reach * 2, 0, world.water_z + reach * 3))])
		draw_colored_polygon(pts, Color(0.03, 0.1, 0.2, 0.9))
	# streets
	var road_col := Color(0.5, 0.52, 0.58, 0.85)
	var w := maxf(City.ROAD * scale_px * 0.55, 2.0)
	for i in OpenWorld.NX + 1:
		var x := world.road_x(i)
		if absf(x - pp.x) < reach:
			draw_line(to_map.call(Vector3(x, 0, maxf(world.z0, pp.z - reach))), to_map.call(Vector3(x, 0, minf(world.z1, pp.z + reach))), road_col, w)
	for j in OpenWorld.NZ + 1:
		var z := world.road_z(j)
		if absf(z - pp.z) < reach:
			draw_line(to_map.call(Vector3(maxf(world.x0, pp.x - reach), 0, z)), to_map.call(Vector3(minf(world.x1, pp.x + reach), 0, z)), road_col, w)
	# link roads
	for i in OpenWorld.EXIT_N:
		draw_line(to_map.call(Vector3(world.road_x(i), 0, world.z0)), to_map.call(Vector3(world.road_x(i), 0, world.z0 - OpenWorld.HW_OFF)), road_col, w)
	for j in OpenWorld.EXIT_WE:
		draw_line(to_map.call(Vector3(world.x0, 0, world.road_z(j))), to_map.call(Vector3(world.x0 - OpenWorld.HW_OFF, 0, world.road_z(j))), road_col, w)
		draw_line(to_map.call(Vector3(world.x1, 0, world.road_z(j))), to_map.call(Vector3(world.x1 + OpenWorld.HW_OFF, 0, world.road_z(j))), road_col, w)
	# expressway
	var hw := world.hw_path
	var n := hw.size()
	var hw_col := Color(1.0, 0.72, 0.2, 0.95)
	for i in n:
		var a := hw[i]
		if absf(a.x - pp.x) > reach or absf(a.z - pp.z) > reach:
			continue
		draw_line(to_map.call(a), to_map.call(hw[(i + 1) % n]), hw_col, maxf(w * 1.25, 3.0))
	# planned route
	if route.size() > 1:
		for i in route.size() - 1:
			draw_line(to_map.call(route[i]), to_map.call(route[i + 1]), Color(0.2, 0.9, 1.0, 0.75), 3.0)
	# traffic
	if traffic:
		for t in traffic.cars:
			var m: Vector2 = to_map.call(t.global_position)
			if Rect2(Vector2.ZERO, size).has_point(m):
				draw_circle(m, 2.2, Color(0.85, 0.85, 0.9, 0.8))
	# markers, pinned to the edge when out of range
	for mk in markers:
		_pin(to_map.call(mk.pos), mk.color, mk.get("kind", "event"))
	if target != null:
		_pin(to_map.call(target), Color(0.2, 0.95, 1.0), "target")
	# player
	var tri := PackedVector2Array([c + Vector2(0, -9), c + Vector2(6.5, 7), c + Vector2(0, 3.5), c + Vector2(-6.5, 7)])
	draw_colored_polygon(tri, Color(1.0, 0.75, 0.1))
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.8), 1.5)
	# frame + north tick
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.69, 0.0, 0.7), false, 2.0)
	var north := c + Vector2(-sn, -cs).rotated(0.0) * (r - 9.0)
	north = c + Vector2(0, -1).rotated(-yaw) * (r - 9.0)
	draw_string(UI.title_font(), north - Vector2(5, -5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))


func _pin(m: Vector2, col: Color, kind: String) -> void:
	var c := size * 0.5
	var lim := size.x * 0.5 - 8.0
	var d := m - c
	var out := absf(d.x) > lim or absf(d.y) > lim
	if out:
		var k := lim / maxf(absf(d.x), absf(d.y))
		m = c + d * k
	var pulse := 1.0 + 0.2 * sin(_t * 5.0)
	if kind == "target":
		draw_arc(m, 6.5 * pulse, 0, TAU, 16, col, 2.5)
		draw_circle(m, 2.5, col)
	else:
		var s := 6.0 if not out else 4.5
		draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s), m + Vector2(s, 0), m + Vector2(0, s), m + Vector2(-s, 0)]), col)
		draw_polyline(PackedVector2Array([m + Vector2(0, -s), m + Vector2(s, 0), m + Vector2(0, s), m + Vector2(-s, 0), m + Vector2(0, -s)]), Color(0, 0, 0, 0.8), 1.2)
