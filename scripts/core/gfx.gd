extends Node
## Graphics presets (autoload "GFX"). Scenes read these flags while building
## and call GFX.apply_environment(env) so presets can change at runtime.

signal changed

const PRESETS := [
	{"name": "PERFORMANCE", "scale": 0.75, "msaa": 0, "glow": false, "shadows": false, "particles": 0.4, "mirror": false, "lights": 4, "fps": 60},
	{"name": "BALANCED", "scale": 1.0, "msaa": 1, "glow": true, "shadows": true, "particles": 0.7, "mirror": true, "lights": 6, "fps": 60},
	{"name": "QUALITY", "scale": 1.0, "msaa": 1, "glow": true, "shadows": true, "particles": 1.0, "mirror": true, "lights": 8, "fps": 60},
]

var index := 1
var p: Dictionary = PRESETS[1]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_preset(i: int) -> void:
	index = clampi(i, 0, PRESETS.size() - 1)
	p = PRESETS[index]
	var vp := get_tree().root
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = p.scale
	vp.msaa_3d = Viewport.MSAA_2X if p.msaa == 1 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if index > 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	Engine.max_fps = p.fps
	changed.emit()


func apply_environment(env: Environment) -> void:
	if env == null:
		return
	env.glow_enabled = p.glow


## Standard night-time environment shared by all 3D scenes.
func make_environment(ambient: Color, ambient_energy: float, fog: Color, fog_density: float, sky_tex: Texture2D = null) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.01, 0.02)
	if sky_tex:
		var sky := Sky.new()
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = sky_tex
		sky.sky_material = pm
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		sky.process_mode = Sky.PROCESS_MODE_REALTIME if false else Sky.PROCESS_MODE_QUALITY
		env.sky = sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = p.glow
	env.glow_intensity = 0.55
	env.glow_strength = 0.95
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 1.0)
	env.set_glow_level(5, 0.6)
	if fog_density > 0.0:
		env.fog_enabled = true
		env.fog_light_color = fog
		env.fog_density = fog_density
		env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	return env
