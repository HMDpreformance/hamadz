class_name PhotoStage
extends Node3D
## The photographic workshop shared by the Car Lot and the Garage.
## A generated photo (textures/showroom_backdrop.jpg) is drawn behind the 3D
## view; a floor plane re-projects that photo's own floor in screen space so
## the car sits on it, gets a soft contact shadow and a wet-concrete
## reflection (a y-flipped copy of the car under `mirror_root`). Lighting and
## reflections come from the matching 360 panorama (EnvKit.photo_sky).

const BACKDROP := "res://textures/showroom_backdrop.jpg"
const CAM_POS := Vector3(0.0, 1.55, 10.2)     # eye point the photo was matched to
const CAM_PITCH := -6.5
const CAM_FOV := 34.0

var env: Environment
var floor_mat: ShaderMaterial
var mirror_root: Node3D
var bg_tex: Texture2D
var tracked: Node3D             # CarVisual whose footprint gets the contact shadow
var key_light: SpotLight3D


func build() -> void:
	bg_tex = load(BACKDROP)
	var bl := CanvasLayer.new()
	bl.layer = -10
	add_child(bl)
	var bg := TextureRect.new()
	bg.texture = bg_tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.add_child(bg)

	env = GFX.make_environment(Color(0.3, 0.32, 0.36), 0.5, Color.BLACK, 0.0)
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.sky = EnvKit.photo_sky()
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 5.0
	env.glow_intensity = 0.35
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var fl := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	fl.mesh = plane
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D backdrop : source_color, filter_linear;
uniform vec4 map = vec4(1.0, 1.0, 0.0, 0.0);
uniform float reflect = 0.8;
uniform vec4 car = vec4(0.0, 1.0, 2.4, 0.0);   // yaw, half width, half length
uniform vec2 car_pos = vec2(0.0);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = SCREEN_UV * map.xy + map.zw;
	vec3 col = texture(backdrop, uv).rgb;
	float c = cos(car.x), s = sin(car.x);
	vec2 d = wp.xz - car_pos;
	vec2 lp = vec2(c * d.x - s * d.y, s * d.x + c * d.y);
	vec2 q = abs(lp) / (car.yz + vec2(0.25, 0.35));
	float e = length(max(q - vec2(0.55), 0.0)) / 0.45;
	float shadow = 1.0 - smoothstep(0.0, 1.0, e);
	vec2 q2 = abs(lp) / (car.yz + vec2(0.04, 0.0));
	float core = 1.0 - smoothstep(0.75, 1.0, max(q2.x, q2.y));
	col *= 1.0 - shadow * 0.55 - core * 0.3;
	ALBEDO = col;
	float fade = smoothstep(0.5, 6.0, length(d));
	ALPHA = clamp(1.0 - reflect * (1.0 - fade * 0.8) * (1.0 - core * 0.6), 0.0, 1.0);
}
"""
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = sh
	floor_mat.set_shader_parameter("backdrop", bg_tex)
	floor_mat.set_shader_parameter("reflect", 0.8 if GFX.p.mirror else 0.0)
	floor_mat.render_priority = -2
	fl.material_override = floor_mat
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fl)

	mirror_root = Node3D.new()
	mirror_root.scale = Vector3(1, -1, 1)
	add_child(mirror_root)

	# lighting that matches the photo: warm overhead tubes, cyan neon behind
	key_light = SpotLight3D.new()
	key_light.position = Vector3(1.2, 4.6, 3.2)
	key_light.look_at_from_position(key_light.position, Vector3(0, 0.4, 0))
	key_light.spot_range = 12.0
	key_light.spot_angle = 42.0
	key_light.light_energy = 5.0
	key_light.light_color = Color(1.0, 0.93, 0.82)
	key_light.shadow_enabled = GFX.p.shadows
	add_child(key_light)
	for d in [[Vector3(-1.5, 4.2, -0.5), Color(1.0, 0.86, 0.66), 2.2, 9.0],
			[Vector3(0.6, 2.4, -4.5), Color(0.2, 0.85, 1.0), 3.0, 9.0],
			[Vector3(-4.5, 1.2, 4.0), Color(0.75, 0.82, 1.0), 0.9, 10.0]]:
		var o := OmniLight3D.new()
		o.position = d[0]
		o.light_color = d[1]
		o.light_energy = d[2]
		o.omni_range = d[3]
		add_child(o)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	## Maps screen UV -> backdrop UV exactly like STRETCH_KEEP_ASPECT_COVERED.
	var vp := get_viewport().get_visible_rect().size
	var isz := Vector2(bg_tex.get_width(), bg_tex.get_height())
	var s := maxf(vp.x / isz.x, vp.y / isz.y)
	var disp := isz * s
	var off := (vp - disp) * 0.5
	floor_mat.set_shader_parameter("map", Vector4(vp.x / disp.x, vp.y / disp.y, -off.x / disp.x, -off.y / disp.y))


func _process(_d: float) -> void:
	if tracked and tracked.is_inside_tree() and tracked.has_method("half_width"):
		var gp := tracked.global_position
		floor_mat.set_shader_parameter("car", Vector4(tracked.global_rotation.y, tracked.half_width(), tracked.length() * 0.5, 0.0))
		floor_mat.set_shader_parameter("car_pos", Vector2(gp.x, gp.z))
