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
	var tgt := path[_i]
	var to := tgt - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 5.0:
		_i = (_i + 1) % path.size()
		return
	var want := cruise
	if dist < 16.0:
		want = 6.5
	if player != null:
		var rel := player.global_position - global_position
		var ahead := rel.dot(-global_transform.basis.z)
		var side := absf(rel.dot(global_transform.basis.x))
		if ahead > 0.0 and ahead < 11.0 and side < 2.6:
			want = 0.0
	_speed = move_toward(_speed, want, (9.0 if want < _speed else 4.0) * dt)
	var dir := to / dist
	var cur := -global_transform.basis.z
	var new_dir := cur.slerp(dir, clampf(dt * 2.6 * maxf(_speed, 2.0) / 6.0, 0.0, 1.0)).normalized()
	var pos := global_position + new_dir * _speed * dt
	global_transform = Transform3D(Basis.looking_at(new_dir, Vector3.UP), pos)
	visual.spin_wheels(_speed * dt / visual.wheel_radius)
	visual.set_brake(want < _speed - 0.5)
