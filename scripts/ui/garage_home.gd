class_name GarageHome
extends Control
## The garage's front screen: chrome-framed workshop view with a curved row
## of icons across the top. The middle icon sits on a gold plate under a name
## tab; tap a side icon (or the arrows) to turn the row, tap the plate or
## ACCEPT to open it. Cash sits bottom right, button hints along the bottom.

signal activated(id: String)
signal back_pressed

const SR := preload("res://scripts/scenes/showroom.gd")
const ITEMS := [
	{"id": "custom", "label": "CUSTOMIZE VEHICLE", "icon": "custom"},
	{"id": "wheels", "label": "WHEELS + STANCE", "icon": "wheel"},
	{"id": "perf", "label": "ENGINE + TUNING", "icon": "gauge"},
	{"id": "drive", "label": "TEST DRIVE", "icon": "flag"},
	{"id": "cars", "label": "MANAGE VEHICLES", "icon": "key"},
	{"id": "lot", "label": "CAR LOT", "icon": "dollar"},
]

var index := 0
var _name: Label
var _big: Icon
var _side := []             # [{icon, off}]
var _cash: Label
var _car: Label
var _plate_btn: Button


func _ready() -> void:
	UI.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_band := SR.MosaicBand.new()
	top_band.anchor_right = 1.0
	top_band.offset_bottom = 64
	add_child(top_band)
	var bot_band := SR.MosaicBand.new()
	bot_band.anchor_top = 1.0
	bot_band.anchor_bottom = 1.0
	bot_band.anchor_right = 1.0
	bot_band.offset_top = -78
	add_child(bot_band)
	var frame := SR.ChromeFrame.new()
	UI.full(frame)
	frame.offset_top = 52
	frame.offset_bottom = -70
	frame.offset_left = 6
	frame.offset_right = -6
	add_child(frame)
	var crumb := UI.label("MAIN MENU  \\  GARAGE", 30, Color.WHITE, true, false)
	UI.chrome(crumb, Color(1, 1, 1), Color(0.86, 0.88, 0.92), Color(0.55, 0.58, 0.64), 36.0)
	UI.outline(crumb, 6)
	crumb.position = Vector2(64, 14)
	add_child(crumb)

	# ---- icon carousel
	var cx := Control.new()
	cx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(cx, Vector2(0.5, 0), Vector2(-640, 0), Vector2(1280, 300))
	add_child(cx)
	var arc := SR.CarouselArc.new()
	arc.size = Vector2(1280, 300)
	cx.add_child(arc)
	var tab := SR.NameTab.new()
	tab.position = Vector2(440, 60)
	tab.size = Vector2(400, 48)
	cx.add_child(tab)
	_name = UI.label("", 30, Color(0.35, 0.9, 1.0), true, false)
	UI.outline(_name, 5)
	_name.position = Vector2(440, 62)
	_name.size = Vector2(400, 44)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cx.add_child(_name)
	var plate := SR.GoldPlate.new()
	plate.position = Vector2(500, 108)
	plate.size = Vector2(280, 120)
	cx.add_child(plate)
	_big = Icon.new()
	_big.position = Vector2(560, 112)
	_big.size = Vector2(160, 112)
	plate.add_child(_big)
	_big.position = Vector2(60, 4)
	_plate_btn = _flat_button(Vector2(480, 104), Vector2(320, 128))
	_plate_btn.pressed.connect(_accept)
	cx.add_child(_plate_btn)
	var spots := [[-2, Vector2(112, 150), 0.6], [-1, Vector2(282, 96), 0.75], [1, Vector2(890, 96), 0.75], [2, Vector2(1066, 150), 0.6]]
	for sp in spots:
		var sz := Vector2(130, 92) * float(sp[2])
		var b := _flat_button(sp[1], sz)
		b.pressed.connect(step.bind(int(sp[0])))
		cx.add_child(b)
		var ic := Icon.new()
		ic.size = sz
		ic.dim = 0.85
		b.add_child(ic)
		_side.append({"icon": ic, "off": int(sp[0])})
	for d in [-1, 1]:
		var ab := SR.HintButton.make("", "<" if d < 0 else ">", Color(0.85, 0.88, 0.95), 46)
		ab.position = Vector2(426 if d < 0 else 808, 146)
		ab.pressed.connect(step.bind(d))
		cx.add_child(ab)

	# ---- cash (bottom right, on a dark strip inside the frame)
	var strip := TextureRect.new()
	strip.texture = UI.gradient_tex([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.75)], [0.0, 1.0], false)
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(strip, Vector2(1, 1), Vector2(-560, -134), Vector2(548, 58))
	add_child(strip)
	_cash = UI.label("", 44, Color.WHITE, true, false)
	UI.chrome(_cash, Color(1, 1, 1), Color(0.9, 0.92, 0.96), Color(0.55, 0.6, 0.7), 52.0)
	UI.outline(_cash, 7)
	UI.place(_cash, Vector2(1, 1), Vector2(-540, -136), Vector2(500, 56))
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_cash)

	# ---- hint bar
	_car = UI.label("", 30, Color.WHITE, true, false)
	UI.chrome(_car, Color(1, 1, 1), Color(0.88, 0.9, 0.94), Color(0.55, 0.58, 0.64), 36.0)
	UI.outline(_car, 6)
	UI.place(_car, Vector2(0, 1), Vector2(56, -62), Vector2(420, 44))
	add_child(_car)
	var acc := SR.HintButton.make("ACCEPT", "X", Color(0.35, 0.55, 1.0), 44)
	UI.place(acc, Vector2(1, 1), Vector2(-520, -64), acc.size)
	acc.pressed.connect(_accept)
	add_child(acc)
	var bk := SR.HintButton.make("BACK", "O", Color(0.2, 0.85, 0.7), 44)
	UI.place(bk, Vector2(1, 1), Vector2(-250, -64), bk.size)
	bk.pressed.connect(func(): back_pressed.emit())
	add_child(bk)
	var hint := UI.label("DRAG THE CAR TO TURN IT", 15, Color(1, 1, 1, 0.5))
	UI.place(hint, Vector2(0.5, 1), Vector2(-160, -112), Vector2(320, 20))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	_refresh()


func _flat_button(pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for sb in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
	b.position = pos
	b.size = sz
	return b


func set_info(car_name: String, cash: int) -> void:
	if _car:
		_car.text = car_name
		_cash.text = CarDB.money(cash)


func step(d: int) -> void:
	index = posmod(index + d, ITEMS.size())
	Audio.sfx("ui_move", -3.0)
	_refresh()


func select(id: String) -> void:
	for i in ITEMS.size():
		if ITEMS[i].id == id:
			index = i
	_refresh()


func current() -> String:
	return ITEMS[index].id


func _accept() -> void:
	Audio.sfx("ui_select", -3.0)
	activated.emit(current())


func _refresh() -> void:
	if not _name:
		return
	_name.text = ITEMS[index].label
	_big.kind = ITEMS[index].icon
	_big.queue_redraw()
	for s in _side:
		var it: Dictionary = ITEMS[posmod(index + int(s.off), ITEMS.size())]
		s.icon.kind = it.icon
		s.icon.queue_redraw()


func handle_key(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_left"):
		step(-1)
		return true
	if event.is_action_pressed("ui_right"):
		step(1)
		return true
	if event.is_action_pressed("ui_accept"):
		_accept()
		return true
	return false


class Icon extends Control:
	## Brushed-steel menu icons drawn from simple shapes.
	var kind := "custom"
	var dim := 1.0
	const STEEL := Color(0.86, 0.88, 0.91)
	const EDGE := Color(0.08, 0.09, 0.1)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _metal(poly: PackedVector2Array) -> void:
		var o := poly.duplicate()
		o.append(poly[0])
		draw_polyline(o, EDGE, 5.0 * _s(), true)
		var top := Color(STEEL.lightened(0.1) * dim, 1.0)
		var bot := Color(STEEL.darkened(0.35) * dim, 1.0)
		var miny := INF
		var maxy := -INF
		for p in poly:
			miny = minf(miny, p.y)
			maxy = maxf(maxy, p.y)
		var cols := PackedColorArray()
		for p in poly:
			cols.append(top.lerp(bot, (p.y - miny) / maxf(maxy - miny, 1.0)))
		draw_polygon(poly, cols)
		draw_polyline(o, Color(1, 1, 1, 0.55 * dim), 1.2 * _s(), true)

	func _s() -> float:
		return size.y / 112.0

	func _ring(c: Vector2, r: float, n := 28) -> PackedVector2Array:
		var p := PackedVector2Array()
		for k in n:
			var a := TAU * k / n
			p.append(c + Vector2(cos(a), sin(a)) * r)
		return p

	func _bar(a: Vector2, b: Vector2, w: float) -> PackedVector2Array:
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * w * 0.5
		return PackedVector2Array([a + n, b + n, b - n, a - n])

	func _xf(poly: PackedVector2Array, c: Vector2, ang: float, s: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in poly:
			out.append(c + p.rotated(ang) * s)
		return out

	func _draw() -> void:
		var s := _s()
		var c := size * 0.5
		match kind:
			"key":
				var head := _xf(_ring(Vector2(-44, 0), 20), c, -0.35, s)
				_metal(head)
				var blade := PackedVector2Array([Vector2(-26, -7), Vector2(48, -7), Vector2(54, 0), Vector2(48, 7), Vector2(40, 7), Vector2(36, 13), Vector2(30, 7), Vector2(22, 7), Vector2(18, 13), Vector2(12, 7), Vector2(-26, 7)])
				_metal(_xf(blade, c, -0.35, s))
				draw_circle(c + Vector2(-44, 0).rotated(-0.35) * s, 7 * s, EDGE)
			"custom":
				# wrench
				var w := PackedVector2Array([Vector2(-40, -6), Vector2(18, -6), Vector2(22, -16), Vector2(34, -18), Vector2(28, -6), Vector2(28, 6), Vector2(34, 18), Vector2(22, 16), Vector2(18, 6), Vector2(-40, 6), Vector2(-46, 0)])
				_metal(_xf(w, c + Vector2(-22, 2) * s, -0.9, s))
				# spray can
				var can := PackedVector2Array([Vector2(-15, -26), Vector2(15, -26), Vector2(17, -20), Vector2(17, 34), Vector2(-17, 34), Vector2(-17, -20)])
				_metal(_xf(can, c + Vector2(26, 4) * s, 0.12, s))
				_metal(_xf(PackedVector2Array([Vector2(-7, -38), Vector2(7, -38), Vector2(7, -27), Vector2(-7, -27)]), c + Vector2(26, 4) * s, 0.12, s))
				draw_colored_polygon(_xf(PackedVector2Array([Vector2(-17, 0), Vector2(17, 0), Vector2(17, 16), Vector2(-17, 16)]), c + Vector2(26, 4) * s, 0.12, s), Color(0.95, 0.75, 0.15, dim))
			"wheel":
				_metal(_ring(c, 44 * s, 36))
				draw_circle(c, 34 * s, Color(0.12, 0.13, 0.15))
				for k in 5:
					var a := TAU * k / 5.0 - PI * 0.5
					_metal(_bar(c + Vector2(cos(a), sin(a)) * 8 * s, c + Vector2(cos(a), sin(a)) * 33 * s, 9 * s))
				_metal(_ring(c, 10 * s, 16))
			"gauge":
				_metal(_ring(c + Vector2(0, 6) * s, 42 * s, 36))
				draw_circle(c + Vector2(0, 6) * s, 34 * s, Color(0.06, 0.07, 0.08))
				for k in 9:
					var a := lerpf(PI * 0.8, PI * 2.2, k / 8.0)
					var col := Color(1, 0.25, 0.15) if k > 6 else Color(0.9, 0.92, 0.95)
					draw_line(c + Vector2(0, 6) * s + Vector2(cos(a), sin(a)) * 25 * s, c + Vector2(0, 6) * s + Vector2(cos(a), sin(a)) * 32 * s, Color(col, dim), 3 * s, true)
				var na := PI * 1.85
				draw_line(c + Vector2(0, 6) * s, c + Vector2(0, 6) * s + Vector2(cos(na), sin(na)) * 28 * s, Color(1.0, 0.8, 0.1, dim), 4 * s, true)
				draw_circle(c + Vector2(0, 6) * s, 5 * s, STEEL * dim)
			"flag":
				_metal(_bar(c + Vector2(-34, -40) * s, c + Vector2(-34, 46) * s, 7 * s))
				var x0 := -30.0
				var y0 := -40.0
				var cw := 13.0
				for i in 5:
					for j in 4:
						var p := Vector2(x0 + i * cw, y0 + j * cw + sin(i * 0.9) * 4)
						var q := PackedVector2Array([p, p + Vector2(cw, 0), p + Vector2(cw, cw), p + Vector2(0, cw)])
						draw_colored_polygon(_xf(q, c, 0.0, s), (Color(0.95, 0.96, 0.98) if (i + j) % 2 == 0 else Color(0.08, 0.08, 0.1)) * Color(dim, dim, dim))
			"dollar":
				var f := UI.title_font(true)
				var fs := int(96 * s)
				var tw := f.get_string_size("$", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var p := c + Vector2(-tw * 0.5, fs * 0.36)
				draw_string_outline(f, p, "$", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(8 * s), EDGE)
				draw_string(f, p, "$", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, STEEL * dim)
