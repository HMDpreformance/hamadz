class_name DynoPanel
extends Control
## LSXmotorsport dyno: a rolling-road power pull. Computes a believable power and
## torque curve from the car's final stats, sweeps the needle up through the revs
## with a rising engine note, and prints peak crank/wheel horsepower, torque,
## 0-60 and top speed. Visual nod to a Mustang-style dyno bay.

signal closed

const REDLINE := {"i4": 7600, "i6": 7400, "v6": 7000, "v8": 6400, "v8sc": 6600,
	"v8tt": 6800, "rotary": 9000, "exotic": 9200}

var car_id := ""
var cfg := {}
var _peak_hp := 0.0
var _peak_tq := 0.0
var _whp := 0.0
var _rl := 7000.0
var _accel := 6.0
var _top := 150.0
var _t := 0.0            # 0..1 sweep progress
var _running := false
var _graph: _Graph
var _read_hp: Label
var _read_tq: Label
var _read_sub: Label
var _run_btn: Button


func setup(id: String, config: Dictionary) -> void:
	car_id = id
	cfg = config
	var s := CarDB.stats(id, config)
	_peak_hp = s.hp
	_peak_tq = s.torque
	_whp = round(s.hp * 0.86)
	_accel = s.accel
	_top = s.top
	_rl = float(REDLINE.get(CarDB.CARS[id].get("engine", "i4"), 7000))
	_build()
	run()


func _build() -> void:
	UI.full(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := UI.full(UI.rect(Color(0.015, 0.016, 0.022, 0.96)))
	add_child(bg)
	# header: logo + title
	var logo := TextureRect.new()
	logo.texture = load("res://textures/lsx_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.position = Vector2(48, 28)
	logo.size = Vector2(230, 60)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	var title := UI.label("DYNAMOMETER", 30, UI.CYAN, true)
	title.position = Vector2(290, 42)
	add_child(title)
	var carname := UI.label(CarDB.CARS[car_id].name, 20, UI.DIM)
	carname.position = Vector2(292, 78)
	add_child(carname)

	# graph
	_graph = _Graph.new()
	_graph.panel = self
	UI.place(_graph, Vector2(0.5, 0.5), Vector2(-470, -210), Vector2(760, 380))
	add_child(_graph)

	# right-hand readouts
	var rx := 320.0
	_read_hp = _big_readout("PEAK POWER", "0 HP", UI.RED, Vector2(0.5, 0.5), Vector2(rx, -200))
	_read_tq = _big_readout("PEAK TORQUE", "0 LB-FT", UI.AMBER, Vector2(0.5, 0.5), Vector2(rx, -96))
	_read_sub = UI.label("", 20, UI.TEXT)
	UI.place(_read_sub, Vector2(0.5, 0.5), Vector2(rx, 12), Vector2(360, 120))
	add_child(_read_sub)

	# buttons
	_run_btn = NeonButton.make("RUN PULL", Vector2(220, 54), UI.GREEN, 24)
	UI.place(_run_btn, Vector2(0.5, 1), Vector2(-240, -96), Vector2(220, 54))
	_run_btn.pressed.connect(run)
	add_child(_run_btn)
	var close := NeonButton.make("DONE", Vector2(200, 54), UI.AMBER, 24)
	UI.place(close, Vector2(0.5, 1), Vector2(40, -96), Vector2(200, 54))
	close.pressed.connect(func(): closed.emit())
	add_child(close)


func _big_readout(label: String, value: String, col: Color, anchor: Vector2, off: Vector2) -> Label:
	var cap := UI.label(label, 18, UI.DIM)
	UI.place(cap, anchor, off, Vector2(360, 24))
	add_child(cap)
	var val := UI.label(value, 52, col, true)
	UI.place(val, anchor, off + Vector2(0, 26), Vector2(360, 64))
	add_child(val)
	return val


func run() -> void:
	_t = 0.0
	_running = true
	Audio.sfx("nitro_start", -4.0)


func _process(d: float) -> void:
	if not _running:
		return
	_t = minf(_t + d / 2.6, 1.0)
	var e := _t * _t * (3.0 - 2.0 * _t)
	var rpm := int(lerpf(900, _rl, e))
	_read_hp.text = "%d HP" % int(hp_at(e) )
	_read_tq.text = "%d LB-FT" % int(tq_at(e))
	if _t >= 1.0:
		_running = false
		_read_hp.text = "%d HP" % int(_peak_hp)
		_read_tq.text = "%d LB-FT" % int(_peak_tq)
		_read_sub.text = "WHEEL POWER   %d WHP\nREDLINE   %d RPM\n0–60 MPH   %.1f s\nTOP SPEED   %d MPH" % [int(_whp), int(_rl), _accel, int(_top)]
		Audio.sfx("finish", -6.0)
	_graph.queue_redraw()


## Normalised torque hump over x = rpm fraction (0.12..1).
func tq_norm(x: float) -> float:
	return clampf(1.0 - 1.35 * pow(x - 0.56, 2.0), 0.25, 1.0)


func hp_norm(x: float) -> float:
	# power tracks torque * revs; peaks high in the band
	return tq_norm(x) * x / (tq_norm(0.85) * 0.85)


func tq_at(frac: float) -> float:
	var x := lerpf(0.12, 1.0, frac)
	return _peak_tq * tq_norm(x)


func hp_at(frac: float) -> float:
	var x := lerpf(0.12, 1.0, frac)
	return _peak_hp * clampf(hp_norm(x), 0.0, 1.0)


class _Graph extends Control:
	var panel: DynoPanel

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# panel
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.05, 0.9))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.5, 0.6, 0.6), false, 2.0)
		# grid
		for i in 9:
			var gx := w * i / 8.0
			draw_line(Vector2(gx, 0), Vector2(gx, h), Color(1, 1, 1, 0.06), 1.0)
			var gy := h * i / 8.0
			draw_line(Vector2(0, gy), Vector2(w, gy), Color(1, 1, 1, 0.06), 1.0)
		var prog: float = panel._t if panel._running else 1.0
		var n := 80
		var hp_line := PackedVector2Array()
		var tq_line := PackedVector2Array()
		for k in n + 1:
			var f := k / float(n)
			if f > prog:
				break
			var gx := f * w
			hp_line.append(Vector2(gx, h - panel.hp_norm(lerpf(0.12, 1.0, f)) * h * 0.92))
			tq_line.append(Vector2(gx, h - panel.tq_norm(lerpf(0.12, 1.0, f)) * h * 0.82))
		if tq_line.size() > 1:
			draw_polyline(tq_line, Color(1.0, 0.72, 0.05), 3.0, true)
		if hp_line.size() > 1:
			draw_polyline(hp_line, Color(1.0, 0.2, 0.15), 3.5, true)
		# sweep needle
		var sx := prog * w
		draw_line(Vector2(sx, 0), Vector2(sx, h), Color(0.4, 0.95, 1.0, 0.8), 2.0)
		# labels
		var f := UI.body_font(true)
		draw_string(f, Vector2(10, 22), "POWER / TORQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.5))
		draw_string(f, Vector2(w - 70, h - 10), "RPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.5))
