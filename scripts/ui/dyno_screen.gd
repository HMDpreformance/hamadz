class_name DynoScreen
extends Control
## What the dyno TV in the LSXmotorsport bay shows: live power and torque
## curves while the car is pulling on the rollers, then the peak numbers.
## Drawn into a SubViewport that is the TV's picture.

const REDLINE := {"i4": 7600, "i6": 7400, "v6": 7000, "v8": 6400, "v8sc": 6600,
	"v8tt": 6800, "rotary": 9000, "exotic": 9200}

var car_name := ""
var peak_hp := 0.0
var peak_tq := 0.0
var whp := 0.0
var redline := 7000.0
var accel := 6.0
var top := 150.0
var progress := 0.0        # 0..1 through the pull
var state := "ready"       # ready | pull | done
var _logo: Texture2D


func setup(id: String, config: Dictionary) -> void:
	var s := CarDB.stats(id, config)
	car_name = CarDB.CARS[id].name
	peak_hp = s.hp
	peak_tq = s.torque
	whp = round(s.hp * 0.86)
	accel = s.accel
	top = s.top
	redline = float(REDLINE.get(CarDB.CARS[id].get("engine", "i4"), 7000))
	_logo = load("res://textures/lsx_logo.png")
	progress = 0.0
	state = "ready"
	queue_redraw()


func set_progress(p: float, st: String) -> void:
	progress = p
	state = st
	queue_redraw()


func tq_norm(x: float) -> float:
	return clampf(1.0 - 1.35 * pow(x - 0.56, 2.0), 0.25, 1.0)


func hp_norm(x: float) -> float:
	return clampf(tq_norm(x) * x / (tq_norm(0.85) * 0.85), 0.0, 1.0)


func rpm_now() -> int:
	return int(lerpf(redline * 0.12, redline, progress))


func _draw() -> void:
	var w := size.x
	var h := size.y
	var tf := UI.title_font(false)
	var bf := UI.body_font(true)
	draw_rect(Rect2(0, 0, w, h), Color(0.012, 0.014, 0.02))
	if _logo:
		draw_texture_rect(_logo, Rect2(22, 12, 222, 72), false)
	draw_string(tf, Vector2(262, 50), "DYNAMOMETER", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.92, 0.94, 0.97))
	draw_string(bf, Vector2(264, 80), car_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 0.65, 0.72))
	var badge := {"ready": "READY", "pull": "PULL IN PROGRESS", "done": "RUN COMPLETE"}[state] as String
	var bc := {"ready": Color(0.6, 0.65, 0.72), "pull": Color(1.0, 0.25, 0.2), "done": Color(0.35, 1.0, 0.35)}[state] as Color
	draw_string(bf, Vector2(w - 330, 50), badge, HORIZONTAL_ALIGNMENT_RIGHT, 310, 24, bc)
	# graph
	var g := Rect2(70, 110, 610, 400)
	draw_rect(g, Color(0.03, 0.036, 0.05))
	for i in 9:
		var gx := g.position.x + g.size.x * i / 8.0
		draw_line(Vector2(gx, g.position.y), Vector2(gx, g.end.y), Color(1, 1, 1, 0.08), 1.0)
		var gy := g.position.y + g.size.y * i / 8.0
		draw_line(Vector2(g.position.x, gy), Vector2(g.end.x, gy), Color(1, 1, 1, 0.08), 1.0)
		if i % 2 == 0:
			draw_string(bf, Vector2(gx - 20, g.end.y + 26), "%d" % int(lerpf(redline * 0.12, redline, i / 8.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.55))
			var top_v := maxf(peak_hp, peak_tq) / 0.92
			draw_string(bf, Vector2(g.position.x - 58, g.end.y - g.size.y * i / 8.0 + 6), "%d" % int(top_v * i / 8.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.55))
	draw_rect(g, Color(0.35, 0.4, 0.48), false, 2.0)
	draw_string(bf, Vector2(g.end.x - 50, g.end.y + 50), "RPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.55))
	var prog := progress if state != "ready" else 0.0
	var scale_v := maxf(peak_hp, peak_tq) / 0.92
	var hp_line := PackedVector2Array()
	var tq_line := PackedVector2Array()
	var n := 90
	for k in n + 1:
		var f := k / float(n)
		if f > prog:
			break
		var x := lerpf(0.12, 1.0, f)
		var wob := sin(f * 61.0) * 0.006 + sin(f * 23.0) * 0.004
		hp_line.append(Vector2(g.position.x + f * g.size.x, g.end.y - (hp_norm(x) + wob) * peak_hp / scale_v * g.size.y))
		tq_line.append(Vector2(g.position.x + f * g.size.x, g.end.y - (tq_norm(x) + wob) * peak_tq / scale_v * g.size.y))
	if tq_line.size() > 1:
		draw_polyline(tq_line, Color(1.0, 0.72, 0.05), 4.0, true)
	if hp_line.size() > 1:
		draw_polyline(hp_line, Color(1.0, 0.2, 0.15), 5.0, true)
	if state == "pull":
		var sx := g.position.x + prog * g.size.x
		draw_line(Vector2(sx, g.position.y), Vector2(sx, g.end.y), Color(0.4, 0.95, 1.0, 0.9), 2.0)
	# read-outs
	var rx := 716.0
	var x_now := lerpf(0.12, 1.0, prog)
	var hp_v := peak_hp if state == "done" else (peak_hp * hp_norm(x_now) if state == "pull" else 0.0)
	var tq_v := peak_tq if state == "done" else (peak_tq * tq_norm(x_now) if state == "pull" else 0.0)
	draw_string(bf, Vector2(rx, 136), "PEAK POWER" if state == "done" else "POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.65, 0.72))
	draw_string(tf, Vector2(rx, 196), "%d HP" % int(hp_v), HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color(1.0, 0.25, 0.2))
	draw_string(bf, Vector2(rx, 240), "PEAK TORQUE" if state == "done" else "TORQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.65, 0.72))
	draw_string(tf, Vector2(rx, 296), "%d LB-FT" % int(tq_v), HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(1.0, 0.72, 0.05))
	var lines := []
	if state == "done":
		lines = ["WHEEL POWER   %d WHP" % int(whp), "REDLINE   %d RPM" % int(redline), "0-60 MPH   %.1f s" % accel, "TOP SPEED   %d MPH" % int(top)]
	elif state == "pull":
		lines = ["ENGINE   %d RPM" % rpm_now(), "ROLLER   %d MPH" % int(top * 0.62 * x_now)]
	else:
		lines = ["STRAPPED DOWN", "WAITING FOR OPERATOR"]
	for i in lines.size():
		draw_string(bf, Vector2(rx, 350 + i * 34), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.92, 0.94, 0.97))
