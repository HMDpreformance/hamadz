class_name TouchKey
extends Control
## Multi-touch on-screen button that presses an input action while held.

var action := ""
var caption := ""
var accent := UI.AMBER
var round_shape := true
var held := false
var toggle_only := false   # fire `tapped` instead of holding an action
signal tapped

var _finger := -1
var _glow := 0.0


static func make(action_name: String, text: String, color: Color, size_px: Vector2) -> TouchKey:
	var k := TouchKey.new()
	k.action = action_name
	k.caption = text
	k.accent = color
	k.custom_minimum_size = size_px
	k.size = size_px
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return k


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1 and get_global_rect().grow(6).has_point(event.position):
			_finger = event.index
			_set_down(true)
		elif not event.pressed and event.index == _finger:
			_finger = -1
			_set_down(false)


func _set_down(down: bool) -> void:
	held = down
	if toggle_only:
		if down:
			tapped.emit()
	elif action != "":
		if down:
			Input.action_press(action)
		else:
			Input.action_release(action)
	queue_redraw()


func _exit_tree() -> void:
	if held and action != "" and not toggle_only:
		Input.action_release(action)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and held:
		_finger = -1
		_set_down(false)


func _process(d: float) -> void:
	var t := 1.0 if held else 0.0
	if _glow != t:
		_glow = move_toward(_glow, t, d * 8.0)
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var fill := Color(0.03, 0.04, 0.06, 0.45).lerp(Color(accent.r, accent.g, accent.b, 0.75), _glow)
	var edge := Color(accent.r, accent.g, accent.b, 0.75 + 0.25 * _glow)
	if round_shape:
		draw_circle(c, r - 2, fill)
		draw_arc(c, r - 2, 0, TAU, 48, edge, 3.0, true)
		draw_arc(c, r - 9, -2.2, -0.9, 16, Color(1, 1, 1, 0.25), 2.0, true)
	else:
		var k := size.y * 0.2
		var pts := PackedVector2Array([Vector2(k, 0), Vector2(size.x, 0), Vector2(size.x - k, size.y), Vector2(0, size.y)])
		draw_colored_polygon(pts, fill)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), edge, 3.0, true)
	var f := UI.title_font()
	var fs := int(r * 0.42)
	if caption.length() <= 2:
		fs = int(r * 0.9)
	var tw := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9) if _glow < 0.5 else UI.INK)
