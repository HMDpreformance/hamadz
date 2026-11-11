class_name CarVisual
extends Node3D
## Procedural car: lofted body shell + swappable parts + wheels.
## Usage:  var car := CarVisual.new(); add_child(car); car.setup("tuner", cfg)
## Call apply(cfg) again whenever the configuration changes; only the parts
## whose option changed are rebuilt.

const J := 13
const DROP := [0.0, 0.028, 0.05, 0.085]            # suspension option -> ride height drop
const PATCH_OFF := 0.006

static var _shell_cache := {}
static var _shared_mats := {}
static var _carbon_tex: ImageTexture

var car_id := ""
var cfg := {}
var spec := {}
var is_reflection := false
var body: Node3D
var wheels := []          # [{pivot, spin, left, front}]
var wheel_radius := 0.315
var mats := {}
var _slots := {}          # slot -> Node3D
var _wheel_root: Node3D
var _L := 4.4
var _lights_on := true
var _glow_light: OmniLight3D
var _shadow: MeshInstance3D


# ====================================================================== public
func setup(id: String, config: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_slots.clear()
	wheels.clear()
	car_id = id
	spec = CarSpecs.get_spec(id)
	_L = spec.L
	cfg = {}
	_make_materials()
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var shell: Dictionary = _shell(id)
	var mi := MeshInstance3D.new()
	mi.name = "Shell"
	mi.mesh = shell.mesh
	for i in shell.names.size():
		mi.set_surface_override_material(i, mats[shell.names[i]])
	body.add_child(mi)
	_add_mirrors()
	_wheel_root = Node3D.new()
	_wheel_root.name = "Wheels"
	add_child(_wheel_root)
	if not is_reflection:
		_shadow = MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(2.9, _L + 1.2)
		_shadow.mesh = q
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_texture = _shadow_tex()
		sm.albedo_color = Color(0, 0, 0, 0.85)
		sm.render_priority = -1
		_shadow.material_override = sm
		_shadow.position.y = 0.012
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shadow)
	apply(config, true)


func apply(config: Dictionary, force := false) -> void:
	var changed := []
	for k in CarDB.SLOT_ORDER:
		var v := int(config.get(k, 0))
		if force or int(cfg.get(k, -1)) != v:
			changed.append(k)
		cfg[k] = v
	if changed.is_empty():
		return
	if changed.has("paint") or changed.has("finish"):
		_update_paint()
	if changed.has("rims") or changed.has("rim_color") or changed.has("wheel_size"):
		_build_wheels()
	if changed.has("wheel_size") or changed.has("suspension"):
		_update_ride()
	for slot in ["front", "rear", "spoiler", "skirts", "hood", "exhaust", "glow", "turbo", "engine"]:
		if changed.has(slot):
			_rebuild_slot(slot)


func set_lights(on: bool) -> void:
	_lights_on = on
	mats["head"].emission_energy_multiplier = 2.2 if on else 0.15
	mats["tail"].emission_energy_multiplier = 1.4 if on else 0.2


func set_brake(on: bool) -> void:
	mats["tail"].emission_energy_multiplier = 4.5 if on else (1.4 if _lights_on else 0.2)


func spin_wheels(angle: float) -> void:
	for w in wheels:
		w.spin.rotate_x(angle if w.left else -angle)


func set_steer(angle: float) -> void:
	for w in wheels:
		if w.front:
			w.pivot.rotation.y = angle


func set_body_tilt(pitch: float, roll: float) -> void:
	body.rotation = Vector3(pitch, 0, roll)


func length() -> float:
	return _L


func half_width() -> float:
	return _hw(0.5)


func exhaust_points() -> Array:
	var out := []
	var e: Dictionary = spec.exhaust
	for x in e.x:
		out.append(Vector3(x, e.y, _L * 0.5 + 0.05))
		if e.mirror or int(cfg.get("exhaust", 0)) > 0:
			out.append(Vector3(-x, e.y, _L * 0.5 + 0.05))
	return out


func axle_z(front: bool) -> float:
	return spec.front_axle if front else spec.rear_axle


# ====================================================================== materials
static func shared_mat(id: String) -> StandardMaterial3D:
	if _shared_mats.has(id):
		return _shared_mats[id]
	var m := StandardMaterial3D.new()
	match id:
		"glass":
			m.albedo_color = Color(0.015, 0.02, 0.03)
			m.metallic = 0.9
			m.roughness = 0.04
			m.clearcoat_enabled = true
		"trim":
			m.albedo_color = Color(0.02, 0.02, 0.022)
			m.roughness = 0.5
			m.metallic = 0.1
		"grille":
			m.albedo_color = Color(0.012, 0.012, 0.014)
			m.roughness = 0.75
		"chrome":
			m.albedo_color = Color(0.9, 0.91, 0.93)
			m.metallic = 1.0
			m.roughness = 0.07
		"titanium":
			m.albedo_color = Color(0.45, 0.5, 0.95)
			m.metallic = 1.0
			m.roughness = 0.16
			m.emission_enabled = true
			m.emission = Color(0.3, 0.1, 0.6)
			m.emission_energy_multiplier = 0.25
		"signal":
			m.albedo_color = Color(1.0, 0.45, 0.02)
			m.roughness = 0.2
			m.emission_enabled = true
			m.emission = Color(1.0, 0.4, 0.0)
			m.emission_energy_multiplier = 0.6
		"plate":
			m.albedo_color = Color(0.85, 0.85, 0.8)
			m.roughness = 0.5
		"carbon":
			m.albedo_color = Color(1, 1, 1)
			m.albedo_texture = _carbon()
			m.uv1_scale = Vector3(14, 14, 1)
			m.metallic = 0.35
			m.roughness = 0.3
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
		"intercooler":
			m.albedo_color = Color(0.7, 0.72, 0.75)
			m.metallic = 1.0
			m.roughness = 0.35
	_shared_mats[id] = m
	return m


static func _carbon() -> ImageTexture:
	if _carbon_tex:
		return _carbon_tex
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var cx := int(x / 4)
			var cy := int(y / 4)
			var horiz := (cx + cy) % 2 == 0
			var t := (x % 4) / 3.0 if horiz else (y % 4) / 3.0
			var v := 0.035 + 0.075 * sin(t * PI)
			img.set_pixel(x, y, Color(v, v, v * 1.08))
	img.generate_mipmaps()
	_carbon_tex = ImageTexture.create_from_image(img)
	return _carbon_tex


static func _shadow_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	return t


func _make_materials() -> void:
	mats = {}
	var paint := StandardMaterial3D.new()
	mats["paint"] = paint
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(0.9, 0.92, 1.0)
	head.roughness = 0.1
	head.emission_enabled = true
	head.emission = Color(0.85, 0.92, 1.0)
	head.emission_energy_multiplier = 2.2
	mats["head"] = head
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.5, 0.0, 0.0)
	tail.roughness = 0.15
	tail.emission_enabled = true
	tail.emission = Color(1.0, 0.03, 0.02)
	tail.emission_energy_multiplier = 1.4
	mats["tail"] = tail
	for id in ["glass", "trim", "grille", "chrome", "signal", "plate", "carbon", "titanium", "intercooler"]:
		mats[id] = shared_mat(id)


func _update_paint() -> void:
	var m: StandardMaterial3D = mats["paint"]
	var col: Color = CarDB.PAINTS[clampi(int(cfg.paint), 0, CarDB.PAINTS.size() - 1)].c
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.04
	m.rim_enabled = false
	m.albedo_color = col
	match int(cfg.finish):
		0:  # gloss
			m.metallic = 0.25
			m.roughness = 0.22
		1:  # metallic
			m.metallic = 0.75
			m.roughness = 0.3
		2:  # pearl
			m.metallic = 0.55
			m.roughness = 0.24
			m.rim_enabled = true
			m.rim = 0.7
			m.rim_tint = 0.2
		3:  # matte
			m.metallic = 0.3
			m.roughness = 0.72
			m.clearcoat_enabled = false
		4:  # chrome
			m.albedo_color = col.lerp(Color(1, 1, 1), 0.45)
			m.metallic = 1.0
			m.roughness = 0.05


# ====================================================================== shape functions
func _top(u: float) -> float:
	return MeshKit.curve(spec.top, clampf(u, 0.0, 1.0))


func _belt(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return minf(MeshKit.curve(spec.belt, u), MeshKit.curve(spec.top, u) - 0.05)


func _bot(u: float) -> float:
	return MeshKit.curve(spec.bot, clampf(u, 0.0, 1.0))


func _hw(u: float) -> float:
	return MeshKit.curve(spec.hw, clampf(u, 0.0, 1.0))


func _z(u: float) -> float:
	return (u - 0.5) * _L


func _u(z: float) -> float:
	return z / _L + 0.5


func _edge_x(u: float) -> float:
	var top := _top(u)
	var belt := _belt(u)
	return maxf(_hw(u) * 0.93 - float(spec.tumble) * maxf(top - belt - 0.05, 0.0), 0.2)


func _arch(z: float, bot: float) -> Vector2:
	## returns (lip height, flare amount)
	var lip := bot
	var flare := 0.0
	var rh: float = spec.arch
	var apex := 2.0 * CarSpecs.R0 + 0.06
	for az in [spec.front_axle, spec.rear_axle]:
		var d := absf(z - az)
		if d < rh:
			lip = maxf(lip, bot + (apex - bot) * pow(1.0 - pow(d / rh, 2.4), 1.0 / 2.4))
		if d < 0.6:
			var b := 1.0 - (d / 0.6) * (d / 0.6)
			flare = maxf(flare, 0.022 * b * b)
	return Vector2(lip, flare)


func _ring(u: float) -> Array:
	var z := _z(u)
	var top := _top(u)
	var belt := _belt(u)
	var bot := _bot(u)
	var hw := _hw(u)
	var ar := _arch(z, bot)
	var lip := minf(ar.x, belt - 0.03)
	var fl := ar.y
	var xi := maxf(hw - 0.30, 0.2)
	var xe := _edge_x(u)
	var y4 := lip + minf(0.05, (belt - lip) * 0.3)
	return [
		Vector3(0, bot, z),
		Vector3(xi, bot, z),
		Vector3(xi, lip, z),
		Vector3(hw - 0.012 + fl, lip, z),
		Vector3(hw + fl, y4, z),
		Vector3(hw + fl, lerpf(y4, belt, 0.5), z),
		Vector3(hw - 0.006 + fl * 0.6, lerpf(y4, belt, 0.85), z),
		Vector3(hw - 0.03, belt, z),
		Vector3(xe, top - 0.04, z),
		Vector3(xe - 0.06, top - 0.012, z),
		Vector3(xe * 0.55, top, z),
		Vector3(xe * 0.27, top, z),
		Vector3(0, top, z),
	]


func _stations() -> Array:
	var us := []
	var u := 0.0
	while u < 1.0001:
		us.append(u)
		u += 0.004 if (u < 0.08 or u > 0.92) else 0.01
	us.append(1.0)
	var rh: float = spec.arch
	for az in [spec.front_axle, spec.rear_axle]:
		for k in 21:
			us.append(_u(az + rh * cos(PI * k / 20.0)))
	for key in ["ws", "rw", "side", "bpillar", "hood"]:
		us.append(spec[key][0])
		us.append(spec[key][1])
	for p in spec.patches:
		us.append(p.u0)
		us.append(p.u1)
	for s in spec.seams:
		us.append(s)
	us.sort()
	var out := []
	for v in us:
		v = clampf(v, 0.0, 1.0)
		if out.is_empty() or v - out[-1] > 0.0012:
			out.append(v)
	out[-1] = 1.0
	return out


func _grid() -> Dictionary:
	var us := _stations()
	var g := []
	for u in us:
		g.append(_ring(u))
	var n := []
	var cnt := us.size()
	for i in cnt:
		var row := []
		var mid_y := (_top(us[i]) + _bot(us[i])) * 0.5
		for j in J:
			var p: Vector3 = g[i][j]
			var di: Vector3 = g[mini(i + 1, cnt - 1)][j] - g[maxi(i - 1, 0)][j]
			var dj: Vector3 = g[i][mini(j + 1, J - 1)] - g[i][maxi(j - 1, 0)]
			var nn := di.cross(dj)
			var ref := Vector3(p.x, p.y - mid_y, 0.0)
			if j == 0:
				ref = Vector3.DOWN
			elif j == J - 1:
				ref = Vector3.UP
			if nn.length_squared() < 1e-10:
				nn = ref
			nn = nn.normalized()
			if nn.dot(ref) < 0.0:
				nn = -nn
			if j == 0 or j == J - 1:
				nn.x = 0.0
				nn = nn.normalized()
			row.append(nn)
		n.append(row)
	return {"us": us, "g": g, "n": n}


static func _mx(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


class Surfs:
	var st := {}

	func get_st(id: String) -> SurfaceTool:
		if not st.has(id):
			st[id] = MeshKit.begin()
		return st[id]

	func build() -> Dictionary:
		var mesh := ArrayMesh.new()
		var names := []
		for id in st:
			var before := mesh.get_surface_count()
			MeshKit.add_surface(mesh, st[id], null)
			if mesh.get_surface_count() > before:
				names.append(id)
		return {"mesh": mesh, "names": names}


func _emit_quad(st: SurfaceTool, gd: Dictionary, i: int, j: int, off := 0.0) -> void:
	var g: Array = gd.g
	var n: Array = gd.n
	var a: Vector3 = g[i][j] + n[i][j] * off
	var b: Vector3 = g[i + 1][j] + n[i + 1][j] * off
	var c: Vector3 = g[i + 1][j + 1] + n[i + 1][j + 1] * off
	var d: Vector3 = g[i][j + 1] + n[i][j + 1] * off
	MeshKit.quad(st, a, b, c, d, n[i][j], n[i + 1][j], n[i + 1][j + 1], n[i][j + 1])
	MeshKit.quad(st, _mx(a), _mx(b), _mx(c), _mx(d), _mx(n[i][j]), _mx(n[i + 1][j]), _mx(n[i + 1][j + 1]), _mx(n[i][j + 1]))


static func _in(r: Array, u: float) -> bool:
	return u >= r[0] and u <= r[1]


func _shell(id: String) -> Dictionary:
	if _shell_cache.has(id):
		return _shell_cache[id]
	var gd := _grid()
	var us: Array = gd.us
	var g: Array = gd.g
	var n: Array = gd.n
	var sf := Surfs.new()
	var cnt := us.size()
	for i in cnt - 1:
		var um: float = (us[i] + us[i + 1]) * 0.5
		for j in J - 1:
			var m := "paint"
			if j == 7 and _in(spec.side, um):
				m = "trim" if _in(spec.bpillar, um) else "glass"
			elif j >= 9 and (_in(spec.ws, um) or _in(spec.rw, um)):
				m = "glass"
			elif j <= 2:
				m = "trim"
			_emit_quad(sf.get_st(m), gd, i, j)
		for p in spec.patches:
			if um >= p.u0 and um <= p.u1:
				for j in range(int(p.j0), int(p.j1)):
					_emit_quad(sf.get_st(p.mat), gd, i, j, PATCH_OFF)
	# panel seams (doors, hood)
	for su in spec.seams:
		var si := _nearest(us, su)
		_seam(sf.get_st("trim"), gd, si, 3, 7)
	_seam(sf.get_st("trim"), gd, _nearest(us, spec.hood[1]), 8, 12)
	_seam(sf.get_st("trim"), gd, _nearest(us, spec.hood[0]), 8, 12)
	# surface lamps
	for lp in spec.lamps:
		var li := _nearest(us, lp.u)
		var j0 := int(floor(lp.j))
		var f: float = lp.j - j0
		var pos: Vector3 = g[li][j0].lerp(g[li][j0 + 1], f)
		var nn: Vector3 = n[li][j0].lerp(n[li][j0 + 1], f).normalized()
		for sgn in [1.0, -1.0]:
			var pp := Vector3(pos.x * sgn, pos.y, pos.z)
			var pn := Vector3(nn.x * sgn, nn.y, nn.z)
			MeshKit.cylinder(sf.get_st("chrome"), pp - pn * 0.01, pn, lp.r + 0.014, 0.04, 20, true, lp.r + 0.008)
			MeshKit.cylinder(sf.get_st(lp.mat), pp + pn * 0.006, pn, lp.r, 0.012, 20)
	# end caps + their details
	for end in [0, 1]:
		var ri := 0 if end == 0 else cnt - 1
		var zc: float = g[ri][0].z
		var nz := Vector3(0, 0, -1.0 if end == 0 else 1.0)
		var center := Vector3(0, (g[ri][0].y + g[ri][J - 1].y) * 0.5, zc)
		var stp := sf.get_st("paint")
		for j in J - 1:
			var a: Vector3 = g[ri][j]
			var b: Vector3 = g[ri][j + 1]
			MeshKit.tri(stp, center, a, b, nz, nz, nz)
			MeshKit.tri(stp, center, _mx(a), _mx(b), nz, nz, nz)
		for d in (spec.front if end == 0 else spec.rear):
			var sides := [1.0, -1.0] if d.get("mirror", false) else [1.0]
			for sgn in sides:
				var c := Vector3(d.x * sgn, d.y, zc + nz.z * 0.004)
				if d.kind == "panel":
					MeshKit.box(sf.get_st(d.mat), c, Vector3(d.w, d.h, 0.014))
				else:
					MeshKit.cylinder(sf.get_st("chrome"), c, nz, d.r + 0.012, 0.016, 18)
					MeshKit.cylinder(sf.get_st(d.mat), c + nz * 0.008, nz, d.r, 0.012, 18)
	var res := sf.build()
	res["grid"] = gd
	_shell_cache[id] = res
	return res


func _nearest(us: Array, u: float) -> int:
	var best := 0
	for i in us.size():
		if absf(us[i] - u) < absf(us[best] - u):
			best = i
	return mini(best, us.size() - 2)


func _seam(st: SurfaceTool, gd: Dictionary, i: int, j0: int, j1: int) -> void:
	var g: Array = gd.g
	var n: Array = gd.n
	for j in range(j0, j1):
		var a: Vector3 = g[i][j] + n[i][j] * 0.003
		var d: Vector3 = g[i][j + 1] + n[i][j + 1] * 0.003
		var dir: Vector3 = (g[i + 1][j] - g[i][j])
		var w := dir.normalized() * 0.011
		MeshKit.quad(st, a, a + w, d + w, d, n[i][j], n[i][j], n[i][j + 1], n[i][j + 1])
		MeshKit.quad(st, _mx(a), _mx(a + w), _mx(d + w), _mx(d), _mx(n[i][j]), _mx(n[i][j]), _mx(n[i][j + 1]), _mx(n[i][j + 1]))


func _add_mirrors() -> void:
	var mu: float = spec.mirror_u
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 12
	sph.rings = 6
	var stalk := BoxMesh.new()
	stalk.size = Vector3(0.09, 0.02, 0.05)
	for sgn in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = sph
		mi.material_override = mats["paint"]
		mi.scale = Vector3(0.17, 0.105, 0.085)
		mi.position = Vector3(sgn * (_hw(mu) + 0.065), _belt(mu) + 0.075, _z(mu))
		mi.rotation.y = -0.25 * sgn
		body.add_child(mi)
		var s := MeshInstance3D.new()
		s.mesh = stalk
		s.material_override = mats["trim"]
		s.position = Vector3(sgn * (_hw(mu) - 0.0), _belt(mu) + 0.05, _z(mu))
		body.add_child(s)


# ====================================================================== wheels / ride
func _build_wheels() -> void:
	for c in _wheel_root.get_children():
		c.queue_free()
	wheels.clear()
	var size_idx := clampi(int(cfg.wheel_size), 0, 3)
	wheel_radius = WheelFactory.radius(size_idx)
	var tw: float = spec.tire_w
	for front in [true, false]:
		var z: float = spec.front_axle if front else spec.rear_axle
		var u := _u(z)
		var x := _hw(u) + 0.022 - tw * 0.5 - 0.012
		for left in [false, true]:
			var w := WheelFactory.build(int(cfg.rims), int(cfg.rim_color), size_idx, tw, left)
			w.pivot.position = Vector3(-x if left else x, wheel_radius, z)
			w["front"] = front
			_wheel_root.add_child(w.pivot)
			wheels.append(w)


func _update_ride() -> void:
	var drop: float = DROP[clampi(int(cfg.suspension), 0, 3)]
	body.position.y = (wheel_radius - CarSpecs.R0) - drop


func ride_offset() -> float:
	return body.position.y


# ====================================================================== parts
func _rebuild_slot(slot: String) -> void:
	if _slots.has(slot) and is_instance_valid(_slots[slot]):
		_slots[slot].queue_free()
	_slots.erase(slot)
	var idx := int(cfg.get(slot, 0))
	var sf := Surfs.new()
	match slot:
		"front": _part_front(sf, idx)
		"rear": _part_rear(sf, idx)
		"spoiler": _part_spoiler(sf, idx)
		"skirts": _part_skirts(sf, idx)
		"hood": _part_hood(sf, idx)
		"exhaust": _part_exhaust(sf, idx)
		"turbo": _part_turbo(sf, idx)
		"glow":
			_part_glow(idx)
			return
		"engine":
			_part_badge(idx)
			return
	var res := sf.build()
	if res.names.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "Part_" + slot
	mi.mesh = res.mesh
	for i in res.names.size():
		mi.set_surface_override_material(i, mats[res.names[i]])
	body.add_child(mi)
	_slots[slot] = mi


## Lofts a mirrored rectangular rail. fn(u) -> [x_in, x_out, y_low, y_high]
func _rail(st: SurfaceTool, u0: float, u1: float, steps: int, fn: Callable) -> void:
	var prev = null
	for k in steps + 1:
		var u := lerpf(u0, u1, float(k) / steps)
		var r: Array = fn.call(u)
		var z := _z(u)
		var q := [Vector3(r[0], r[2], z), Vector3(r[1], r[2], z), Vector3(r[1], r[3], z), Vector3(r[0], r[3], z)]
		if prev != null:
			if r[0] <= 0.0:
				var a2 := [_mx(prev[1]), prev[1], prev[2], _mx(prev[2])]
				var b2 := [_mx(q[1]), q[1], q[2], _mx(q[2])]
				MeshKit.hexa(st, a2, b2)
			else:
				MeshKit.hexa(st, prev, q)
				MeshKit.hexa(st, [_mx(prev[0]), _mx(prev[1]), _mx(prev[2]), _mx(prev[3])], [_mx(q[0]), _mx(q[1]), _mx(q[2]), _mx(q[3])])
		prev = q


func _nose_hw(u: float, extra: float) -> float:
	if u >= 0.0:
		return _hw(u) + extra
	return maxf(_hw(0.0) + extra + u * _L * 1.3, 0.1)


func _tail_hw(u: float, extra: float) -> float:
	if u <= 1.0:
		return _hw(u) + extra
	return maxf(_hw(1.0) + extra - (u - 1.0) * _L * 1.3, 0.1)


func _part_front(sf: Surfs, idx: int) -> void:
	if idx == 0:
		return
	var low := _bot(0.06)
	var ext := 0.012 if idx == 1 else 0.03
	var lip_mat := "trim" if idx == 1 else "carbon"
	# air dam fills the gap under the nose
	_rail(sf.get_st("paint"), -0.003, 0.05, 8, func(u): return [0.0, _nose_hw(u, 0.006), low - 0.02, _bot(maxf(u, 0.0)) + 0.03])
	# splitter plate
	var reach := 0.008 if idx == 1 else 0.02
	_rail(sf.get_st(lip_mat), -reach, 0.115, 14, func(u): return [0.0, _nose_hw(u, ext + 0.02), low - 0.05, low - 0.022])
	if idx == 2:
		# canards + support rods
		for sgn in [1.0, -1.0]:
			var cx: float = (_hw(0.035) + 0.035) * sgn
			var bs := Basis(Vector3.UP, -0.5 * sgn) * Basis(Vector3.RIGHT, 0.0) * Basis(Vector3.FORWARD, 0.35 * sgn)
			MeshKit.box(sf.get_st("carbon"), Vector3(cx, _bot(0.03) + 0.13, _z(0.04)), Vector3(0.16, 0.012, 0.2), bs)
			MeshKit.box(sf.get_st("carbon"), Vector3(cx, _bot(0.03) + 0.23, _z(0.045)), Vector3(0.13, 0.012, 0.17), bs)
			MeshKit.cylinder(sf.get_st("chrome"), Vector3(0.36 * sgn, low + 0.03, _z(-0.012)), Vector3(0, 0.95, 0.3).normalized(), 0.006, 0.17, 6)


func _part_rear(sf: Surfs, idx: int) -> void:
	if idx == 0:
		return
	var low := _bot(0.9)
	var m := "paint" if idx == 1 else "carbon"
	_rail(sf.get_st(m), 0.925, 1.004, 10, func(u): return [0.0, _tail_hw(u, 0.008), low - 0.035, _bot(minf(u, 1.0)) + 0.03])
	if idx == 1:
		_rail(sf.get_st("trim"), 0.985, 1.006, 2, func(u): return [0.0, 0.42, low - 0.045, low + 0.05])
	else:
		for k in 7:
			var x := lerpf(-0.48, 0.48, k / 6.0)
			MeshKit.box(sf.get_st("carbon"), Vector3(x, low + 0.005, _L * 0.5 - 0.13), Vector3(0.014, 0.13, 0.42), Basis(Vector3.RIGHT, 0.12))
		MeshKit.box(sf.get_st("carbon"), Vector3(0, low + 0.07, _L * 0.5 - 0.12), Vector3(1.05, 0.012, 0.4), Basis(Vector3.RIGHT, 0.12))


func _part_skirts(sf: Surfs, idx: int) -> void:
	if idx == 0:
		return
	var rh: float = spec.arch
	var u0 := _u(spec.front_axle + rh + 0.015)
	var u1 := _u(spec.rear_axle - rh - 0.015)
	var out := 0.028 if idx == 1 else 0.055
	var h := 0.05 if idx == 1 else 0.085
	var dn := 0.04 if idx == 1 else 0.06
	_rail(sf.get_st("paint"), u0, u1, 12, func(u): return [_hw(u) - 0.04, _hw(u) + out, _bot(u) - dn, _bot(u) + h])
	if idx == 2:
		_rail(sf.get_st("carbon"), u0 + 0.01, u1 - 0.01, 8, func(u): return [_hw(u) - 0.02, _hw(u) + out + 0.035, _bot(u) - dn - 0.012, _bot(u) - dn + 0.004])
		for sgn in [1.0, -1.0]:
			MeshKit.box(sf.get_st("carbon"), Vector3((_hw(u1) + out + 0.02) * sgn, _bot(u1) + 0.02, _z(u1) - 0.1), Vector3(0.012, 0.16, 0.2))


func _part_hood(sf: Surfs, idx: int) -> void:
	if idx == 0:
		return
	var gd: Dictionary = _shell(car_id).grid
	var us: Array = gd.us
	if idx == 1:
		var s0: float = spec.scoop[0]
		var s1: float = spec.scoop[1]
		var st := sf.get_st("paint")
		var prev = null
		var steps := 10
		for k in steps + 1:
			var t := float(k) / steps
			var u := lerpf(s0, s1, t)
			var hgt := 0.085 * (1.0 - t * t) + 0.004
			var wid := 0.21 * (1.0 - 0.25 * t)
			var yb := _top(u) - 0.01
			var z := _z(u)
			var q := [Vector3(-wid, yb, z), Vector3(wid, yb, z), Vector3(wid * 0.82, yb + hgt, z), Vector3(-wid * 0.82, yb + hgt, z)]
			if prev != null:
				MeshKit.hexa(st, prev, q)
			prev = q
		var yb0 := _top(s0)
		MeshKit.box(sf.get_st("grille"), Vector3(0, yb0 + 0.04, _z(s0) - 0.003), Vector3(0.34, 0.055, 0.01))
	else:
		var h0: float = spec.hood[0] + 0.012
		var h1: float = spec.hood[1] - 0.008
		var len := h1 - h0
		for i in us.size() - 1:
			var um: float = (us[i] + us[i + 1]) * 0.5
			if um > h0 and um < h1:
				for j in range(8, 12):
					_emit_quad(sf.get_st("carbon"), gd, i, j, 0.004)
				if um > h0 + len * 0.5 and um < h0 + len * 0.8:
					_emit_quad(sf.get_st("grille"), gd, i, 10, 0.009)
		# vent louvres
		for k in 4:
			var u := h0 + len * (0.53 + 0.07 * k)
			for sgn in [1.0, -1.0]:
				var x: float = _edge_x(u) * 0.41 * sgn
				MeshKit.box(sf.get_st("carbon"), Vector3(x, _top(u) + 0.014, _z(u)), Vector3(_edge_x(u) * 0.27, 0.006, 0.05), Basis(Vector3.RIGHT, 0.5))


func _part_spoiler(sf: Surfs, idx: int) -> void:
	if idx == 0:
		return
	var su: float = spec.spoiler_u
	if idx == 1:
		var st := sf.get_st("paint")
		var prev = null
		var steps := 8
		for k in steps + 1:
			var t := float(k) / steps
			var u := lerpf(su - 0.07, su + 0.02, t)
			var xw := _edge_x(u) * 0.96
			var yb := _top(u) - 0.05
			var hgt := 0.05 + 0.1 * pow(t, 1.6)
			var z := _z(u)
			var q := [Vector3(-xw, yb, z), Vector3(xw, yb, z), Vector3(xw * 0.97, yb + hgt, z), Vector3(-xw * 0.97, yb + hgt, z)]
			if prev != null:
				MeshKit.hexa(st, prev, q)
			prev = q
		return
	var gt := idx == 3
	var base_y := _top(su)
	var z := _z(su)
	var rise := 0.36 if gt else 0.2
	var span := (_hw(su) * 2.0 + 0.04) if gt else _edge_x(su) * 2.0 * 0.92
	var chord := 0.30 if gt else 0.2
	var blade_mat := "carbon" if gt else "paint"
	var tilt := Basis(Vector3.RIGHT, -0.16 if gt else -0.1)
	var st2 := sf.get_st(blade_mat)
	# airfoil-ish blade from three slabs
	MeshKit.box(st2, Vector3(0, base_y + rise, z), Vector3(span, 0.022, chord), tilt)
	MeshKit.box(st2, Vector3(0, base_y + rise + 0.012, z - chord * 0.18), Vector3(span, 0.016, chord * 0.5), tilt)
	var up_x := span * 0.5 * (0.52 if gt else 0.6)
	for sgn in [1.0, -1.0]:
		var um := "chrome" if gt else "trim"
		MeshKit.hexa(sf.get_st(um),
			[Vector3(up_x * sgn - 0.012, base_y - 0.05, z - 0.09), Vector3(up_x * sgn + 0.012, base_y - 0.05, z - 0.09), Vector3(up_x * sgn + 0.012, base_y - 0.05, z + 0.07), Vector3(up_x * sgn - 0.012, base_y - 0.05, z + 0.07)],
			[Vector3(up_x * sgn - 0.008, base_y + rise, z - 0.05), Vector3(up_x * sgn + 0.008, base_y + rise, z - 0.05), Vector3(up_x * sgn + 0.008, base_y + rise, z + 0.06), Vector3(up_x * sgn - 0.008, base_y + rise, z + 0.06)])
		if gt:
			MeshKit.box(sf.get_st("carbon"), Vector3(span * 0.5 * sgn, base_y + rise + 0.01, z + 0.01), Vector3(0.012, 0.17, chord + 0.08))
	if gt:
		MeshKit.box(st2, Vector3(0, base_y + rise + 0.07, z + chord * 0.42), Vector3(span, 0.012, 0.09), Basis(Vector3.RIGHT, -0.45))


func _part_exhaust(sf: Surfs, idx: int) -> void:
	var e: Dictionary = spec.exhaust
	var r: float = e.r * [1.0, 1.25, 1.5][clampi(idx, 0, 2)]
	var m := "titanium" if idx == 2 else "chrome"
	var zc := _L * 0.5 - 0.02
	var xs := []
	for x in e.x:
		xs.append(x)
		if e.mirror or idx > 0:
			xs.append(-x)
		if idx == 2:
			xs.append(x + r * 2.3)
			if e.mirror or idx > 0:
				xs.append(-x - r * 2.3)
	for x in xs:
		var c := Vector3(x, e.y, zc)
		MeshKit.cylinder(sf.get_st(m), c, Vector3.BACK, r, 0.2, 14, false, r * 1.08)
		MeshKit.cylinder(sf.get_st("grille"), c + Vector3(0, 0, 0.06), Vector3.BACK, r * 0.86, 0.01, 14)


func _part_turbo(sf: Surfs, idx: int) -> void:
	## Front-mount intercooler visible through the lower intake.
	if idx == 0:
		return
	if idx == 3:
		_part_blower(sf)
		return
	var w := 0.5 if idx == 1 else 0.68
	var zc := -_L * 0.5 - 0.006
	var y := _bot(0.0) + 0.085
	MeshKit.box(sf.get_st("intercooler"), Vector3(0, y, zc), Vector3(w, 0.1 if idx == 1 else 0.125, 0.02))
	var fins := 12 if idx == 1 else 18
	for k in fins:
		MeshKit.box(sf.get_st("grille"), Vector3(lerpf(-w * 0.46, w * 0.46, k / float(fins - 1)), y, zc - 0.011), Vector3(0.006, 0.09, 0.004))
	for sgn in [1.0, -1.0]:
		MeshKit.cylinder(sf.get_st("chrome"), Vector3((w * 0.5 + 0.03) * sgn, y, zc), Vector3.RIGHT, 0.035, 0.07, 10)


func _part_blower(sf: Surfs) -> void:
	## Roots blower standing through the hood: polished case, belt pulley and a scoop.
	var z: float = float(spec.front_axle) + 0.1
	var y := _top(_u(z)) - 0.01
	MeshKit.box(sf.get_st("chrome"), Vector3(0, y + 0.06, z), Vector3(0.3, 0.12, 0.42))
	for k in 6:
		MeshKit.box(sf.get_st("trim"), Vector3(0, y + 0.06, z - 0.18 + k * 0.072), Vector3(0.31, 0.1, 0.012))
	MeshKit.cylinder(sf.get_st("trim"), Vector3(0, y + 0.06, z - 0.25), Vector3.BACK, 0.07, 0.05, 14)
	MeshKit.box(sf.get_st("chrome"), Vector3(0, y + 0.16, z + 0.02), Vector3(0.26, 0.08, 0.3))
	MeshKit.box(sf.get_st("grille"), Vector3(0, y + 0.165, z - 0.132), Vector3(0.22, 0.05, 0.004))


func _part_badge(idx: int) -> void:
	## Engine stage shows as a fender badge behind each front wheel.
	if idx == 0:
		return
	var root := Node3D.new()
	root.name = "Badge"
	body.add_child(root)
	_slots["engine"] = root
	var z: float = spec.front_axle + float(spec.arch) + 0.24
	var u := _u(z)
	var cols := [Color(0.9, 0.9, 0.95), Color(1.6, 1.1, 0.1), Color(2.2, 0.15, 0.1)]
	for sgn in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "STAGE %d" % idx
		l.font = UI.title_font()
		l.font_size = 64
		l.pixel_size = 0.0011
		l.modulate = cols[idx - 1]
		l.outline_size = 10
		l.outline_modulate = Color(0.02, 0.02, 0.02)
		l.shaded = false
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.position = Vector3(sgn * (_hw(u) + 0.004), lerpf(_bot(u), _belt(u), 0.62), z)
		l.rotation.y = PI * 0.5 * sgn
		root.add_child(l)
		var strip := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.006, 0.012, 0.3)
		strip.mesh = bm
		strip.material_override = mats["chrome"]
		strip.position = l.position + Vector3(0, -0.055, 0)
		root.add_child(strip)


func _part_glow(idx: int) -> void:
	if idx == 0:
		return
	var col: Color = CarDB.UNDERGLOW[idx].c
	var root := Node3D.new()
	root.name = "Glow"
	add_child(root)
	_slots["glow"] = root
	var q := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.9, _L + 0.9)
	q.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _shadow_tex()
	m.albedo_color = Color(col.r, col.g, col.b, 1.0) * 0.9
	q.material_override = m
	q.position.y = 0.02
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(q)
	# neon tubes under the sills
	var tube := BoxMesh.new()
	tube.size = Vector3(0.025, 0.025, _L * 0.5)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = col * 3.0
	for sgn in [1.0, -1.0]:
		var t := MeshInstance3D.new()
		t.mesh = tube
		t.material_override = tm
		t.position = Vector3(sgn * (_hw(0.5) - 0.1), _bot(0.5) + body.position.y - 0.01, 0)
		root.add_child(t)
	if not is_reflection:
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 1.6
		l.omni_range = 3.2
		l.position.y = 0.12
		l.shadow_enabled = false
		root.add_child(l)
