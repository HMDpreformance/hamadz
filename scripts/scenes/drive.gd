extends Node3D
## Free roam in Halcyon Bay with street race events. Owns the world, the player
## car, cameras, HUD/touch controls, event cards, race presentation and menus.
## The rules of a race live in Race (scripts/race/race.gd).

var city: OpenWorld
var car: PlayerCar
var cam: ChaseCamera
var engine_audio: EngineAudio
var fx: CarFX
var env: Environment
var post: PostFX

var state := "roam"            # roam | intro | countdown | race | done
var race: Race
var run_time := 0.0
var _events := {}              # id -> {ev, pos, yaw, node}
var _near_event := ""
var _card: Control
var _pos_label: Label
var _radio_toast: Label
var _radio_btn: NeonButton
var _toast_tw: Tween
var _fade: ColorRect
var _bars: Array = []
var _cine: Camera3D
var _cine_t := 0.0
var _cine_center := Vector3.ZERO
var _race_holder: Node3D
var _title_card: Control
var _drive_ui: Array = []
var _last_event := ""
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
var traffic: Traffic
var minimap: MiniMap
var _space_t := 0.0
var _district := ""


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

	city = OpenWorld.new()
	add_child(city)
	city.build()

	spawn_pos = Vector3(city.road_x(6) + 1.9, 0, 22.0)
	city.preload_around(spawn_pos)
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
	engine_audio.start_engine()
	Audio.set_space("street")
	fx = CarFX.new()
	car.add_child(fx)
	fx.attach(car)
	engine_audio.backfire.connect(fx.backfire)
	cam = ChaseCamera.new()
	cam.target = car
	cam.fov = 62.0
	cam.far = 600.0
	add_child(cam)
	cam.make_current()

	_race_holder = Node3D.new()
	add_child(_race_holder)
	_cine = Camera3D.new()
	_cine.far = 600.0
	_cine.fov = 50.0
	add_child(_cine)
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	_make_marker()
	_build_hud()
	_spawn_traffic()
	_make_event_markers()
	_set_state("roam")
	Audio.play_ambience("city", -10.0)
	Audio.music_state("roam", 1.5)
	GFX.changed.connect(func(): GFX.apply_environment(env))


func _exit_tree() -> void:
	Controls.release_all()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	# Escape on desktop / Back on Android
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()


# ====================================================================== events in the world
func _make_event_markers() -> void:
	for ev in EventDB.EVENTS:
		var pts := EventDB.build_points(city, ev)
		var pos := pts[0]
		var d := Vector3(pts[1].x - pts[0].x, 0, pts[1].z - pts[0].z).normalized()
		var col: Color = EventDB.TYPE_COLOR[ev.type]
		var n := Node3D.new()
		n.position = pos
		add_child(n)
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 5.0
		cm.bottom_radius = 5.0
		cm.height = 40.0
		cm.radial_segments = 16
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		beam.mesh = cm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_texture = UI.gradient_tex([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.6)], [0.0, 0.7, 1.0])
		m.albedo_color = col
		m.disable_receive_shadows = true
		beam.material_override = m
		beam.position.y = 20.0
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(beam)
		var l := Label3D.new()
		l.font = UI.title_font()
		l.font_size = 96
		l.pixel_size = 0.022
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.shaded = false
		l.no_depth_test = true
		l.text = ev.name
		l.modulate = Color(col.r * 2.0 + 0.3, col.g * 2.0 + 0.3, col.b * 2.0 + 0.3)
		l.position.y = 7.5
		n.add_child(l)
		var l2 := Label3D.new()
		l2.font = UI.body_font(true)
		l2.font_size = 64
		l2.pixel_size = 0.02
		l2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l2.shaded = false
		l2.no_depth_test = true
		l2.text = EventDB.TYPE_LABEL[ev.type]
		l2.position.y = 5.6
		n.add_child(l2)
		_events[ev.id] = {"ev": ev, "pos": pos, "yaw": atan2(-d.x, -d.z), "node": n}
	_refresh_event_markers()


func _event_lock(ev: Dictionary) -> String:
	if _dev_unlock:
		return ""
	if Game.rep() < int(ev.rep):
		return "NEEDS %d REP  (YOU HAVE %d)" % [int(ev.rep), Game.rep()]
	var need := int(ev.get("rating", 0))
	if need > 0 and CarDB.rating(Game.current_car(), Game.config()) < need:
		return "NEEDS CAR RATING %d  (YOURS %d)" % [need, CarDB.rating(Game.current_car(), Game.config())]
	return ""


func _refresh_event_markers() -> void:
	var mk := []
	for id in _events:
		var e: Dictionary = _events[id]
		var show := state == "roam"
		e.node.visible = show
		if show:
			var col: Color = EventDB.TYPE_COLOR[e.ev.type]
			if _event_lock(e.ev) != "":
				col = Color(0.45, 0.45, 0.5)
			mk.append({"pos": e.pos, "color": col})
	minimap.markers = mk


func _update_event_card() -> void:
	var p := car.global_position
	var best := ""
	var bd := 11.0
	for id in _events:
		var e: Dictionary = _events[id]
		var d := Vector2(p.x - e.pos.x, p.z - e.pos.z).length()
		if d < bd:
			bd = d
			best = id
	if best == _near_event:
		return
	_near_event = best
	if best == "":
		create_tween().tween_property(_card, "modulate:a", 0.0, 0.2)
		get_tree().create_timer(0.2).timeout.connect(func():
			if _near_event == "":
				_card.visible = false)
		return
	var ev: Dictionary = _events[best].ev
	var col: Color = EventDB.TYPE_COLOR[ev.type]
	(_card.get_node("Type") as Label).text = EventDB.TYPE_LABEL[ev.type]
	(_card.get_node("Type") as Label).add_theme_color_override("font_color", col)
	(_card.get_node("Name") as Label).text = ev.name
	(_card.get_node("Blurb") as Label).text = ev.blurb
	var bits := ["REWARD " + CarDB.money(int(ev.reward))]
	if int(ev.opponents) > 0:
		bits.append("%d RIVAL%s" % [int(ev.opponents), "" if int(ev.opponents) == 1 else "S"])
	if int(ev.get("laps", 1)) > 1:
		bits.append("%d LAPS" % int(ev.laps))
	(_card.get_node("Info") as Label).text = "   •   ".join(bits)
	var rec := Game.event_record(ev.id)
	var lock := _event_lock(ev)
	var st := _card.get_node("Status") as Label
	var go := _card.get_node("Go") as NeonButton
	if lock != "":
		st.text = "LOCKED  •  " + lock
		st.add_theme_color_override("font_color", UI.RED)
	elif int(rec.runs) > 0:
		st.text = "BEST: %s  •  %s" % [_place_name(int(rec.best_place)), _fmt(float(rec.best_time))]
		st.add_theme_color_override("font_color", UI.GREEN)
	else:
		st.text = "NOT RACED YET  •  FIRST WIN PAYS +50%"
		st.add_theme_color_override("font_color", UI.DIM)
	go.locked = lock != ""
	_card.visible = true
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.2)
	Audio.sfx("ui_move", -4.0)


static func _place_name(n: int) -> String:
	return ["-", "1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH"][clampi(n, 0, 8)]


func _start_event(id: String) -> void:
	if state != "roam" or not _events.has(id):
		return
	var ev: Dictionary = _events[id].ev
	if _event_lock(ev) != "":
		Audio.sfx("ui_deny")
		return
	_last_event = id
	_set_state("intro")
	Audio.sfx("ui_select")
	Audio.sfx("whoosh", -3.0)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	await tw.finished
	race = Race.new()
	add_child(race)
	race.setup(city, ev, car, traffic, _race_holder)
	race.countdown.connect(_on_countdown)
	race.go.connect(_on_go)
	race.checkpoint_hit.connect(_on_checkpoint)
	race.lap_done.connect(_on_lap)
	race.finished.connect(_on_race_finished)
	city.preload_around(car.global_position)
	minimap.route = race.path.pts
	if race.path.closed:
		var loop := race.path.pts.duplicate()
		loop.append(race.path.pts[0])
		minimap.route = loop
	# short cinematic: sweep around the grid with the event title
	_cine_center = race.path.pts[0] - race.path.dir_at(0.0) * 9.0
	_cine_t = 0.0
	_cine.make_current()
	_set_bars(true)
	_hud_driving(false)
	(_title_card.get_node("Name") as Label).text = ev.name
	(_title_card.get_node("Type") as Label).text = EventDB.TYPE_LABEL[ev.type]
	(_title_card.get_node("Type") as Label).add_theme_color_override("font_color", EventDB.TYPE_COLOR[ev.type])
	_title_card.visible = true
	_title_card.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.4)
	tw2.parallel().tween_property(_title_card, "modulate:a", 1.0, 0.4)
	tw2.tween_interval(2.3)
	tw2.tween_property(_title_card, "modulate:a", 0.0, 0.3)
	await tw2.finished
	if race == null:
		return
	_title_card.visible = false
	_set_bars(false)
	cam.snap_behind()
	cam.make_current()
	_hud_driving(true)
	_set_state("countdown")
	race.run_countdown()


func _on_track_changed(title: String, artist: String) -> void:
	if not is_instance_valid(_radio_toast) or title == "":
		return
	_radio_toast.text = "%s\n%s  •  %s" % [Soundtrack.STATION, title.to_upper(), artist.to_upper()]
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_property(_radio_toast, "modulate:a", 1.0, 0.3)
	_toast_tw.tween_interval(4.5)
	_toast_tw.tween_property(_radio_toast, "modulate:a", 0.0, 0.8)


func _on_countdown(n: int) -> void:
	Audio.sfx("beep_lo", -4.0 if Audio.voice("count_%d" % n, 2.0) else 0.0)
	if n == 3:
		# the music sinks under the countdown and comes back on GO
		Audio.music_filter(650.0)
		Audio.duck_music(-7.0, 0.5)
	_show_banner(str(n), 0.45)


func _on_go() -> void:
	_set_state("race")
	Audio.sfx("beep_hi", -4.0 if Audio.voice("go", 3.0) else 0.0)
	Audio.music_state("race", 0.3)
	Audio.music_filter(20000.0)
	Audio.duck_music(0.0, 0.25)
	_show_banner("GO!", 0.9)
	_place_marker(race.next_checkpoint(), "1" if race.cps.size() > 1 else "FINISH", UI.CYAN)


func _on_checkpoint(index: int, total: int) -> void:
	Audio.sfx("checkpoint", -2.0)
	var last := race.is_last_checkpoint()
	_place_marker(race.next_checkpoint(), "FINISH" if last else str(index + 1), UI.GREEN if last else UI.CYAN)


func _on_lap(lap: int, laps: int) -> void:
	Audio.sfx("checkpoint", 0.0, 1.25)
	_show_banner("FINAL LAP" if lap == laps - 1 else "LAP %d" % (lap + 1), 1.0)
	_place_marker(race.next_checkpoint(), "1", UI.CYAN)


func _on_race_finished(res: Dictionary) -> void:
	_set_state("done")
	Audio.sting(res.place == 1 or (res.medal != "" and res.place <= 3))
	Audio.voice("win" if res.place == 1 else ("podium" if res.place <= 3 else "lose"), 2.0)
	_pos_label.text = ""
	(_info.get_parent() as Control).visible = false
	Audio.sfx("finish")
	car.input_enabled = false
	_hud_driving(false)
	_cine_center = car.global_position
	_cine_t = 0.0
	_cine.make_current()
	_set_bars(true)
	var win: bool = res.place == 1
	_show_banner(("WINNER!" if win else _place_name(res.place) + " PLACE") if res.medal == "" else res.medal, 1.6)
	await get_tree().create_timer(2.4).timeout
	if state != "done":
		return
	_set_bars(false)
	_show_result(res)


func _end_race(to_roam := true) -> void:
	if race:
		race.cleanup()
		race.queue_free()
		race = null
	minimap.route = PackedVector3Array()
	minimap.target = null
	_marker.visible = false
	_result_panel.visible = false
	_title_card.visible = false
	_set_bars(false)
	car.input_enabled = true
	car.hold = false
	cam.make_current()
	_hud_driving(true)
	_near_event = "?"          # so the card for the event you are parked on shows again
	Audio.music_state("roam", 1.0)
	Audio.music_filter(20000.0)
	Audio.duck_music(0.0, 1.0)
	if to_roam:
		_set_state("roam")


func _retry_event() -> void:
	var id := _last_event
	_end_race(true)
	if id != "":
		_start_event(id)


func _set_bars(on: bool) -> void:
	for b in _bars:
		create_tween().tween_property(b, "custom_minimum_size:y", 70.0 if on else 0.0, 0.3)


func _hud_driving(on: bool) -> void:
	for n in _drive_ui:
		n.visible = on


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
	if minimap:
		minimap.target = pos
	_marker.visible = true
	_marker.position = pos
	_marker_label.text = text
	_marker_label.modulate = Color(color.r * 2.0 + 0.3, color.g * 2.0 + 0.3, color.b * 2.0 + 0.3)
	_marker_mat.albedo_color = color


func _spawn_traffic() -> void:
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(city, car, [5, 8, 11][GFX.index], [2, 3, 4][GFX.index])
	if minimap:
		minimap.traffic = traffic


# ====================================================================== state
func _set_state(st: String) -> void:
	state = st
	if st != "done":
		(_info.get_parent() as Control).visible = true
	match st:
		"roam":
			_info.text = "FREE ROAM  •  " + city.district_name(car.global_position)
			_timer.text = ""
			_pos_label.text = ""
			_best.text = "REP %d   •   %s" % [Game.rep(), CarDB.money(Game.money())]
		"intro", "countdown":
			_card.visible = false
			_near_event = ""
			_info.text = race.ev.name if race else ""
			_timer.text = ""
			_best.text = ""
	if minimap:
		_refresh_event_markers()


func _physics_process(_dt: float) -> void:
	if race and state == "race":
		run_time = race.time


func _process(_dt: float) -> void:
	var p := car.global_position
	if state == "roam":
		_update_event_card()
	elif state == "race" and race:
		var bits := []
		if race.laps > 1:
			bits.append("LAP %d / %d" % [mini(race.lap + 1, race.laps), race.laps])
		bits.append("CHECKPOINT %d / %d" % [mini(race.cp_index + 1, race.cps.size()), race.cps.size()])
		_info.text = "   •   ".join(bits)
		_timer.text = _fmt(race.time)
		if race.ev.type == "trial":
			_pos_label.text = ""
			_best.text = "GOLD %s   SILVER %s   BRONZE %s" % [_fmt(race.trial_times[0]), _fmt(race.trial_times[1]), _fmt(race.trial_times[2])]
		else:
			_pos_label.text = "%s / %d" % [_place_name(race.position()), race.field_size()]
	# cinematic camera: slow orbit around the grid / the finished car
	if _cine.current:
		_cine_t += _dt
		var a := 0.9 + _cine_t * 0.42
		var r := 9.5 - minf(_cine_t, 3.0) * 0.6
		_cine.position = _cine_center + Vector3(sin(a) * r, 1.5 + _cine_t * 0.25, cos(a) * r)
		_cine.look_at(_cine_center + Vector3(0, 0.7, 0), Vector3.UP)
	# acoustics and district name follow the car
	_space_t -= _dt
	if _space_t <= 0.0:
		_space_t = 0.3
		Audio.set_space(city.space_at(p))
		var dn: String = city.district_name(p)
		if dn != _district:
			_district = dn
			if state == "roam":
				_show_banner(dn, 1.6)
				_info.text = "FREE ROAM  •  " + dn
	# marker pulse
	if _marker.visible:
		var ring := _marker.get_node("Ring") as Node3D
		var sc := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.006)
		ring.scale = Vector3(sc, 0.2, sc)
	# speed post effect
	var sp := clampf(absf(car.speed) / car.vmax, 0.0, 1.2)
	var amt := clampf((sp - 0.7) * 1.6, 0.0, 0.5) + (0.55 if car.using_nitro else 0.0)
	post.use_blur = GFX.index == 2
	post.amount = lerpf(post.amount, amt, 0.15)
	if Input.is_action_just_pressed("camera"):
		_toggle_cam()
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()
	if Input.is_action_just_pressed("ui_accept") and state == "roam" and _near_event != "" and _events.has(_near_event):
		_start_event(_near_event)
	for k in _steer_keys:
		k.visible = int(Game.setting("steer_mode", 0)) == 0 and _gauge.visible


static func _fmt(t: float) -> String:
	var m := int(t / 60.0)
	return "%02d:%05.2f" % [m, t - m * 60.0]


func _on_crash(force: float) -> void:
	Audio.sfx("crash", clampf(-12.0 + force * 0.5, -12.0, 0.0), randf_range(0.85, 1.1))
	cam.shake(clampf(force * 0.012, 0.05, 0.35))


func _toggle_cam() -> void:
	cam.toggle()
	engine_audio.set_view(["chase", "hood", "cabin"][cam.mode])
	_show_banner(["CHASE CAM", "HOOD CAM", "COCKPIT CAM"][cam.mode], 1.0)
	Audio.sfx("ui_move")


func _restart() -> void:
	## Pause menu: restart the race, or in free roam put the car back on the road.
	if race:
		_retry_event()
		return
	var p := car.global_position
	var gx := clampf(round((p.x - city.x0) / City.PITCH), 0, OpenWorld.NX)
	var road_pos := Vector3(city.x0 + gx * City.PITCH + 1.9, 0, clampf(p.z, city.z0 + 20.0, city.z1 - 20.0))
	car.reset_to(road_pos, 0.0)
	car.nitro = 1.0


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
	var rk := TouchKey.make("", "RADIO", UI.MAGENTA, Vector2(104, 64))
	rk.toggle_only = true
	rk.round_shape = false
	rk.position = Vector2(184, 16)
	rk.tapped.connect(func():
		if Audio.radio_on():
			Audio.radio_next()
		else:
			Audio.radio_set(true))
	_hud.add_child(rk)
	_drive_ui.append(rk)
	# "now playing" toast under the position readout
	_radio_toast = UI.label("", 17, Color.WHITE)
	UI.outline(_radio_toast, 6)
	_radio_toast.position = Vector2(24, 152)
	_radio_toast.size = Vector2(520, 48)
	_radio_toast.modulate.a = 0.0
	_hud.add_child(_radio_toast)
	Audio.track_changed.connect(_on_track_changed)

	# --- top right: checkpoint arrow
	_arrow = _Arrow.new()
	_arrow.scene = self
	UI.place(_arrow, Vector2(1, 0), Vector2(-150, 14), Vector2(130, 130))
	_hud.add_child(_arrow)

	# --- minimap under the checkpoint arrow
	minimap = MiniMap.new()
	minimap.world = city
	minimap.player = car
	UI.place(minimap, Vector2(1, 0), Vector2(-196, 168), Vector2(176, 176))
	_hud.add_child(minimap)

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
	UI.place(_gauge, Vector2(0, 1), Vector2(304, -228), Vector2(240, 200))
	_hud.add_child(_gauge)

	_banner = UI.label("", 84, Color.WHITE, true)
	UI.chrome(_banner, Color(1, 1, 1), Color(1.0, 0.8, 0.15), Color(0.85, 0.25, 0.0), 100.0)
	UI.outline(_banner, 14)
	UI.place(_banner, Vector2(0.5, 0.5), Vector2(-500, -150), Vector2(1000, 110))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_hud.add_child(_banner)

	# --- race position (top left, under the pause button)
	_pos_label = UI.label("", 46, Color.WHITE, true)
	UI.chrome(_pos_label, Color(1, 1, 1), Color(1.0, 0.8, 0.15), Color(0.85, 0.25, 0.0), 54.0)
	UI.outline(_pos_label, 9)
	_pos_label.position = Vector2(22, 90)
	_pos_label.size = Vector2(260, 56)
	_hud.add_child(_pos_label)

	# --- event card (shown when parked on an event marker)
	_card = Control.new()
	_card.visible = false
	_card.modulate.a = 0.0
	UI.place(_card, Vector2(0.5, 0), Vector2(-300, 116), Vector2(600, 236))
	_hud.add_child(_card)
	var cbg := UI.panel(Color(0.02, 0.03, 0.05, 0.88), Color(1.0, 0.69, 0.0, 0.6))
	UI.full(cbg)
	_card.add_child(cbg)
	var defs := [["Type", 18, 12.0, UI.AMBER, false], ["Name", 44, 34.0, Color.WHITE, true], ["Blurb", 18, 88.0, UI.TEXT, false],
		["Info", 20, 116.0, UI.AMBER, false], ["Status", 16, 146.0, UI.DIM, false]]
	for d in defs:
		var l := UI.label("", d[1], d[3], d[4])
		l.position = Vector2(20, d[2])
		l.size = Vector2(560, d[1] + 10)
		l.name = d[0]
		_card.add_child(l)
	var gob := NeonButton.make("START RACE", Vector2(260, 52), UI.GREEN, 26)
	gob.align_left = false
	gob.filled = true
	gob.position = Vector2(320, 174)
	gob.name = "Go"
	gob.pressed.connect(func(): _start_event(_near_event))
	_card.add_child(gob)
	var ch := UI.label("DRIVE AWAY TO CANCEL", 14, Color(1, 1, 1, 0.45))
	ch.position = Vector2(20, 196)
	_card.add_child(ch)

	# --- cinematic letterbox, event title and fade
	for top_bar in [true, false]:
		var bar := UI.rect(Color.BLACK)
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top_bar else 1.0
		bar.anchor_bottom = 0.0 if top_bar else 1.0
		bar.grow_vertical = Control.GROW_DIRECTION_END if top_bar else Control.GROW_DIRECTION_BEGIN
		bar.custom_minimum_size.y = 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(bar)
		_bars.append(bar)
	_title_card = Control.new()
	_title_card.visible = false
	_title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_title_card, Vector2(0, 1), Vector2(60, -250), Vector2(900, 150))
	layer.add_child(_title_card)
	var tt := UI.label("", 24, UI.AMBER)
	tt.name = "Type"
	_title_card.add_child(tt)
	var tn := UI.label("", 78, Color.WHITE, true)
	UI.chrome(tn, Color(1, 1, 1), Color(1.0, 0.8, 0.15), Color(0.85, 0.25, 0.0), 92.0)
	UI.outline(tn, 12)
	tn.position = Vector2(0, 30)
	tn.size = Vector2(900, 100)
	tn.name = "Name"
	_title_card.add_child(tn)
	_fade = UI.full(UI.rect(Color(0, 0, 0, 0)))
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_drive_ui = [left, right, gas, brk, nos, hb, _gauge, minimap, _arrow, pk, ck]

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
		["RESTART RACE / RESET CAR", func():
			_toggle_pause()
			_restart()],
		["LEAVE RACE", func():
			_toggle_pause()
			if race:
				_end_race()],
		["RADIO: ON", func():
			Audio.radio_set(not Audio.radio_on())
			_radio_btn.set_caption("RADIO: ON" if Audio.radio_on() else "RADIO: OFF"), UI.MAGENTA],
		["BACK TO GARAGE", func(): _leave("garage"), UI.CYAN],
		["MAIN MENU", func(): _leave("menu")],
	], 170.0)
	for c in _pause_panel.get_children():
		if c is NeonButton and (c as NeonButton).caption.begins_with("RADIO"):
			_radio_btn = c
	var hint := UI.label("KEYBOARD: WASD / ARROWS  •  SPACE HANDBRAKE  •  SHIFT NITRO  •  C CAMERA  •  ENTER START RACE", 16, UI.DIM)
	UI.place(hint, Vector2(0.5, 1), Vector2(-500, -50), Vector2(1000, 24))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_panel.add_child(hint)


func _build_result(layer: CanvasLayer) -> void:
	_result_panel = _menu_panel(layer, "RACE OVER", UI.GREEN)
	var defs := [["Place", 44, 150.0], ["Time", 56, 198.0], ["Pay", 28, 264.0]]
	for d in defs:
		var l := UI.label("", d[1], Color.WHITE, true)
		UI.outline(l, 8)
		UI.place(l, Vector2(0.5, 0), Vector2(-620, d[2]), Vector2(700, d[1] + 14))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.name = d[0]
		_result_panel.add_child(l)
	var tb := UI.label("", 24, UI.TEXT)
	UI.outline(tb, 5)
	UI.place(tb, Vector2(0.5, 0), Vector2(120, 160), Vector2(420, 260))
	tb.name = "Table"
	_result_panel.add_child(tb)
	var y := 330.0
	var btns := [["RACE AGAIN", _retry_event, UI.GREEN], ["FREE ROAM", func(): _end_race(), UI.AMBER], ["BACK TO GARAGE", func(): _leave("garage"), UI.CYAN]]
	for d in btns:
		var b := NeonButton.make(d[0], Vector2(380, 58), d[2], 28)
		b.align_left = false
		UI.place(b, Vector2(0.5, 0), Vector2(-460, y), Vector2(380, 58))
		b.pressed.connect(d[1])
		_result_panel.add_child(b)
		y += 68.0


func _show_result(res: Dictionary) -> void:
	var title := _result_panel.get_node("Title") as Label
	var place := _result_panel.get_node("Place") as Label
	var col := UI.TEXT
	if res.medal != "":
		title.text = "TIME TRIAL"
		place.text = res.medal
		col = [Color(1.0, 0.82, 0.2), Color(0.8, 0.85, 0.9), Color(0.85, 0.5, 0.25), UI.DIM][res.place - 1]
	else:
		title.text = "YOU WIN" if res.place == 1 else "RACE OVER"
		place.text = "%s PLACE  OF %d" % [_place_name(res.place), res.field]
		col = [Color(1.0, 0.82, 0.2), Color(0.8, 0.85, 0.9), Color(0.85, 0.5, 0.25)][res.place - 1] if res.place <= 3 else UI.DIM
	place.add_theme_color_override("font_color", col)
	(_result_panel.get_node("Time") as Label).text = _fmt(res.time) + ("  BEST!" if res.best else "")
	var pay := "+" + CarDB.money(res.pay)
	if res.first_win:
		pay += "  (FIRST WIN BONUS)"
	if res.rep > 0:
		pay += "   +%d REP" % res.rep
	(_result_panel.get_node("Pay") as Label).text = pay
	(_result_panel.get_node("Pay") as Label).add_theme_color_override("font_color", UI.AMBER)
	var lines := ""
	var i := 1
	for row in res.table:
		lines += "%d.  %-9s %s\n" % [i, row[0], _fmt(row[1]) if row[1] >= 0.0 else "DNF"]
		i += 1
	(_result_panel.get_node("Table") as Label).text = lines if res.field > 1 else ""
	_result_panel.visible = true
	_result_panel.modulate.a = 0.0
	create_tween().tween_property(_result_panel, "modulate:a", 1.0, 0.4)


func _toggle_pause() -> void:
	if Nav.busy or _result_panel.visible:
		return
	var p := not get_tree().paused
	get_tree().paused = p
	_pause_panel.visible = p
	engine_audio.hush(p)
	Audio.music_filter(900.0 if p else 20000.0)      # the radio keeps playing, muffled, behind the menu
	if p:
		Controls.release_all()
		_radio_btn.set_caption("RADIO: ON" if Audio.radio_on() else "RADIO: OFF")
	Audio.sfx("ui_select" if p else "ui_back", -4.0)


func _leave(dest: String) -> void:
	engine_audio.hush(true)
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


func dev_cam() -> void:
	_toggle_cam()


func dev_pause() -> void:
	_toggle_pause()


func dev_finish() -> void:
	if race:
		race.time = 44.0
		race._finish()


var _dev_unlock := false


func dev_event(id: String) -> void:
	_dev_unlock = true
	_start_event(id)


func dev_race_log() -> void:
	if race == null:
		print("RACE none")
		return
	var out := "RACE t=%.1f state=%s pos=%d/%d cp=%d/%d lap=%d player_s=%.0f/%.0f |" % [race.time, race.state, race.position(), race.field_size(), race.cp_index, race.cps.size(), race.lap, race.player_progress(), race.path.total]
	for r in race.rivals:
		out += " %s s=%.0f lap=%d v=%.0f%s" % [r.name, r.driver.s, r.driver.lap, r.car.speed_mph(), " FIN %.1f" % r.finish_time if r.finish_time >= 0.0 else ""]
		if OS.get_environment("AH_POS") != "":
			var tp: Vector3 = race.path.pos_at(r.driver.s)
			out += " @(%.0f,%.1f,%.0f) line(%.0f,%.0f)" % [r.car.global_position.x, r.car.global_position.y, r.car.global_position.z, tp.x, tp.z]
	print(out)


## Test helper: the player's car is driven by the same AI as the rivals.
func dev_autopilot() -> void:
	if race == null:
		return
	var drv := RaceDriver.new()
	car.add_child(drv)
	drv.attach(car, race.path)
	drv.world = city
	drv.skill = 0.95
	drv.active = true
	var obs: Array = []
	for r in race.rivals:
		obs.append(r.car)
	for t in traffic.cars:
		obs.append(t)
	drv.obstacles = obs
	race.tree_exiting.connect(func():
		car.ai = false
		drv.queue_free())


func dev_log(tag := "") -> void:
	print("SIM %s t=%.2f mph=%.1f gear=%d rpm=%.2f slip=%.1f yaw=%.0f pos=(%.0f,%.0f) nitro=%.2f state=%s" % [tag, run_time, car.speed_mph(), car.gear + 1, car.rpm, car.slip, rad_to_deg(car.rotation.y), car.global_position.x, car.global_position.z, car.nitro, state])


func dev_traffic() -> void:
	var worst := 0.0
	for t in traffic.cars:
		if t.hw_index >= 0:
			continue
		var c: Vector3 = t.global_position
		# distance from the nearest lane line of the grid
		var fx := absf(fposmod(c.x - city.x0 + City.PITCH * 0.5, City.PITCH) - City.PITCH * 0.5)
		var fz := absf(fposmod(c.z - city.z0 + City.PITCH * 0.5, City.PITCH) - City.PITCH * 0.5)
		worst = maxf(worst, minf(absf(fx - Traffic.LANE), absf(fz - Traffic.LANE)))
	print("TRAFFIC max lane error %.2f m, blocks loaded %d, lamps %d" % [worst, city.loaded_count(), city.lamp_positions.size()])


func dev_warp(x: String, z: String, yaw := "0") -> void:
	car.reset_to(Vector3(float(x), 0, float(z)), deg_to_rad(float(yaw)))


func dev_top(size := "1300", x := "0", z := "60") -> void:
	var c := Camera3D.new()
	add_child(c)
	c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.size = float(size)
	c.far = 2000.0
	c.position = Vector3(float(x), 600, float(z))
	c.rotation_degrees = Vector3(-90, 0, 0)
	c.make_current()
	_hud.visible = false
	env.fog_enabled = false
	env.ambient_light_energy = 3.0


func dev_look(x: String, y: String, z: String, tx: String, ty: String, tz: String) -> void:
	var c := Camera3D.new()
	add_child(c)
	c.far = 1500.0
	c.fov = 65.0
	c.look_at_from_position(Vector3(float(x), float(y), float(z)), Vector3(float(tx), float(ty), float(tz)), Vector3.UP)
	c.make_current()
	_hud.visible = false
	post.amount = 0.0
	post.visible = false


func dev_near(x: String, z: String) -> void:
	var p := Vector3(float(x), 0, float(z))
	for t in traffic.cars:
		var q: Vector3 = t.global_position
		if Vector2(q.x - p.x, q.z - p.z).length() < 40.0:
			print("NEAR traffic (%.0f,%.1f,%.0f) v=%.1f hw=%d blocked=%s" % [q.x, q.y, q.z, t.speed(), t.hw_index, t.blocked])
	var space := car.get_world_3d().direct_space_state
	for dx in [-8, -4, 0, 4, 8, 12]:
		var from := Vector3(p.x + dx, 1.0, p.z + 12.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 0, -30)))
		if hit:
			var cs: CollisionShape3D = hit.collider.shape_owner_get_owner(hit.collider.shape_find_owner(hit.shape))
			print("NEAR ray dx=%d hit %s at (%.0f,%.1f,%.0f) n=%s shape=%s size=%s at %s parent=%s" % [dx, hit.collider.name, hit.position.x, hit.position.y, hit.position.z, hit.normal, cs.shape, cs.shape.get("size"), cs.global_position, hit.collider.get_parent().name])


func dev_goto_event(id: String, back := "0") -> void:
	var e: Dictionary = _events[id]
	var yaw: float = e.yaw
	car.reset_to(e.pos + Vector3(sin(yaw), 0, cos(yaw)) * float(back), yaw)
	cam.snap_behind()
