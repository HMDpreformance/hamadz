extends Node
## Graphics presets (autoload "GFX"). Scenes read these flags while building
## and call GFX.apply_environment(env) so presets can change at runtime.

signal changed

const PRESETS := [
	{"name": "PERFORMANCE", "scale": 0.6, "msaa": 0, "glow": false, "shadows": false, "particles": 0.22, "mirror": false, "lights": 4, "fps": 60},
	{"name": "BALANCED", "scale": 0.85, "msaa": 1, "glow": true, "shadows": true, "particles": 0.55, "mirror": true, "lights": 6, "fps": 60},
	{"name": "QUALITY", "scale": 1.0, "msaa": 1, "glow": true, "shadows": true, "particles": 1.0, "mirror": true, "lights": 8, "fps": 60},
]

var index := 1
var p: Dictionary = PRESETS[1]
var is_mobile := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_mobile = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]


func set_preset(i: int) -> void:
	index = clampi(i, 0, PRESETS.size() - 1)
	p = PRESETS[index]
	var vp := get_tree().root
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	# Phones are high-DPI and fragment-bound; render 3D at a lower internal scale
	# than desktop for the same preset, then upscale.
	var scale: float = p.scale
	if is_mobile:
		scale = minf(scale, 0.75) * 0.9
	vp.scaling_3d_scale = scale
	vp.msaa_3d = Viewport.MSAA_2X if p.msaa == 1 and not is_mobile else Viewport.MSAA_DISABLED
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
	# Filmic AgX tone curve: rolls off bright neon cleanly instead of clipping to
	# white. Works on both the mobile and forward+ renderers.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.tonemap_exposure = 0.95
	# Bloom: only genuinely bright sources glow, soft blend so shop windows don't
	# smear into a flare.
	env.glow_enabled = p.glow
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.35
	env.glow_hdr_scale = 1.4
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	# High blur passes are the costly part of bloom; skip them on phones.
	env.set_glow_level(4, 0.0 if is_mobile else 1.0)
	env.set_glow_level(5, 0.0 if is_mobile else 0.6)
	# Screen-space effects: forward+ (desktop/Steam) only -- silently ignored by
	# the mobile renderer, so the same code path covers both tiers.
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.ssil_enabled = true
	env.ssil_intensity = 1.0
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	env.ssao_radius = 2.5
	if fog_density > 0.0:
		env.fog_enabled = true
		env.fog_light_color = fog
		env.fog_density = fog_density
		env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	return env
