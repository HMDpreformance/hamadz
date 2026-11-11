class_name City
extends Node3D
## Procedural night city: a grid of wet streets, sidewalks, lit buildings,
## neon signs, street lights and traffic lights. One instance powers the test
## drive; smaller ones (blocks = 2..3) back the menu and the intro cinematic.

const BLOCK := 64.0
const ROAD := 18.0
const PITCH := BLOCK + ROAD
const CURB := 0.14
const SIGNS := ["NOODLE BAR", "24 HR", "PAWN", "ARCADE", "TATTOO", "MOTEL", "DINER", "KARAOKE", "CLUB VOLT", "SUSHI", "HOTEL", "RAMEN", "LOANS", "PARTS", "TIRES", "BILLIARDS", "CAR WASH", "PIZZA", "LAUNDRY", "RECORDS"]
const NEON := [Color(1.0, 0.1, 0.5), Color(0.1, 0.85, 1.0), Color(1.0, 0.65, 0.05), Color(0.3, 1.0, 0.3), Color(0.65, 0.25, 1.0), Color(1.0, 0.2, 0.1)]

var blocks := 5
var seed_v := 77
var with_colliders := true
var half := 0.0                      # half extent of the road grid
var lamp_positions: PackedVector3Array = []
var block_rects: Array[Rect2] = []
var _rng := RandomNumberGenerator.new()
var _bld_mat: ShaderMaterial
var _signal_mm: MultiMesh
var _signal_data := []               # [{pos_g, pos_y, pos_r, ns}]
var _signal_t := 0.0
var _signal_phase := -1
var _light_pool: Array[OmniLight3D] = []
var _pool_timer := 0.0
var focus: Node3D                    # lights gather around this node


func road(i: int) -> float:
	return (i - blocks * 0.5) * PITCH


func build() -> void:
	_rng.seed = seed_v
	half = blocks * 0.5 * PITCH
	_ground()
	_blocks()
	_boundary()
	_street_lights()
	_traffic_lights()
	set_process(true)


## Height of the drivable surface (sidewalks are raised).
func ground_height(p: Vector3) -> float:
	var v := Vector2(p.x, p.z)
	for r in block_rects:
		if r.has_point(v):
			return CURB
	return 0.0


# ---------------------------------------------------------------- ground
func _ground() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform float pitch = 82.0;
uniform float half_road = 9.0;
uniform float offset = 0.0;
uniform float extent = 205.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float lane(float d, float along) {
	float m = 0.0;
	m += smoothstep(0.09, 0.06, abs(d - 3.75)) * step(fract(along / 9.0), 0.38);
	m += smoothstep(0.1, 0.07, abs(d - 7.7));
	return m;
}
void fragment() {
	vec2 p = wp.xz;
	vec2 q = mod(p - offset + pitch * 0.5, pitch) - pitch * 0.5;
	vec2 d = abs(q);
	bool in_grid = abs(p.x) < extent + half_road && abs(p.y) < extent + half_road;
	bool on_x = d.x < half_road && in_grid;
	bool on_z = d.y < half_road && in_grid;
	float white = 0.0;
	float yellow = 0.0;
	if (on_x && !on_z) {
		white = lane(d.x, p.y);
		yellow = smoothstep(0.09, 0.06, abs(d.x - 0.2));
		float cw = step(half_road + 1.2, d.y) * step(d.y, half_road + 4.2);
		white = max(white * (1.0 - step(d.y, half_road + 5.4)), cw * step(0.5, fract(q.x / 1.3)) * step(d.x, 7.4));
		yellow *= 1.0 - step(d.y, half_road + 5.4);
		white = max(white, step(half_road + 5.0, d.y) * step(d.y, half_road + 5.4) * step(d.x, 7.4));
	} else if (on_z && !on_x) {
		white = lane(d.y, p.x);
		yellow = smoothstep(0.09, 0.06, abs(d.y - 0.2));
		float cw = step(half_road + 1.2, d.x) * step(d.x, half_road + 4.2);
		white = max(white * (1.0 - step(d.x, half_road + 5.4)), cw * step(0.5, fract(q.y / 1.3)) * step(d.y, 7.4));
		yellow *= 1.0 - step(d.x, half_road + 5.4);
		white = max(white, step(half_road + 5.0, d.x) * step(d.x, half_road + 5.4) * step(d.y, 7.4));
	}
	float n = texture(noise_tex, p * 0.035).r;
	float n2 = texture(noise_tex, p * 0.011 + 0.37).r;
	float fine = texture(noise_tex, p * 0.6).r;
	vec3 asphalt = vec3(0.035, 0.036, 0.04) * (0.7 + 0.6 * fine);
	float wear = 0.55 + 0.45 * n;
	vec3 col = mix(asphalt, vec3(0.62, 0.62, 0.6), clamp(white, 0.0, 1.0) * wear);
	col = mix(col, vec3(0.7, 0.5, 0.05), clamp(yellow, 0.0, 1.0) * wear);
	float puddle = smoothstep(0.52, 0.66, n2);
	ALBEDO = col * (1.0 - puddle * 0.45);
	ROUGHNESS = mix(0.42, 0.06, puddle) + fine * 0.12;
	METALLIC = 0.25 * puddle;
	SPECULAR = 0.6;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("pitch", PITCH)
	m.set_shader_parameter("half_road", ROAD * 0.5)
	m.set_shader_parameter("offset", road(0))
	m.set_shader_parameter("extent", half)
	m.set_shader_parameter("noise_tex", EnvKit.noise_tex(3, 0.03))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2 + 140, half * 2 + 140)
	mi.mesh = pm
	mi.material_override = m
	add_child(mi)


# ---------------------------------------------------------------- buildings
func _building_material() -> ShaderMaterial:
	if _bld_mat:
		return _bld_mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 lp;
varying vec3 ln;
varying flat float seed;
varying float wy;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 neon(float h) {
	if (h < 0.2) return vec3(1.0, 0.1, 0.5);
	if (h < 0.4) return vec3(0.1, 0.85, 1.0);
	if (h < 0.6) return vec3(1.0, 0.65, 0.05);
	if (h < 0.8) return vec3(0.9, 0.9, 1.0);
	return vec3(0.55, 0.25, 1.0);
}
void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	vec3 o = MODEL_MATRIX[3].xyz;
	seed = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453);
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	float side = step(0.5, abs(ln.x));
	vec2 uv = mix(lp.xy, lp.zy, side);
	vec3 base = mix(vec3(0.05, 0.055, 0.07), vec3(0.09, 0.07, 0.065), step(0.5, seed)) * (0.7 + 0.6 * seed);
	vec3 col = base;
	vec3 emi = vec3(0.0);
	float rough = 0.75;
	float metal = 0.0;
	if (abs(ln.y) < 0.5) {
		float cw = mix(2.4, 3.4, fract(seed * 7.0));
		vec2 cell = floor(vec2(uv.x / cw, wy / 3.3));
		vec2 f = fract(vec2(uv.x / cw, wy / 3.3));
		float win = step(0.14, f.x) * step(f.x, 0.86) * step(0.22, f.y) * step(f.y, 0.8);
		float h = hash(cell + vec2(seed * 71.0, side * 13.0));
		float lit = step(0.66, h);
		vec3 wc = mix(vec3(1.0, 0.74, 0.4), vec3(0.55, 0.8, 1.0), step(0.86, hash(cell + 5.0)));
		if (wy > 4.2) {
			emi = wc * win * lit * (0.5 + 1.6 * hash(cell + 9.0));
			col = mix(base, vec3(0.01, 0.012, 0.02), win);
			rough = mix(0.75, 0.12, win);
			metal = win * 0.7;
		} else if (wy > 0.5 && wy < 3.5) {
			float sx = uv.x / 8.0;
			float shop = step(0.08, fract(sx)) * step(fract(sx), 0.92);
			float sh = hash(vec2(floor(sx), seed * 31.0 + side));
			float mull = step(0.06, fract(uv.x / 2.0)) * step(0.12, fract(wy / 1.5));
			float glowv = 0.25 + 0.75 * smoothstep(3.5, 0.5, wy);
			emi = mix(neon(sh), vec3(1.0, 0.85, 0.6), 0.45) * shop * mull * step(0.3, sh) * 0.5 * glowv;
			col = mix(base, vec3(0.02), shop);
			rough = mix(0.75, 0.15, shop);
		} else if (wy >= 3.5 && wy < 4.0) {
			emi = neon(fract(seed * 3.7)) * 1.3 * step(0.25, fract(seed * 9.1));
		}
	}
	ALBEDO = col;
	EMISSION = emi;
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""
	_bld_mat = ShaderMaterial.new()
	_bld_mat.shader = sh
	return _bld_mat


func add_building(pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _building_material()
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	add_child(mi)
	# rooftop: parapet glow + beacon on tall towers
	if size.y > 38.0:
		EnvKit.box(self, Vector3(0.6, 3.0, 0.6), pos + Vector3(0, size.y + 1.5, 0), EnvKit.solid(Color(0.05, 0.05, 0.05)))
		EnvKit.box(self, Vector3(0.9, 0.5, 0.9), pos + Vector3(0, size.y + 3.2, 0), EnvKit.emissive(Color(1.0, 0.1, 0.05), 5.0))


func add_sign(text: String, pos: Vector3, rot_y: float, color: Color, height := 2.2, vertical := false) -> void:
	var l := Label3D.new()
	var t := text
	if vertical:
		t = ""
		for ch in text.replace(" ", ""):
			t += ch + "\n"
		t = t.strip_edges()
	l.text = t
	l.font = UI.title_font(not vertical)
	l.font_size = 96
	l.pixel_size = height / 96.0
	l.line_spacing = -22.0
	l.modulate = Color(color.r * 2.6 + 0.25, color.g * 2.6 + 0.25, color.b * 2.6 + 0.25)
	l.shaded = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = pos
	l.rotation.y = rot_y
	add_child(l)
	# dark backing board + halo
	var fwd := Vector3(sin(rot_y), 0, cos(rot_y))
	var w := height * 0.62 * (1.4 if vertical else float(text.length())) + 1.0
	var h := (height * 0.82 * text.replace(" ", "").length() + 1.0) if vertical else height * 1.5
	EnvKit.box(self, Vector3(w, h, 0.2), pos - fwd * 0.16, EnvKit.solid(Color(0.015, 0.015, 0.02), 0.4), Vector3(0, rot_y, 0))
	var halo := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w * 2.2, h * 2.2)
	halo.mesh = qm
	halo.material_override = EnvKit.glow_mat(color, 0.22)
	halo.position = pos + fwd * 0.12
	halo.rotation.y = rot_y
	add_child(halo)


func _blocks() -> void:
	var sidewalk := StandardMaterial3D.new()
	sidewalk.albedo_color = Color(0.2, 0.2, 0.21)
	sidewalk.albedo_texture = EnvKit.noise_tex(8, 0.05)
	sidewalk.uv1_triplanar = true
	sidewalk.uv1_scale = Vector3(0.2, 0.2, 0.2)
	sidewalk.roughness = 0.7
	var swm := BoxMesh.new()
	swm.size = Vector3(BLOCK, CURB, BLOCK)
	for bi in blocks:
		for bj in blocks:
			var cx := road(bi) + PITCH * 0.5
			var cz := road(bj) + PITCH * 0.5
			var sw := MeshInstance3D.new()
			sw.mesh = swm
			sw.material_override = sidewalk
			sw.position = Vector3(cx, CURB * 0.5, cz)
			add_child(sw)
			block_rects.append(Rect2(cx - BLOCK * 0.5, cz - BLOCK * 0.5, BLOCK, BLOCK))
			_fill_block(cx, cz, bi, bj)


func _fill_block(cx: float, cz: float, bi: int, bj: int) -> void:
	var setback := 5.0
	var lot := (BLOCK - setback * 2.0)
	var central := 1.0 - (absf(bi - (blocks - 1) * 0.5) + absf(bj - (blocks - 1) * 0.5)) / maxf(blocks, 1.0)
	var pattern := _rng.randi() % 4
	var rects := []
	if with_colliders:
		# one solid collider per block (no alley pockets for the car to wedge into)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(lot, 14.0, lot)
		cs.shape = bs
		sb.add_child(cs)
		sb.position = Vector3(cx, 7.0, cz)
		add_child(sb)
	match pattern:
		0:  # four towers with alleys
			var s := lot * 0.5 - 2.5
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					rects.append([Vector2(sx * (s * 0.5 + 2.5), sz * (s * 0.5 + 2.5)), Vector2(s, s)])
		1:  # one slab + two small
			rects.append([Vector2(0, -lot * 0.25 - 1.5), Vector2(lot, lot * 0.5 - 3.0)])
			var s2 := lot * 0.5 - 2.5
			rects.append([Vector2(-(s2 * 0.5 + 2.5), lot * 0.25 + 1.5), Vector2(s2, lot * 0.5 - 3.0)])
			rects.append([Vector2(s2 * 0.5 + 2.5, lot * 0.25 + 1.5), Vector2(s2, lot * 0.5 - 3.0)])
		2:  # two slabs
			rects.append([Vector2(-lot * 0.25 - 1.5, 0), Vector2(lot * 0.5 - 3.0, lot)])
			rects.append([Vector2(lot * 0.25 + 1.5, 0), Vector2(lot * 0.5 - 3.0, lot)])
		3:  # big tower with podium
			rects.append([Vector2(0, 0), Vector2(lot, lot)])
	for r in rects:
		var c: Vector2 = r[0]
		var sz: Vector2 = r[1]
		var hgt := _rng.randf_range(10.0, 26.0) + central * _rng.randf_range(8.0, 46.0)
		if pattern == 3:
			add_building(Vector3(cx, CURB, cz), Vector3(sz.x, 9.0, sz.y))
			add_building(Vector3(cx, CURB + 9.0, cz), Vector3(sz.x * 0.6, hgt + 14.0, sz.y * 0.6))
		else:
			add_building(Vector3(cx + c.x, CURB, cz + c.y), Vector3(sz.x, hgt, sz.y))
		# signs on the faces that look onto streets
		var faces := []
		if c.x + sz.x * 0.5 > lot * 0.5 - 1.0:
			faces.append([Vector3(cx + c.x + sz.x * 0.5 + 0.25, 0, cz + c.y), PI * 0.5, sz.y])
		if c.x - sz.x * 0.5 < -lot * 0.5 + 1.0:
			faces.append([Vector3(cx + c.x - sz.x * 0.5 - 0.25, 0, cz + c.y), -PI * 0.5, sz.y])
		if c.y + sz.y * 0.5 > lot * 0.5 - 1.0:
			faces.append([Vector3(cx + c.x, 0, cz + c.y + sz.y * 0.5 + 0.25), 0.0, sz.x])
		if c.y - sz.y * 0.5 < -lot * 0.5 + 1.0:
			faces.append([Vector3(cx + c.x, 0, cz + c.y - sz.y * 0.5 - 0.25), PI, sz.x])
		for f in faces:
			if _rng.randf() < 0.55:
				var txt: String = SIGNS[_rng.randi() % SIGNS.size()]
				var col: Color = NEON[_rng.randi() % NEON.size()]
				var fp: Vector3 = f[0]
				var along := Vector3(cos(f[1]), 0, -sin(f[1])) * _rng.randf_range(-0.25, 0.25) * float(f[2])
				if _rng.randf() < 0.3 and hgt > 18.0:
					add_sign(txt, fp + along + Vector3(0, minf(hgt, 22.0) * 0.6 + 2.0, 0), f[1], col, 1.9, true)
				else:
					add_sign(txt, fp + along + Vector3(0, _rng.randf_range(5.6, 8.5), 0), f[1], col, _rng.randf_range(1.5, 2.4))


func _boundary() -> void:
	## Ring of dark towers + colliders so the player stays in the district.
	var e := half + ROAD * 0.5
	var n := int((e * 2.0) / 42.0) + 1
	for side in 4:
		for k in n:
			var t := -e + (k + 0.5) * (e * 2.0 / n)
			var hgt := _rng.randf_range(18.0, 70.0)
			var depth := 30.0
			var p := Vector3(t, 0, -e - depth * 0.5 - 1.0)
			var s := Vector3(e * 2.0 / n - 3.0, hgt, depth)
			match side:
				1: p = Vector3(t, 0, e + depth * 0.5 + 1.0)
				2:
					p = Vector3(-e - depth * 0.5 - 1.0, 0, t)
					s = Vector3(depth, hgt, e * 2.0 / n - 3.0)
				3:
					p = Vector3(e + depth * 0.5 + 1.0, 0, t)
					s = Vector3(depth, hgt, e * 2.0 / n - 3.0)
			var wc := with_colliders
			with_colliders = false
			add_building(p, s)
			with_colliders = wc
	if with_colliders:
		for side in 4:
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(e * 2.0 + 80.0, 20.0, 10.0) if side < 2 else Vector3(10.0, 20.0, e * 2.0 + 80.0)
			cs.shape = bs
			sb.add_child(cs)
			sb.position = [Vector3(0, 10, -e - 5.5), Vector3(0, 10, e + 5.5), Vector3(-e - 5.5, 10, 0), Vector3(e + 5.5, 10, 0)][side]
			add_child(sb)


# ---------------------------------------------------------------- street furniture
func _mm(mesh: Mesh, mat: Material, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _street_lights() -> void:
	var poles := []
	var arms := []
	var heads := []
	var pools := []
	var hr := ROAD * 0.5 + 0.9
	for i in blocks + 1:
		var rc := road(i)
		for seg in blocks:
			var base := road(seg) + ROAD * 0.5
			for k in 2:
				var t := base + BLOCK * (0.25 + 0.5 * k)
				for sgn in [-1.0, 1.0]:
					if (k == 0) != (sgn > 0.0):
						continue  # stagger: alternate sides
					# along z (north-south road at x = rc)
					for axis in 2:
						var p := Vector3(rc + sgn * hr, 0, t) if axis == 0 else Vector3(t, 0, rc + sgn * hr)
						var inward := Vector3(-sgn, 0, 0) if axis == 0 else Vector3(0, 0, -sgn)
						poles.append(Transform3D(Basis.IDENTITY, p + Vector3(0, 3.6 + CURB, 0)))
						var ab := Basis.looking_at(inward, Vector3.UP)
						arms.append(Transform3D(ab, p + Vector3(0, 7.2, 0) + inward * 1.3))
						heads.append(Transform3D(ab, p + Vector3(0, 7.1, 0) + inward * 2.7))
						pools.append(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.03, 0) + inward * 3.4))
						lamp_positions.append(p + Vector3(0, 6.6, 0) + inward * 3.0)
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.12
	pm.height = 7.2
	pm.radial_segments = 6
	pm.rings = 1
	var metal := EnvKit.solid(Color(0.08, 0.085, 0.09), 0.5, 0.7)
	_mm(pm, metal, poles)
	var am := BoxMesh.new()
	am.size = Vector3(0.09, 0.09, 2.8)
	_mm(am, metal, arms)
	var hm := BoxMesh.new()
	hm.size = Vector3(0.34, 0.1, 0.7)
	_mm(hm, EnvKit.emissive(Color(1.0, 0.72, 0.38), 6.0), heads)
	var qm := PlaneMesh.new()
	qm.size = Vector2(17, 17)
	_mm(qm, EnvKit.glow_mat(Color(1.0, 0.6, 0.25), 0.16), pools)
	# pooled real lights that follow the focus node
	var count: int = maxi(int(GFX.p.lights) - 2, 2)
	for i in count:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 3.0
		l.omni_range = 19.0
		l.omni_attenuation = 1.1
		l.shadow_enabled = false
		add_child(l)
		_light_pool.append(l)
		if i < lamp_positions.size():
			l.position = lamp_positions[i]


func _traffic_lights() -> void:
	var posts := []
	var boxes := []
	var hr := ROAD * 0.5 + 0.7
	for i in range(1, blocks):
		for j in range(1, blocks):
			var c := Vector3(road(i), 0, road(j))
			# one signal per approach, on the far-right corner
			var defs := [
				[Vector3(hr, 0, -hr), 0.0, true],        # faces +z (traffic heading -z)
				[Vector3(-hr, 0, hr), PI, true],
				[Vector3(hr, 0, hr), PI * 0.5, false],
				[Vector3(-hr, 0, -hr), -PI * 0.5, false],
			]
			for d in defs:
				var p: Vector3 = c + d[0]
				var b := Basis(Vector3.UP, d[1])
				posts.append(Transform3D(Basis.IDENTITY, p + Vector3(0, 2.6 + CURB, 0)))
				boxes.append(Transform3D(b, p + Vector3(0, 4.9, 0)))
				var f: Vector3 = b * Vector3(0, 0, 0.16)
				_signal_data.append({"g": p + Vector3(0, 4.5, 0) + f, "y": p + Vector3(0, 4.9, 0) + f, "r": p + Vector3(0, 5.3, 0) + f, "ns": d[2], "basis": b})
	if posts.is_empty():
		return
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.09
	pm.height = 5.2
	pm.radial_segments = 6
	pm.rings = 1
	var metal := EnvKit.solid(Color(0.06, 0.06, 0.065), 0.5, 0.6)
	_mm(pm, metal, posts)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 1.3, 0.3)
	_mm(bm, EnvKit.solid(Color(0.02, 0.02, 0.02), 0.6), boxes)
	_signal_mm = MultiMesh.new()
	_signal_mm.transform_format = MultiMesh.TRANSFORM_3D
	_signal_mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	sm.radial_segments = 8
	sm.rings = 4
	_signal_mm.mesh = sm
	_signal_mm.instance_count = _signal_data.size()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _signal_mm
	mi.material_override = mat
	add_child(mi)
	_update_signals(0)


func _update_signals(phase: int) -> void:
	if _signal_mm == null or phase == _signal_phase:
		return
	_signal_phase = phase
	for i in _signal_data.size():
		var d: Dictionary = _signal_data[i]
		var state := "r"
		if d.ns:
			state = ["g", "y", "r", "r"][phase]
		else:
			state = ["r", "r", "g", "y"][phase]
		var col := Color(0.2, 3.0, 0.5)
		if state == "y":
			col = Color(3.0, 1.8, 0.1)
		elif state == "r":
			col = Color(3.2, 0.15, 0.1)
		_signal_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, d[state]))
		_signal_mm.set_instance_color(i, col)


func _process(delta: float) -> void:
	_signal_t = fmod(_signal_t + delta, 17.0)
	var ph := 0
	if _signal_t > 15.0:
		ph = 3
	elif _signal_t > 8.5:
		ph = 2
	elif _signal_t > 7.0:
		ph = 1
	_update_signals(ph)
	_pool_timer -= delta
	if _pool_timer <= 0.0 and focus != null and not _light_pool.is_empty():
		_pool_timer = 0.3
		_assign_lights(focus.global_position)


func _assign_lights(center: Vector3) -> void:
	var cand := []
	for p in lamp_positions:
		var d := Vector2(p.x - center.x, p.z - center.z).length_squared()
		if d < 90.0 * 90.0:
			cand.append([d, p])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for i in _light_pool.size():
		if i < cand.size():
			_light_pool[i].visible = true
			_light_pool[i].position = cand[i][1]
		else:
			_light_pool[i].visible = false
