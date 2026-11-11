class_name PostFX
extends ColorRect
## Full-screen speed effect: radial motion blur (samples the screen) plus
## streaking speed lines. `amount` 0..1 drives both; hidden when 0.

var amount := 0.0: set = set_amount
var use_blur := true


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
uniform float blur = 1.0;
uniform vec3 tint : source_color = vec3(0.7, 0.85, 1.0);
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 c = SCREEN_UV - vec2(0.5, 0.55);
	float r = length(c * vec2(1.0, 0.75));
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (blur > 0.5) {
		float k = amount * 0.07 * smoothstep(0.08, 0.6, r);
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			acc += texture(screen_tex, SCREEN_UV - c * k * float(i) / 5.0).rgb;
		}
		col = acc / 6.0;
		a = smoothstep(0.05, 0.3, r);
	}
	float ang = atan(c.y, c.x);
	float seg = floor(ang * 38.0);
	float h = hash(seg);
	float streak = step(0.72, h) * smoothstep(0.25 + 0.3 * hash(seg + 7.0), 0.75, r);
	streak *= 0.5 + 0.5 * sin(TIME * (18.0 + 20.0 * h) + h * 40.0 - r * 30.0);
	float s = clamp(streak, 0.0, 1.0) * amount * 0.35;
	if (blur > 0.5) {
		COLOR = vec4(col + tint * s, a);
	} else {
		COLOR = vec4(tint, s);
	}
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	material = m
	visible = false


func set_amount(v: float) -> void:
	amount = clampf(v, 0.0, 1.0)
	visible = amount > 0.02
	if visible:
		material.set_shader_parameter("amount", amount)
		material.set_shader_parameter("blur", 1.0 if use_blur else 0.0)
