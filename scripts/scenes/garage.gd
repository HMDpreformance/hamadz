extends Node3D
## Garage scene: vehicle selection + customization with live 3D preview.
## Flow: pick a group -> slot tab -> option card (previews on the car) ->
## BUY / INSTALL commits it through Game (which saves automatically).

var room: GarageRoom
var cam: OrbitCamera
var car: CarVisual
var car_mirror: CarVisual
var env: Environment

var view_car := ""              # car currently on the turntable
var preview := {}               # config being shown (installed + pending option)
var group_id := ""              # "" | cars | paint | body | wheels | perf
var slot := ""
var option := -1

var ui: Control
var _money: Label
var _name: Label
var _tag: Label
var _specline: Label
var _blurb: Label
var _stat_rows := {}
var _group_buttons := {}
var _tabs: HBoxContainer
var _cards: HBoxContainer
var _scroll: ScrollContainer
var _strip: Control
var _action: NeonButton
var _sel_name: Label
var _sel_price: Label
var _toast: Label
var _drive: NeonButton
var _owned_badge: Label
var _hint: Label
var _voice: EngineVoice
var _ind: AudioStreamPlayer
var _ind_kind := ""
var _eng_on := false
var _eng_idle := 0.0
var _rpm := 0.14
var _boost := 0.0
var _lim := 0.0
var _auto_rev := 0.0
var _was_thr := 0.0
var _pops := 0
var _pop_t := 0.0
var _turn := 0.0


func _ready() -> void:
	env = GFX.make_environment(Color(0.3, 0.32, 0.4), 0.35, Color.BLACK, 0.0, EnvKit.studio_sky())
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	room = GarageRoom.new()
	add_child(room)
	room.build()
	cam = OrbitCamera.new()
	add_child(cam)
	cam.snap("showcase")
	cam.focus("default", 1.6)
	car = CarVisual.new()
	add_child(car)
	if GFX.p.mirror:
		car_mirror = CarVisual.new()
		car_mirror.is_reflection = true
		room.mirror_root.add_child(car_mirror)
	_build_ui()
	_show_car(Game.current_car(), false)
	_select_group("")
	Audio.play_music("menu", 1.0, -9.0)
	Audio.play_ambience("garage", -3.0)
	Game.money_changed.connect(_on_money)
	GFX.changed.connect(func(): GFX.apply_environment(env))
	if not InputMap.has_action("garage_rev"):
		InputMap.add_action("garage_rev")
	_voice = EngineVoice.new()
	add_child(_voice)
	_ind = AudioStreamPlayer.new()
	_ind.bus = "Engine"
	add_child(_ind)
	Audio.set_space("garage")
	_sync_voice()
	_sync_induction()


func _unhandled_input(event: InputEvent) -> void:
	cam.handle_input(event)
	if event.is_action_pressed("ui_cancel"):
		_on_back()


func _process(delta: float) -> void:
	_turn += delta
	if _voice:
		_engine_process(delta)


func _exit_tree() -> void:
	Input.action_release("garage_rev")


func _sync_induction() -> void:
	var au := _audio_cfg()
	var kind := ""
	if au.induction == "turbo":
		kind = "turbo_spool_big" if au.turbo >= 2 else "turbo_spool"
	elif au.induction == "sc":
		kind = "sc_whine"
	if kind == _ind_kind:
		return
	_ind_kind = kind
	_ind.stop()
	if kind != "":
		_ind.stream = Audio.stream("res://audio/car/%s.wav" % kind, true)
		_ind.volume_db = -60.0
		_ind.play()
		_ind.stream_paused = true


# ====================================================================== car
func _show_car(id: String, animate := true) -> void:
	view_car = id
	preview = Game.config(id).duplicate()
	car.setup(id, preview)
	if car_mirror:
		car_mirror.setup(id, preview)
	if animate:
		Audio.sfx("whoosh", -4.0)
		car.rotation.y = -1.2
		car.scale = Vector3.ONE * 0.92
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(car, "rotation:y", 0.0, 0.7)
		tw.tween_property(car, "scale", Vector3.ONE, 0.5)
		if car_mirror:
			car_mirror.rotation.y = -1.2
			tw.tween_property(car_mirror, "rotation:y", 0.0, 0.7)
	if _voice:
		_engine_stop()
		_sync_voice()
		_sync_induction()
	_refresh_info()


func _apply_preview() -> void:
	if _voice:
		_sync_voice()
		_sync_induction()
	car.apply(preview)
	if car_mirror:
		car_mirror.apply(preview)
	_refresh_info()


# ---- engine preview: start it, hold REV, hear the installed/previewed parts
func _audio_cfg() -> Dictionary:
	return CarDB.audio_setup(view_car, preview)


func _sync_voice() -> void:
	var au := _audio_cfg()
	if _voice.profile_id != au.profile or _voice.get_child_count() == 0:
		_voice.setup(au.profile)
		if not _eng_on:
			_voice.silence()
	Audio.set_engine_cutoff([5600.0, 8200.0, 12500.0][clampi(au.exhaust, 0, 2)] * (0.85 if au.induction == "turbo" else 1.0))
	_voice.gain_db = -6.0 + au.exhaust * 2.2
	_voice.intake_db = -4.0


func _engine_start() -> void:
	if _eng_on:
		return
	_eng_on = true
	_eng_idle = 0.0
	_rpm = 0.14
	_sync_voice()
	_voice.silence()
	var sp := _voice.start_sound_path()
	if ResourceLoader.exists(sp):
		Audio.sfx(sp, -4.0, 1.0, "Engine")
	get_tree().create_timer(0.9).timeout.connect(func():
		if _eng_on:
			_voice.start(0.5))
	car.set_lights(true)


func _engine_stop() -> void:
	if not _eng_on:
		return
	_eng_on = false
	_voice.stop(0.9)


## Automatic blip after fitting a part, so the change is heard straight away.
func _rev_engine(_strength := 1.0) -> void:
	_engine_start()
	_auto_rev = 1.5


func _engine_process(dt: float) -> void:
	var held := Input.is_action_pressed("garage_rev")
	if held and not _eng_on:
		_engine_start()
	var thr := 0.0
	if held:
		thr = 1.0
	elif _auto_rev > 0.0:
		_auto_rev -= dt
		thr = 1.0 if (_auto_rev > 1.05 or (_auto_rev < 0.6 and _auto_rev > 0.25)) else 0.0
	var au := _audio_cfg()
	var p := EngineProfiles.get_profile(au.profile)
	var rate: float = p.rev_rate * 0.12
	if thr > 0.0:
		_rpm = move_toward(_rpm, 1.0, rate * dt * (1.3 - _rpm * 0.5))
		_eng_idle = 0.0
	else:
		_rpm = move_toward(_rpm, 0.14, rate * 0.75 * dt * (0.5 + _rpm))
		_eng_idle += dt
	var load := thr
	if _rpm > 0.985 and thr > 0.0:
		# on the limiter
		_lim = fmod(_lim + dt * 13.0, 1.0)
		if _lim > 0.5:
			load = 0.0
			_rpm -= dt * 0.8
	# turbo and blower follow the revs here (no road load, so boost stays modest)
	if au.induction == "turbo":
		var bt := thr * clampf((_rpm - 0.3) / 0.4, 0.0, 1.0) * 0.8
		_boost = move_toward(_boost, bt, dt * (1.6 if bt > _boost else 3.0))
		_ind.stream_paused = _boost < 0.03 or not _eng_on
		_ind.volume_db = linear_to_db(maxf(_boost * _boost * 0.5, 0.001)) - 3.0
		_ind.pitch_scale = 0.5 + _boost * 0.75 + _rpm * 0.25
		if _was_thr > 0.5 and thr < 0.5 and _boost > 0.25 and _eng_on:
			var big: bool = au.turbo >= 2
			if _boost > 0.6:
				Audio.sfx("res://audio/car/%s.wav" % ("bov_big" if big else "bov_small"), -6.0, 1.0, "Engine")
			else:
				Audio.sfx("res://audio/car/%s.wav" % ("flutter_1" if big else "flutter_2"), -7.0, 1.0, "Engine")
	elif au.induction == "sc":
		_ind.stream_paused = not _eng_on
		_ind.volume_db = linear_to_db((0.12 + 0.5 * load) * clampf(_rpm * 1.4, 0.2, 1.0)) - 3.0
		_ind.pitch_scale = 0.42 + _rpm * 1.25
	else:
		_ind.stream_paused = true
	# overrun pops when the throttle snaps shut from high revs
	if _was_thr > 0.5 and thr < 0.5 and _rpm > 0.55 and _eng_on:
		_pops = int(round(float(p.pops) * [1.0, 3.0, 5.0][clampi(au.exhaust, 0, 2)]))
		_pop_t = 0.12
	if _pops > 0 and thr < 0.5:
		_pop_t -= dt
		if _pop_t <= 0.0:
			_pops -= 1
			_pop_t = randf_range(0.07, 0.22)
			Audio.sfx("res://audio/car/pop_%d.wav" % (1 + randi() % 5), -9.0 + au.exhaust * 2.0, randf_range(0.85, 1.15), "Engine")
	_was_thr = thr
	var wob := sin(Time.get_ticks_msec() * 0.011) * float(p.idle_shake) * clampf((0.3 - _rpm) / 0.16, 0.0, 1.0)
	_voice.update(_rpm + wob, load, dt)
	# the body rocks with the engine
	if _eng_on and car.body:
		car.set_body_tilt(0.0, sin(Time.get_ticks_msec() * 0.03) * 0.0025 * (1.0 + float(p.idle_shake) * 20.0) + (_rpm - 0.14) * 0.012 * thr)
	if _eng_on and _eng_idle > 9.0:
		_engine_stop()


# ====================================================================== UI build
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = UI.full(Control.new())
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	ui.add_child(UI.crt_overlay())

	# ---- top bar
	var top := UI.rect(Color(0, 0, 0, 0.0))
	top.anchor_right = 1.0
	top.offset_bottom = 84
	ui.add_child(top)
	var top_grad := TextureRect.new()
	top_grad.texture = UI.gradient_tex([Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.0)], [0.0, 1.0])
	top_grad.anchor_right = 1.0
	top_grad.offset_bottom = 110
	top_grad.stretch_mode = TextureRect.STRETCH_SCALE
	top_grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top_grad)
	var back := NeonButton.make("BACK", Vector2(150, 46), UI.AMBER, 22)
	back.click_sound = "ui_back"
	back.position = Vector2(22, 18)
	back.pressed.connect(_on_back)
	ui.add_child(back)
	var title := UI.label("GARAGE", 44, Color.WHITE, true)
	UI.chrome(title, Color(1, 1, 1), Color(1.0, 0.75, 0.1), Color(0.8, 0.25, 0.0), 54.0)
	title.position = Vector2(196, 10)
	ui.add_child(title)
	var sub := UI.label("SYNDICATE TUNING  //  BAY 01", 16, UI.DIM)
	sub.position = Vector2(200, 62)
	ui.add_child(sub)
	# money
	var mp := Control.new()
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(mp, Vector2(1, 0), Vector2(-300, 16), Vector2(280, 54))
	ui.add_child(mp)
	var mbg := UI.panel(Color(0.03, 0.04, 0.06, 0.85), Color(1.0, 0.69, 0.0, 0.7), 0.25)
	UI.full(mbg)
	mp.add_child(mbg)
	var ml := UI.label("CASH", 15, UI.DIM)
	ml.position = Vector2(26, 5)
	mp.add_child(ml)
	_money = UI.label(CarDB.money(Game.money()), 30, UI.AMBER, true)
	_money.position = Vector2(26, 18)
	_money.size = Vector2(236, 34)
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mp.add_child(_money)

	# ---- left: groups
	var defs := [["cars", "VEHICLES"]]
	for g in CarDB.GROUPS:
		defs.append([g.id, g.label])
	var y := 112.0
	for d in defs:
		var b := NeonButton.make(d[1], Vector2(232, 52), UI.AMBER, 23)
		b.position = Vector2(22, y)
		b.pressed.connect(_select_group.bind(d[0]))
		ui.add_child(b)
		_group_buttons[d[0]] = b
		UI.pop(b, 0.05 * _group_buttons.size())
		y += 60.0
	_hint = UI.label("DRAG TO ROTATE  •  PINCH TO ZOOM", 16, Color(1, 1, 1, 0.45))
	UI.place(_hint, Vector2(0.5, 0), Vector2(-200, 92), Vector2(400, 22))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(_hint)

	# ---- right: car info + stats
	var info := Control.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(info, Vector2(1, 0), Vector2(-330, 92), Vector2(310, 390))
	ui.add_child(info)
	var ibg := UI.panel(Color(0.03, 0.04, 0.065, 0.8), Color(1, 1, 1, 0.1))
	UI.full(ibg)
	info.add_child(ibg)
	var bar := UI.rect(UI.AMBER)
	bar.size = Vector2(310, 4)
	info.add_child(bar)
	_name = UI.label("", 32, Color.WHITE, true)
	_name.position = Vector2(16, 12)
	info.add_child(_name)
	_tag = UI.label("", 16, UI.CYAN)
	_tag.position = Vector2(18, 50)
	info.add_child(_tag)
	_specline = UI.label("", 15, UI.TEXT)
	_specline.position = Vector2(18, 69)
	info.add_child(_specline)
	_owned_badge = UI.label("", 15, UI.GREEN)
	_owned_badge.position = Vector2(18, 88)
	info.add_child(_owned_badge)
	_blurb = UI.label("", 15, UI.DIM)
	_blurb.position = Vector2(18, 108)
	_blurb.size = Vector2(276, 40)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_blurb)
	var rows := [["hp", "POWER", "HP"], ["torque", "TORQUE", "LB-FT"], ["top", "TOP SPEED", "MPH"], ["accel", "0-60", "SEC"], ["handling", "HANDLING", ""]]
	var ry := 156.0
	for r in rows:
		var row := _StatRow.new()
		row.label = r[1]
		row.unit = r[2]
		row.position = Vector2(16, ry)
		row.size = Vector2(278, 44)
		info.add_child(row)
		_stat_rows[r[0]] = row
		ry += 45.0

	# ---- selection + action (right, under stats)
	var act := Control.new()
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(act, Vector2(1, 1), Vector2(-330, -226), Vector2(310, 120))
	ui.add_child(act)
	_sel_name = UI.label("", 20, Color.WHITE)
	_sel_name.size = Vector2(310, 26)
	_sel_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sel_name.clip_text = true
	UI.shadow(_sel_name)
	act.add_child(_sel_name)
	_sel_price = UI.label("", 18, UI.AMBER)
	_sel_price.position = Vector2(0, 26)
	_sel_price.size = Vector2(310, 24)
	_sel_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.shadow(_sel_price)
	act.add_child(_sel_price)
	_action = NeonButton.make("", Vector2(310, 60), UI.GREEN, 26)
	_action.position = Vector2(0, 56)
	_action.align_left = false
	_action.filled = true
	_action.click_sound = "ui_move"
	_action.pressed.connect(_on_action)
	act.add_child(_action)

	# ---- bottom strip: tabs + option cards
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.anchor_top = 1.0
	_strip.anchor_bottom = 1.0
	_strip.anchor_right = 1.0
	_strip.offset_top = -158
	_strip.offset_right = -350
	_strip.offset_left = 22
	_strip.offset_bottom = -14
	ui.add_child(_strip)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	_tabs.position = Vector2(0, 0)
	_tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_top = 50
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_strip.add_child(_scroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 6)
	_scroll.add_child(_cards)

	# ---- hold to rev the engine with whatever is fitted or being previewed
	var rk := TouchKey.make("garage_rev", "REV", UI.RED, Vector2(104, 104))
	rk.position = Vector2(64, 436)
	ui.add_child(rk)
	var rl := UI.label("HOLD TO REV", 14, Color(1, 1, 1, 0.5))
	rl.position = Vector2(70, 542)
	ui.add_child(rl)

	# ---- test drive
	_drive = NeonButton.make("TEST DRIVE", Vector2(310, 76), UI.CYAN, 34)
	_drive.align_left = false
	_drive.filled = true
	UI.place(_drive, Vector2(1, 1), Vector2(-330, -94), Vector2(310, 76))
	_drive.pressed.connect(_on_drive)
	ui.add_child(_drive)

	_toast = UI.label("", 30, Color.WHITE, true)
	UI.outline(_toast, 8)
	UI.place(_toast, Vector2(0.5, 0), Vector2(-400, 130), Vector2(800, 44))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	ui.add_child(_toast)


class _StatRow extends Control:
	var label := ""
	var unit := ""
	var value := 0.0
	var base := 0.0
	var frac := 0.0
	var base_frac := 0.0
	var text := ""
	var better := 0
	var _shown := 0.0

	func set_values(v_text: String, f: float, bf: float, cmp: int) -> void:
		text = v_text
		frac = f
		base_frac = bf
		better = cmp

	func _process(d: float) -> void:
		var old := _shown
		_shown = lerpf(_shown, frac, 1.0 - exp(-d * 8.0))
		if absf(old - _shown) > 0.0005 or true:
			queue_redraw()

	func _draw() -> void:
		var f := UI.body_font(true)
		draw_string(f, Vector2(0, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.DIM)
		var col := UI.TEXT if better == 0 else (UI.GREEN if better > 0 else UI.RED)
		var vt := text + (" " + unit if unit != "" else "")
		if better != 0:
			vt = ("▲ " if better > 0 else "▼ ") + vt
		draw_string(f, Vector2(0, 16), vt, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 19, col)
		var by := 24.0
		var bh := 10.0
		var segs := 28
		var sw := size.x / segs
		for i in segs:
			var t := (i + 0.5) / segs
			var c := Color(1, 1, 1, 0.09)
			if t <= minf(_shown, base_frac):
				c = UI.AMBER
			elif t <= _shown:
				c = UI.GREEN
			elif t <= base_frac:
				c = UI.RED
			var x := i * sw
			draw_colored_polygon(PackedVector2Array([Vector2(x + 3, by), Vector2(x + sw - 1, by), Vector2(x + sw - 4, by + bh), Vector2(x, by + bh)]), c)


# ====================================================================== UI state
func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _on_money(amount: int) -> void:
	_money.text = CarDB.money(amount)
	var tw := create_tween()
	tw.tween_property(_money, "modulate", Color(2, 2, 2), 0.08)
	tw.tween_property(_money, "modulate", Color.WHITE, 0.3)


func _toast_msg(text: String, color := Color.WHITE) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	var tw := create_tween()
	_toast.scale = Vector2(1.2, 1.2)
	_toast.pivot_offset = _toast.size * 0.5
	tw.tween_property(_toast, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(_toast, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _refresh_info() -> void:
	var d: Dictionary = CarDB.CARS[view_car]
	_name.text = d.name
	_tag.text = d.tag
	_specline.text = "%s  •  %s  •  %d KG" % [d.cyl, d.drive, d.weight]
	_blurb.text = d.blurb
	var owned := Game.owns_car(view_car)
	_owned_badge.text = ("IN YOUR GARAGE" + ("  •  ACTIVE" if view_car == Game.current_car() else "")) if owned else "NOT OWNED  •  " + CarDB.money(d.price)
	_owned_badge.add_theme_color_override("font_color", UI.GREEN if owned else UI.AMBER)
	var base := CarDB.stats(view_car, Game.config(view_car))
	var cur := CarDB.stats(view_car, preview)
	_set_stat("hp", cur.hp, base.hp, 700.0, "%d", false)
	_set_stat("torque", cur.torque, base.torque, 700.0, "%d", false)
	_set_stat("top", cur.top, base.top, 220.0, "%d", false)
	_set_stat("accel", cur.accel, base.accel, 0.0, "%.1f", true)
	_set_stat("handling", cur.handling, base.handling, 100.0, "%d", false)
	_drive.locked = not owned
	_drive.accent = UI.CYAN if owned else Color(0.4, 0.45, 0.5)
	_drive.queue_redraw()


func _set_stat(key: String, v: float, b: float, max_v: float, fmt: String, invert: bool) -> void:
	var f := v / max_v if not invert else clampf((8.0 - v) / 6.0, 0.0, 1.0)
	var bf := b / max_v if not invert else clampf((8.0 - b) / 6.0, 0.0, 1.0)
	var cmp := 0
	if absf(v - b) > 0.001:
		cmp = 1 if (v > b) != invert else -1
	_stat_rows[key].set_values(fmt % v, clampf(f, 0.0, 1.0), clampf(bf, 0.0, 1.0), cmp)


func _select_group(id: String) -> void:
	# drop any un-bought preview when leaving a slot
	if view_car != "" and Game.owns_car(view_car) or view_car != "":
		preview = Game.config(view_car).duplicate()
		_apply_preview()
	group_id = id
	for k in _group_buttons:
		_group_buttons[k].selected = (k == id)
	_clear(_tabs)
	slot = ""
	option = -1
	if id == "":
		_fill_cards()
		cam.focus("default")
		return
	if id == "cars":
		_fill_cards()
		cam.focus("default")
		return
	var g: Dictionary
	for gg in CarDB.GROUPS:
		if gg.id == id:
			g = gg
	for s in g.slots:
		var tb := NeonButton.make(CarDB.parts()[s].label, Vector2(0, 42), UI.CYAN, 15)
		tb.custom_minimum_size = Vector2(UI.title_font().get_string_size(CarDB.parts()[s].label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 46, 42)
		tb.click_sound = "ui_move"
		tb.pressed.connect(_select_slot.bind(s))
		tb.set_meta("slot", s)
		_tabs.add_child(tb)
	_select_slot(g.slots[0])


func _select_slot(s: String) -> void:
	preview = Game.config(view_car).duplicate()
	_apply_preview()
	slot = s
	option = int(preview[s])
	for tb in _tabs.get_children():
		tb.selected = tb.get_meta("slot") == s
	cam.focus(CarDB.parts()[s].cam)
	_fill_cards()


func _fill_cards() -> void:
	_clear(_cards)
	_scroll.scroll_horizontal = 0
	if group_id == "":
		_sel_name.text = ""
		_sel_price.text = ""
		_action.visible = false
		return
	_action.visible = true
	if group_id == "cars":
		for id in CarDB.CAR_ORDER:
			var d: Dictionary = CarDB.CARS[id]
			var b := NeonButton.make(d.name, Vector2(250, 84), UI.AMBER, 22)
			b.sub = "ACTIVE" if id == Game.current_car() else ("OWNED" if Game.owns_car(id) else CarDB.money(d.price))
			b.selected = id == view_car
			b.click_sound = "ui_move"
			b.pressed.connect(_on_car_card.bind(id))
			_cards.add_child(b)
		_update_action()
		return
	var opts: Array = CarDB.parts()[slot].options
	var installed := int(Game.config(view_car)[slot])
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := NeonButton.make(o.name, Vector2(204, 84), UI.AMBER, 18)
		if o.has("swatch"):
			b.swatch = o.swatch if o.swatch.a > 0.0 and (o.swatch.r + o.swatch.g + o.swatch.b) > 0.0 else Color(0.1, 0.1, 0.1, 1.0)
			b.swatch.a = 1.0
		if i == installed:
			b.sub = "INSTALLED"
		elif Game.owns_part(view_car, slot, i):
			b.sub = "OWNED"
		else:
			b.sub = CarDB.money(o.price) if o.price > 0 else "FREE"
		b.selected = i == option
		b.click_sound = "ui_move"
		b.pressed.connect(_on_option_card.bind(i))
		_cards.add_child(b)
	_update_action()


func _update_action() -> void:
	if group_id == "cars":
		var d: Dictionary = CarDB.CARS[view_car]
		_sel_name.text = d.name
		if view_car == Game.current_car():
			_sel_price.text = "YOUR ACTIVE RIDE"
			_action.set_caption("ACTIVE")
			_action.accent = Color(0.35, 0.4, 0.45)
		elif Game.owns_car(view_car):
			_sel_price.text = "OWNED"
			_action.set_caption("SELECT CAR")
			_action.accent = UI.GREEN
		else:
			_sel_price.text = CarDB.money(d.price)
			_action.set_caption("BUY CAR")
			_action.accent = UI.AMBER if Game.money() >= d.price else UI.RED
		return
	if slot == "":
		return
	var o: Dictionary = CarDB.parts()[slot].options[option]
	var installed := int(Game.config(view_car)[slot])
	_sel_name.text = "%s: %s" % [CarDB.parts()[slot].label, o.name.to_upper()]
	if not Game.owns_car(view_car):
		_sel_price.text = "BUY THIS CAR TO MODIFY IT"
		_action.set_caption("LOCKED")
		_action.accent = Color(0.35, 0.4, 0.45)
	elif option == installed:
		_sel_price.text = "CURRENTLY ON THE CAR"
		_action.set_caption("INSTALLED")
		_action.accent = Color(0.35, 0.4, 0.45)
	elif Game.owns_part(view_car, slot, option):
		_sel_price.text = "OWNED"
		_action.set_caption("INSTALL")
		_action.accent = UI.GREEN
	else:
		_sel_price.text = CarDB.money(o.price)
		_action.set_caption("BUY + INSTALL")
		_action.accent = UI.AMBER if Game.money() >= o.price else UI.RED


func _on_car_card(id: String) -> void:
	if id != view_car:
		_show_car(id)
	for i in _cards.get_child_count():
		_cards.get_child(i).selected = CarDB.CAR_ORDER[i] == id
	_update_action()


func _on_option_card(i: int) -> void:
	option = i
	preview = Game.config(view_car).duplicate()
	preview[slot] = i
	_apply_preview()
	for k in _cards.get_child_count():
		_cards.get_child(k).selected = k == i
	_update_action()


func _on_action() -> void:
	if group_id == "cars":
		if view_car == Game.current_car():
			return
		if Game.owns_car(view_car):
			Game.select_car(view_car)
			_rev_engine()
			_toast_msg("ACTIVE RIDE: " + CarDB.CARS[view_car].name, UI.GREEN)
		elif Game.buy_car(view_car):
			Game.select_car(view_car)
			Audio.sfx("purchase")
			_rev_engine()
			_toast_msg("PURCHASED  •  SAVED", UI.GREEN)
		else:
			Audio.sfx("ui_deny")
			_toast_msg("NOT ENOUGH CASH", UI.RED)
		_fill_cards()
		_refresh_info()
		return
	if slot == "" or option < 0:
		return
	var installed := int(Game.config(view_car)[slot])
	if option == installed:
		return
	var had := Game.owns_part(view_car, slot, option)
	match Game.install_part(view_car, slot, option):
		"ok":
			if not had:
				Audio.sfx("purchase")
			Audio.sfx("install", -2.0)
			_toast_msg("INSTALLED  •  SAVED" if had else "PURCHASED + INSTALLED", UI.GREEN)
			if slot in ["engine", "turbo", "exhaust"]:
				get_tree().create_timer(0.7).timeout.connect(_rev_engine)
			# little bounce on the car
			var tw := create_tween()
			tw.tween_property(car.body, "position:y", car.body.position.y - 0.03, 0.08)
			tw.tween_property(car.body, "position:y", car.body.position.y, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		"poor":
			Audio.sfx("ui_deny")
			_toast_msg("NOT ENOUGH CASH", UI.RED)
		"locked":
			Audio.sfx("ui_deny")
			_toast_msg("BUY THIS CAR FIRST", UI.RED)
	preview = Game.config(view_car).duplicate()
	_apply_preview()
	_fill_cards()


func _on_drive() -> void:
	if not Game.owns_car(view_car):
		_toast_msg("BUY THIS CAR FIRST", UI.RED)
		return
	if view_car != Game.current_car():
		Game.select_car(view_car)
	Nav.goto("drive", {}, "HITTING THE STREETS")


func _on_back() -> void:
	if group_id != "":
		_select_group("")
		return
	Nav.goto("menu")


# ====================================================================== dev hooks
func dev_group(id: String, s := "", opt := "-1") -> void:
	_select_group(id)
	if s != "":
		_select_slot(s)
	if int(opt) >= 0:
		_on_option_card(int(opt))


func dev_car(id: String) -> void:
	_select_group("cars")
	_on_car_card(id)


func dev_action() -> void:
	_on_action()
