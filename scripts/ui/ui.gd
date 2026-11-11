class_name UI
## UI toolkit: fonts, palette and factory helpers shared by every screen.

const AMBER := Color(1.0, 0.69, 0.0)
const CYAN := Color(0.1, 0.89, 1.0)
const MAGENTA := Color(1.0, 0.16, 0.55)
const GREEN := Color(0.35, 1.0, 0.35)
const RED := Color(1.0, 0.25, 0.2)
const INK := Color(0.03, 0.035, 0.05)
const PANEL := Color(0.04, 0.05, 0.08, 0.86)
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.55, 0.6, 0.68)

static var _title: Font
static var _title_i: Font
static var _body: Font
static var _body_b: Font
static var _chrome_shader: Shader
static var _tex := {}


static func title_font(italic := true) -> Font:
	if _title == null:
		_title = load("res://fonts/russoone_RussoOne-Regular.ttf")
		var fv := FontVariation.new()
		fv.base_font = _title
		fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
		fv.spacing_glyph = 1
		_title_i = fv
	return _title_i if italic else _title


static func body_font(bold := false) -> Font:
	if _body == null:
		_body = load("res://fonts/rajdhani_Rajdhani-SemiBold.ttf")
		_body_b = load("res://fonts/rajdhani_Rajdhani-Bold.ttf")
	return _body_b if bold else _body


static func label(text: String, size := 22, color := TEXT, title := false, italic := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font(italic) if title else body_font(true))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func outline(l: Label, size := 6, color := Color(0, 0, 0, 0.85)) -> Label:
	l.add_theme_constant_override("outline_size", size)
	l.add_theme_color_override("font_outline_color", color)
	return l


static func shadow(l: Label, off := Vector2(2, 3), color := Color(0, 0, 0, 0.7)) -> Label:
	l.add_theme_color_override("font_shadow_color", color)
	l.add_theme_constant_override("shadow_offset_x", int(off.x))
	l.add_theme_constant_override("shadow_offset_y", int(off.y))
	return l


## Vertical chrome gradient for big title text (period-correct "polished metal" look).
static func chrome(l: CanvasItem, top := Color(1, 1, 1), mid := Color(1.0, 0.75, 0.1), bottom := Color(0.75, 0.2, 0.0), height := 100.0) -> void:
	if _chrome_shader == null:
		_chrome_shader = Shader.new()
		_chrome_shader.code = """
shader_type canvas_item;
uniform vec4 top : source_color;
uniform vec4 mid : source_color;
uniform vec4 bottom : source_color;
uniform float height = 100.0;
uniform float shine = 0.0;
varying vec2 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float t = clamp(lp.y / height, 0.0, 1.0);
	vec3 c = t < 0.48 ? mix(top.rgb, mid.rgb, t / 0.48) : mix(bottom.rgb * 0.55, bottom.rgb + mid.rgb * 0.35, (t - 0.48) / 0.52);
	float band = smoothstep(0.46, 0.48, t) * (1.0 - smoothstep(0.48, 0.52, t));
	c = mix(c, vec3(1.0), band * 0.6);
	float sweep = 1.0 - smoothstep(0.0, 60.0, abs(lp.x + lp.y * 0.4 - shine));
	c += vec3(sweep) * 0.8;
	float is_fill = step(1.5, COLOR.r + COLOR.g + COLOR.b);
	COLOR.rgb = mix(COLOR.rgb, c, is_fill);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _chrome_shader
	m.set_shader_parameter("top", top)
	m.set_shader_parameter("mid", mid)
	m.set_shader_parameter("bottom", bottom)
	m.set_shader_parameter("height", height)
	m.set_shader_parameter("shine", -2000.0)
	l.material = m


static func flat(color: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 0, skew := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.skew = Vector2(skew, 0)
	s.anti_aliasing = true
	return s


static func panel(color := PANEL, border := Color(1, 1, 1, 0.08), skew := 0.0) -> Panel:
	var pn := Panel.new()
	pn.add_theme_stylebox_override("panel", flat(color, border, 1, 2, skew))
	pn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pn


static func rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func place(c: Control, anchor: Vector2, pos: Vector2, size: Vector2) -> Control:
	## Anchors a control to a fractional point of its parent with a pixel offset.
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + size.x
	c.offset_bottom = pos.y + size.y
	return c


static func gradient_tex(colors: Array, offsets: Array, vertical := true, size := 64) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	return t


static func radial_tex(inner: Color, outer: Color, size := 128) -> GradientTexture2D:
	var key := "rad%s%s%d" % [inner, outer, size]
	if _tex.has(key):
		return _tex[key]
	var g := Gradient.new()
	g.colors = PackedColorArray([inner, Color(inner.r, inner.g, inner.b, inner.a * 0.35), outer])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_tex[key] = t
	return t


## Full-screen overlay: vignette + faint scanlines + film grain for the PS2-era CRT feel.
static func crt_overlay() -> ColorRect:
	var r := ColorRect.new()
	full(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float vignette = 0.5;
uniform float scan = 0.03;
uniform float grain = 0.035;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV - 0.5;
	float v = smoothstep(0.35, 0.95, length(uv * vec2(1.0, 1.25)));
	float s = sin(FRAGCOORD.y * 3.14159 * 0.5) * 0.5 + 0.5;
	float g = hash(FRAGCOORD.xy + fract(TIME) * 100.0) - 0.5;
	float a = v * vignette + s * scan;
	COLOR = vec4(vec3(max(g, 0.0) * grain * 4.0), clamp(a + abs(min(g, 0.0)) * grain, 0.0, 1.0));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	return r


static func pop(c: Control, delay := 0.0, from := Vector2(-60, 0), time := 0.35) -> void:
	## Slide + fade a control into place.
	var target := c.position
	c.position = target + from
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "position", target, time).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, time * 0.8).set_delay(delay)
