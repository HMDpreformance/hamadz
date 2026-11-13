extends Node3D
## Car Lot: buy and pick cars in a photographic workshop. A glossy 3D car sits
## on a generated backdrop (textures/showroom_backdrop.jpg) whose floor is
## re-projected in 3D so the car can reflect in it. Bold chrome HUD on top:
## car carousel with class letters, price, three stat bars, paint changer.

const CLASS_COLORS := {"D": Color(1.0, 0.78, 0.2), "C": Color(0.35, 0.9, 1.0), "B": Color(0.45, 1.0, 0.45), "A": Color(1.0, 0.45, 0.2), "S": Color(1.0, 0.25, 0.6)}
const CATEGORY := {"tuner": "TUNERS", "rotary": "TUNERS", "muscle": "MUSCLE", "classic": "LOWRIDERS", "sedan": "LUXURY", "suv": "LUXURY", "euro": "EXOTICS", "exotic": "EXOTICS"}
const BAR_COLORS := [Color(0.95, 0.08, 0.06), Color(1.0, 0.45, 0.05), Color(1.0, 0.85, 0.1)]

static var _thumbs := {}         # car id -> Texture2D (rendered once per session)

var car: CarVisual
var car_mirror: CarVisual
var cam: Camera3D
var env: Environment
var stage: PhotoStage

var index := 0                   # position in CarDB.CAR_ORDER
var paint := 0                   # paint shown on the car
var _yaw := 0.0
var _yaw_target := 0.0
var _drag := false
var _idle := 0.0
var _t := 0.0
var _confirm_t := 0.0
var _from := "menu"

var ui: Control
var _name: Label
var _plate: Control
var _class_l: Label
var _thumb: TextureRect
var _price: Label
var _side := []                  # [{root, tex, cls, offset}]
var _bars := []                  # StatBar
var _bar_vals := []              # Label
var _class_line: Label
var _cash: Label
var _paint_name: Label
var _bottom_name: Label
var _buy: HintButton
var _toast: Label


func _ready() -> void:
	_from = Nav.args.get("from", "menu") if Nav.args is Dictionary else "menu"
	_build_world()
	_build_ui()
	index = maxi(CarDB.CAR_ORDER.find(Game.current_car()), 0)
	_show(index, false)
	Audio.music_state("garage")
	Audio.play_ambience("garage", -6.0)
	Game.money_changed.connect(func(_m): _cash.text = CarDB.money(Game.money()))
	GFX.changed.connect(func(): GFX.apply_environment(env))
	_render_thumbs()
	var vp := get_tree().root
	vp.msaa_3d = Viewport.MSAA_4X if GFX.index >= 1 else Viewport.MSAA_2X
	vp.scaling_3d_scale = 1.0


func _exit_tree() -> void:
	GFX.set_preset(GFX.index)


# ====================================================================== world
func _build_world() -> void:
	stage = PhotoStage.new()
	add_child(stage)
	stage.build()
	env = stage.env
	cam = Camera3D.new()
	cam.fov = PhotoStage.CAM_FOV
	cam.position = PhotoStage.CAM_POS
	cam.rotation_degrees = Vector3(PhotoStage.CAM_PITCH, 0, 0)
	add_child(cam)
	cam.make_current()
	car = CarVisual.new()
	add_child(car)
	stage.tracked = car
	if GFX.p.mirror:
		car_mirror = CarVisual.new()
		car_mirror.is_reflection = true
		stage.mirror_root.add_child(car_mirror)


func _process(delta: float) -> void:
	_t += delta
	_idle += delta
	if not _drag and _idle > 3.0:
		_yaw_target = lerpf(_yaw_target, 0.0, delta * 0.8)
	_yaw = lerpf(_yaw, _yaw_target, 1.0 - exp(-delta * 8.0))
	var base := deg_to_rad(-122.0)
	car.rotation.y = base + _yaw
	if car_mirror:
		car_mirror.rotation.y = car.rotation.y
	# slow breathing camera
	cam.position.x = sin(_t * 0.23) * 0.18
	cam.position.y = 1.55 + sin(_t * 0.31) * 0.04
	if _confirm_t > 0.0:
		_confirm_t -= delta
		if _confirm_t <= 0.0:
			_update_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		_drag = event.pressed
		_idle = 0.0
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and _drag):
		_yaw_target += event.relative.x * 0.008
		_idle = 0.0
	if event.is_action_pressed("ui_cancel"):
		_on_back()
	elif event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)
	elif event.is_action_pressed("ui_accept"):
		_on_buy()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_paint_step(-1)
		elif event.keycode == KEY_E:
			_paint_step(1)


# ====================================================================== data
static func class_of(id: String, cfg: Dictionary) -> String:
	var r := CarDB.rating(id, cfg)
	if r >= 700:
		return "S"
	if r >= 600:
		return "A"
	if r >= 520:
		return "B"
	if r >= 460:
		return "C"
	return "D"


static func scores(id: String, cfg: Dictionary) -> Array:
	## 0..10 scores for acceleration, top speed, handling.
	var s := CarDB.stats(id, cfg)
	return [
		clampf((9.0 - s.accel) / 6.6 * 10.0, 0.3, 10.0),
		clampf((s.top - 95.0) / 125.0 * 10.0, 0.3, 10.0),
		clampf(s.handling / 10.0, 0.3, 10.0),
	]


func _cfg_for(id: String) -> Dictionary:
	var c: Dictionary = Game.config(id).duplicate()
	c["paint"] = paint
	return c


func _show(i: int, animate := true) -> void:
	index = posmod(i, CarDB.CAR_ORDER.size())
	var id: String = CarDB.CAR_ORDER[index]
	paint = int(Game.config(id).paint)
	var c := _cfg_for(id)
	car.setup(id, c)
	car.set_lights(true)
	if car_mirror:
		car_mirror.setup(id, c)
	if animate:
		Audio.sfx("whoosh", -6.0)
		_yaw = -0.9
		_yaw_target = 0.0
		car.position.x = -0.6
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(car, "position:x", 0.0, 0.45)
		if car_mirror:
			car_mirror.position.x = -0.6
			create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(car_mirror, "position:x", 0.0, 0.45)
	_confirm_t = 0.0
	_refresh()


func _step(d: int) -> void:
	Audio.sfx("ui_move", -4.0)
	_show(index + d)
	UI.pop(_plate, 0.0, Vector2(40 * d, 0), 0.25)


func _paint_step(d: int) -> void:
	var id: String = CarDB.CAR_ORDER[index]
	var n := CarDB.PAINTS.size()
	if Game.owns_car(id):
		# owned cars cycle through the colours already bought for them
		var owned: Array = Game.data.owned_parts[id]["paint"].duplicate()
		owned.sort()
		var k := owned.find(paint)
		paint = int(owned[posmod(k + d, owned.size())])
		Game.data.configs[id]["paint"] = paint
		Game.save_game()
	else:
		paint = posmod(paint + d, n)
	Audio.sfx("ui_move", -4.0)
	var c := _cfg_for(id)
	car.apply(c)
	if car_mirror:
		car_mirror.apply(c)
	_paint_name.text = CarDB.PAINTS[paint].name.to_upper()


# ====================================================================== actions
func _on_buy() -> void:
	var id: String = CarDB.CAR_ORDER[index]
	if Game.owns_car(id):
		if Game.current_car() != id:
			Game.select_car(id)
			Audio.sfx("ui_select", -2.0)
			_flash("NOW DRIVING: " + CarDB.CARS[id].name, UI.GREEN)
		_refresh()
		return
	var price: int = CarDB.CARS[id].price
	if Game.money() < price:
		Audio.sfx("ui_deny", -2.0)
		_flash("NOT ENOUGH CASH  -  NEED " + CarDB.money(price - Game.money()) + " MORE", UI.RED)
		return
	if _confirm_t <= 0.0:
		_confirm_t = 3.0
		Audio.sfx("ui_move", -2.0)
		_update_buttons()
		return
	if Game.buy_car(id):
		var own: Array = Game.data.owned_parts[id]["paint"]
		if not own.has(paint):
			own.append(paint)
		Game.data.configs[id]["paint"] = paint
		Game.select_car(id)
		Game.save_game()
		Audio.sfx("purchase", -1.0)
		_flash("SOLD!  " + CarDB.CARS[id].name + " IS YOURS", UI.AMBER)
	_confirm_t = 0.0
	_refresh()


func _on_back() -> void:
	if Nav.busy:
		return
	Audio.sfx("ui_back", -3.0)
	if _from == "garage":
		Nav.goto("garage", {}, "ENTERING GARAGE")
	else:
		Nav.goto("menu", {}, "MAIN MENU")


func _flash(text: String, color: Color) -> void:
	_toast.text = text
	_toast.modulate = color
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


# ====================================================================== thumbnails
func _render_thumbs() -> void:
	## Renders every car once into a small off-screen viewport for the carousel.
	var todo := []
	for id in CarDB.CAR_ORDER:
		if not _thumbs.has(id):
			todo.append(id)
	if todo.is_empty():
		_refresh()
		return
	var sv := SubViewport.new()
	sv.size = Vector2i(320, 180)
	sv.transparent_bg = true
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.sky = env.sky
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = e
	sv.add_child(we)
	var c := Camera3D.new()
	c.fov = 30.0
	c.position = Vector3(0, 1.5, 7.4)
	c.rotation_degrees = Vector3(-8, 0, 0)
	sv.add_child(c)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-50, 30, 0)
	l.light_energy = 1.4
	sv.add_child(l)
	var tc := CarVisual.new()
	tc.rotation.y = deg_to_rad(-122.0)
	sv.add_child(tc)
	for id in todo:
		var cfg: Dictionary = Game.config(id)
		tc.setup(id, cfg)
		tc.set_lights(false)
		if tc._shadow:
			tc._shadow.visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
		var img := sv.get_texture().get_image()
		_thumbs[id] = ImageTexture.create_from_image(img)
		_refresh_carousel()
	sv.queue_free()


# ====================================================================== UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = UI.full(Control.new())
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# checker bands top + bottom, chrome frame between them
	var top_band := MosaicBand.new()
	top_band.anchor_right = 1.0
	top_band.offset_bottom = 64
	ui.add_child(top_band)
	var bot_band := MosaicBand.new()
	bot_band.anchor_top = 1.0
	bot_band.anchor_bottom = 1.0
	bot_band.anchor_right = 1.0
	bot_band.offset_top = -78
	ui.add_child(bot_band)
	var frame := ChromeFrame.new()
	UI.full(frame)
	frame.offset_top = 52
	frame.offset_bottom = -70
	frame.offset_left = 6
	frame.offset_right = -6
	ui.add_child(frame)

	# breadcrumb tab
	var crumb := UI.label(("GARAGE" if _from == "garage" else "MAIN MENU") + "  \\  CAR LOT", 30, Color.WHITE, true, false)
	UI.chrome(crumb, Color(1, 1, 1), Color(0.86, 0.88, 0.92), Color(0.55, 0.58, 0.64), 36.0)
	UI.outline(crumb, 6)
	crumb.position = Vector2(64, 14)
	ui.add_child(crumb)

	# ---- carousel (top centre)
	var cx := Control.new()
	cx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(cx, Vector2(0.5, 0), Vector2(-640, 0), Vector2(1280, 300))
	ui.add_child(cx)
	var arc := CarouselArc.new()
	arc.position = Vector2(0, 0)
	arc.size = Vector2(1280, 300)
	cx.add_child(arc)
	var tab := NameTab.new()
	tab.position = Vector2(470, 60)
	tab.size = Vector2(340, 48)
	cx.add_child(tab)
	_name = UI.label("", 30, Color(0.35, 0.9, 1.0), true, false)
	UI.outline(_name, 5)
	_name.position = Vector2(470, 62)
	_name.size = Vector2(340, 44)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cx.add_child(_name)
	_plate = GoldPlate.new()
	_plate.position = Vector2(500, 108)
	_plate.size = Vector2(280, 92)
	cx.add_child(_plate)
	_class_l = UI.label("D", 56, Color.WHITE, true)
	UI.outline(_class_l, 6)
	_class_l.position = Vector2(26, 10)
	_plate.add_child(_class_l)
	_thumb = TextureRect.new()
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.position = Vector2(76, 2)
	_thumb.size = Vector2(160, 90)
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_thumb)
	var pill := PricePill.new()
	pill.position = Vector2(478, 204)
	pill.size = Vector2(324, 52)
	cx.add_child(pill)
	_price = UI.label("", 32, Color.WHITE, true, false)
	UI.chrome(_price, Color(1, 1, 1), Color(0.92, 0.94, 0.98), Color(0.6, 0.65, 0.75), 40.0)
	UI.outline(_price, 6)
	_price.position = Vector2(478, 208)
	_price.size = Vector2(324, 44)
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cx.add_child(_price)
	# neighbours on the arc: -2, -1, +1, +2
	var spots := [[-2, Vector2(150, 150), 0.62], [-1, Vector2(300, 98), 0.78], [1, Vector2(860, 98), 0.78], [2, Vector2(1010, 150), 0.62]]
	for sp in spots:
		var root := Button.new()
		root.flat = true
		root.focus_mode = Control.FOCUS_NONE
		for sb in ["normal", "hover", "pressed", "focus"]:
			root.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
		root.position = sp[1]
		root.size = Vector2(140, 80) * float(sp[2]) * 1.25
		root.pressed.connect(_step.bind(int(sp[0])))
		cx.add_child(root)
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = root.size
		tr.position.x = 22.0 * float(sp[2])
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
		var cl := UI.label("D", int(30 * float(sp[2])), Color.WHITE, true)
		UI.outline(cl, 5)
		cl.position = Vector2(-8, -4)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(cl)
		_side.append({"tex": tr, "cls": cl, "off": int(sp[0])})
	# big touch arrows either side of the plate
	for d in [-1, 1]:
		var ab := HintButton.make("", "<" if d < 0 else ">", Color(0.85, 0.88, 0.95), 46)
		ab.position = Vector2(440 if d < 0 else 794, 128)
		ab.pressed.connect(_step.bind(d))
		cx.add_child(ab)

	# ---- stat bars (left)
	var names := ["ACCELERATION", "TOP SPEED", "HANDLING"]
	for k in 3:
		var x := 52.0 + k * 88.0
		var b := StatBar.new()
		b.color = BAR_COLORS[k]
		b.caption = names[k]
		UI.place(b, Vector2(0, 1), Vector2(x, -470), Vector2(78, 330))
		ui.add_child(b)
		_bars.append(b)
		var v := UI.label("0.0", 26, Color.WHITE, true, false)
		UI.outline(v, 6)
		UI.place(v, Vector2(0, 1), Vector2(x - 6, -138), Vector2(90, 32))
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui.add_child(v)
		_bar_vals.append(v)
	_class_line = UI.label("", 30, Color.WHITE, true, false)
	UI.chrome(_class_line, Color(1, 1, 1), Color(0.9, 0.92, 0.96), Color(0.6, 0.64, 0.72), 36.0)
	UI.outline(_class_line, 6)
	UI.place(_class_line, Vector2(0, 1), Vector2(46, -112), Vector2(520, 40))
	ui.add_child(_class_line)

	# ---- paint changer (right)
	var pc := Control.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(pc, Vector2(1, 0), Vector2(-380, 300), Vector2(360, 140))
	ui.add_child(pc)
	var lb := HintButton.make("", "<", Color(0.85, 0.88, 0.95), 46)
	lb.position = Vector2(160, 0)
	lb.pressed.connect(_paint_step.bind(-1))
	pc.add_child(lb)
	var rb := HintButton.make("", ">", Color(0.85, 0.88, 0.95), 46)
	rb.position = Vector2(270, 0)
	rb.pressed.connect(_paint_step.bind(1))
	pc.add_child(rb)
	var cc := UI.label("CHANGE COLOR", 32, Color.WHITE, true, false)
	UI.chrome(cc, Color(1, 1, 1), Color(0.9, 0.92, 0.96), Color(0.6, 0.64, 0.72), 38.0)
	UI.outline(cc, 6)
	cc.position = Vector2(0, 56)
	cc.size = Vector2(350, 40)
	cc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pc.add_child(cc)
	_paint_name = UI.label("", 18, Color(0.8, 0.85, 0.92), false)
	UI.outline(_paint_name, 4)
	_paint_name.position = Vector2(0, 98)
	_paint_name.size = Vector2(350, 24)
	_paint_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pc.add_child(_paint_name)

	# ---- cash (bottom right inside the frame)
	var cash_bg := TextureRect.new()
	cash_bg.texture = UI.gradient_tex([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.7)], [0.0, 1.0], false)
	cash_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cash_bg.stretch_mode = TextureRect.STRETCH_SCALE
	cash_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(cash_bg, Vector2(1, 1), Vector2(-520, -134), Vector2(508, 56))
	ui.add_child(cash_bg)
	_cash = UI.label(CarDB.money(Game.money()), 40, Color.WHITE, true, false)
	UI.chrome(_cash, Color(1, 1, 1), Color(0.92, 0.94, 0.98), Color(0.62, 0.66, 0.74), 48.0)
	UI.outline(_cash, 6)
	UI.place(_cash, Vector2(1, 1), Vector2(-470, -136), Vector2(430, 52))
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(_cash)

	# ---- bottom hint bar
	_bottom_name = UI.label("", 30, Color(0.9, 0.92, 0.96), true, false)
	UI.outline(_bottom_name, 6)
	UI.place(_bottom_name, Vector2(0, 1), Vector2(56, -60), Vector2(420, 44))
	ui.add_child(_bottom_name)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 26)
	hb.alignment = BoxContainer.ALIGNMENT_END
	UI.place(hb, Vector2(1, 1), Vector2(-760, -66), Vector2(730, 56))
	ui.add_child(hb)
	var browse := HintButton.make("BROWSE", "<>", Color(0.75, 0.78, 0.85), 44)
	browse.pressed.connect(_step.bind(1))
	hb.add_child(browse)
	_buy = HintButton.make("BUY", "OK", Color(0.25, 0.55, 1.0), 44)
	_buy.pressed.connect(_on_buy)
	hb.add_child(_buy)
	var back := HintButton.make("BACK", "<-", Color(0.15, 0.75, 0.4), 44)
	back.pressed.connect(_on_back)
	hb.add_child(back)

	_toast = UI.label("", 26, Color.WHITE, true, false)
	UI.outline(_toast, 7)
	UI.place(_toast, Vector2(0.5, 0.5), Vector2(-500, 80), Vector2(1000, 40))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	ui.add_child(_toast)
	ui.add_child(UI.crt_overlay())


func _refresh() -> void:
	var id: String = CarDB.CAR_ORDER[index]
	var d: Dictionary = CarDB.CARS[id]
	var cfg := _cfg_for(id)
	var cls := class_of(id, cfg)
	_name.text = d.name
	_bottom_name.text = d.name
	_class_l.text = cls
	_class_l.modulate = CLASS_COLORS[cls]
	_class_line.text = "CLASS %s  /  %s" % [cls, CATEGORY.get(id, "STREET")]
	_paint_name.text = CarDB.PAINTS[paint].name.to_upper()
	if Game.owns_car(id):
		_price.text = "ACTIVE" if Game.current_car() == id else "OWNED"
	else:
		_price.text = CarDB.money(d.price)
	var sc := scores(id, cfg)
	for k in 3:
		_bars[k].set_value(sc[k] / 10.0)
		_bar_vals[k].text = "%.1f" % sc[k]
	_cash.text = CarDB.money(Game.money())
	_refresh_carousel()
	_update_buttons()


func _refresh_carousel() -> void:
	var id: String = CarDB.CAR_ORDER[index]
	_thumb.texture = _thumbs.get(id)
	for s in _side:
		var nid: String = CarDB.CAR_ORDER[posmod(index + int(s.off), CarDB.CAR_ORDER.size())]
		s.tex.texture = _thumbs.get(nid)
		var cl := class_of(nid, Game.config(nid))
		s.cls.text = cl
		s.cls.modulate = CLASS_COLORS[cl]


func _update_buttons() -> void:
	var id: String = CarDB.CAR_ORDER[index]
	if Game.owns_car(id):
		_buy.set_text_caption("ACTIVE" if Game.current_car() == id else "DRIVE THIS")
	elif _confirm_t > 0.0:
		_buy.set_text_caption("CONFIRM " + CarDB.money(CarDB.CARS[id].price))
	else:
		_buy.set_text_caption("BUY")


# ---- dev hooks (AH_DEV)
func dev_car(id: String) -> void:
	_show(CarDB.CAR_ORDER.find(id))


func dev_paint(d: String) -> void:
	_paint_step(int(d))


func dev_yaw(deg: String) -> void:
	_yaw_target = deg_to_rad(float(deg))
	_yaw = _yaw_target
	_idle = -100.0


# ====================================================================== widgets
class MosaicBand extends ColorRect:
	## Dark tiled mosaic: squares of slightly different greys, slow shimmer.
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;
float h(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.55); }
void fragment() {
	vec2 px = FRAGCOORD.xy / 26.0;
	vec2 cell = floor(px);
	vec2 f = fract(px);
	float v = 0.05 + h(cell) * 0.16 + 0.05 * sin(TIME * 0.6 + h(cell + 3.1) * 6.28);
	float edge = step(0.06, f.x) * step(0.06, f.y);
	COLOR = vec4(vec3(v * edge + 0.015), 1.0);
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		material = m


class ChromeFrame extends Control:
	## Rounded chrome outline around the 3D view.
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var outer := StyleBoxFlat.new()
		outer.draw_center = false
		outer.set_border_width_all(7)
		outer.border_color = Color(0.08, 0.09, 0.1)
		outer.set_corner_radius_all(34)
		outer.anti_aliasing = true
		draw_style_box(outer, r)
		var mid := outer.duplicate()
		mid.set_border_width_all(4)
		mid.border_color = Color(0.82, 0.84, 0.88)
		draw_style_box(mid, r.grow(-1.5))
		var hi := outer.duplicate()
		hi.set_border_width_all(1)
		hi.border_color = Color(1, 1, 1, 0.9)
		draw_style_box(hi, r.grow(-2.5))
		var inner := outer.duplicate()
		inner.set_border_width_all(2)
		inner.border_color = Color(0, 0, 0, 0.7)
		draw_style_box(inner, r.grow(-6.0))
		# breadcrumb tab on the top edge
		var tab := Rect2(46, -42, 560, 52)
		var tb := StyleBoxFlat.new()
		tb.bg_color = Color(0.02, 0.025, 0.03, 0.96)
		tb.border_color = Color(0.82, 0.84, 0.88)
		tb.set_border_width_all(3)
		tb.border_width_bottom = 0
		tb.corner_radius_top_left = 22
		tb.corner_radius_top_right = 22
		tb.anti_aliasing = true
		draw_style_box(tb, tab)


class CarouselArc extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for side in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			for k in 25:
				var t := float(k) / 24.0
				var x: float = 640.0 + float(side) * lerpf(180.0, 560.0, t)
				var y := 70.0 + pow(t, 1.7) * 160.0
				pts.append(Vector2(x, y))
			draw_polyline(pts, Color(1, 1, 1, 0.75), 3.0, true)


class NameTab extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.025, 0.035, 0.94)
		sb.border_color = Color(0.82, 0.84, 0.88)
		sb.set_border_width_all(3)
		sb.border_width_bottom = 0
		sb.corner_radius_top_left = 18
		sb.corner_radius_top_right = 18
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size))


class GoldPlate extends Control:
	## Brushed-gold trapezoid behind the selected car.
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var poly := PackedVector2Array([Vector2(-30, 0), Vector2(w + 30, 0), Vector2(w - 6, h), Vector2(6, h)])
		var cols := PackedColorArray([Color(0.55, 0.42, 0.12), Color(0.55, 0.42, 0.12), Color(0.2, 0.14, 0.03), Color(0.2, 0.14, 0.03)])
		draw_polygon(poly, cols)
		var shine := PackedVector2Array([Vector2(-30, 0), Vector2(w + 30, 0), Vector2(w + 18, 14), Vector2(-18, 14)])
		draw_colored_polygon(shine, Color(1.0, 0.86, 0.45, 0.35))
		poly.append(poly[0])
		draw_polyline(poly, Color(0.95, 0.85, 0.55), 2.0, true)


class PricePill extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.08, 0.2, 0.95)
		sb.border_color = Color(0.82, 0.84, 0.88)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(6, 5, size.x - 12, size.y * 0.42), Color(0.35, 0.5, 0.9, 0.22))


class StatBar extends Control:
	## Vertical glass tube with a coloured fill, tick marks and a stacked caption.
	var color := Color.RED
	var caption := ""
	var value := 0.0
	var _shown := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: float) -> void:
		value = clampf(v, 0.0, 1.0)

	func _process(d: float) -> void:
		if absf(_shown - value) > 0.001:
			_shown = move_toward(_shown, value, d * 1.6)
			queue_redraw()

	func _draw() -> void:
		var tube := Rect2(size.x - 34, 0, 30, size.y)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.02, 0.025, 0.88)
		sb.border_color = Color(0.7, 0.72, 0.76)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		draw_style_box(sb, tube)
		var inner := tube.grow(-5)
		var fh := inner.size.y * _shown
		var fill := Rect2(inner.position.x, inner.end.y - fh, inner.size.x, fh)
		draw_rect(fill, color.darkened(0.25))
		draw_rect(Rect2(fill.position.x + 3, fill.position.y, inner.size.x * 0.35, fh), color.lightened(0.25))
		# green tick ladder
		for k in 21:
			var y := inner.position.y + inner.size.y * k / 20.0
			var wv := 8.0 if k % 5 == 0 else 4.0
			draw_line(Vector2(inner.end.x - wv, y), Vector2(inner.end.x, y), Color(0.3, 0.9, 0.3, 0.45), 1.0)
		# caption: letters stacked vertically on a dark strip
		var font := UI.title_font(false)
		var fs := 22
		var n := caption.length()
		var strip_h := minf(size.y, n * 22.0 + 10.0)
		draw_rect(Rect2(0, size.y - strip_h, 34, strip_h), Color(0, 0, 0, 0.82))
		for i in n:
			var ch := caption[i]
			var y := size.y - strip_h + 26.0 + i * 22.0
			var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(17 - cw * 0.5, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


class HintButton extends Button:
	## Round glyph + caption, used for the bottom hint bar and arrows.
	var glyph := ""
	var cap := ""
	var tint := Color.WHITE
	var dia := 44.0
	var _press := 0.0

	static func make(text: String, g: String, c: Color, d := 44.0) -> HintButton:
		var b := HintButton.new()
		b.cap = text
		b.glyph = g
		b.tint = c
		b.dia = d
		b._resize()
		return b

	func _resize() -> void:
		var w := dia + 8.0
		if cap != "":
			w += UI.title_font(false).get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 10.0
		custom_minimum_size = Vector2(w, dia + 8.0)
		size = custom_minimum_size

	func set_text_caption(t: String) -> void:
		cap = t
		_resize()
		queue_redraw()

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for sb in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(sb, StyleBoxEmpty.new())
		button_down.connect(func():
			_press = 1.0
			queue_redraw())
		button_up.connect(func():
			_press = 0.0
			queue_redraw())

	func _draw() -> void:
		var r := dia * 0.5
		var c := Vector2(r + 4, size.y * 0.5)
		draw_circle(c, r + 2, Color(0, 0, 0, 0.8))
		draw_circle(c, r, Color(0.8, 0.82, 0.86))
		draw_circle(c, r - 3, tint.darkened(0.45 + _press * 0.2))
		draw_circle(c + Vector2(0, -r * 0.3), r * 0.62, Color(tint.lightened(0.3), 0.35))
		var font := UI.title_font(false)
		var gs := int(dia * 0.42)
		var gw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
		draw_string_outline(font, c + Vector2(-gw * 0.5, gs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, 4, Color(0, 0, 0, 0.8))
		draw_string(font, c + Vector2(-gw * 0.5, gs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color.WHITE)
		if cap != "":
			var p := Vector2(dia + 14, size.y * 0.5 + 11)
			draw_string_outline(font, p, cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color(0, 0, 0, 0.85))
			draw_string(font, p, cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.95, 0.96, 0.98))


func dev_reflect(v: String) -> void:
	stage.floor_mat.set_shader_parameter("reflect", float(v))
	print("mirror: ", car_mirror, " visible ", car_mirror.is_visible_in_tree() if car_mirror else false)
