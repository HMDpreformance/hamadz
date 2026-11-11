class_name CarFX
extends Node3D
## Visual effects for the player car: tyre smoke, nitro flames, headlight beam.

var car: PlayerCar
var _smoke: Array[GPUParticles3D] = []
var _flames: Array[GPUParticles3D] = []
var _bf := 0.0
var _beam: SpotLight3D
var _flare: MeshInstance3D


func attach(c: PlayerCar) -> void:
	car = c
	var v := c.visual
	var amount := int(48 * float(GFX.p.particles))
	for sgn in [1.0, -1.0]:
		var p := _make_smoke(amount)
		p.position = Vector3(sgn * (v.half_width() - 0.15), 0.12, v.axle_z(false) + 0.25)
		add_child(p)
		_smoke.append(p)
	for ep in v.exhaust_points():
		var f := _make_flame()
		f.position = ep + Vector3(0, v.ride_offset(), 0.05)
		add_child(f)
		_flames.append(f)
	_beam = SpotLight3D.new()
	_beam.position = Vector3(0, 0.75, -v.length() * 0.5 + 0.3)
	_beam.rotation_degrees = Vector3(-7, 0, 0)
	_beam.spot_range = 46.0
	_beam.spot_angle = 34.0
	_beam.spot_attenuation = 0.7
	_beam.light_energy = 6.5
	_beam.light_color = Color(0.92, 0.95, 1.0)
	_beam.shadow_enabled = false
	add_child(_beam)
	# soft pool of light on the road right in front of the car
	_flare = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7.0, 12.0)
	_flare.mesh = pm
	_flare.material_override = EnvKit.glow_mat(Color(0.8, 0.88, 1.0), 0.2)
	_flare.position = Vector3(0, 0.03, -v.length() * 0.5 - 5.5)
	add_child(_flare)


func _make_smoke(amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 8)
	p.lifetime = 1.3
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0.3)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.9, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.25))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.85, 0.85, 0.9, 0.0), Color(0.8, 0.8, 0.85, 0.32), Color(0.7, 0.7, 0.75, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 2.4)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = UI.radial_tex(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	m.disable_receive_shadows = true
	q.material = m
	p.draw_pass_1 = q
	return p


func _make_flame() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 20
	p.lifetime = 0.22
	p.emitting = false
	p.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 6.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3.ZERO
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(2.5, 2.5, 3.0, 1.0), Color(0.3, 0.7, 3.0, 0.9), Color(0.6, 0.1, 2.0, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.34)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = UI.radial_tex(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	q.material = m
	p.draw_pass_1 = q
	return p


func _process(_dt: float) -> void:
	if car == null:
		return
	var smoking := (absf(car.slip) > 3.2 and absf(car.speed) > 6.0) or (car.handbraking and absf(car.speed) > 8.0) \
		or (absf(car.speed) < 4.0 and car.throttle > 0.9 and car.gear == 0 and car.rpm > 0.35)
	for p in _smoke:
		p.emitting = smoking
	_bf = maxf(_bf - _dt, 0.0)
	for f in _flames:
		f.emitting = car.using_nitro or _bf > 0.0


## Short flame burst from the tailpipes (backfire on a hard shift).
func backfire() -> void:
	_bf = 0.14
