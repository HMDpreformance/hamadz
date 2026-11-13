class_name SkylineKit
## Gulf-city building blocks: glass towers in several plan shapes (chamfered
## box, round, three-lobed, lens), stepped and twisted, with lit edge bands;
## the central supertall needle; date palms. Everything is generated meshes
## sharing a handful of materials, so towers batch well on phones.

static var _cache := {}


# ====================================================================== materials
static func glass() -> ShaderMaterial:
	if _cache.has("glass"):
		return _cache.glass
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
varying vec3 wp;
varying vec3 wn;
varying vec3 tint;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR.rgb;
}
void fragment() {
	vec2 tn = wn.xz / max(length(wn.xz), 0.001);
	float u = dot(wp.xz, vec2(-tn.y, tn.x));
	float floor_h = 3.8;
	float cw = 2.8;
	vec2 cell = floor(vec2(u / cw, wp.y / floor_h));
	vec2 f = fract(vec2(u / cw, wp.y / floor_h));
	float wall = step(abs(wn.y), 0.6);
	float mull = 1.0 - (step(f.x, 0.05) + step(0.9, f.y)) * 0.85;
	float slab = step(0.9, f.y);
	float h = hash(cell + floor(tint.rg * 97.0));
	float blk = hash(floor(vec2(u / 14.0, wp.y / 15.0)) + tint.b * 31.0);
	float lit = step(0.7, h) * step(0.4, blk) * wall * step(7.0, wp.y);
	vec3 warm = vec3(1.0, 0.8, 0.55);
	vec3 cool = vec3(0.75, 0.88, 1.0);
	vec3 wc = mix(warm, cool, step(0.55, hash(cell + 3.0)));
	ALBEDO = mix(tint * 0.1, vec3(0.03), slab * wall);
	METALLIC = mix(0.3, 0.95, wall * mull);
	ROUGHNESS = mix(0.6, 0.04, wall * mull);
	SPECULAR = 0.8;
	EMISSION = wc * lit * (0.15 + 0.5 * hash(cell + 7.0)) * mull * (1.0 - slab) + tint * 0.025 * wall;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_cache.glass = m
	return m


static func led(color: Color, energy := 4.0) -> StandardMaterial3D:
	var k := "led_%s_%s" % [color.to_html(), energy]
	if not _cache.has(k):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color * energy
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_cache[k] = m
	return _cache[k]


static func stone() -> StandardMaterial3D:
	if not _cache.has("stone"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.85
		_cache.stone = m
	return _cache.stone


# ====================================================================== plan shapes
static func plan(kind: String, n := 0) -> PackedVector2Array:
	## Unit plan (fits a 1 x 1 square around the origin), counter-clockwise from above.
	var p := PackedVector2Array()
	match kind:
		"round":
			for k in 20:
				var a := TAU * k / 20.0
				p.append(Vector2(cos(a), sin(a)) * 0.5)
		"tri":
			for k in 30:
				var a := TAU * k / 30.0
				var r := 0.5 * (0.72 + 0.28 * cos(3.0 * a))
				p.append(Vector2(cos(a), sin(a)) * r)
		"lens":
			for k in 24:
				var a := TAU * k / 24.0
				p.append(Vector2(cos(a) * 0.5, sin(a) * 0.5 * (0.45 + 0.55 * absf(cos(a)))))
		_:
			var c := 0.13
			var q := [Vector2(0.5, 0.5 - c), Vector2(0.5 - c, 0.5), Vector2(-0.5 + c, 0.5), Vector2(-0.5, 0.5 - c),
				Vector2(-0.5, -0.5 + c), Vector2(-0.5 + c, -0.5), Vector2(0.5 - c, -0.5), Vector2(0.5, -0.5 + c)]
			for v in q:
				p.append(v)
	return p


# ====================================================================== towers
## tiers: Array of {h, s (scale at top of tier), twist (radians over the tier)}
static func tower(kind: String, w: float, d: float, tiers: Array, tint: Color, band: Color) -> Node3D:
	var root := Node3D.new()
	var pl := plan(kind)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bands := SurfaceTool.new()
	bands.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.0
	var s := 1.0
	var rot := 0.0
	for t in tiers:
		s = float(t.get("from", s))
		var s_top: float = float(t.s)
		var tw: float = float(t.get("twist", 0.0))
		var steps: int = 1 if absf(tw) < 0.01 and absf(s_top - s) < 0.01 else 6
		var y_end: float = y + float(t.h)
		for k in steps:
			var a0 := float(k) / steps
			var a1 := float(k + 1) / steps
			_ring_wall(st, pl, w, d, lerpf(y, y_end, a0), lerpf(y, y_end, a1), lerpf(s, s_top, a0), lerpf(s, s_top, a1), rot + tw * a0, rot + tw * a1, tint)
		rot += tw
		s = s_top
		y = y_end
		# glowing edge band at the top of every tier, then the setback roof
		_ring_wall(bands, pl, w * 1.012, d * 1.012, y - 0.6, y, s, s, rot, rot, band)
		_cap(st, pl, w, d, y, s, rot, tint * 0.4)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = glass()
	root.add_child(mi)
	var bm := MeshInstance3D.new()
	bm.mesh = bands.commit()
	bm.material_override = led(band, 3.5)
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bm)
	root.set_meta("height", y)
	return root


static func _ring_wall(st: SurfaceTool, pl: PackedVector2Array, w: float, d: float, ya: float, yb: float, sa: float, sb: float, ra: float, rb: float, col: Color) -> void:
	var n := pl.size()
	for i in n:
		var p0 := pl[i]
		var p1 := pl[(i + 1) % n]
		var a0 := (p0 * sa).rotated(ra) * Vector2(w, d)
		var a1 := (p1 * sa).rotated(ra) * Vector2(w, d)
		var b0 := (p0 * sb).rotated(rb) * Vector2(w, d)
		var b1 := (p1 * sb).rotated(rb) * Vector2(w, d)
		var v := [Vector3(a0.x, ya, a0.y), Vector3(a1.x, ya, a1.y), Vector3(b1.x, yb, b1.y), Vector3(b0.x, yb, b0.y)]
		st.set_color(col)
		# outward winding for Godot (clockwise seen from outside)
		st.add_vertex(v[0]); st.add_vertex(v[2]); st.add_vertex(v[1])
		st.add_vertex(v[0]); st.add_vertex(v[3]); st.add_vertex(v[2])


static func _cap(st: SurfaceTool, pl: PackedVector2Array, w: float, d: float, y: float, s: float, r: float, col: Color) -> void:
	var n := pl.size()
	for i in n:
		var a := (pl[i] * s).rotated(r) * Vector2(w, d)
		var b := (pl[(i + 1) % n] * s).rotated(r) * Vector2(w, d)
		st.set_color(col)
		st.add_vertex(Vector3(0, y, 0)); st.add_vertex(Vector3(b.x, y, b.y)); st.add_vertex(Vector3(a.x, y, a.y))


static func spire(parent: Node3D, base_y: float, h: float, r: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.08
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.52, 0.56)
	m.metallic = 0.9
	m.roughness = 0.25
	mi.material_override = m
	mi.position.y = base_y + h * 0.5
	parent.add_child(mi)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = maxf(r * 0.35, 0.6)
	sm.height = sm.radius * 2.0
	tip.mesh = sm
	tip.material_override = led(Color(1.0, 0.12, 0.08), 6.0)
	tip.position.y = base_y + h + 0.4
	parent.add_child(tip)


## A random glass tower for a lot of size w x d, height h.
static func random_tower(r: RandomNumberGenerator, w: float, d: float, h: float) -> Node3D:
	var kinds := ["box", "box", "round", "tri", "lens"]
	var kind: String = kinds[r.randi() % kinds.size()]
	var tints := [Color(0.35, 0.55, 0.7), Color(0.4, 0.6, 0.62), Color(0.55, 0.6, 0.65), Color(0.6, 0.5, 0.38), Color(0.3, 0.42, 0.6)]
	var bands := [Color(1, 1, 1), Color(0.3, 0.75, 1.0), Color(1.0, 0.75, 0.35), Color(0.75, 0.4, 1.0), Color(0.3, 1.0, 0.85)]
	var tiers := []
	match r.randi() % 4:
		0:  # straight shaft, small crown setback
			tiers = [{"h": h * 0.88, "s": 1.0}, {"h": h * 0.12, "s": 0.7, "from": 0.78}]
		1:  # tapering
			tiers = [{"h": h, "s": 0.62}]
		2:  # twisting
			tiers = [{"h": h, "s": 0.85, "twist": r.randf_range(0.6, 1.2) * (1.0 if r.randf() < 0.5 else -1.0)}]
		_:  # stepped setbacks
			tiers = [{"h": h * 0.5, "s": 1.0}, {"h": h * 0.3, "s": 0.78, "from": 0.78}, {"h": h * 0.2, "s": 0.55, "from": 0.55}]
	var t := tower(kind, w, d, tiers, tints[r.randi() % tints.size()], bands[r.randi() % bands.size()])
	if h > 70.0 and r.randf() < 0.6:
		spire(t, float(t.get_meta("height")), h * r.randf_range(0.12, 0.25), minf(w, d) * 0.06)
	return t


## The city's centrepiece: a three-winged needle that steps in as it climbs.
static func supertall(h := 420.0) -> Node3D:
	var tiers := []
	var n := 9
	var s := 1.0
	for k in n:
		var ns := s * 0.84
		tiers.append({"h": h * 0.78 / n, "s": s, "from": ns})
		s = ns
	var t := tower("tri", 74.0, 74.0, tiers, Color(0.62, 0.68, 0.76), Color(0.75, 0.88, 1.0))
	spire(t, float(t.get_meta("height")), h * 0.22, 4.0)
	return t


# ====================================================================== palms
static func palm_mesh() -> ArrayMesh:
	if _cache.has("palm"):
		return _cache.palm
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Color(0.32, 0.24, 0.16)
	var frond := Color(0.16, 0.3, 0.1)
	# trunk: 6-sided, slight lean, ringed by colour
	var segs := 6
	var hgt := 7.5
	for k in 7:
		var y0 := hgt * k / 7.0
		var y1 := hgt * (k + 1) / 7.0
		var r0 := lerpf(0.28, 0.18, float(k) / 7.0)
		var r1 := lerpf(0.28, 0.18, float(k + 1) / 7.0)
		var l0 := Vector3(0.05 * y0 * y0 / hgt, 0, 0)
		var l1 := Vector3(0.05 * y1 * y1 / hgt, 0, 0)
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var v := [l0 + Vector3(cos(a0) * r0, y0, sin(a0) * r0), l0 + Vector3(cos(a1) * r0, y0, sin(a1) * r0),
				l1 + Vector3(cos(a1) * r1, y1, sin(a1) * r1), l1 + Vector3(cos(a0) * r1, y1, sin(a0) * r1)]
			st.set_color(trunk * (0.8 + 0.2 * (k % 2)))
			st.add_vertex(v[0]); st.add_vertex(v[2]); st.add_vertex(v[1])
			st.add_vertex(v[0]); st.add_vertex(v[3]); st.add_vertex(v[2])
	# fronds: drooping blades fanned around the crown
	var top := Vector3(0.05 * hgt, hgt, 0)
	var nf := 11
	for f in nf:
		var a := TAU * f / nf + (0.3 if f % 2 == 0 else 0.0)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var lift := 0.35 if f % 2 == 0 else 0.1
		var len := 3.6 if f % 2 == 0 else 3.1
		var prev_c := top
		var prev_w := 0.05
		for k in 6:
			var t := float(k + 1) / 6.0
			var c := top + dir * len * t + Vector3(0, lift * len * t - 1.9 * t * t, 0)
			var w := 0.55 * sin(t * PI) + 0.05
			var col := frond * (0.8 + 0.4 * t)
			var p0 := prev_c - side * prev_w
			var p1 := prev_c + side * prev_w
			var q0 := c - side * w
			var q1 := c + side * w
			st.set_color(col)
			st.add_vertex(p0); st.add_vertex(q1); st.add_vertex(p1)
			st.add_vertex(p0); st.add_vertex(q0); st.add_vertex(q1)
			prev_c = c
			prev_w = w
	st.generate_normals()
	var m := st.commit()
	_cache.palm = m
	return m


static func palm_material() -> StandardMaterial3D:
	if not _cache.has("palm_mat"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.8
		_cache.palm_mat = m
	return _cache.palm_mat
