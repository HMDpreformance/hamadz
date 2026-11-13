class_name EnvKit
## Procedural environment textures: reflection panoramas, concrete/asphalt, glow sprites.

static var _cache := {}


## Panorama used only for reflections: dark room with soft light strips, so
## glossy paint picks up long studio-style highlights.
static func studio_sky(accent_a := Color(1.0, 0.6, 0.15), accent_b := Color(0.1, 0.7, 1.0), strength := 1.0) -> ImageTexture:
	var key := "sky%s%s%f" % [accent_a, accent_b, strength]
	if _cache.has(key):
		return _cache[key]
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBAH)
	for y in h:
		var v := float(y) / h           # 0 = zenith, 1 = nadir
		for x in w:
			var u := float(x) / w
			var c := Color(0.012, 0.014, 0.022)
			# horizon haze
			var hz := exp(-pow((v - 0.5) / 0.07, 2.0))
			c += Color(0.05, 0.045, 0.07) * hz
			# overhead strip lights (3 long tubes)
			for k in 3:
				var cu := 0.12 + k * 0.33
				var du := absf(fposmod(u - cu + 0.5, 1.0) - 0.5)
				var s := smoothstep(0.045, 0.02, du) * smoothstep(0.02, 0.07, v) * smoothstep(0.36, 0.26, v)
				c += Color(1.0, 0.97, 0.9) * s * 5.0 * strength
			# side accent panels near the horizon
			for k in 2:
				var cu2 := 0.25 + k * 0.5
				var du2 := absf(fposmod(u - cu2 + 0.5, 1.0) - 0.5)
				var s2 := smoothstep(0.1, 0.06, du2) * smoothstep(0.34, 0.38, v) * smoothstep(0.5, 0.46, v)
				c += (accent_a if k == 0 else accent_b) * s2 * 2.2 * strength
			if v > 0.52:
				c *= 0.35
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## Night-city panorama: dark sky, glowing skyline band with coloured light specks.
static func city_sky() -> ImageTexture:
	if _cache.has("city"):
		return _cache["city"]
	var w := 320
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBAH)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var skyline := []
	var cur := 0.0
	for x in w:
		if x % 4 == 0:
			cur = rng.randf_range(0.0, 0.07) + (0.05 if rng.randf() < 0.15 else 0.0)
		skyline.append(cur)
	for y in h:
		var v := float(y) / h
		for x in w:
			var c := Color(0.01, 0.014, 0.035).lerp(Color(0.10, 0.05, 0.13), exp(-pow((v - 0.5) / 0.16, 2.0)))
			c += Color(0.5, 0.22, 0.1) * exp(-pow((v - 0.5) / 0.045, 2.0)) * 0.5
			var top: float = 0.5 - skyline[x]
			if v > top and v < 0.5:
				c = Color(0.012, 0.012, 0.02)
				var hsh := fposmod(sin(float(x / 2) * 12.9898 + float(y / 2) * 78.233) * 43758.5453, 1.0)
				if hsh > 0.72:
					c = Color(1.0, 0.8, 0.45) * (0.5 + hsh)
				if hsh > 0.975:
					c = Color(0.2, 0.9, 1.0) * 2.5 if x % 3 == 0 else Color(1.0, 0.2, 0.6) * 2.5
			if v >= 0.5:
				c = Color(0.02, 0.02, 0.03)
			# a few stars
			if v < 0.4 and fposmod(sin(x * 91.7 + y * 47.3) * 9631.1, 1.0) > 0.9985:
				c += Color(0.6, 0.6, 0.7)
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_cache["city"] = t
	return t


## Gulf night sky: deep blue overhead, warm dusty haze over the desert horizon, stars.
static func desert_sky() -> ImageTexture:
	if _cache.has("desert"):
		return _cache["desert"]
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBAH)
	for y in h:
		var v := float(y) / h
		for x in w:
			var c := Color(0.012, 0.018, 0.05).lerp(Color(0.16, 0.09, 0.12), exp(-pow((v - 0.5) / 0.13, 2.0)))
			c += Color(0.55, 0.3, 0.12) * exp(-pow((v - 0.5) / 0.035, 2.0)) * 0.55
			if v >= 0.5:
				c = Color(0.05, 0.035, 0.03)
			if v < 0.42 and fposmod(sin(x * 91.7 + y * 47.3) * 9631.1, 1.0) > 0.9988:
				c += Color(0.5, 0.5, 0.6) * (1.0 - v * 2.0)
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_cache["desert"] = t
	return t


static func noise_tex(seed_v: int, freq: float, size := 256, as_normal := false, strength := 4.0) -> NoiseTexture2D:
	var key := "n%d_%f_%d_%s" % [seed_v, freq, size, as_normal]
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = size
	t.height = size
	t.seamless = true
	t.as_normal_map = as_normal
	t.bump_strength = strength
	t.generate_mipmaps = true
	_cache[key] = t
	return t


## Soft additive glow sprite material (light pools, flares).
static func glow_mat(color: Color, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = UI.radial_tex(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


static func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


static func solid(color: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func cyl(parent: Node, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## Photographic workshop sky from the generated 360 panorama (LDR jpg).
## Bright light tubes are boosted in the shader so they read as HDR light
## sources in reflections and ambient light.
static func photo_sky(boost := 14.0, gain := 1.0) -> Sky:
	var key := "photo_sky%f%f" % [boost, gain]
	if _cache.has(key):
		return _cache[key]
	var sh := Shader.new()
	sh.code = """
shader_type sky;
uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float boost = 14.0;
uniform float gain = 1.0;
void sky() {
	vec2 uv = vec2(atan(EYEDIR.x, -EYEDIR.z) / 6.2831853 + 0.5, acos(clamp(EYEDIR.y, -1.0, 1.0)) / 3.1415927);
	vec3 c = texture(pano, uv).rgb;
	float l = dot(c, vec3(0.3333));
	float b = clamp((l - 0.45) / 0.4, 0.0, 1.0);
	c *= 1.0 + b * b * boost;
	if (EYEDIR.y < -0.05) { c *= 0.8; }
	COLOR = c * gain;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("pano", load("res://textures/garage_pano.jpg"))
	m.set_shader_parameter("boost", boost)
	m.set_shader_parameter("gain", gain)
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	_cache[key] = sky
	return sky
