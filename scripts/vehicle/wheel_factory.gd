class_name WheelFactory
## Builds wheels (tyre + rim + brake) procedurally. Axis is local X, outer face +X.

const RIM_RADIUS := [0.216, 0.229, 0.241, 0.254]   # 17" .. 20"
const TIRE_RADIUS := [0.315, 0.320, 0.326, 0.333]

## hub/rim spoke half-widths, dish depth, hub recess, twist (radians)
const STYLES := [
	{"n": 5, "wh": 0.036, "wr": 0.026, "dish": 0.030, "cav": 0.010, "twist": 0.0, "twin": 0.0, "cross": false},
	{"n": 6, "wh": 0.020, "wr": 0.016, "dish": 0.034, "cav": 0.030, "twist": 0.0, "twin": 0.0, "cross": false},
	{"n": 5, "wh": 0.012, "wr": 0.010, "dish": 0.030, "cav": 0.018, "twist": 0.0, "twin": 0.24, "cross": false},
	{"n": 5, "wh": 0.040, "wr": 0.034, "dish": 0.095, "cav": 0.0, "twist": 0.0, "twin": 0.0, "cross": false},
	{"n": 8, "wh": 0.008, "wr": 0.007, "dish": 0.050, "cav": 0.012, "twist": 0.42, "twin": 0.0, "cross": true},
	{"n": 11, "wh": 0.016, "wr": 0.011, "dish": 0.040, "cav": 0.022, "twist": 0.5, "twin": 0.0, "cross": false},
]

static var _mesh_cache := {}
static var _mats := {}
static var _brake_cache := {}


static func radius(size_idx: int) -> float:
	return TIRE_RADIUS[clampi(size_idx, 0, 3)]


static func mat(id: String) -> StandardMaterial3D:
	if _mats.has(id):
		return _mats[id]
	var m := StandardMaterial3D.new()
	match id:
		"rubber":
			m.albedo_color = Color(0.035, 0.035, 0.04)
			m.roughness = 0.85
		"disc":
			m.albedo_color = Color(0.45, 0.45, 0.48)
			m.metallic = 0.9
			m.roughness = 0.35
		"caliper":
			m.albedo_color = Color(0.85, 0.05, 0.03)
			m.roughness = 0.35
			m.metallic = 0.2
		"lug":
			m.albedo_color = Color(0.8, 0.8, 0.82)
			m.metallic = 1.0
			m.roughness = 0.2
	_mats[id] = m
	return m


static func rim_mat(color_idx: int) -> StandardMaterial3D:
	var key := "rim%d" % color_idx
	if _mats.has(key):
		return _mats[key]
	var d: Dictionary = CarDB.RIM_COLORS[clampi(color_idx, 0, CarDB.RIM_COLORS.size() - 1)]
	var m := StandardMaterial3D.new()
	m.albedo_color = d.c
	m.metallic = d.metal
	m.roughness = d.rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func _spoke(st: SurfaceTool, a0: float, a1: float, rh: float, rr: float, xh: float, xr: float, wh: float, wr: float, th: float) -> void:
	var c0 := Vector3(xh, rh * cos(a0), rh * sin(a0))
	var t0 := Vector3(0, -sin(a0), cos(a0))
	var c1 := Vector3(xr, rr * cos(a1), rr * sin(a1))
	var t1 := Vector3(0, -sin(a1), cos(a1))
	var bx := Vector3(th, 0, 0)
	MeshKit.hexa(st,
		[c0 - t0 * wh, c0 + t0 * wh, c0 + t0 * wh * 0.8 - bx, c0 - t0 * wh * 0.8 - bx],
		[c1 - t1 * wr, c1 + t1 * wr, c1 + t1 * wr * 0.8 - bx, c1 - t1 * wr * 0.8 - bx])


static func wheel_mesh(style: int, size_idx: int, w: float) -> ArrayMesh:
	var key := "%d_%d_%.3f" % [style, size_idx, w]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rr: float = RIM_RADIUS[size_idx]
	var rt: float = TIRE_RADIUS[size_idx]
	var s: Dictionary = STYLES[clampi(style, 0, STYLES.size() - 1)]
	var hw := w * 0.5
	var mesh := ArrayMesh.new()
	# --- tyre
	var st := MeshKit.begin()
	var sh := 0.035
	MeshKit.lathe_x(st, [
		Vector2(-hw + 0.012, rr - 0.004), Vector2(-hw, rr + 0.012), Vector2(-hw - 0.004, (rr + rt) * 0.5), Vector2(-hw, rt - sh),
		Vector2(-hw + sh * 0.5, rt - 0.008), Vector2(-hw + sh, rt), Vector2(hw - sh, rt), Vector2(hw - sh * 0.5, rt - 0.008),
		Vector2(hw, rt - sh), Vector2(hw + 0.004, (rr + rt) * 0.5), Vector2(hw, rr + 0.012), Vector2(hw - 0.012, rr - 0.004)], 36)
	MeshKit.add_surface(mesh, st, mat("rubber"))
	# --- rim barrel + lip, spokes, hub
	st = MeshKit.begin()
	var xf := hw - float(s.dish)
	MeshKit.lathe_x(st, [
		Vector2(hw - 0.012, rr + 0.004), Vector2(hw + 0.003, rr + 0.002), Vector2(hw + 0.003, rr - 0.012),
		Vector2(hw - 0.006, rr - 0.02), Vector2(xf - 0.01, rr - 0.03), Vector2(-hw + 0.02, rr - 0.034)], 36)
	var n: int = s.n
	var rhub := 0.058
	var rrim := rr - 0.026
	var xh := xf - float(s.cav)
	for i in n:
		var a := TAU * i / n
		if s.cross:
			_spoke(st, a, a + s.twist, rhub, rrim, xh, xf, s.wh, s.wr, 0.022)
			_spoke(st, a, a - s.twist, rhub, rrim, xh - 0.004, xf - 0.004, s.wh, s.wr, 0.022)
		elif s.twin > 0.0:
			_spoke(st, a - s.twin * 0.5, a - s.twin * 0.22, rhub, rrim, xh, xf, s.wh, s.wr, 0.026)
			_spoke(st, a + s.twin * 0.5, a + s.twin * 0.22, rhub, rrim, xh, xf, s.wh, s.wr, 0.026)
		else:
			_spoke(st, a, a + s.twist, rhub, rrim, xh, xf, s.wh, s.wr, 0.03)
	MeshKit.cylinder(st, Vector3(xh - 0.012, 0, 0), Vector3.RIGHT, rhub + 0.012, 0.045, 20, true, rhub + 0.004)
	MeshKit.add_surface(mesh, st, null)  # surface 1 = rim paint (set per instance)
	# --- lugs + cap
	st = MeshKit.begin()
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		MeshKit.cylinder(st, Vector3(xh + 0.012, 0.036 * cos(a), 0.036 * sin(a)), Vector3.RIGHT, 0.008, 0.012, 6)
	MeshKit.cylinder(st, Vector3(xh + 0.014, 0, 0), Vector3.RIGHT, 0.022, 0.012, 12, true, 0.018)
	MeshKit.add_surface(mesh, st, mat("lug"))
	_mesh_cache[key] = mesh
	return mesh


static func brake_mesh(size_idx: int) -> ArrayMesh:
	if _brake_cache.has(size_idx):
		return _brake_cache[size_idx]
	var rr: float = RIM_RADIUS[size_idx]
	var mesh := ArrayMesh.new()
	var st := MeshKit.begin()
	MeshKit.cylinder(st, Vector3(0.0, 0, 0), Vector3.RIGHT, rr - 0.05, 0.024, 24)
	MeshKit.add_surface(mesh, st, mat("disc"))
	st = MeshKit.begin()
	var a := 2.2
	var c := Vector3(0.012, (rr - 0.085) * cos(a), (rr - 0.085) * sin(a))
	var rad := Vector3(0, cos(a), sin(a))
	var tan := Vector3(0, -sin(a), cos(a))
	MeshKit.box(st, c, Vector3(0.075, 0.075, 0.17), Basis(Vector3.RIGHT, rad, tan))
	MeshKit.add_surface(mesh, st, mat("caliper"))
	_brake_cache[size_idx] = mesh
	return mesh


## Returns {"pivot": Node3D, "spin": Node3D}. `left` flips the wheel to face -X.
static func build(style: int, color_idx: int, size_idx: int, w: float, left: bool) -> Dictionary:
	size_idx = clampi(size_idx, 0, 3)
	var pivot := Node3D.new()
	var flip := Node3D.new()
	if left:
		flip.rotation.y = PI
	pivot.add_child(flip)
	var spin := Node3D.new()
	flip.add_child(spin)
	var mi := MeshInstance3D.new()
	mi.mesh = wheel_mesh(style, size_idx, w)
	mi.set_surface_override_material(1, rim_mat(color_idx))
	spin.add_child(mi)
	var br := MeshInstance3D.new()
	br.mesh = brake_mesh(size_idx)
	flip.add_child(br)
	return {"pivot": pivot, "spin": spin, "left": left}
