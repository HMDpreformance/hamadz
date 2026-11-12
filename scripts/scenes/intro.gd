extends Node3D
## Startup sequence: studio logo -> in-engine night cinematic -> title -> "tap to start".
## Any tap skips ahead to the title; a tap on the title goes to the main menu.

enum Phase { LOGO, CINE, TITLE }

const LOGO_TIME := 4.6

var phase := Phase.LOGO
var t := 0.0
var city: City
var cam: Camera3D
var env: Environment
var actors: Array = []          # [{car: CarVisual, vel: Vector3, fx: flames}]
var _shot := -1
var _shot_t := 0.0
var _ui: Control
var _logo: Control
var _bars: Array = []
var _post: PostFX
var _fade: ColorRect
var _title_root: Control
var _title: Label
var _tap: Label
var _flash: ColorRect
var _title_t := 0.0
var _leaving := false
var _world_ready := false


func _ready() -> void:
	env = GFX.make_environment(Color(0.3, 0.33, 0.5), 0.6, Color(0.08, 0.05, 0.12), 0.007, EnvKit.city_sky())
	env.background_mode = Environment.BG_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.far = 600.0
	cam.fov = 45.0
	add_child(cam)
	_build_ui()
	Audio.music_state("", 0.2)
	# draw the logo first, then build the 3D set behind it
	await get_tree().process_frame
	await get_tree().process_frame
	city = City.new()
	city.blocks = 3
	city.seed_v = 52
	city.with_colliders = false
	add_child(city)
	city.build()
	cam.position = Vector3(city.road(1), 1.0, 60)
	await get_tree().process_frame
	_make_actors()
	city.focus = actors[0].car
	_world_ready = true
	Audio.sfx("logo_sting", 0.0)


func _make_actors() -> void:
	var defs := [["tuner", {"paint": 1, "finish": 1, "spoiler": 2, "front": 1, "rims": 1, "rim_color": 5, "glow": 1, "suspension": 2, "skirts": 1}],
		["muscle", {"paint": 11, "finish": 0, "hood": 1, "rims": 3, "glow": 5, "suspension": 1, "exhaust": 2}],
		["euro", {"paint": 6, "finish": 1, "spoiler": 3, "front": 2, "rims": 2, "rim_color": 2, "glow": 3, "suspension": 2, "rear": 2}]]
	for d in defs:
		var cfg := CarDB.default_config(d[0])
		for k in d[1]:
			cfg[k] = d[1][k]
		var c := CarVisual.new()
		add_child(c)
		c.setup(d[0], cfg)
		var l := SpotLight3D.new()
		l.position = Vector3(0, 0.7, -2.0)
		l.rotation_degrees = Vector3(-6, 0, 0)
		l.spot_range = 40.0
		l.spot_angle = 32.0
		l.light_energy = 5.0
		c.add_child(l)
		actors.append({"car": c, "vel": Vector3.ZERO})


func _place(i: int, pos: Vector3, yaw: float, speed: float) -> void:
	var a: Dictionary = actors[i]
	a.car.position = pos
	a.car.rotation.y = yaw
	a.vel = Vector3(-sin(yaw), 0, -cos(yaw)) * speed


# ====================================================================== shots
func _begin_shot(i: int) -> void:
	_shot = i
	_shot_t = 0.0
	var x := city.road(1)        # the avenue the cars race down (north = -z)
	match i:
		0:  # headlights approach and blast past a road-level camera
			_place(0, Vector3(x + 2.0, 0, 150), 0.0, 52.0)
			_place(1, Vector3(x + 5.8, 0, 162), 0.0, 53.0)
			_place(2, Vector3(x - 2.0, 0, 176), 0.0, 54.0)
		1:  # side tracking shot on the tuner
			_place(0, Vector3(x + 2.0, 0, 110), 0.0, 46.0)
			_place(1, Vector3(x + 5.8, 0, 121), 0.0, 47.5)
			_place(2, Vector3(x - 2.0, 0, 128), 0.0, 47.0)
		2:  # chase from behind the muscle car
			_place(1, Vector3(x + 2.0, 0, 90), 0.0, 50.0)
			_place(0, Vector3(x + 5.8, 0, 78), 0.0, 49.0)
			_place(2, Vector3(x - 2.0, 0, 99), 0.0, 51.5)
		3:  # hero: the euro car slides to a stop under the neon
			var hz := city.road(2)
			_place(2, Vector3(x, 0, hz), 0.25, 0.0)
			_place(0, Vector3(x - 3.6, 0, hz + 2.5), 0.12, 0.0)
			_place(1, Vector3(x + 3.8, 0, hz + 3.5), -0.2, 0.0)


func _shot_len(i: int) -> float:
	return [3.4, 3.2, 3.2, 99.0][i]


func _update_shot(dt: float) -> void:
	_shot_t += dt
	for a in actors:
		a.car.position += a.vel * dt
		a.car.spin_wheels(a.vel.length() * dt / a.car.wheel_radius)
	var x := city.road(1)
	var blur := 0.0
	match _shot:
		0:
			cam.position = Vector3(x + 0.2, 0.28, 30.0 - _shot_t * 1.5)
			cam.look_at(actors[0].car.position + Vector3(0, 0.6, 0), Vector3.UP)
			cam.fov = 58.0
			blur = clampf(1.0 - absf(actors[0].car.position.z - cam.position.z) / 40.0, 0.0, 1.0) * 0.8
		1:
			var cp: Vector3 = actors[0].car.position
			cam.position = cp + Vector3(5.5 - _shot_t * 0.5, 0.75, -1.5 + _shot_t * 1.2)
			cam.look_at(cp + Vector3(0, 0.55, -0.4), Vector3.UP)
			cam.fov = 50.0
			blur = 0.75
		2:
			var mp: Vector3 = actors[1].car.position
			cam.position = mp + Vector3(-1.2 + _shot_t * 0.5, 1.15 + _shot_t * 0.3, 6.5 - _shot_t * 0.6)
			cam.look_at(mp + Vector3(0, 0.6, -6.0), Vector3.UP)
			cam.fov = 72.0
			blur = 0.9
		3:
			var k := clampf(_shot_t / 14.0, 0.0, 1.0)
			var ang := -0.9 + _shot_t * 0.085
			var r := 9.5 - 2.5 * k
			var hc := Vector3(x, 0, city.road(2))
			cam.position = hc + Vector3(sin(ang) * r, 0.9 + 0.9 * k, -cos(ang) * r)
			cam.look_at(hc + Vector3(0, 0.75, 0.5), Vector3.UP)
			cam.fov = 40.0
	_post.use_blur = GFX.index > 0
	_post.amount = lerpf(_post.amount, blur, 0.2)
	# cut with a short dip to black
	var edge := minf(_shot_t, _shot_len(_shot) - _shot_t)
	_fade.color.a = clampf(1.0 - edge / 0.22, 0.0, 1.0) if _shot < 3 else clampf(1.0 - _shot_t / 0.3, 0.0, 1.0)
	if _shot < 3 and _shot_t >= _shot_len(_shot):
		_begin_shot(_shot + 1)
		if _shot == 3:
			_enter_title()


# ====================================================================== flow
func _process(dt: float) -> void:
	if not _world_ready:
		return
	dt = minf(dt, 0.05)
	t += dt
	match phase:
		Phase.LOGO:
			if t >= LOGO_TIME:
				_enter_cine()
		Phase.CINE, Phase.TITLE:
			_update_shot(dt)
			if phase == Phase.TITLE:
				_title_t += dt
				_tap.modulate.a = 0.0 if _title_t < 2.2 else 0.55 + 0.45 * sin(_title_t * 4.0)
				if _title.material:
					(_title.material as ShaderMaterial).set_shader_parameter("shine", fmod(_title_t * 700.0, 3600.0) - 500.0)


func _enter_cine() -> void:
	phase = Phase.CINE
	_logo.queue_free()
	_fade.color.a = 1.0
	for b in _bars:
		b.visible = true
	Audio.music_state("intro", 0.3)
	_begin_shot(0)


func _enter_title() -> void:
	phase = Phase.TITLE
	_title_t = 0.0
	_title_root.visible = true
	Audio.sfx("title_slam", 2.0)
	_flash.color.a = 0.9
	create_tween().tween_property(_flash, "color:a", 0.0, 0.7)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(2.6, 2.6)
	_title.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_title, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(_title, "modulate:a", 1.0, 0.2)
	var sub: Control = _title_root.get_node("Sub")
	var line: Control = _title_root.get_node("Line")
	sub.modulate.a = 0.0
	line.scale.x = 0.0
	var tw2 := create_tween()
	tw2.tween_interval(0.6)
	tw2.tween_property(line, "scale:x", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(sub, "modulate:a", 1.0, 0.5)


func _input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventJoypadButton and event.pressed)
	if not tap or _leaving or not _world_ready:
		return
	match phase:
		Phase.LOGO:
			if t > 0.6:
				_enter_cine()
				_skip_to_title()
		Phase.CINE:
			_skip_to_title()
		Phase.TITLE:
			if _title_t > 0.8:
				_leaving = true
				Audio.sfx("ui_select")
				Nav.goto("menu", {}, "AFTER HOURS")


func _skip_to_title() -> void:
	_begin_shot(3)
	_post.amount = 0.0
	_enter_title()


# ====================================================================== UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_post = PostFX.new()
	layer.add_child(_post)
	_ui = UI.full(Control.new())
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	_fade = UI.full(UI.rect(Color(0, 0, 0, 1))) as ColorRect
	_ui.add_child(_fade)
	_ui.add_child(UI.crt_overlay())
	# cinematic letterbox
	for top in [true, false]:
		var b := UI.rect(Color.BLACK)
		b.anchor_right = 1.0
		b.custom_minimum_size = Vector2(0, 74)
		if top:
			b.offset_bottom = 74
		else:
			b.anchor_top = 1.0
			b.anchor_bottom = 1.0
			b.offset_top = -74
			b.grow_vertical = Control.GROW_DIRECTION_BEGIN
		b.visible = false
		_ui.add_child(b)
		_bars.append(b)

	# title block
	_title_root = UI.full(Control.new())
	_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.visible = false
	_ui.add_child(_title_root)
	var glow := TextureRect.new()
	glow.texture = UI.radial_tex(Color(0, 0, 0, 0.7), Color(0, 0, 0, 0))
	UI.place(glow, Vector2(0.5, 0.5), Vector2(-640, -330), Vector2(1280, 520))
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(glow)
	_title = UI.label("AFTER HOURS", 136, Color.WHITE, true)
	UI.chrome(_title, Color(1, 1, 1), Color(1.0, 0.8, 0.14), Color(0.9, 0.22, 0.0), 164.0)
	UI.outline(_title, 18, Color(0, 0, 0, 0.92))
	UI.place(_title, Vector2(0.5, 0.5), Vector2(-620, -230), Vector2(1240, 170))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_root.add_child(_title)
	var line := UI.rect(UI.AMBER)
	line.name = "Line"
	UI.place(line, Vector2(0.5, 0.5), Vector2(-360, -52), Vector2(720, 5))
	line.pivot_offset = Vector2(360, 2)
	_title_root.add_child(line)
	var sub := UI.label("S T R E E T    S Y N D I C A T E", 40, UI.CYAN, true)
	sub.name = "Sub"
	UI.outline(sub, 10)
	UI.place(sub, Vector2(0.5, 0.5), Vector2(-500, -40), Vector2(1000, 56))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_root.add_child(sub)
	_tap = UI.label("TAP TO START", 34, Color.WHITE, true)
	UI.outline(_tap, 10)
	UI.place(_tap, Vector2(0.5, 1), Vector2(-300, -150), Vector2(600, 48))
	_tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tap.modulate.a = 0.0
	_title_root.add_child(_tap)
	var copy := UI.label("DEMO BUILD  •  AN ORIGINAL REDLINE FOUNDRY PRODUCTION", 14, Color(1, 1, 1, 0.5))
	UI.place(copy, Vector2(0.5, 1), Vector2(-400, -62), Vector2(800, 20))
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_root.add_child(copy)
	_flash = UI.full(UI.rect(Color(1, 1, 1, 0))) as ColorRect
	_ui.add_child(_flash)

	_logo = _StudioLogo.new()
	UI.full(_logo)
	_ui.add_child(_logo)


## Animated studio ident: a tach needle sweeps to the redline, then the name slams in.
class _StudioLogo extends Control:
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		if get_parent().get_parent().get_parent()._world_ready:
			t += minf(d, 0.05)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		var c := size * 0.5 + Vector2(0, -40)
		var fade_out := clampf((4.6 - t) / 0.5, 0.0, 1.0)
		var r := 120.0
		var a0 := PI * 0.75
		var a1 := PI * 2.25
		# gauge sweep 0.3 -> 1.5s
		var sweep := clampf((t - 0.3) / 1.2, 0.0, 1.0)
		sweep = 1.0 - pow(1.0 - sweep, 3.0)
		var hit := t > 1.75
		var col := Color(1.0, 0.69, 0.0, fade_out)
		var red := Color(1.0, 0.2, 0.12, fade_out)
		for i in 9:
			var a := lerpf(a0, a1, i / 8.0)
			if (i / 8.0) <= sweep + 0.01:
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * (r - 18), c + d * r, red if i >= 7 else Color(1, 1, 1, fade_out), 4.0, true)
		draw_arc(c, r + 10, a0, lerpf(a0, a1, sweep), 48, col, 6.0, true)
		if sweep > 0.78:
			draw_arc(c, r + 10, lerpf(a0, a1, 0.78), lerpf(a0, a1, sweep), 16, red, 6.0, true)
		var na := lerpf(a0, a1, sweep)
		if hit:
			na += sin(t * 60.0) * 0.02 * clampf(2.6 - t, 0.0, 1.0)
		var nd := Vector2(cos(na), sin(na))
		draw_line(c - nd * 16, c + nd * (r - 10), red, 5.0, true)
		draw_circle(c, 10, Color(1, 1, 1, fade_out))
		# name slam at 1.75s
		if hit:
			var k := clampf((t - 1.75) / 0.25, 0.0, 1.0)
			var sc := lerpf(1.8, 1.0, 1.0 - pow(1.0 - k, 3.0))
			var f := UI.title_font()
			var fs := int(64 * sc)
			var name_s := "REDLINE FOUNDRY"
			var w := f.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := Vector2(size.x * 0.5 - w * 0.5, c.y + r + 96)
			draw_string(f, pos + Vector2(4, 4), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.25, 0.1, 0.6 * k * fade_out))
			draw_string(f, pos, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, k * fade_out))
			var lw := 520.0 * clampf((t - 2.0) / 0.4, 0.0, 1.0)
			draw_rect(Rect2(size.x * 0.5 - lw * 0.5, c.y + r + 114, lw, 4), col)
			if t > 2.3:
				var k2 := clampf((t - 2.3) / 0.4, 0.0, 1.0)
				var bf := UI.body_font(true)
				var s2 := "G A M E S    P R E S E N T S"
				var w2 := bf.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
				draw_string(bf, Vector2(size.x * 0.5 - w2 * 0.5, c.y + r + 150), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.7, 0.75, 0.82, k2 * fade_out))
			# impact flash
			var fl := clampf(1.0 - (t - 1.75) / 0.35, 0.0, 1.0)
			if fl > 0.0:
				draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, fl * 0.6))


func dev_skip() -> void:
	if phase == Phase.LOGO:
		_enter_cine()
	_skip_to_title()
