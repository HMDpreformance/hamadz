class_name GarageDyno
extends Node
## The dyno run in the LSXmotorsport bay. The car is strapped down on the
## rollers, the engine starts, the driven wheels and rollers spin up through
## the revs with the engine note rising, and the power graph draws live on the
## wall TV. Tapping the TV moves the camera up close to it.

const PULL_T := 6.5

var g: Node                    # the garage scene
var stage: LsxWorkshop
var screen: DynoScreen
var active := false
var _phase := ""               # "" | settle | pull | cool | done
var _t := 0.0
var _rpm := 0.14
var _w := 0.0                  # wheel speed, rad/s
var _zoom := false
var _busy := false
var _tap_t := 0.0
var _awd := false
var _layer: CanvasLayer
var _fade: ColorRect
var _hint: Label
var _btn_run: NeonButton
var _btn_done: NeonButton
var _cam_tw: Tween
var _cam_pos := Vector3.ZERO
var _cam_at := Vector3.ZERO
var _pops := 0
var _pop_t := 0.0


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	var root := UI.full(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	var title := UI.label("LSX DYNO", 34, UI.TEXT, true)
	UI.outline(title)
	title.position = Vector2(40, 26)
	root.add_child(title)
	_hint = UI.label("", 24, UI.TEXT)
	UI.outline(_hint)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(_hint, Vector2(0.5, 0), Vector2(-320, 30), Vector2(640, 32))
	root.add_child(_hint)
	_btn_run = NeonButton.make("RUN AGAIN", Vector2(230, 56), UI.GREEN, 24)
	UI.place(_btn_run, Vector2(1, 1), Vector2(-520, -96), Vector2(230, 56))
	_btn_run.pressed.connect(_run_again)
	root.add_child(_btn_run)
	_btn_done = NeonButton.make("DONE", Vector2(200, 56), UI.AMBER, 24)
	UI.place(_btn_done, Vector2(1, 1), Vector2(-260, -96), Vector2(200, 56))
	_btn_done.pressed.connect(finish)
	root.add_child(_btn_done)
	_fade = UI.full(UI.rect(Color(0, 0, 0, 1))) as ColorRect
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	root.add_child(_fade)


func _fade_to(a: float, time := 0.35) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", a, time)
	await tw.finished


func start() -> void:
	if active or _busy:
		return
	_busy = true
	if _layer == null:
		_build_ui()
	_layer.visible = true
	_btn_run.visible = false
	_btn_done.visible = false
	_hint.text = ""
	g.home.visible = false
	g._work.visible = false
	g.cam.enabled = false
	await _fade_to(1.0)
	active = true
	g.dyno_on = true
	g.cam.set_process(false)
	var car: CarVisual = g.car
	_awd = String(CarDB.CARS[g.view_car].get("drive", "RWD")) == "AWD"
	for n in [g.mover, g.mmover]:
		if n:
			n.position = LsxWorkshop.DYNO + Vector3(0, 0.03, 0)
			n.rotation.y = PI
	for n in [g.turn_node, g.mturn_node]:
		if n:
			n.rotation.y = 0.0
	stage.set_axles(car.axle_z(true), car.axle_z(false), car.length())
	stage.straps.visible = true
	screen.setup(g.view_car, g.preview)
	_zoom = false
	_set_cam(LsxWorkshop.DYNO + Vector3(-4.7, 0.7, 4.9), LsxWorkshop.DYNO + Vector3(0.9, 0.95, -0.6))
	_phase = "settle"
	_t = 0.0
	_rpm = 0.14
	_w = 0.0
	Audio.sfx("whoosh", -8.0)
	await _fade_to(0.0, 0.5)
	_busy = false


func _run_again() -> void:
	if _phase != "done":
		return
	_btn_run.visible = false
	_btn_done.visible = false
	if _zoom:
		_toggle_zoom()
	screen.set_progress(0.0, "ready")
	_phase = "settle"
	_t = 0.6


func finish() -> void:
	if not active or _busy:
		return
	_busy = true
	await _fade_to(1.0)
	active = false
	_phase = ""
	g.dyno_on = false
	g._engine_stop()
	stage.straps.visible = false
	for n in [g.mover, g.mmover]:
		if n:
			n.position = Vector3.ZERO
			n.rotation.y = 0.0
	g.car.set_body_tilt(0.0, 0.0)
	if _cam_tw:
		_cam_tw.kill()
	g.cam.fov = 42.0
	g.cam.set_process(true)
	g.cam.enabled = true
	g.cam.snap("default")
	g._set_home(true)
	_layer.visible = true
	_btn_run.visible = false
	_btn_done.visible = false
	_hint.text = ""
	await _fade_to(0.0, 0.45)
	_layer.visible = false
	_busy = false


# ------------------------------------------------------------------ camera
func _set_cam(pos: Vector3, at: Vector3) -> void:
	_cam_pos = pos
	_cam_at = at
	g.cam.look_at_from_position(pos, at, Vector3.UP)


func _move_cam(pos: Vector3, at: Vector3, time: float) -> void:
	if _cam_tw:
		_cam_tw.kill()
	var p0 := _cam_pos
	var a0 := _cam_at
	_cam_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tw.tween_method(func(k: float): _set_cam(p0.lerp(pos, k), a0.lerp(at, k)), 0.0, 1.0, time)


func _toggle_zoom() -> void:
	_zoom = not _zoom
	Audio.sfx("ui_select", -4.0)
	if _zoom:
		_move_cam(LsxWorkshop.TV_POS + Vector3(-2.95, 0.0, 0.0), LsxWorkshop.TV_POS, 0.9)
		_hint.text = "TAP AGAIN TO GO BACK"
	else:
		_move_cam(LsxWorkshop.DYNO + Vector3(-3.6, 0.62, 3.6), LsxWorkshop.DYNO + Vector3(0.9, 0.95, -0.6), 0.9)
		_hint.text = "TAP THE TV TO SEE THE GRAPH UP CLOSE"


func _input(event: InputEvent) -> void:
	if not active or _busy:
		return
	var pos := Vector2(-1, -1)
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	if pos.x < 0.0 or _tap_t > 0.0:
		return
	for b in [_btn_run, _btn_done]:
		if b.visible and b.get_global_rect().has_point(pos):
			return
	if _zoom:
		_tap_t = 0.3
		_toggle_zoom()
	elif stage.tv_screen_rect(g.cam).grow(24.0).has_point(pos):
		_tap_t = 0.3
		_toggle_zoom()


# ------------------------------------------------------------------ the run
func _process(dt: float) -> void:
	_tap_t = maxf(_tap_t - dt, 0.0)
	if not active:
		return
	var car: CarVisual = g.car
	var load := 0.0
	match _phase:
		"settle":
			_t += dt
			if _t > 0.6 and not g._eng_on:
				g._engine_start()
			_rpm = move_toward(_rpm, 0.16, dt)
			_w = move_toward(_w, 6.0 if _t > 1.6 else 0.0, dt * 6.0)
			if _t > 2.6:
				_phase = "pull"
				_t = 0.0
				_hint.text = "TAP THE TV TO SEE THE GRAPH UP CLOSE"
				if not _zoom:
					_move_cam(LsxWorkshop.DYNO + Vector3(-3.6, 0.62, 3.6), LsxWorkshop.DYNO + Vector3(0.9, 0.95, -0.6), PULL_T)
		"pull":
			_t = minf(_t + dt / PULL_T, 1.0)
			load = 1.0
			_rpm = lerpf(0.16, 1.0, _t)
			_w = lerpf(6.0, 170.0, _t)
			screen.set_progress(_t, "pull")
			if _t >= 1.0:
				_phase = "cool"
				_t = 0.0
				screen.set_progress(1.0, "done")
				Audio.sfx("finish", -6.0)
				_pops = 4
				_pop_t = 0.15
		"cool":
			_t += dt
			_rpm = move_toward(_rpm, 0.14, dt * 0.55)
			_w = move_toward(_w, 0.0, dt * 70.0)
			if _pops > 0:
				_pop_t -= dt
				if _pop_t <= 0.0:
					_pops -= 1
					_pop_t = randf_range(0.1, 0.3)
					Audio.sfx("res://audio/car/pop_%d.wav" % (1 + randi() % 5), -8.0, randf_range(0.85, 1.15), "Engine")
			if _t > 2.4:
				_phase = "done"
				_t = 0.0
				_btn_run.visible = true
				_btn_done.visible = true
		"done":
			_t += dt
			_rpm = move_toward(_rpm, 0.14, dt)
			if _t > 6.0 and g._eng_on:
				g._engine_stop()
	if g._voice:
		var wob := sin(Time.get_ticks_msec() * 0.011) * 0.006
		g._voice.update(_rpm + wob, load, dt)
	# driven wheels and rollers turn together; the body squats and shakes under load
	var a := _w * dt
	for cv in [car, g.car_mirror]:
		if cv == null:
			continue
		for wh in cv.wheels:
			if _awd or not wh.front:
				wh.spin.rotate_x(a if wh.left else -a)
	var ratio := car.wheel_radius / 0.2
	stage.spin_rollers(a * ratio if _awd else 0.0, a * ratio, dt * (30.0 if _phase != "done" else 8.0))
	if car.body:
		var shake := sin(Time.get_ticks_msec() * 0.045) * 0.0018 * (1.0 + _rpm * 2.0) if g._eng_on else 0.0
		car.set_body_tilt(0.012 * load * (0.4 + _rpm), shake)
