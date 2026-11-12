class_name TrafficCar
extends AnimatableBody3D
## Ambient traffic car. Follows one lane segment at a time (pure pursuit of a
## point a few metres ahead on the lane line); when the segment ends it asks its
## Traffic manager for the next one, so routes are open ended. Stops for red
## lights, for the player and for other traffic ahead.

var manager: Node
var visual: CarVisual
var cruise := 12.0
var seg_a := Vector3.ZERO
var seg_b := Vector3.FORWARD
var stop_at_end := 0          # 0 no signal, 1 north-south approach, 2 east-west approach
var grid_node := Vector2i.ZERO
var grid_dir := 0
var hw_index := -1            # >= 0: highway car, index into the lane polyline
var hw_sign := 1
var blocked := false
var loop: PackedVector3Array = []   # manager-less mode: lap these points forever (menu backdrop)
var _li := 0
var _speed := 0.0


func setup(id: String, paint: int) -> void:
	sync_to_physics = false
	var cfg := CarDB.default_config(id)
	cfg["paint"] = paint
	cfg["finish"] = 1
	visual = CarVisual.new()
	add_child(visual)
	visual.setup(id, cfg)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(visual.half_width() * 2.0, 1.2, visual.length())
	cs.shape = bs
	cs.position.y = 0.7
	add_child(cs)


func place(a: Vector3, b: Vector3, t: float) -> void:
	seg_a = a
	seg_b = b
	var p := a.lerp(b, t)
	global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), p)
	_speed = cruise


func run_loop(points: PackedVector3Array, start: int) -> void:
	loop = points
	_li = start % points.size()
	place(points[(_li + points.size() - 1) % points.size()], points[_li], 0.3)


func speed() -> float:
	return _speed


func _physics_process(dt: float) -> void:
	if manager == null and loop.is_empty():
		return
	var seg := seg_b - seg_a
	seg.y = 0.0
	var seg_len := maxf(seg.length(), 0.01)
	var seg_dir := seg / seg_len
	var rel := global_position - seg_a
	rel.y = 0.0
	var along := rel.dot(seg_dir)
	var want := cruise
	if hw_index < 0:
		if along > seg_len - 18.0 or along < 5.0:
			want = minf(cruise, 7.0)          # corners and junctions
		if manager and stop_at_end != 0 and along > seg_len - 16.0 and not manager.green(stop_at_end):
			want = 0.0 if along > seg_len - 7.0 else 4.0
	if blocked:
		want = 0.0
	if along > seg_len - (5.0 if hw_index < 0 else 9.0) and want > 0.0:
		if manager:
			manager.next_segment(self)
		else:
			_li = (_li + 1) % loop.size()
			seg_a = seg_b
			seg_b = loop[_li]
		return
	var aim := seg_a + seg_dir * minf(along + (7.0 if hw_index < 0 else 14.0), seg_len)
	var to := aim - global_position
	to.y = 0.0
	_speed = move_toward(_speed, want, (11.0 if want < _speed else 4.0) * dt)
	var cur := -global_transform.basis.z
	cur.y = 0.0
	var yaw0 := atan2(cur.x, cur.z)
	var yaw1 := lerp_angle(yaw0, atan2(to.x, to.z), clampf(dt * 4.0, 0.0, 1.0)) if to.length_squared() > 0.0001 else yaw0
	var new_dir := Vector3(sin(yaw1), 0.0, cos(yaw1))
	var pos := global_position + new_dir * _speed * dt
	pos.y = manager.height_at(pos) if manager else 0.0
	global_transform = Transform3D(Basis.looking_at(new_dir, Vector3.UP), pos)
	visual.spin_wheels(_speed * dt / visual.wheel_radius)
	visual.set_brake(want < _speed - 0.5)
