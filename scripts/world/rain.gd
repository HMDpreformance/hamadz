class_name Rain
extends GPUParticles3D
## Light desert-night rain that follows the active camera.

func _ready() -> void:
	amount = int(900 * float(GFX.p.particles))
	lifetime = 0.7
	preprocess = 0.7
	local_coords = false
	visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 2.0
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(0, -6, 0)
	process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.9)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 1.0, 0.22)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	draw_pass_1 = q
	transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_dt: float) -> void:
	var c := get_viewport().get_camera_3d()
	if c:
		global_position = c.global_position + Vector3(0, 14, 0) - c.global_transform.basis.z * 10.0
