extends Node3D
## Test drive: night city free-roam with a checkpoint run ("Midnight Loop").
## Owns the world, the player car, the HUD/touch controls and the pause menu.

const GOLD := 46.0
const SILVER := 58.0
const BRONZE := 75.0

var city: City
var car: PlayerCar
var cam: ChaseCamera
var engine_audio: EngineAudio
var fx: CarFX
var env: Environment
var post: PostFX

var state := "roam"            # roam | run | done
var checkpoints: Array[Vector3] = []
var cp_index := 0
var run_time := 0.0
var spawn_pos := Vector3.ZERO
var spawn_yaw := 0.0

var _marker: Node3D
var _marker_label: Label3D
var _marker_mat: StandardMaterial3D
var _hud: Control
var _info: Label
var _timer: Label
var _best: Label
var _gauge: Control
var _arrow: Control
var _banner: Label
var _pause_panel: Control
var _result_panel: Control
var _steer_keys: Array = []
var _traffic: Array = []


func _ready() -> void:
	env = GFX.make_environment(Color(0.3, 0.34, 0.5), 0.55, Color(0.07, 0.05, 0.11), 0.0065, EnvKit.city_sky())
	env.background_mode = Environment.BG_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-48, 35, 0)
	moon.light_color = Color(0.5, 0.6, 1.0)
	moon.light_energy = 0.28
	moon.shadow_enabled = GFX.p.shadows
	moon.directional_shadow_max_distance = 60.0
	add_child(moon)

	city = City.new()
	city.blocks = 5
	add_child(city)
	city.build()

	spawn_pos = Vector3(city.road(2) + 1.9, 0, 22.0)
	spawn_yaw = 0.0
	car = PlayerCar.new()
	add_child(car)
	car.setup(Game.current_car(), Game.config())
	car.ground_fn = city.ground_height
	car.reset_to(spawn_pos, spawn_yaw)
	car.crashed.connect(_on_crash)
	city.focus = car
	engine_audio = EngineAudio.new()
	car.add_child(engine_audio)
	engine_audio.attach(car)
	fx = CarFX.new()
	car.add_child(fx)
	fx.attach(car)
	cam = ChaseCamera.new()
	cam.target = car
	cam.fov = 62.0
	cam.far = 600.0
	add_child(cam)
	cam.make_current()

	_route()
	_make_marker()
	_spawn_traffic()
	_build_hud()
	_set_state("roam")
	Audio.play_ambience("city", -10.0)
	Audio.play_music("drive", 1.5, -11.0)
	GFX.changed.connect(func(): GFX.apply_environment(env))
	_show_banner("FREE ROAM", 2.2)


func _exit_tree() -> void:
	Controls.release_all()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	# Escape on desktop / Back on Android
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()


# ====================================================================== route
func _route() -> void:
	var r := func(i: int) -> float: return city.road(i)
	var mid := func(a: int, b: int) -> float: return (city.road(a) + city.road(b)) * 0.5
	checkpoints = [
		Vector3(r.call(2), 0, mid.call(1, 2)),
		Vector3(mid.call(2, 3), 0, r.call(1)),
		Vector3(mid.call(3, 4), 0, r.call(1)),
		Vector3(r.call(4), 0, mid.call(1, 2)),
		Vector3(r.call(4), 0, mid.call(2, 3)),
		Vector3(mid.call(3, 4), 0, r.call(3)),
		Vector3(r.call(3), 0, mid.call(3, 4)),
		Vector3(mid.call(2, 3), 0, r.call(4)),
		Vector3(mid.call(1, 2), 0, r.call(4)),
		Vector3(r.call(1), 0, mid.call(3, 4)),
		Vector3(mid.call(1, 2), 0, r.call(3)),
		Vector3(r.call(2), 0, mid.call(2, 3)),
	]


func _start_gate() -> Vector3:
	return Vector3(city.road(2), 0, (city.road(2) + city.road(3)) * 0.5)


func _make_marker() -> void:
	_marker = Node3D.new()
	add_child(_marker)
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 7.5
	cm.bottom_radius = 7.5
	cm.height = 26.0
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	col.mesh = cm
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_mat.albedo_texture = UI.gradient_tex([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.75)], [0.0, 0.6, 1.0])
	_marker_mat.disable_receive_shadows = true
	col.material_override = _marker_mat
	col.position.y = 13.0
	_marker.add_child(col)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 7.2
	tm.outer_radius = 7.7
	tm.rings = 32
	tm.ring_segments = 4
	ring.mesh = tm
	ring.scale.y = 0.2
	ring.position.y = 0.08
	ring.material_override = _marker_mat
	ring.name = "Ring"
	_marker.add_child(ring)
	_marker_label = Label3D.new()
	_marker_label.font = UI.title_font()
	_marker_label.font_size = 128
	_marker_label.pixel_size = 0.03
	_marker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker_label.shaded = false
	_marker_label.no_depth_test = true
	_marker_label.position.y = 9.0
	_marker.add_child(_marker_label)


func _place_marker(pos: Vector3, text: String, color: Color) -> void:
	_marker.visible = true
	_marker.position = pos
	_marker_label.text = text
	_marker_label.modulate = Color(color.r * 2.0 + 0.3, color.g * 2.0 + 0.3, color.b * 2.0 + 0.3)
	_marker_mat.albedo_color = color


func _spawn_traffic() -> void:
	var count: int = [2, 4, 6][GFX.index]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var used := {}
	var h := City.PITCH * 0.5 - 5.6
	for k in count:
		var bi := rng.randi() % 5
		var bj := rng.randi() % 5
		while used.has(bi * 10 + bj):
			bi = rng.randi() % 5
			bj = rng.randi() % 5
		used[bi * 10 + bj] = true
		var c := Vector3(city.road(bi) + City.PITCH * 0.5, 0, city.road(bj) + City.PITCH * 0.5)
		var path := PackedVector3Array([c + Vector3(-h, 0, h), c + Vector3(-h, 0, -h), c + Vector3(h, 0, -h), c + Vector3(h, 0, h)])
		var t := TrafficCar.new()
		add_child(t)
		t.setup(CarDB.CAR_ORDER[rng.randi() % 3], [6, 9, 10, 11, 5, 4][rng.randi() % 6], path, rng.randi() % 4, rng.randf_range(0.2, 0.8))
		t.cruise = rng.randf_range(10.0, 14.0)
		t.player = car
		_traffic.append(t)


# ====================================================================== state
func _set_state(s: String) -> void:
	state = s
	match s:
		"roam":
			_place_marker(_start_gate(), "START", UI.AMBER)
			_info.text = "FREE ROAM  •  DRIVE INTO THE START GATE"
			_timer.text = ""
		"run":
			cp_index = 0
			run_time = 0.0
			_place_marker(checkpoints[0], "1", UI.CYAN)
			Audio.sfx("beep_hi")
			_show_banner("GO!", 1.2)
		"done":
			_marker.visible = false


func _physics_process(dt: float) -> void:
	if state == "run":
		run_time += dt


func _process(_dt: float) -> void:
	var p := car.global_position
	if state == "roam":
		if Vector2(p.x - _marker.position.x, p.z - _marker.position.z).length() < 8.0:
			_set_state("run")
	elif state == "run":
		var cp := checkpoints[cp_index]
		if Vector2(p.x - cp.x, p.z - cp.z).length() < 9.5:
			cp_index += 1
			if cp_index >= checkpoints.size():
				_finish()
			else:
				Audio.sfx("checkpoint", -2.0)
				var last := cp_index == checkpoints.size() - 1
				_place_marker(checkpoints[cp_index], "FINISH" if last else str(cp_index + 1), UI.GREEN if last else UI.CYAN)
		_info.text = "CHECKPOINT  %d / %d" % [mini(cp_index + 1, checkpoints.size()), checkpoints.size()]
		_timer.text = _fmt(run_time)
	# marker pulse
	if _marker.visible:
		var ring := _marker.get_node("Ring") as Node3D
		var s := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.006)
		ring.scale = Vector3(s, 0.2, s)
	# speed post effect
	var sp := clampf(absf(car.speed) / car.vmax, 0.0, 1.2)
	var amt := clampf((sp - 0.7) * 1.6, 0.0, 0.5) + (0.55 if car.using_nitro else 0.0)
	post.use_blur = GFX.index == 2
	post.amount = lerpf(post.amount, amt, 0.15)
	if Input.is_action_just_pressed("camera"):
		_toggle_cam()
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()
	for k in _steer_keys:
		k.visible = int(Game.setting("steer_mode", 0)) == 0


static func _fmt(t: float) -> String:
	var m := int(t / 60.0)
	return "%02d:%05.2f" % [m, t - m * 60.0]


func _finish() -> void:
	_set_state("done")
	Audio.sfx("finish")
	var medal := "FINISHED"
	var pay := 600
	var col := UI.TEXT
	if run_time <= GOLD:
		medal = "GOLD"
		pay = 3000
		col = Color(1.0, 0.82, 0.2)
	elif run_time <= SILVER:
		medal = "SILVER"
		pay = 2000
		col = Color(0.8, 0.85, 0.9)
	elif run_time <= BRONZE:
		medal = "BRONZE"
		pay = 1200
		col = Color(0.85, 0.5, 0.25)
	var is_best := Game.record_run(run_time)
	if is_best:
		pay += 500
	Game.add_money(pay)
	_best.text = "BEST  " + _fmt(float(Game.data.best_time))
	_show_result(medal, col, pay, is_best)


func _on_crash(force: float) -> void:
	Audio.sfx("crash", clampf(-12.0 + force * 0.5, -12.0, 0.0), randf_range(0.85, 1.1))
	cam.shake(clampf(force * 0.012, 0.05, 0.35))


func _toggle_cam() -> void:
	cam.toggle()
	Audio.sfx("ui_move")


func _restart() -> void:
	car.reset_to(spawn_pos, spawn_yaw)
	car.nitro = 1.0
	_set_state("roam")
	_result_panel.visible = false


# ====================================================================== HUD
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	post = PostFX.new()
	layer.add_child(post)
	_hud = UI.full(Control.new())
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_hud.add_child(UI.crt_overlay())

	# --- top centre info
	var top := Control.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(top, Vector2(0.5, 0), Vector2(-260, 10), Vector2(520, 96))
	_hud.add_child(top)
	var bg := UI.panel(Color(0.02, 0.03, 0.05, 0.6), Color(1, 1, 1, 0.1), 0.3)
	bg.size = Vector2(520, 34)
	top.add_child(bg)
	_info = UI.label("", 18, UI.AMBER)
	_info.size = Vector2(520, 34)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_info)
	_timer = UI.label("", 44, Color.WHITE, true)
	UI.outline(_timer, 8)
	_timer.position = Vector2(0, 34)
	_timer.size = Vector2(520, 52)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_timer)
	_best = UI.label("", 16, UI.DIM)
	UI.outline(_best, 5)
	_best.position = Vector2(0, 84)
	_best.size = Vector2(520, 22)
	_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_best)
	if float(Game.data.best_time) > 0.0:
		_best.text = "BEST  " + _fmt(float(Game.data.best_time))

	# --- top left: pause + camera
	var pk := TouchKey.make("", "II", UI.AMBER, Vector2(64, 64))
	pk.toggle_only = true
	pk.round_shape = false
	pk.position = Vector2(20, 16)
	pk.tapped.connect(_toggle_pause)
	_hud.add_child(pk)
	var ck := TouchKey.make("", "CAM", UI.CYAN, Vector2(84, 64))
	ck.toggle_only = true
	ck.round_shape = false
	ck.position = Vector2(92, 16)
	ck.tapped.connect(_toggle_cam)
	_hud.add_child(ck)

	# --- top right: checkpoint arrow
	_arrow = _Arrow.new()
	_arrow.scene = self
	UI.place(_arrow, Vector2(1, 0), Vector2(-150, 14), Vector2(130, 130))
	_hud.add_child(_arrow)

	# --- driving controls
	var left := TouchKey.make("steer_left", "<", UI.TEXT, Vector2(124, 124))
	UI.place(left, Vector2(0, 1), Vector2(28, -156), Vector2(124, 124))
	_hud.add_child(left)
	var right := TouchKey.make("steer_right", ">", UI.TEXT, Vector2(124, 124))
	UI.place(right, Vector2(0, 1), Vector2(172, -156), Vector2(124, 124))
	_hud.add_child(right)
	_steer_keys = [left, right]
	var gas := TouchKey.make("gas", "GAS", UI.GREEN, Vector2(136, 136))
	UI.place(gas, Vector2(1, 1), Vector2(-164, -164), Vector2(136, 136))
	_hud.add_child(gas)
	var brk := TouchKey.make("brake", "BRAKE", UI.RED, Vector2(112, 112))
	UI.place(brk, Vector2(1, 1), Vector2(-296, -136), Vector2(112, 112))
	_hud.add_child(brk)
	var nos := TouchKey.make("nitro", "N2O", UI.CYAN, Vector2(98, 98))
	UI.place(nos, Vector2(1, 1), Vector2(-128, -276), Vector2(98, 98))
	_hud.add_child(nos)
	var hb := TouchKey.make("handbrake", "DRIFT", UI.AMBER, Vector2(98, 98))
	UI.place(hb, Vector2(1, 1), Vector2(-252, -256), Vector2(98, 98))
	_hud.add_child(hb)

	# --- gauge
	_gauge = _Gauge.new()
	_gauge.car = car
	UI.place(_gauge, Vector2(0, 1), Vector2(304, -204), Vector2(240, 200))
	_hud.add_child(_gauge)

	_banner = UI.label("", 84, Color.WHITE, true)
	UI.chrome(_banner, Color(1, 1, 1), Color(1.0, 0.8, 0.15), Color(0.85, 0.25, 0.0), 100.0)
	UI.outline(_banner, 14)
	UI.place(_banner, Vector2(0.5, 0.5), Vector2(-500, -150), Vector2(1000, 110))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_hud.add_child(_banner)

	_build_pause(layer)
	_build_result(layer)


func _show_banner(text: String, hold: float) -> void:
	_banner.text = text
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.4)


func _menu_panel(layer: CanvasLayer, title: String, title_color: Color) -> Control:
	var root := UI.full(Control.new())
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	layer.add_child(root)
	var dim := UI.full(UI.rect(Color(0, 0, 0, 0.72)))
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var t := UI.label(title, 72, Color.WHITE, true)
	UI.chrome(t, Color(1, 1, 1), title_color, title_color.darkened(0.6), 86.0)
	UI.place(t, Vector2(0.5, 0), Vector2(-500, 60), Vector2(1000, 90))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.name = "Title"
	root.add_child(t)
	return root


func _menu_buttons(root: Control, defs: Array, y0: float) -> void:
	var y := y0
	for d in defs:
		var b := NeonButton.make(d[0], Vector2(380, 58), d[2] if d.size() > 2 else UI.AMBER, 28)
		b.align_left = false
		UI.place(b, Vector2(0.5, 0), Vector2(-190, y), Vector2(380, 58))
		b.pressed.connect(d[1])
		root.add_child(b)
		y += 68.0


func _build_pause(layer: CanvasLayer) -> void:
	_pause_panel = _menu_panel(layer, "PAUSED", UI.AMBER)
	_menu_buttons(_pause_panel, [
		["RESUME", _toggle_pause, UI.GREEN],
		["RESTART AT START GATE", func():
			_toggle_pause()
			_restart()],
		["BACK TO GARAGE", func(): _leave("garage"), UI.CYAN],
		["MAIN MENU", func(): _leave("menu")],
	], 220.0)
	var hint := UI.label("KEYBOARD: WASD / ARROWS  •  SPACE HANDBRAKE  •  SHIFT NITRO  •  C CAMERA", 16, UI.DIM)
	UI.place(hint, Vector2(0.5, 1), Vector2(-500, -50), Vector2(1000, 24))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_panel.add_child(hint)


func _build_result(layer: CanvasLayer) -> void:
	_result_panel = _menu_panel(layer, "RUN COMPLETE", UI.GREEN)
	for n in ["Medal", "Time", "Pay"]:
		var l := UI.label("", 40 if n != "Time" else 64, Color.WHITE, true)
		UI.outline(l, 8)
		UI.place(l, Vector2(0.5, 0), Vector2(-500, {"Medal": 160.0, "Time": 212.0, "Pay": 296.0}[n]), Vector2(1000, 70))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.name = n
		_result_panel.add_child(l)
	_menu_buttons(_result_panel, [
		["RUN IT AGAIN", _restart, UI.GREEN],
		["FREE ROAM", func():
			_result_panel.visible = false
			_set_state("roam")],
		["BACK TO GARAGE", func(): _leave("garage"), UI.CYAN],
	], 380.0)


func _show_result(medal: String, col: Color, pay: int, is_best: bool) -> void:
	(_result_panel.get_node("Medal") as Label).text = medal + ("   •   NEW BEST!" if is_best else "")
	(_result_panel.get_node("Medal") as Label).add_theme_color_override("font_color", col)
	(_result_panel.get_node("Time") as Label).text = _fmt(run_time)
	(_result_panel.get_node("Pay") as Label).text = "+" + CarDB.money(pay) + "   CASH: " + CarDB.money(Game.money())
	(_result_panel.get_node("Pay") as Label).add_theme_color_override("font_color", UI.AMBER)
	_result_panel.visible = true
	_result_panel.modulate.a = 0.0
	create_tween().tween_property(_result_panel, "modulate:a", 1.0, 0.4)


func _toggle_pause() -> void:
	if Nav.busy or _result_panel.visible:
		return
	var p := not get_tree().paused
	get_tree().paused = p
	_pause_panel.visible = p
	engine_audio.muted = p
	if p:
		Controls.release_all()
		engine_audio._process(0.0)
	Audio.sfx("ui_select" if p else "ui_back", -4.0)


func _leave(dest: String) -> void:
	engine_audio.muted = true
	engine_audio._process(0.0)
	get_tree().paused = false
	Nav.goto(dest)


# ====================================================================== HUD widgets
class _Gauge extends Control:
	var car: PlayerCar
	var _nitro_flash := 0.0

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if car == null:
			return
		var c := Vector2(size.x * 0.5, size.y * 0.58)
		var r := 96.0
		var a0 := PI * 0.75
		var a1 := PI * 2.25
		draw_circle(c, r + 6, Color(0.02, 0.025, 0.04, 0.72))
		draw_arc(c, r + 6, 0, TAU, 64, Color(1, 1, 1, 0.14), 2.0, true)
		# rpm ticks
		var ticks := 9
		var f := UI.body_font(true)
		for i in ticks:
			var t := float(i) / (ticks - 1)
			var a := lerpf(a0, a1, t)
			var d := Vector2(cos(a), sin(a))
			var col := UI.RED if i >= ticks - 2 else Color(1, 1, 1, 0.8)
			draw_line(c + d * (r - 12), c + d * r, col, 3.0, true)
			draw_string(f, c + d * (r - 26) - Vector2(5, -5), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		draw_arc(c, r - 2, lerpf(a0, a1, 0.78), a1, 16, Color(1, 0.2, 0.15, 0.8), 5.0, true)
		# rpm sweep + needle
		var ra := lerpf(a0, a1, clampf(car.rpm, 0.0, 1.0))
		draw_arc(c, r - 6, a0, ra, 32, Color(UI.AMBER.r, UI.AMBER.g, UI.AMBER.b, 0.35), 12.0, true)
		var nd := Vector2(cos(ra), sin(ra))
		draw_line(c - nd * 14, c + nd * (r - 8), UI.RED, 4.0, true)
		draw_circle(c, 9, Color(0.1, 0.1, 0.12))
		draw_arc(c, 9, 0, TAU, 20, UI.RED, 2.0, true)
		# speed + gear
		var tf := UI.title_font()
		var spd := str(int(round(car.speed_mph())))
		var w := tf.get_string_size(spd, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
		draw_string_outline(tf, Vector2(c.x - w * 0.5, c.y + 56), spd, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, 8, Color(0, 0, 0, 0.9))
		draw_string(tf, Vector2(c.x - w * 0.5, c.y + 56), spd, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color.WHITE)
		draw_string(f, Vector2(c.x - 14, c.y + 74), "MPH", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.DIM)
		var g := "R" if car.speed < -0.5 else str(car.gear + 1)
		draw_string(tf, Vector2(c.x + 34, c.y - 22), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UI.AMBER)
		# nitro bar (arc under the gauge)
		var na0 := PI * 0.25 + 0.15
		var na1 := PI * 0.75 - 0.15
		draw_arc(c, r + 14, na0, na1, 16, Color(1, 1, 1, 0.15), 7.0, true)
		var ncol := UI.CYAN if not car.using_nitro else Color(1, 1, 1)
		draw_arc(c, r + 14, lerpf(na1, na0, car.nitro), na1, 16, ncol, 7.0, true)
		draw_string(f, Vector2(c.x - 14, c.y + r + 34), "N2O", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.CYAN)


class _Arrow extends Control:
	var scene: Node

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if scene == null or not scene._marker.visible:
			return
		var car: PlayerCar = scene.car
		var to: Vector3 = scene._marker.position - car.global_position
		to.y = 0.0
		var fwd := car.forward()
		var ang := atan2(to.dot(car.global_transform.basis.x), to.dot(fwd))
		var c := size * 0.5 - Vector2(0, 8)
		var r := 46.0
		draw_circle(c, r + 8, Color(0.02, 0.025, 0.04, 0.6))
		draw_arc(c, r + 8, 0, TAU, 48, Color(1, 1, 1, 0.14), 2.0, true)
		var col: Color = scene._marker_mat.albedo_color
		var d := Vector2(sin(ang), -cos(ang))
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([c + d * r, c - d * r * 0.5 + n * r * 0.55, c - d * r * 0.15, c - d * r * 0.5 - n * r * 0.55]), col)
		var dist := "%d M" % int(to.length())
		var f := UI.body_font(true)
		var w := f.get_string_size(dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string_outline(f, Vector2(c.x - w * 0.5, c.y + r + 30), dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(c.x - w * 0.5, c.y + r + 30), dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


# ====================================================================== dev hooks
func dev_press(action: String, on := "1") -> void:
	if on == "1":
		Input.action_press(action)
	else:
		Input.action_release(action)


func dev_pause() -> void:
	_toggle_pause()


func dev_finish() -> void:
	run_time = 44.0
	_finish()
