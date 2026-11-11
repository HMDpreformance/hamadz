class_name TrafficCar
extends AnimatableBody3D
## Simple ambient traffic: loops clockwise around one city block in the kerb lane,
## slows for corners and stops when the player is right ahead.

var path: PackedVector3Array = []
var cruise := 12.0
var player: Node3D
var visual: CarVisual
var _i := 0
var _speed := 0.0


func setup(id: String, paint: int, waypoints: PackedVector3Array, start_index: int, start_t: float) -> void:
	path = waypoints
	sync_to_physics = false
	_i = start_index
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
	var a := path[(_i + path.size() - 1) % path.size()]
	var b := path[_i]
	position = a.lerp(b, start_t)
	look_at_from_position(position, b, Vector3.UP)
	_speed = cruise


func _physics_process(dt: float) -> void:
	if path.is_empty():
		return
	var n := path.size()
	var a := path[(_i + n - 1) % n]
	var b := path[_i]
	var seg := b - a
	var seg_len := seg.length()
	var seg_dir := seg / seg_len
	var along := (global_position - a).dot(seg_dir)
	# start the next leg a little early so corners come out rounded but tight
	if along > seg_len - 7.0:
		_i = (_i + 1) % n
		return
	# pure pursuit of a point a few metres ahead on the lane line keeps the car in its lane
	var aim := a + seg_dir * minf(along + 7.0, seg_len)
	var to := aim - global_position
	to.y = 0.0
	var want := cruise
	if along > seg_len - 20.0 or along < 6.0:
		want = 6.5
	if player != null:
		var rel := player.global_position - global_position
		var ahead := rel.dot(-global_transform.basis.z)
		var side := absf(rel.dot(global_transform.basis.x))
		if ahead > 0.0 and ahead < 11.0 and side < 2.1:
			want = 0.0
	_speed = move_toward(_speed, want, (9.0 if want < _speed else 4.0) * dt)
	var dir := to.normalized()
	var cur := -global_transform.basis.z
	var new_dir := cur.slerp(dir, clampf(dt * 4.0, 0.0, 1.0)).normalized()
	var pos := global_position + new_dir * _speed * dt
	pos.y = 0.0
	global_transform = Transform3D(Basis.looking_at(new_dir, Vector3.UP), pos)
	visual.spin_wheels(_speed * dt / visual.wheel_radius)
	visual.set_brake(want < _speed - 0.5)
