class_name GarageRoom
extends Node3D
## Underground tuning garage, built procedurally: polished floor (with optional
## mirror reflection of the car), concrete walls, neon, lift, tools and props.

const HX := 9.0     # half width  (x)
const HZ := 7.0     # half depth  (z)
const H := 4.8      # ceiling height

var key_light: SpotLight3D
var probe: ReflectionProbe
var mirror_root: Node3D        # y-flipped duplicates that appear "in" the floor
var _floor_mat: StandardMaterial3D


func build() -> void:
	var mirror: bool = GFX.p.mirror
	mirror_root = Node3D.new()
	mirror_root.scale = Vector3(1, -1, 1)
	add_child(mirror_root)
	_floor(mirror)
	_walls()
	_ceiling_and_lights()
	_neon_sign()
	_lift()
	_workbench_side()
	_tire_side()
	_door()
	_lights()


# ---------------------------------------------------------------- pieces
func _concrete(tint: Color, uv := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = EnvKit.noise_tex(5, 0.02)
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.0 / uv, 1.0 / uv, 1.0 / uv)
	return m


func _floor(mirror: bool) -> void:
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HX * 2, HZ * 2)
	fl.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.21, 0.23, 0.74 if mirror else 1.0)
	m.albedo_texture = EnvKit.noise_tex(9, 0.012)
	m.uv1_scale = Vector3(3, 3, 1)
	m.roughness = 0.16
	m.metallic = 0.35
	if mirror:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_floor_mat = m
	fl.material_override = m
	add_child(fl)
	# black void under the glassy floor so only mirrored objects show through
	if mirror:
		EnvKit.box(self, Vector3(HX * 2, 0.1, HZ * 2), Vector3(0, -H - 0.2, 0), EnvKit.solid(Color(0, 0, 0), 1.0))
	# bay markings
	var yellow := EnvKit.emissive(Color(1.0, 0.72, 0.05), 0.35)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.25
	tm.outer_radius = 3.33
	tm.rings = 64
	tm.ring_segments = 4
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	ring.material_override = EnvKit.emissive(Color(1.0, 0.6, 0.05), 2.4)
	ring.position.y = 0.004
	add_child(ring)
	var ring2 := MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 3.45
	tm2.outer_radius = 3.48
	tm2.rings = 64
	tm2.ring_segments = 4
	ring2.mesh = tm2
	ring2.scale = Vector3(1, 0.05, 1)
	ring2.material_override = EnvKit.solid(Color(0.6, 0.6, 0.62), 0.3, 0.9)
	ring2.position.y = 0.004
	add_child(ring2)
	for k in 12:
		var a := TAU * k / 12.0
		EnvKit.box(self, Vector3(0.05, 0.004, 0.3), Vector3(sin(a) * 3.8, 0.003, cos(a) * 3.8), yellow, Vector3(0, a, 0))
	# hazard stripes by the door
	var hz_y := EnvKit.solid(Color(0.85, 0.62, 0.05), 0.5)
	for k in 14:
		EnvKit.box(self, Vector3(0.22, 0.004, 0.75), Vector3(-3.2 + k * 0.5, 0.003, -HZ + 0.6), hz_y, Vector3(0, 0.6, 0))


func _walls() -> void:
	var wall := _concrete(Color(0.34, 0.35, 0.37))
	var dark := _concrete(Color(0.12, 0.125, 0.14))
	var stripe := EnvKit.emissive(Color(1.0, 0.62, 0.05), 0.9)
	# back (+z), front (-z), left (-x), right (+x)
	var defs := [
		[Vector3(HX * 2, H, 0.3), Vector3(0, H * 0.5, HZ + 0.15)],
		[Vector3(HX * 2, H, 0.3), Vector3(0, H * 0.5, -HZ - 0.15)],
		[Vector3(0.3, H, HZ * 2), Vector3(-HX - 0.15, H * 0.5, 0)],
		[Vector3(0.3, H, HZ * 2), Vector3(HX + 0.15, H * 0.5, 0)],
	]
	for d in defs:
		EnvKit.box(self, d[0], d[1], wall)
		# dark wainscot + glowing pin-stripe
		var s: Vector3 = d[0]
		var p: Vector3 = d[1]
		var inset := Vector3(0, 0, -0.02 * signf(p.z)) if s.z < 1.0 else Vector3(-0.02 * signf(p.x), 0, 0)
		EnvKit.box(self, Vector3(s.x + (0.0 if s.z < 1.0 else 0.02), 1.3, s.z + (0.02 if s.z < 1.0 else 0.0)), Vector3(p.x, 0.65, p.z) + inset, dark)
		EnvKit.box(self, Vector3(s.x + (0.0 if s.z < 1.0 else 0.03), 0.04, s.z + (0.03 if s.z < 1.0 else 0.0)), Vector3(p.x, 1.34, p.z) + inset * 1.5, stripe)
	# pillars
	var pil := _concrete(Color(0.26, 0.27, 0.29))
	var hz := EnvKit.solid(Color(0.85, 0.62, 0.05), 0.55)
	var blk := EnvKit.solid(Color(0.03, 0.03, 0.03), 0.6)
	for px in [-HX + 0.35, -3.0, 3.0, HX - 0.35]:
		for pz in [-HZ + 0.35, HZ - 0.35]:
			EnvKit.box(self, Vector3(0.6, H, 0.6), Vector3(px, H * 0.5, pz), pil)
			for k in 4:
				EnvKit.box(self, Vector3(0.62, 0.14, 0.62), Vector3(px, 0.12 + k * 0.28, pz), hz if k % 2 == 0 else blk)
	# ceiling
	EnvKit.box(self, Vector3(HX * 2, 0.3, HZ * 2), Vector3(0, H + 0.15, 0), _concrete(Color(0.1, 0.1, 0.11)))
	var beam := EnvKit.solid(Color(0.07, 0.07, 0.08), 0.6, 0.6)
	for bz in [-4.5, -1.5, 1.5, 4.5]:
		EnvKit.box(self, Vector3(HX * 2, 0.35, 0.25), Vector3(0, H - 0.17, bz), beam)
	# ducting + pipes
	var duct := EnvKit.solid(Color(0.42, 0.44, 0.46), 0.35, 0.9)
	EnvKit.cyl(self, 0.28, HX * 2, Vector3(0, H - 0.7, 5.6), duct, Vector3(0, 0, PI * 0.5), 12)
	var pipe := EnvKit.solid(Color(0.6, 0.15, 0.08), 0.5, 0.3)
	EnvKit.cyl(self, 0.05, HZ * 2, Vector3(-HX + 0.25, 3.6, 0), pipe, Vector3(PI * 0.5, 0, 0), 8)
	EnvKit.cyl(self, 0.05, HZ * 2, Vector3(-HX + 0.25, 3.4, 0), EnvKit.solid(Color(0.1, 0.25, 0.6), 0.5, 0.3), Vector3(PI * 0.5, 0, 0), 8)


func _tube(pos: Vector3, length: float, color: Color, energy: float, along_x := true, mirrored := true) -> void:
	var size := Vector3(length, 0.07, 0.07) if along_x else Vector3(0.07, 0.07, length)
	var m := EnvKit.emissive(color, energy)
	EnvKit.box(self, size, pos, m)
	if mirrored and GFX.p.mirror:
		EnvKit.box(mirror_root, size, pos, m)


func _ceiling_and_lights() -> void:
	var housing := EnvKit.solid(Color(0.05, 0.05, 0.055), 0.5, 0.5)
	var white := Color(1.0, 0.97, 0.9)
	for x in [-1.9, 1.9]:
		for z in [-2.4, 2.4]:
			EnvKit.box(self, Vector3(0.28, 0.08, 3.2), Vector3(x, H - 0.75, z), housing)
			_tube(Vector3(x - 0.07, H - 0.82, z), 3.0, white, 5.0, false)
			_tube(Vector3(x + 0.07, H - 0.82, z), 3.0, white, 5.0, false)
			for e in [-1.4, 1.4]:
				EnvKit.cyl(self, 0.008, 0.72, Vector3(x, H - 0.36, z + e), housing, Vector3.ZERO, 4)
	# coloured wall neon
	_tube(Vector3(-HX + 0.08, 2.6, 0), 9.0, Color(0.1, 0.8, 1.0), 4.0, false)
	_tube(Vector3(HX - 0.08, 2.6, 0), 9.0, Color(1.0, 0.15, 0.55), 4.0, false)


func _text(parent: Node, text: String, size: float, pos: Vector3, color: Color, rot_y := 0.0, title := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.title_font() if title else UI.body_font(true)
	l.font_size = 128
	l.pixel_size = size / 128.0
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = pos
	l.rotation.y = rot_y
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	parent.add_child(l)
	return l


func _neon_sign() -> void:
	# back wall faces -z, so text must be rotated to face the room
	var z := HZ - 0.03
	EnvKit.box(self, Vector3(8.6, 2.1, 0.06), Vector3(0, 3.15, z + 0.01), EnvKit.solid(Color(0.03, 0.03, 0.04), 0.4, 0.5))
	_text(self, "SYNDICATE", 1.05, Vector3(0, 3.42, z - 0.04), Color(3.0, 0.35, 1.3), PI)
	_text(self, "AFTER HOURS  TUNING", 0.36, Vector3(0, 2.56, z - 0.04), Color(0.3, 2.2, 3.0), PI)
	_tube(Vector3(0, 4.12, z - 0.05), 8.2, Color(1.0, 0.15, 0.55), 3.5)
	_tube(Vector3(0, 2.18, z - 0.05), 8.2, Color(1.0, 0.15, 0.55), 3.5)
	if GFX.p.mirror:
		_text(mirror_root, "SYNDICATE", 1.05, Vector3(0, 3.42, z - 0.04), Color(3.0, 0.35, 1.3), PI)
	# small posters on the right wall
	_text(self, "NO SLOW CARS", 0.3, Vector3(HX - 0.02, 1.95, 3.6), Color(2.2, 1.5, 0.1), -PI * 0.5)
	_text(self, "BAY 01", 0.5, Vector3(-HX + 0.02, 3.3, -3.5), Color(1.6, 1.6, 1.7), PI * 0.5)


func _lift() -> void:
	## Two-post hydraulic lift in the back-right corner, arms lowered.
	var root := Node3D.new()
	root.position = Vector3(5.6, 0, 4.2)
	add_child(root)
	var blue := EnvKit.solid(Color(0.05, 0.16, 0.5), 0.4, 0.5)
	var steel := EnvKit.solid(Color(0.5, 0.52, 0.55), 0.3, 0.9)
	var blk := EnvKit.solid(Color(0.03, 0.03, 0.03), 0.7)
	for sx in [-1.45, 1.45]:
		EnvKit.box(root, Vector3(0.32, 3.6, 0.36), Vector3(sx, 1.8, 0), blue)
		EnvKit.box(root, Vector3(0.6, 0.04, 0.7), Vector3(sx, 0.02, 0), steel)
		EnvKit.box(root, Vector3(0.22, 0.36, 0.3), Vector3(sx - 0.2 * signf(sx), 1.5, 0), blk)
		EnvKit.cyl(root, 0.045, 2.0, Vector3(sx, 1.2, 0.2), steel, Vector3.ZERO, 8)
		for sz in [-1.0, 1.0]:
			var arm := EnvKit.box(root, Vector3(1.15, 0.09, 0.11), Vector3(sx - 0.55 * signf(sx), 1.42, sz * 0.42), blk, Vector3(0, sz * signf(sx) * 0.55, 0))
			EnvKit.cyl(root, 0.07, 0.07, Vector3(sx - 1.0 * signf(sx), 1.5, sz * 0.72), steel, Vector3.ZERO, 10)
	EnvKit.box(root, Vector3(3.2, 0.14, 0.2), Vector3(0, 3.62, 0), blue)
	EnvKit.box(root, Vector3(0.2, 0.3, 0.14), Vector3(1.72, 1.3, 0), EnvKit.solid(Color(0.7, 0.7, 0.1), 0.5))
	# a bare engine block on a stand next to it
	var stand := Node3D.new()
	stand.position = Vector3(2.4, 0, 5.6)
	add_child(stand)
	EnvKit.box(stand, Vector3(0.6, 0.5, 0.75), Vector3(0, 0.85, 0), EnvKit.solid(Color(0.36, 0.37, 0.4), 0.45, 0.8))
	EnvKit.box(stand, Vector3(0.66, 0.12, 0.8), Vector3(0, 1.15, 0), EnvKit.solid(Color(0.75, 0.1, 0.06), 0.35, 0.4))
	for k in 4:
		EnvKit.cyl(stand, 0.04, 0.3, Vector3(0.36, 0.95, -0.27 + k * 0.18), steel, Vector3(0, 0, 1.0), 8)
	EnvKit.box(stand, Vector3(0.08, 0.6, 0.08), Vector3(0, 0.3, 0), blk)
	EnvKit.box(stand, Vector3(0.9, 0.06, 0.08), Vector3(0, 0.04, 0.3), blk)
	EnvKit.box(stand, Vector3(0.9, 0.06, 0.08), Vector3(0, 0.04, -0.3), blk)


func _workbench_side() -> void:
	## Left wall: workbench, pegboard with tools, rolling tool chest, shelves.
	var x := -HX + 0.55
	var wood := EnvKit.solid(Color(0.3, 0.2, 0.11), 0.7)
	var steel := EnvKit.solid(Color(0.45, 0.47, 0.5), 0.35, 0.85)
	var red := EnvKit.solid(Color(0.7, 0.05, 0.04), 0.3, 0.5)
	var blk := EnvKit.solid(Color(0.03, 0.03, 0.035), 0.6)
	EnvKit.box(self, Vector3(0.9, 0.07, 3.6), Vector3(x, 0.95, 1.2), wood)
	for lz in [-0.5, 2.9]:
		EnvKit.box(self, Vector3(0.8, 0.92, 0.08), Vector3(x, 0.46, lz), steel)
	EnvKit.box(self, Vector3(0.8, 0.04, 3.4), Vector3(x, 0.3, 1.2), steel)
	# pegboard
	EnvKit.box(self, Vector3(0.04, 1.3, 3.4), Vector3(-HX + 0.04, 2.0, 1.2), EnvKit.solid(Color(0.16, 0.13, 0.1), 0.8))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for k in 16:
		var tz := -0.35 + (k % 8) * 0.44
		var ty := 2.35 if k < 8 else 1.75
		var th := rng.randf_range(0.22, 0.45)
		EnvKit.box(self, Vector3(0.025, th, 0.045), Vector3(-HX + 0.075, ty - th * 0.5 + 0.2, tz), steel)
		EnvKit.box(self, Vector3(0.03, 0.09, 0.08), Vector3(-HX + 0.08, ty + 0.2, tz), red if k % 3 == 0 else blk)
	# items on the bench
	EnvKit.box(self, Vector3(0.3, 0.22, 0.42), Vector3(x, 1.1, 0.0), red)
	EnvKit.cyl(self, 0.09, 0.3, Vector3(x + 0.1, 1.14, 0.9), EnvKit.solid(Color(0.1, 0.3, 0.7), 0.4, 0.3), Vector3.ZERO, 10)
	EnvKit.cyl(self, 0.07, 0.24, Vector3(x - 0.15, 1.11, 1.2), EnvKit.solid(Color(0.8, 0.6, 0.05), 0.4, 0.3), Vector3.ZERO, 10)
	EnvKit.box(self, Vector3(0.5, 0.05, 0.3), Vector3(x, 1.01, 2.2), steel, Vector3(0, 0.3, 0))
	# bench vice
	EnvKit.box(self, Vector3(0.2, 0.16, 0.14), Vector3(x + 0.25, 1.07, 2.75), EnvKit.solid(Color(0.1, 0.2, 0.45), 0.5, 0.6))
	# rolling tool chest
	var cx := -HX + 0.6
	var cz := -2.0
	EnvKit.box(self, Vector3(0.6, 0.95, 1.1), Vector3(cx, 0.6, cz), red)
	EnvKit.box(self, Vector3(0.56, 0.4, 1.0), Vector3(cx, 1.28, cz), red)
	for k in 6:
		EnvKit.box(self, Vector3(0.02, 0.02, 0.85), Vector3(cx + 0.31, 0.25 + k * 0.15, cz), steel)
	for k in 3:
		EnvKit.box(self, Vector3(0.02, 0.02, 0.8), Vector3(cx + 0.29, 1.16 + k * 0.12, cz), steel)
	for wz in [-0.45, 0.45]:
		EnvKit.cyl(self, 0.06, 0.05, Vector3(cx, 0.06, cz + wz), blk, Vector3(0, 0, PI * 0.5), 8)
	# shelves with boxes and oil cans
	var sz0 := -5.0
	for k in 3:
		EnvKit.box(self, Vector3(0.5, 0.04, 2.2), Vector3(-HX + 0.4, 0.5 + k * 0.75, sz0), steel)
	for k in 9:
		var by := 0.5 + (k / 3) * 0.75
		var bz := sz0 - 0.8 + (k % 3) * 0.75 + rng.randf_range(-0.1, 0.1)
		var col: Color = [Color(0.5, 0.36, 0.2), Color(0.7, 0.1, 0.05), Color(0.1, 0.25, 0.6), Color(0.85, 0.7, 0.1)][rng.randi() % 4]
		EnvKit.box(self, Vector3(0.36, rng.randf_range(0.25, 0.5), rng.randf_range(0.3, 0.55)), Vector3(-HX + 0.4, by + 0.22, bz), EnvKit.solid(col, 0.7))
	# floor jack + creeper in front of bench
	EnvKit.box(self, Vector3(0.3, 0.14, 0.75), Vector3(-6.2, 0.1, 3.9), EnvKit.solid(Color(0.8, 0.4, 0.02), 0.4, 0.4), Vector3(0, 0.6, 0))
	EnvKit.cyl(self, 0.02, 0.9, Vector3(-6.0, 0.4, 4.3), steel, Vector3(0.9, 0.6, 0), 6)


func _tire_side() -> void:
	## Right wall: tyre stacks, oil drums, compressor, spare panels.
	var tire := WheelFactory.wheel_mesh(0, 1, 0.235)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for stack in 3:
		var sx := HX - 0.75 - (0.15 if stack == 1 else 0.0)
		var sz := -4.6 + stack * 0.78
		for k in (5 if stack != 1 else 3):
			var mi := MeshInstance3D.new()
			mi.mesh = tire
			mi.set_surface_override_material(1, WheelFactory.rim_mat([1, 2, 0][stack]))
			mi.rotation = Vector3(0, rng.randf() * 6.0, PI * 0.5)
			mi.position = Vector3(sx + rng.randf_range(-0.03, 0.03), 0.12 + k * 0.245, sz)
			add_child(mi)
	# leaning wheel
	var lw := MeshInstance3D.new()
	lw.mesh = WheelFactory.wheel_mesh(3, 2, 0.255)
	lw.set_surface_override_material(1, WheelFactory.rim_mat(4))
	lw.position = Vector3(HX - 0.35, 0.34, -2.1)
	lw.rotation = Vector3(0, 0, 0.22)
	add_child(lw)
	# oil drums
	var drum_cols := [Color(0.1, 0.3, 0.65), Color(0.7, 0.08, 0.05), Color(0.1, 0.1, 0.1)]
	for k in 3:
		var p := Vector3(HX - 0.6 - (k % 2) * 0.1, 0.45, -0.6 + k * 0.72)
		EnvKit.cyl(self, 0.3, 0.9, p, EnvKit.solid(drum_cols[k], 0.4, 0.5), Vector3.ZERO, 16)
		EnvKit.cyl(self, 0.31, 0.03, p + Vector3(0, 0.15, 0), EnvKit.solid(Color(0.3, 0.3, 0.32), 0.4, 0.8), Vector3.ZERO, 16)
		EnvKit.cyl(self, 0.31, 0.03, p + Vector3(0, -0.15, 0), EnvKit.solid(Color(0.3, 0.3, 0.32), 0.4, 0.8), Vector3.ZERO, 16)
	# air compressor
	var comp := Vector3(HX - 0.75, 0, 2.0)
	EnvKit.cyl(self, 0.28, 1.2, comp + Vector3(0, 0.5, 0), EnvKit.solid(Color(0.75, 0.1, 0.05), 0.35, 0.5), Vector3(PI * 0.5, 0, 0), 14)
	EnvKit.box(self, Vector3(0.35, 0.3, 0.45), comp + Vector3(0, 0.95, 0), EnvKit.solid(Color(0.08, 0.08, 0.09), 0.5, 0.5))
	EnvKit.cyl(self, 0.16, 0.06, comp + Vector3(-0.2, 0.95, 0.3), EnvKit.solid(Color(0.4, 0.4, 0.42), 0.3, 0.9), Vector3(0, 0, PI * 0.5), 12)
	# spare bumper / hood leaning on the back wall
	EnvKit.box(self, Vector3(1.5, 1.2, 0.05), Vector3(-5.6, 0.62, HZ - 0.3), EnvKit.solid(Color(0.03, 0.03, 0.035), 0.3, 0.4), Vector3(-0.2, 0, 0))
	EnvKit.box(self, Vector3(1.7, 0.3, 0.2), Vector3(-3.4, 0.2, HZ - 0.35), EnvKit.solid(Color(0.75, 0.05, 0.05), 0.25, 0.3))


func _door() -> void:
	## Roll-up shutter on the front wall (-z).
	var z := -HZ + 0.02
	var slat := EnvKit.solid(Color(0.2, 0.21, 0.23), 0.35, 0.8)
	var slat2 := EnvKit.solid(Color(0.14, 0.15, 0.16), 0.4, 0.8)
	for k in 22:
		EnvKit.box(self, Vector3(6.4, 0.15, 0.05), Vector3(0, 0.08 + k * 0.155, z), slat if k % 2 == 0 else slat2)
	var frame := EnvKit.solid(Color(0.85, 0.62, 0.05), 0.5)
	EnvKit.box(self, Vector3(0.2, 3.6, 0.14), Vector3(-3.3, 1.8, z), frame)
	EnvKit.box(self, Vector3(0.2, 3.6, 0.14), Vector3(3.3, 1.8, z), frame)
	EnvKit.box(self, Vector3(6.8, 0.4, 0.3), Vector3(0, 3.7, z + 0.05), EnvKit.solid(Color(0.08, 0.08, 0.09), 0.5, 0.6))
	_text(self, "EXIT TO STREETS", 0.3, Vector3(0, 4.25, z + 0.03), Color(0.3, 2.4, 0.5), 0.0)
	# exit lamp
	EnvKit.box(self, Vector3(0.5, 0.18, 0.1), Vector3(4.3, 3.0, z + 0.04), EnvKit.emissive(Color(0.1, 1.0, 0.3), 2.5))


func _lights() -> void:
	key_light = SpotLight3D.new()
	key_light.position = Vector3(0.6, H - 0.5, -1.2)
	key_light.rotation_degrees = Vector3(-84, 10, 0)
	key_light.spot_range = 9.0
	key_light.spot_angle = 58.0
	key_light.spot_attenuation = 0.6
	key_light.light_energy = 3.2
	key_light.light_color = Color(1.0, 0.96, 0.9)
	key_light.shadow_enabled = GFX.p.shadows
	add_child(key_light)
	var defs := [
		[Vector3(4.5, 2.8, 3.5), Color(1.0, 0.6, 0.35), 1.3, 11.0],
		[Vector3(-6.5, 2.4, -1.0), Color(0.3, 0.75, 1.0), 1.5, 11.0],
		[Vector3(6.5, 2.4, -2.0), Color(1.0, 0.25, 0.55), 1.3, 10.0],
		[Vector3(0, 3.0, 5.6), Color(1.0, 0.35, 0.8), 1.0, 9.0],
		[Vector3(-3.0, 3.6, -5.0), Color(1.0, 0.95, 0.85), 1.1, 10.0],
	]
	for d in defs:
		var o := OmniLight3D.new()
		o.position = d[0]
		o.light_color = d[1]
		o.light_energy = d[2]
		o.omni_range = d[3]
		o.omni_attenuation = 1.2
		add_child(o)
	probe = ReflectionProbe.new()
	probe.position = Vector3(0, H * 0.5, 0)
	probe.size = Vector3(HX * 2, H, HZ * 2)
	probe.origin_offset = Vector3(0, -H * 0.5 + 0.9, 0)
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.32, 0.34, 0.42)
	probe.ambient_color_energy = 0.5
	probe.intensity = 1.0
	probe.max_distance = 30.0
	add_child(probe)
