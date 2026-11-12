class_name ChaseCamera
extends Camera3D
## Follow camera with two modes: chase (springy, speed-sensitive FOV) and hood.

enum Mode { CHASE, HOOD, CABIN }

var target: PlayerCar
var mode := Mode.CHASE
var _yaw := 0.0
var _shake := 0.0
var _pos := Vector3.ZERO
var _inited := false
var _cockpit: Node3D
var _wheel: MeshInstance3D


func toggle() -> void:
	mode = ((mode + 1) % 3) as Mode
	_inited = false
	if mode == Mode.CABIN and _cockpit == null:
		_build_cockpit()
	if _cockpit:
		_cockpit.visible = mode == Mode.CABIN


## Minimal interior seen from the driver's seat: dash, wheel, pillars, roof edge.
func _build_cockpit() -> void:
	_cockpit = Node3D.new()
	target.add_child(_cockpit)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.035, 0.035, 0.04)
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hw: float = target.visual.half_width()
	var y0: float = 0.78 + target.visual.ride_offset()
	var boxes := [
		[Vector3(0, y0 - 0.02, -0.5), Vector3(hw * 2.0, 0.2, 0.5)],            # dash top
		[Vector3(0, y0 + 0.7, 0.25), Vector3(hw * 2.0, 0.05, 1.0)],            # roof
		[Vector3(-hw + 0.03, y0 - 0.04, 0.25), Vector3(0.06, 0.3, 1.3)],       # door tops
		[Vector3(hw - 0.03, y0 - 0.04, 0.25), Vector3(0.06, 0.3, 1.3)],
	]
	for p in boxes:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.material_override = m
		mi.position = p[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cockpit.add_child(mi)
	# A pillars: thin posts from the dash corners up to the roof
	for sgn in [-1.0, 1.0]:
		var a := Vector3(sgn * (hw - 0.02), y0 + 0.06, -0.62)
		var b := Vector3(sgn * (hw - 0.14), y0 + 0.7, -0.2)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.06, a.distance_to(b))
		mi.mesh = bm
		mi.material_override = m
		_cockpit.add_child(mi)
		mi.position = (a + b) * 0.5
		mi.transform.basis = Basis.looking_at(b - a, Vector3.UP)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wheel = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.15
	tm.outer_radius = 0.185
	tm.rings = 24
	tm.ring_segments = 8
	_wheel.mesh = tm
	_wheel.material_override = m
	_wheel.position = Vector3(-0.36, y0 + 0.08, -0.16)
	_wheel.rotation = Vector3(1.25, 0, 0)
	_cockpit.add_child(_wheel)
	var glow := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.15, 0.035, 0.01)
	glow.mesh = gm
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(0.55, 0.26, 0.02)
	glow.material_override = em
	glow.position = Vector3(-0.36, y0 + 0.1, -0.3)
	_cockpit.add_child(glow)


func snap_behind() -> void:
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
		# taller cars (the SUV) get a higher, further camera so the road stays visible
		var tall := maxf(target.visual.height() - 1.3, 0.0) if target.visual else 0.0
		var dist := 5.4 + sp * 1.3 - (0.5 if target.using_nitro else 0.0) + tall * 2.2
		var want := target.global_position + back * dist + Vector3(0, 1.95 + sp * 0.25 + tall * 1.5, 0)
		if not _inited:
			_pos = want
			_inited = true
		_pos = _pos.lerp(want, 1.0 - exp(-dt * 12.0))
		global_position = _pos
		look_at(target.global_position + Vector3(0, 0.95 + tall * 0.6, 0) - back * (3.0 + sp * 4.0), Vector3.UP)
		fov_target = 60.0 + sp * 16.0 + (9.0 if target.using_nitro else 0.0)
	elif mode == Mode.CABIN:
		_inited = true
		var bc := target.global_transform.basis
		global_position = target.global_position + bc * Vector3(-0.36, target.visual.height() * 0.88, 0.28)
		global_transform.basis = bc * Basis(Vector3.UP, target.steer * 0.12) * Basis(Vector3.RIGHT, -0.03)
		fov_target = 72.0 + sp * 9.0 + (6.0 if target.using_nitro else 0.0)
		if _wheel:
			_wheel.rotation = Vector3(1.25, 0, 0)
			_wheel.rotate_object_local(Vector3.UP, target.steer * 1.6)
	else:
		_inited = true
		var b := target.global_transform.basis
		global_position = target.global_position + b * Vector3(0, target.visual.height() * 0.8, -0.35)
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
