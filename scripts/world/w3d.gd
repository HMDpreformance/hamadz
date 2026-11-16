class_name W3D
## Real-asset layer for the 3D world: photo-scanned CC0 PBR materials
## (Poly Haven / ambientCG), the modular apartment facade kit, street props,
## the night HDRI and the shared window / wet-road shaders.
## Everything is cached; nothing here touches the scene tree.

const TEX := "res://w3d/tex/"
const FAC := "res://w3d/facade/"

static var _mats := {}
static var _kit := {}            # node name -> Mesh
static var _kit_aabb := {}
static var _props := {}          # file -> [ {mesh, xf} ]
static var _sky: Texture2D
static var _shaders := {}
static var reflection_tex: Texture2D     # planar reflection of the street (set by PlanarReflection)


# ------------------------------------------------------------------ materials
## Photo-scanned PBR material. `tile` = metres covered by one texture repeat
## (UVs are generated in metres by MeshBatch).
static func pbr(name: String, tile := 2.0, tint := Color.WHITE, rough_mul := 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%s|%.2f" % [name, tile, tint, rough_mul]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + name + "_diff.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX + name + "_nor.jpg")
	m.orm_texture = null
	var arm: Texture2D = load(TEX + name + "_arm.jpg")
	m.ao_enabled = true
	m.ao_texture = arm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness_texture = arm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough_mul
	m.metallic_texture = arm
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.metallic = 1.0
	m.uv1_scale = Vector3(1.0 / tile, 1.0 / tile, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## ambientCG facade (whole building skin: windows painted in, with normal map
## and, where the set has one, an emission map of lit windows).
## tile = metres per repeat (x, y).
static func facade(name: String, tile: Vector2, glow := 1.6, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "F%s|%s|%.2f|%s" % [name, tile, glow, tint]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(FAC + name + "_diff.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(FAC + name + "_nor.jpg")
	var arm: Texture2D = load(FAC + name + "_arm.jpg")
	m.roughness_texture = arm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.metallic_texture = arm
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.metallic = 1.0
	if ResourceLoader.exists(FAC + name + "_emit.jpg"):
		m.emission_enabled = true
		m.emission_texture = load(FAC + name + "_emit.jpg")
		m.emission_energy_multiplier = glow
	m.uv1_scale = Vector3(1.0 / tile.x, 1.0 / tile.y, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


static func flat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var key := "C%s|%.2f|%.2f" % [c, rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


static func glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "E%s|%.2f" % [c, energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0, 0, 0)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		m.roughness = 0.4
		_mats[key] = m
	return _mats[key]


## Unlit textured panel (lit shop interiors, billboards): emissive photo.
static func photo(path: String, energy := 1.0, region := Rect2(0, 0, 1, 1)) -> StandardMaterial3D:
	var key := "P%s|%.2f|%s" % [path, energy, region]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		var t: Texture2D = load(path)
		m.albedo_color = Color(0.05, 0.05, 0.05)
		m.emission_enabled = true
		m.emission_texture = t
		m.emission_energy_multiplier = energy
		m.uv1_scale = Vector3(region.size.x, region.size.y, 1)
		m.uv1_offset = Vector3(region.position.x, region.position.y, 0)
		m.roughness = 0.7
		_mats[key] = m
	return _mats[key]


# ------------------------------------------------------------------ window glass
## One shader for every window in the city. Works from world position and the
## wall normal only (all buildings sit on the street grid), so it needs no UVs:
## each 3 m x 3 m cell behind the glass is a small box room (interior mapping).
## Some rooms are lit, most are dark; the glass itself is a dark mirror.
static func window_glass(lit := 0.42, cell := Vector2(3.0, 3.0), depth := 3.5, energy := 2.2, shop := false, uv_mode := false) -> ShaderMaterial:
	var key := "W%.2f|%s|%.2f|%.2f|%s|%s" % [lit, cell, depth, energy, shop, uv_mode]
	if _mats.has(key):
		return _mats[key]
	if not _shaders.has("window"):
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_back;
uniform sampler2D rooms : source_color, filter_linear_mipmap, repeat_disable;
uniform float lit_ratio = 0.42;
uniform vec2 cell = vec2(3.0, 3.0);
uniform float depth = 3.5;
uniform float energy = 2.2;
uniform float always_lit = 0.0;
uniform float use_uv = 0.0;
varying vec3 wp;
varying vec3 wn;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 n = normalize(vec3(wn.x, 0.0, wn.z));
	vec3 t = vec3(n.z, 0.0, -n.x);                 // along the wall
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(wp - cam);
	// room space: x along wall, y up, z into the building
	vec2 wall = mix(vec2(dot(wp, t), wp.y), UV, use_uv);
	vec2 id = floor(wall / cell);
	vec2 f = fract(wall / cell);
	vec3 rd = vec3(dot(v, t) / cell.x, v.y / cell.y, -dot(v, n) / depth);
	vec3 ro = vec3(f, 0.0);
	vec3 inv = 1.0 / (rd + vec3(1e-5));
	vec3 tmax = (step(vec3(0.0), rd) - ro) * inv;
	float tt = min(min(tmax.x, tmax.y), tmax.z);
	vec3 hit = ro + rd * tt;
	float r1 = h21(id + n.xz * 17.0);
	float r2 = h21(id.yx + 3.7);
	float on = max(step(1.0 - lit_ratio, r1), always_lit);
	// back wall photo from an 4x2 atlas of rooms; side walls / floor / ceiling flat
	vec2 tile = vec2(floor(r2 * 4.0), floor(fract(r2 * 7.3) * 2.0));
	vec3 col;
	if (tmax.z <= tt + 1e-4) {
		col = texture(rooms, (tile + vec2(0.08) + vec2(hit.x, 1.0 - hit.y) * 0.84) / vec2(4.0, 2.0)).rgb;
	} else {
		vec3 wallc = texture(rooms, (tile + vec2(0.12, 0.3)) / vec2(4.0, 2.0)).rgb;
		float lightc = hit.y > 0.98 ? 1.5 : (hit.y < 0.02 ? 0.45 : 0.85);
		col = wallc * lightc * (1.0 - hit.z * 0.55);
	}
	vec3 warm = mix(vec3(1.0, 0.78, 0.5), vec3(0.75, 0.88, 1.0), step(0.72, r2));
	// curtains / blinds drawn part of the way on some lit rooms
	float curtain = step(0.6, fract(r2 * 13.1)) * step(f.x, 0.22 + 0.5 * fract(r1 * 9.7));
	col = mix(col, vec3(0.75, 0.68, 0.55) * (0.6 + 0.4 * sin(f.x * 90.0)), curtain * 0.85);
	float fres = pow(1.0 - clamp(dot(-v, n), 0.0, 1.0), 4.0);
	ALBEDO = vec3(0.012, 0.016, 0.022);
	METALLIC = 0.9;
	ROUGHNESS = 0.06;
	SPECULAR = 0.8;
	EMISSION = col * warm * on * energy * (1.0 - fres * 0.7) * (0.55 + 0.45 * fract(r1 * 31.0));
}
"""
		_shaders["window"] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders["window"]
	m.set_shader_parameter("lit_ratio", lit)
	m.set_shader_parameter("cell", cell)
	m.set_shader_parameter("depth", depth)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("always_lit", 1.0 if shop else 0.0)
	m.set_shader_parameter("use_uv", 1.0 if uv_mode else 0.0)
	var path := "res://w3d/gen/shops.jpg" if shop else "res://w3d/gen/rooms.jpg"
	if ResourceLoader.exists(path):
		m.set_shader_parameter("rooms", load(path))
	_mats[key] = m
	return m


# ------------------------------------------------------------------ kit + props
static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		out.append({"name": String(n.name), "mesh": (n as MeshInstance3D).mesh, "xf": t})
	for c in n.get_children():
		_collect(c, t, out)


## Modular apartment facade kit (Poly Haven, CC0). 3 m x 3 m bays, front = +z,
## each module spans x in [-3, 0].
static func kit(name: String) -> Mesh:
	if _kit.is_empty():
		var ps: PackedScene = load("res://w3d/kit/apartments.glb")
		var root := ps.instantiate()
		var parts := []
		_collect(root, Transform3D.IDENTITY, parts)
		for p in parts:
			_kit[p.name] = p.mesh
			_kit_aabb[p.name] = (p.mesh as Mesh).get_aabb()
		root.free()
	return _kit.get(name)


static func kit_aabb(name: String) -> AABB:
	kit(name)
	return _kit_aabb.get(name, AABB())


static func kit_material(idx_name: String) -> Material:
	## The five materials of the kit by short name: objects, glass, trim_01, trim_02, plaster.
	var key := "K" + idx_name
	if _mats.has(key):
		return _mats[key]
	var probe := {"plaster": "wall_standard_standard_01", "trim_02": "base_standard_01", "trim_01": "crown_standard_standard_01"}
	var want := "modular_urban_apartments_facade_" + idx_name
	for nm in ["window_centered_large_01", "window_centered_large_03", "wall_standard_standard_01", "base_standard_01", "crown_standard_standard_01", "cornice_standard_standard_01"]:
		var m := kit(nm)
		if m == null:
			continue
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat and mat.resource_name == want:
				_mats[key] = mat
				return mat
	return null


## A prop file as a list of {mesh, xf} parts (node transforms baked), plus its AABB.
static func prop(file: String, only := "") -> Dictionary:
	var key := file + "|" + only
	if _props.has(key):
		return _props[key]
	var ps: PackedScene = load("res://w3d/props/" + file + ".glb")
	var root := ps.instantiate()
	var parts := []
	_collect(root, Transform3D.IDENTITY, parts)
	root.free()
	var keep := []
	var box := AABB()
	var first := true
	for p in parts:
		if only != "" and not String(p.name).begins_with(only):
			continue
		if String(p.name).contains("_aged") or String(p.name).contains("_rust"):
			continue
		keep.append(p)
		var b: AABB = p.xf * (p.mesh as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var d := {"parts": keep, "aabb": box}
	_props[key] = d
	return d


static func sky() -> Texture2D:
	if _sky == null:
		_sky = load("res://w3d/sky/night_sky_2k.hdr")
	return _sky
