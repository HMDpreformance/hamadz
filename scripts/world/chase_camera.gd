class_name ChaseCamera
extends Camera3D
## Follow camera with two modes: chase (springy, speed-sensitive FOV) and hood.

enum Mode { CHASE, HOOD }

var target: PlayerCar
var mode := Mode.CHASE
var _yaw := 0.0
var _shake := 0.0
var _pos := Vector3.ZERO
var _inited := false


func toggle() -> void:
	mode = Mode.HOOD if mode == Mode.CHASE else Mode.CHASE
	_inited = false


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(dt: float) -> void:
	if target == null:
		return
	var sp := clampf(absf(target.speed) / target.vmax, 0.0, 1.2)
	var car_yaw := target.rotation.y
	var fov_target := 0.0
	if mode == Mode.CHASE:
		if not _inited:
			_yaw = car_yaw
		# look slightly toward where the car is actually travelling (shows off drifts)
		var travel_yaw := car_yaw
		if absf(target.speed) > 5.0:
			travel_yaw = car_yaw - clampf(atan2(target.slip, absf(target.speed)), -0.5, 0.5) * 0.6
		_yaw = lerp_angle(_yaw, travel_yaw, 1.0 - exp(-dt * (4.0 + sp * 3.0)))
		var back := Vector3(sin(_yaw), 0, cos(_yaw))
		var dist := 5.4 + sp * 1.3 - (0.5 if target.using_nitro else 0.0)
		var want := target.global_position + back * dist + Vector3(0, 1.95 + sp * 0.25, 0)
		if not _inited:
			_pos = want
			_inited = true
		_pos = _pos.lerp(want, 1.0 - exp(-dt * 12.0))
		global_position = _pos
		look_at(target.global_position + Vector3(0, 0.95, 0) - back * (3.0 + sp * 4.0), Vector3.UP)
		fov_target = 60.0 + sp * 16.0 + (9.0 if target.using_nitro else 0.0)
	else:
		_inited = true
		var b := target.global_transform.basis
		global_position = target.global_position + b * Vector3(0, 1.02 + target.visual.ride_offset(), -0.35)
		global_transform.basis = b * Basis(Vector3.RIGHT, -0.04)
		fov_target = 68.0 + sp * 12.0 + (8.0 if target.using_nitro else 0.0)
	fov = lerpf(fov, fov_target, 1.0 - exp(-dt * 5.0))
	if target.using_nitro:
		_shake = maxf(_shake, 0.035)
	if _shake > 0.001:
		h_offset = randf_range(-1, 1) * _shake
		v_offset = randf_range(-1, 1) * _shake
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-dt * 7.0))
	else:
		h_offset = 0.0
		v_offset = 0.0
