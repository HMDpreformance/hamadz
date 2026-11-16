class_name StreetSurface
## Wet night street: photo-scanned asphalt / paving with normal maps, worn
## paint, puddles, sodium light pools computed from the lamp grid (no light
## limit), and a planar mirror reflection of the city in the wet surface.

static var _shader: Shader
static var _road: ShaderMaterial
static var _walk: ShaderMaterial


static func shader() -> Shader:
	if _shader:
		return _shader
	_shader = Shader.new()
	_shader.code = """
shader_type spatial;
uniform float pitch = 82.0;
uniform float half_road = 9.0;
uniform vec2 offset = vec2(0.0);
uniform vec2 extent = vec2(205.0);
uniform float mode = 0.0;                 // 0 = road plane, 1 = sidewalk slab
uniform vec3 outside : source_color = vec3(0.2, 0.15, 0.1);
uniform sampler2D tex_d : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_n : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_arm : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D refl_tex : source_color, filter_linear, repeat_disable;
uniform float refl_on = 0.0;
uniform float tile = 4.0;
uniform float wet = 1.0;
uniform float rainf = 1.0;      // 1 = rain is falling (rings on the puddles)
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.7, 0.4);
uniform float lamp_power = 5.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

float lane(float d, float along) {
	float m = 0.0;
	m += smoothstep(0.09, 0.06, abs(d - 3.75)) * step(fract(along / 9.0), 0.38);
	m += smoothstep(0.1, 0.07, abs(d - 7.7));
	return m;
}
// one street lamp: diffuse pool + wet specular streak
vec3 lamp(vec3 lp, vec3 p, vec3 n, vec3 v, vec3 alb, float rough) {
	vec3 l = lp - p;
	float d2 = dot(l, l);
	l *= inversesqrt(d2);
	float att = 1.0 / (1.0 + d2 * 0.012);
	att *= att;
	float ndl = max(dot(n, l), 0.0);
	vec3 h = normalize(l + v);
	float a = max(rough * rough, 0.002);
	float ndh = max(dot(n, h), 0.0);
	float dd = ndh * ndh * (a * a - 1.0) + 1.0;
	float spec = (a * a) / (3.14159 * dd * dd);
	float fr = 0.04 + 0.96 * pow(1.0 - max(dot(h, v), 0.0), 5.0);
	return lamp_color * lamp_power * att * (alb * ndl + vec3(min(spec, 60.0) * fr * ndl * 0.25));
}
void fragment() {
	vec2 p = wp.xz;
	vec2 q = mod(p - offset + pitch * 0.5, pitch) - pitch * 0.5;
	vec2 d = abs(q);
	bool in_grid = abs(p.x) < extent.x + half_road && abs(p.y) < extent.y + half_road;
	bool on_x = d.x < half_road && in_grid;
	bool on_z = d.y < half_road && in_grid;
	float white = 0.0;
	float yellow = 0.0;
	if (mode < 0.5) {
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
	}
	float n1 = texture(noise_tex, p * 0.035).r;
	float n2 = texture(noise_tex, p * 0.011 + 0.37).r;
	vec2 uv = p / tile;
	vec3 alb = texture(tex_d, uv).rgb;
	vec3 macro = texture(tex_d, uv * 0.23 + 0.31).rgb;
	alb = alb * (0.65 + 1.1 * macro.g) * tint;
	vec3 arm = texture(tex_arm, uv).rgb;
	vec3 nm = texture(tex_n, uv).rgb;
	float rough = arm.g;
	// worn paint
	float wear = smoothstep(0.15, 0.75, n1 * 0.6 + texture(noise_tex, p * 0.9).r * 0.6);
	alb = mix(alb, vec3(0.62, 0.62, 0.58), clamp(white, 0.0, 1.0) * wear);
	alb = mix(alb, vec3(0.72, 0.5, 0.04), clamp(yellow, 0.0, 1.0) * wear);
	rough = mix(rough, 0.45, clamp(white + yellow, 0.0, 1.0) * wear);
	// rain: thin film everywhere, standing water in the low spots and along the kerb
	float gutter = (on_x && !on_z) ? smoothstep(6.6, 8.9, d.x) : ((on_z && !on_x) ? smoothstep(6.6, 8.9, d.y) : 0.0);
	float puddle = smoothstep(0.5, 0.66, n2 + gutter * 0.22 - arm.r * 0.08) * wet;
	if (mode > 0.5) puddle *= 0.55;
	if (!in_grid && mode < 0.5) {
		alb = outside * (0.6 + 0.8 * texture(noise_tex, p * 0.6).r) * (0.8 + 0.4 * n1);
		puddle = 0.0;
		rough = 0.95;
	}
	float film = wet * (in_grid || mode > 0.5 ? 1.0 : 0.0);
	alb *= mix(1.0, 0.5, film) * (1.0 - puddle * 0.35);
	rough = mix(rough, rough * 0.42, film);
	rough = mix(rough, 0.03, puddle);
	// rain rings on standing water
	vec2 rc = floor(p * 2.2);
	float rh = fract(sin(dot(rc, vec2(127.1, 311.7))) * 43758.5453);
	float rt = fract(TIME * 1.3 + rh * 7.0);
	float ring = smoothstep(0.08, 0.0, abs(length(fract(p * 2.2) - 0.5) - rt * 0.45)) * (1.0 - rt) * step(0.55, rh) * puddle * rainf;
	float ndepth = mix(1.0, 0.12, puddle);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nm, ndepth);
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = alb;
	ROUGHNESS = clamp(rough + ring * 0.2, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.9, film);
	AO = arm.r;

	// ---- lighting that does not depend on Godot's per-mesh light limit
	vec3 nw = normalize(vec3((nm.x - 0.5) * 1.6 * ndepth, 1.0, (nm.y - 0.5) * 1.6 * ndepth));
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 e = vec3(0.0);
	if (in_grid) {
		// lamps stand 25 m and 57 m after every crossing, on alternating sides, heads 6.9 m off the centre line
		vec2 f = mod(p - offset, pitch);            // 0..pitch measured from the road centre lines
		vec3 pw = vec3(p.x, wp.y, p.y);
		float hh = 7.4;
		// nearest north-south road (x line) and nearest east-west road (z line)
		float rx = p.x - q.x;
		float rz = p.y - q.y;
		float bz = p.y - f.y;
		float bx = p.x - f.x;
		if (d.x < half_road + 14.0) {
			e += lamp(vec3(rx - 6.9, hh, bz + 25.0), pw, nw, vw, alb, ROUGHNESS);
			e += lamp(vec3(rx + 6.9, hh, bz + 57.0), pw, nw, vw, alb, ROUGHNESS);
			e += lamp(vec3(rx + 6.9, hh, bz + 57.0 - pitch), pw, nw, vw, alb, ROUGHNESS);
		}
		if (d.y < half_road + 14.0) {
			e += lamp(vec3(bx + 25.0, hh, rz - 6.9), pw, nw, vw, alb, ROUGHNESS);
			e += lamp(vec3(bx + 57.0, hh, rz + 6.9), pw, nw, vw, alb, ROUGHNESS);
			e += lamp(vec3(bx + 57.0 - pitch, hh, rz + 6.9), pw, nw, vw, alb, ROUGHNESS);
		}
	}
	// ---- mirror reflection of the city in the wet surface
	if (refl_on > 0.5) {
		vec2 suv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
		suv += (nm.xy - 0.5) * vec2(0.035, 0.07) * ndepth + vec2(0.0, ring * 0.01);
		// wet asphalt smears reflections downwards: a few taps along the screen vertical
		float sm = mix(0.05, 0.006, puddle);
		vec3 r = vec3(0.0);
		for (int i = 0; i < 4; i++) {
			float o = (float(i) - 1.5) * sm;
			r += texture(refl_tex, clamp(suv + vec2(0.0, o), vec2(0.002), vec2(0.998))).rgb;
		}
		r *= 0.25;
		float fres = pow(1.0 - clamp(dot(nw, vw), 0.0, 1.0), 3.0);
		float k = mix(0.3, 0.85, puddle) * film * (0.25 + 0.75 * fres);
		e += r * k;
	}
	EMISSION = e;
}
"""
	return _shader


static func _make(mode: float, tex: String, tile: float, tint: Color, city: Node) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("tex_d", load(W3D.TEX + tex + "_diff.jpg"))
	m.set_shader_parameter("tex_n", load(W3D.TEX + tex + "_nor.jpg"))
	m.set_shader_parameter("tex_arm", load(W3D.TEX + tex + "_arm.jpg"))
	m.set_shader_parameter("noise_tex", EnvKit.noise_tex(3, 0.03))
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("pitch", City.PITCH)
	m.set_shader_parameter("half_road", City.ROAD * 0.5)
	m.set_shader_parameter("wet", 1.0 if raining else DRY_WET)
	m.set_shader_parameter("rainf", 1.0 if raining else 0.0)
	return m


## Weather. Dry nights are the norm: the street keeps a light sheen (hosed-down,
## night-shoot look) with few puddles; rain brings the full wet road and rings.
const DRY_WET := 0.42
static var raining := false


static func set_rain(on: bool) -> void:
	raining = on
	for m in [_road, _walk]:
		if m:
			m.set_shader_parameter("wet", 1.0 if on else DRY_WET)
			m.set_shader_parameter("rainf", 1.0 if on else 0.0)


static func road(offset: Vector2, extent: Vector2) -> ShaderMaterial:
	_road = _make(0.0, "asphalt_04", 5.0, Color(0.8, 0.8, 0.82), null)
	_road.set_shader_parameter("offset", offset)
	_road.set_shader_parameter("extent", extent)
	return _road


static func walk(offset: Vector2, extent: Vector2) -> ShaderMaterial:
	_walk = _make(1.0, "concrete_pavement", 3.0, Color(0.85, 0.85, 0.87), null)
	_walk.set_shader_parameter("offset", offset)
	_walk.set_shader_parameter("extent", extent)
	return _walk


static func set_reflection(tex: Texture2D) -> void:
	for m in [_road, _walk]:
		if m:
			m.set_shader_parameter("refl_tex", tex)
			m.set_shader_parameter("refl_on", 1.0 if tex != null else 0.0)
