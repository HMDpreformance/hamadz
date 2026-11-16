extends Node3D
## Main menu: the player's car parked under neon at a city intersection,
## cinematic cameras cycling behind an animated menu.

const ITEMS := [
	["HIT THE STREETS", "streets"],
	["STORY MODE", "career"],
	["CAR LOT", "lot"],
	["GARAGE", "garage"],
	["OPTIONS", "options"],
	["CREDITS", "credits"],
	["EXIT", "exit"],
]
const SOON := {
	"career": ["CAREER MODE", "Rise through the Syndicate. Take on crew leaders across four districts, win their pink slips and unlock sponsored parts.", ["12 story races across 4 districts", "Rival crews and boss battles", "Pink-slip races and sponsor unlocks"]],
	"arcade": ["ARCADE MODE", "Jump straight into circuit, sprint and drift events against seven rivals, with any car you own.", ["Circuit, Sprint and Drift events", "7 AI rivals with rubber-band tuning", "Split-screen and ghost replays"]],
}
const CREDITS := """HMDNIGHT CLUB
Vertical Slice Demo

GAME DESIGN  •  PROGRAMMING  •  VEHICLE MODELLING
Redline Foundry

VEHICLES
Kaido RS-7, Brawler 427 and Verano GT are original designs,
generated procedurally at runtime.

SOUNDTRACK AND SOUND DESIGN
All music and sound effects were synthesized from scratch
for this project (see tools/gen_audio.py).

TYPEFACES
Russo One by Jovanny Lemonad
Rajdhani by Indian Type Foundry
Both licensed under the SIL Open Font License 1.1

ENGINE
Godot Engine 4, MIT licensed
godotengine.org/license

This is an original work. It is not affiliated with or
endorsed by any other game, publisher or car maker.

THANKS FOR PLAYING"""

var city: City
var car: CarVisual
var cam: Camera3D
var env: Environment
var ui: Control
var _menu_root: Control
var _buttons: Array = []
var _panel: Control
var _fade: ColorRect
var _shot := -1
var _shot_t := 0.0
var _t := 0.0
var _traffic: TrafficCar
var _logo: Label
var _base := Transform3D.IDENTITY


func _ready() -> void:
	# the menu plays in front of the real game city (same streets, buildings and wet road)
	env = GFX.make_environment(Color(0.5, 0.55, 0.7), 0.5, Color(0.045, 0.05, 0.075), 0.0022, W3D.sky())
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 0.1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.4, 0.58)
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_energy = 0.95
	env.tonemap_exposure = 1.15
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.08
	env.glow_intensity = 0.7
	env.glow_hdr_threshold = 1.1
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var world := OpenWorld.new()
	world.LOAD_R = 150.0
	world.UNLOAD_R = 200.0
	city = world
	add_child(city)
	city.build()
	_base = Transform3D(Basis(Vector3.UP, PI), Vector3(world.road_x(6) + 1.7, 0, 16.0))
	world.preload_around(_base.origin)
	car = CarVisual.new()
	add_child(car)
	car.setup(Game.current_car(), Game.config())
	car.transform = _base * Transform3D(Basis(Vector3.UP, 0.35), Vector3.ZERO)
	car.set_steer(0.3)
	car.set_lights(true)
	city.focus = car
	# hero lighting on the car
	var key := SpotLight3D.new()
	add_child(key)
	key.look_at_from_position(_base * Vector3(2.5, 7.0, 4.0), _base * Vector3(0, 0.5, 0), Vector3.UP)
	key.spot_range = 16.0
	key.spot_angle = 32.0
	key.light_energy = 6.0
	key.light_color = Color(1.0, 0.86, 0.68)
	key.shadow_enabled = GFX.p.shadows
	var fill := OmniLight3D.new()
	fill.position = _base * Vector3(-4.5, 1.6, 3.0)
	fill.light_color = Color(0.75, 0.85, 1.0)
	fill.light_energy = 1.4
	fill.omni_range = 9.0
	add_child(fill)
	if GFX.p.mirror:
		var mirror := PlanarReflection.new()
		add_child(mirror)
		mirror.setup(0.5)
	# passing traffic for life
	var h := City.PITCH * 0.5 - 5.6
	var c := Vector3(world.road_x(6) + City.PITCH * 0.5, 0, 0)
	_traffic = TrafficCar.new()
	add_child(_traffic)
	_traffic.setup("muscle" if Game.current_car() != "muscle" else "euro", 11)
	_traffic.run_loop(PackedVector3Array([c + Vector3(-h, 0, h), c + Vector3(-h, 0, -h), c + Vector3(h, 0, -h), c + Vector3(h, 0, h)]), 1)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.h_offset = -1.3
	cam.far = 500.0
	add_child(cam)
	_build_ui()
	_next_shot()
	Audio.music_state("menu")
	Audio.play_ambience("city", -14.0)
	GFX.changed.connect(func(): GFX.apply_environment(env))


# ====================================================================== cameras
func _shots() -> Array:
	# [from_pos, to_pos, from_look, to_look, fov, duration]
	# the first shot shows the back of the car
	return [
		[Vector3(-3.8, 1.0, 5.6), Vector3(-1.6, 1.35, 6.9), Vector3(0.3, 0.7, 0), Vector3(0.3, 0.7, 0), 40.0, 8.0],
		[Vector3(4.6, 0.35, 1.4), Vector3(4.2, 0.5, -2.4), Vector3(0, 0.5, 0.6), Vector3(0, 0.55, -0.6), 34.0, 7.0],
		[Vector3(3.2, 3.4, 7.2), Vector3(-1.5, 2.3, 6.6), Vector3(0, 0.5, 0), Vector3(0, 0.6, 0), 42.0, 8.0],
		[Vector3(-2.4, 0.5, 3.2), Vector3(-3.4, 0.6, 1.4), Vector3(-0.3, 0.45, 1.2), Vector3(-0.6, 0.5, 0.4), 30.0, 7.0],
	]


func _next_shot() -> void:
	_shot = (_shot + 1) % _shots().size()
	_shot_t = 0.0


func _process(dt: float) -> void:
	_t += dt
	_shot_t += dt
	var s: Array = _shots()[_shot]
	var k := clampf(_shot_t / float(s[5]), 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	cam.look_at_from_position(_base * (s[0] as Vector3).lerp(s[1], e), _base * (s[2] as Vector3).lerp(s[3], e), Vector3.UP)
	cam.fov = s[4]
	# quick dip to black between shots
	var edge := minf(_shot_t, float(s[5]) - _shot_t)
	_fade.color.a = clampf(1.0 - edge / 0.35, 0.0, 1.0)
	if _shot_t >= float(s[5]):
		_next_shot()
	# idle shake: the engine is running
	car.body.position.x = sin(_t * 31.0) * 0.0015
	car.set_body_tilt(sin(_t * 23.0) * 0.0012, sin(_t * 29.0) * 0.0015)
	if _logo and _logo.material:
		(_logo.material as ShaderMaterial).set_shader_parameter("shine", fmod(_t * 420.0, 2600.0) - 400.0)


# ====================================================================== UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_fade = UI.full(UI.rect(Color(0, 0, 0, 0))) as ColorRect
	layer.add_child(_fade)
	ui = UI.full(Control.new())
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	# left shade so the menu always reads
	var shade := TextureRect.new()
	shade.texture = UI.gradient_tex([Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.0)], [0.0, 0.6, 1.0], false)
	shade.anchor_bottom = 1.0
	shade.offset_right = 620
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	ui.add_child(UI.crt_overlay())

	_menu_root = UI.full(Control.new())
	_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_menu_root)
	_logo = UI.label("HMDNIGHT", 68, Color.WHITE, true)
	UI.chrome(_logo, Color(1, 1, 1), Color(1.0, 0.78, 0.12), Color(0.85, 0.22, 0.0), 82.0)
	UI.outline(_logo, 10, Color(0, 0, 0, 0.9))
	_logo.position = Vector2(44, 30)
	_menu_root.add_child(_logo)
	var sub := UI.label("C L U B", 26, UI.CYAN, true)
	UI.outline(sub, 6)
	sub.position = Vector2(52, 108)
	_menu_root.add_child(sub)
	var line := UI.rect(UI.AMBER)
	line.position = Vector2(48, 146)
	line.size = Vector2(420, 3)
	_menu_root.add_child(line)

	var y := 178.0
	for i in ITEMS.size():
		var it: Array = ITEMS[i]
		var b := NeonButton.make(it[0], Vector2(400, 60), UI.AMBER, 30)
		b.position = Vector2(44 + i * 7, y)
		b.pressed.connect(_on_item.bind(it[1]))
		_menu_root.add_child(b)
		_buttons.append(b)
		UI.pop(b, 0.15 + 0.07 * i, Vector2(-120, 0), 0.45)
		y += 70.0

	# bottom-right: current ride + cash
	var info := Control.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(info, Vector2(1, 1), Vector2(-420, -112), Vector2(400, 96))
	_menu_root.add_child(info)
	var ibg := UI.panel(Color(0.02, 0.03, 0.05, 0.75), Color(1, 1, 1, 0.12), 0.2)
	UI.full(ibg)
	info.add_child(ibg)
	var l1 := UI.label("CURRENT RIDE", 15, UI.DIM)
	l1.position = Vector2(30, 8)
	info.add_child(l1)
	var l2 := UI.label(CarDB.CARS[Game.current_car()].name, 32, Color.WHITE, true)
	l2.position = Vector2(30, 24)
	info.add_child(l2)
	var l3 := UI.label("CASH  " + CarDB.money(Game.money()), 20, UI.AMBER)
	l3.position = Vector2(30, 62)
	info.add_child(l3)
	var vstr: String = str(ProjectSettings.get_setting("application/config/version", "?"))
	var ver := UI.label("BUILD v" + vstr, 26, UI.CYAN, true)
	UI.outline(ver, 5)
	UI.place(ver, Vector2(1, 1), Vector2(-260, -44), Vector2(240, 30))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_menu_root.add_child(ver)

	_panel = UI.full(Control.new())
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_panel)


func _on_item(id: String) -> void:
	if Nav.busy:
		return
	match id:
		"garage":
			Nav.goto("garage", {}, "ENTERING GARAGE")
		"lot":
			Nav.goto("showroom", {"from": "menu"}, "CAR LOT")
		"streets":
			Nav.goto("drive", {}, "HITTING THE STREETS")
		"career":
			_open(_career())
		"arcade":
			_open(_coming_soon(id))
		"options":
			var op := OptionsPanel.new()
			op.closed.connect(_close_panel)
			_open(op)
		"credits":
			_open(_credits())
		"exit":
			_open(_exit_confirm())


func _open(p: Control) -> void:
	for c in _panel.get_children():
		c.queue_free()
	_panel.add_child(p)
	p.modulate.a = 0.0
	create_tween().tween_property(p, "modulate:a", 1.0, 0.2)
	var tw := create_tween()
	tw.tween_property(_menu_root, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): _menu_root.visible = false)


func _close_panel() -> void:
	for c in _panel.get_children():
		c.queue_free()
	_menu_root.visible = true
	create_tween().tween_property(_menu_root, "modulate:a", 1.0, 0.25)


func _frame(w: float, h: float, title: String, accent: Color) -> Control:
	var root := UI.full(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := UI.full(UI.rect(Color(0, 0, 0, 0.45)))
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var box := Control.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(box, Vector2(0.5, 0.5), Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
	root.add_child(box)
	var bg := UI.panel(Color(0.02, 0.03, 0.05, 0.92), Color(accent.r, accent.g, accent.b, 0.5))
	UI.full(bg)
	box.add_child(bg)
	var bar := UI.rect(accent)
	bar.size = Vector2(w, 5)
	box.add_child(bar)
	var t := UI.label(title, 46, Color.WHITE, true)
	UI.chrome(t, Color(1, 1, 1), Color(1.0, 0.78, 0.12), Color(0.85, 0.22, 0.0), 56.0)
	t.position = Vector2(34, 18)
	box.add_child(t)
	return root


func _back_button(box: Control, w: float, h: float, text := "BACK") -> NeonButton:
	var b := NeonButton.make(text, Vector2(220, 54), UI.AMBER, 24)
	b.align_left = false
	b.click_sound = "ui_back"
	b.position = Vector2(w - 254, h - 78)
	b.pressed.connect(_close_panel)
	box.add_child(b)
	return b


func _coming_soon(id: String) -> Control:
	var d: Array = SOON[id]
	var root := _frame(820, 470, d[0], UI.CYAN)
	var box: Control = root.get_node("Box")
	var tag := UI.panel(UI.MAGENTA, Color(0, 0, 0, 0), 0.3)
	tag.position = Vector2(560, 28)
	tag.size = Vector2(220, 40)
	box.add_child(tag)
	var tl := UI.label("COMING SOON", 22, Color.WHITE, true)
	tl.size = Vector2(220, 40)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_child(tl)
	var desc := UI.label(d[1], 22, UI.TEXT)
	desc.position = Vector2(36, 96)
	desc.size = Vector2(748, 90)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)
	var y := 200.0
	for f in d[2]:
		var dot := UI.panel(UI.AMBER, Color(0, 0, 0, 0), 0.4)
		dot.position = Vector2(40, y + 8)
		dot.size = Vector2(18, 14)
		box.add_child(dot)
		var fl := UI.label(f, 22, UI.TEXT)
		fl.position = Vector2(72, y)
		box.add_child(fl)
		y += 38.0
	var note := UI.label("Not part of this demo. Head to the GARAGE to build your car and take it for a test drive.", 17, UI.DIM)
	note.position = Vector2(36, 330)
	note.size = Vector2(748, 50)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var g := NeonButton.make("GO TO GARAGE", Vector2(280, 54), UI.GREEN, 24)
	g.align_left = false
	g.position = Vector2(34, 392)
	g.pressed.connect(func(): Nav.goto("garage", {}, "ENTERING GARAGE"))
	box.add_child(g)
	_back_button(box, 820, 470)
	return root


## Story mode: the chapter list with progress, and CONTINUE STORY.
func _career() -> Control:
	var w := 1040.0
	var h := 640.0
	var root := _frame(w, h, "STORY MODE", UI.MAGENTA)
	var box: Control = root.get_node("Box")
	var cur := Game.story_chapter()
	var fin: bool = Game.story().finished
	var sub := UI.label("Five crews run Dubai after dark. Above them sits the Night Club. Earn your name.", 20, UI.TEXT)
	sub.position = Vector2(36, 80)
	box.add_child(sub)
	var y := 120.0
	for i in StoryDB.chapter_count():
		var ch := StoryDB.chapter(i)
		var done := fin or i < cur
		var now := not fin and i == cur
		var crew: Dictionary = StoryDB.CREWS.get(ch.crew, {})
		var col: Color = crew.get("color", UI.AMBER)
		var row := UI.panel(Color(col.r * 0.12, col.g * 0.12, col.b * 0.12, 0.9) if now else Color(0, 0, 0, 0.35),
			Color(col.r, col.g, col.b, 0.8 if now else 0.15), 0.15)
		row.position = Vector2(30, y)
		row.size = Vector2(w - 60, 50)
		box.add_child(row)
		var s1 := UI.label(ch.sub, 15, col if (done or now) else UI.DIM)
		s1.position = Vector2(22, 4)
		row.add_child(s1)
		var s2 := UI.label(ch.title, 26, Color.WHITE if (done or now) else UI.DIM, true)
		s2.position = Vector2(20, 16)
		row.add_child(s2)
		var info := ""
		if not crew.is_empty():
			info = "%s  •  %s" % [crew.district, crew.family]
		else:
			info = ch.district
		var s3 := UI.label(info, 16, UI.DIM)
		s3.position = Vector2(380, 16)
		row.add_child(s3)
		var won := 0
		for id in ch.missions:
			if Game.event_passed(id):
				won += 1
		var st := "COMPLETE" if done else ("%d / %d RACES" % [won, ch.missions.size()] if now else "LOCKED")
		var s4 := UI.label(st, 18, UI.GREEN if done else (UI.AMBER if now else UI.DIM))
		s4.position = Vector2(w - 260, 14)
		s4.size = Vector2(180, 24)
		s4.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(s4)
		y += 58.0
	var abil := []
	for a in Game.story().abilities:
		abil.append(StoryDB.ABILITIES[a].name)
	var al := UI.label("ABILITIES WON: " + (", ".join(abil) if not abil.is_empty() else "NONE YET"), 17, UI.CYAN)
	al.position = Vector2(36, h - 66)
	box.add_child(al)
	var go := NeonButton.make("REPLAY CITY" if fin else ("START STORY" if cur == 0 and int(Game.story().seen) < 0 else "CONTINUE STORY"), Vector2(320, 54), UI.GREEN, 24)
	go.align_left = false
	go.filled = true
	go.position = Vector2(w - 600, h - 78)
	go.pressed.connect(func(): Nav.goto("drive", {"story": true}, StoryDB.chapter(Game.story_chapter()).title))
	box.add_child(go)
	_back_button(box, w, h)
	return root


func _credits() -> Control:
	var root := _frame(820, 580, "CREDITS", UI.AMBER)
	var box: Control = root.get_node("Box")
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(34, 86)
	clip.size = Vector2(752, 400)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(clip)
	var l := UI.label(CREDITS, 20, UI.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(752, 0)
	l.position = Vector2(0, 400)
	clip.add_child(l)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "position:y", -820.0, 26.0).from(400.0)
	_back_button(box, 820, 580)
	return root


func _exit_confirm() -> Control:
	var root := _frame(620, 300, "EXIT GAME?", UI.RED)
	var box: Control = root.get_node("Box")
	var l := UI.label("Your garage is saved. See you on the streets.", 22, UI.TEXT)
	l.position = Vector2(36, 104)
	box.add_child(l)
	var yes := NeonButton.make("EXIT", Vector2(220, 54), UI.RED, 24)
	yes.align_left = false
	yes.position = Vector2(34, 212)
	yes.pressed.connect(func():
		Game.save_game()
		get_tree().quit())
	box.add_child(yes)
	_back_button(box, 620, 300, "STAY")
	return root


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _panel.get_child_count() > 0:
			_close_panel()
		else:
			_on_item("exit")


func dev_item(id: String) -> void:
	_on_item(id)
