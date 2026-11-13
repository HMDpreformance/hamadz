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


const FACADES := {
	# kind: [texture, tile size in metres, window grid in one tile, gloss]
	"stone": ["city_stone", Vector2(19.0, 17.5), Vector2(6, 5), 0.15],
	"office": ["city_office", Vector2(24.0, 21.0), Vector2(8, 6), 0.7],
	"resi": ["city_resi", Vector2(21.0, 20.0), Vector2(6, 6), 0.3],
	"glass": ["city_glass", Vector2(26.0, 28.0), Vector2(0, 0), 0.9],
	"villa": ["city_villa", Vector2(7.0, 3.3), Vector2(0, 0), 0.05],
	"mash": ["city_mash", Vector2(20.0, 18.0), Vector2(6, 5), 0.2],
}
const SHOPS := [["city_shops_a", Vector2(11.0, 6.0)], ["city_shops_b", Vector2(15.2, 6.0)]]


## Photo facade mapped in world space. shop >= 0 adds a street-level shopfront strip.
static func facade(kind: String, shop := -1) -> ShaderMaterial:
	var key := "facade_%s_%d" % [kind, shop]
	if _cache.has(key):
		return _cache[key]
	if not _cache.has("facade_shader"):
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
uniform sampler2D tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D shop_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec2 tile = vec2(20.0);
uniform vec2 grid = vec2(0.0);
uniform vec2 shop_tile = vec2(11.0, 6.0);
uniform float shop_h = 0.0;
uniform float gloss = 0.3;
uniform float gain = 2.4;
uniform float wash = 0.2;
varying vec3 wp;
varying vec3 wn;
varying float base_y;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	base_y = 0.14;
}
void fragment() {
	vec2 tn = wn.xz / max(length(wn.xz), 0.001);
	float u = dot(wp.xz, vec2(-tn.y, tn.x));
	float y = wp.y - base_y;
	float wall = step(abs(wn.y), 0.6);
	vec3 c;
	float lit_keep = 1.0;
	float g = gloss;
	if (y < shop_h) {
		c = texture(shop_tex, vec2(u / shop_tile.x, 1.0 - y / shop_tile.y)).rgb;
		g = 0.25;
	} else {
		vec2 uv = vec2(u / tile.x, (y - shop_h) / tile.y);
		c = texture(tex, vec2(uv.x, 1.0 - uv.y)).rgb;
		if (grid.x > 0.5) {
			vec2 cell = floor(uv * grid);
			lit_keep = step(0.3, hash(cell + floor(tn * 3.0)));
		}
	}
	float lum = max(c.r, max(c.g, c.b));
	float glow = smoothstep(0.32, 0.7, lum);
	vec3 night = c * mix(0.5, 0.16, glow * (1.0 - lit_keep));
	ALBEDO = mix(vec3(0.03, 0.03, 0.035), night, wall);
	// lit rooms glow; the rest of the facade keeps a soft dusk/street-light wash so it never goes black
	EMISSION = (c * glow * lit_keep * gain + c * wash * (1.0 - glow)) * wall;
	float glassy = (1.0 - glow * lit_keep) * g;
	METALLIC = glassy * 0.9 * wall;
	ROUGHNESS = mix(0.75, 0.06, glassy * wall);
	SPECULAR = 0.6;
}
"""
		_cache["facade_shader"] = sh
	var f: Array = FACADES[kind]
	var m := ShaderMaterial.new()
	m.shader = _cache["facade_shader"]
	m.set_shader_parameter("tex", load("res://textures/%s.jpg" % f[0]))
	m.set_shader_parameter("tile", f[1])
	m.set_shader_parameter("grid", f[2])
	m.set_shader_parameter("gloss", f[3])
	if kind == "villa":
		m.set_shader_parameter("gain", 0.3)
		m.set_shader_parameter("wash", 0.06)
	if shop >= 0:
		var sp: Array = SHOPS[shop % SHOPS.size()]
		m.set_shader_parameter("shop_tex", load("res://textures/%s.jpg" % sp[0]))
		m.set_shader_parameter("shop_tile", sp[1])
		m.set_shader_parameter("shop_h", 6.0)
	_cache[key] = m
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
static func tower(kind: String, w: float, d: float, tiers: Array, tint: Color, band: Color, mat: Material = null) -> Node3D:
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
	mi.material_override = mat if mat else glass()
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
	var skins := ["office", "glass", "glass", "resi", "mash", "office", "stone"]
	var t := tower(kind, w, d, tiers, tints[r.randi() % tints.size()], bands[r.randi() % bands.size()], facade(skins[r.randi() % skins.size()]))
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
	var t := tower("tri", 74.0, 74.0, tiers, Color(0.62, 0.68, 0.76), Color(0.75, 0.88, 1.0), facade("glass"))
	spire(t, float(t.get_meta("height")), h * 0.22, 4.0)
	return t


# ====================================================================== palms
static func palm_mesh() -> ArrayMesh:
	## Date palm as three crossed photo cards (textures/palm_card.png, cut from a
	## generated photo): reads as a real tree from the street for ~12 triangles.
	if _cache.has("palm"):
		return _cache.palm
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 9.5
	var w := h * 0.5
	for k in 3:
		var a := PI * k / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * w
		var v := [-d, d, d + Vector3(0, h, 0), -d + Vector3(0, h, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal((Vector3(0, 1, 0) + Vector3(-sin(a), 0, cos(a)) * 0.4).normalized())
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	var m := st.commit()
	_cache.palm = m
	return m


static func palm_material() -> StandardMaterial3D:
	if not _cache.has("palm_mat"):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://textures/palm_card.png")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.85
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 0.06
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_cache.palm_mat = m
	return _cache.palm_mat
