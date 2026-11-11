class_name NeonButton
extends Button
## Skewed arcade-style button with animated highlight, glow edge and UI sounds.

var caption := ""
var sub := ""
var accent := UI.AMBER
var font_size := 26
var skew := 0.28
var align_left := true
var selected := false: set = set_selected
var locked := false
var swatch := Color(0, 0, 0, 0)
var click_sound := "ui_select"
var filled := false
var _hl := 0.0
var _press := 0.0
var _t := 0.0


static func make(text: String, min_size := Vector2(300, 54), accent_color := UI.AMBER, size := 26) -> NeonButton:
	var b := NeonButton.new()
	b.caption = text
	b.accent = accent_color
	b.font_size = size
	b.custom_minimum_size = min_size
	b.size = min_size
	return b


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	for sb in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(sb, StyleBoxEmpty.new())
	mouse_entered.connect(func():
		if not disabled:
			Audio.sfx("ui_move", -8.0))
	button_down.connect(func(): _press = 1.0)
	pressed.connect(func():
		Audio.sfx("ui_deny" if locked else click_sound, -3.0))
	set_process(true)


func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()


func set_caption(text: String, subtitle := "") -> void:
	caption = text
	sub = subtitle
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var target := 1.0 if (selected or is_hovered() or button_pressed) and not disabled else 0.0
	var old := _hl
	_hl = move_toward(_hl, target, delta * 7.0)
	_press = move_toward(_press, 0.0, delta * 4.0)
	if old != _hl or _press > 0.0 or selected:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var k := h * skew
	var e := 1.0 - pow(1.0 - _hl, 3.0)
	var inset := _press * 3.0
	var pts := PackedVector2Array([Vector2(k + inset, inset), Vector2(w - inset, inset), Vector2(w - k - inset, h - inset), Vector2(inset, h - inset)])
	var base := Color(0.05, 0.06, 0.09, 0.82)
	if disabled:
		base.a = 0.45
	draw_colored_polygon(pts, base)
	# sweeping fill
	if e > 0.01 or filled:
		var fw := w * (1.0 if filled else e)
		var fill := PackedVector2Array([Vector2(k, 0), Vector2(minf(fw, w), 0), Vector2(maxf(minf(fw, w) - k, 0), h), Vector2(0, h)])
		var c := accent
		c.a = (0.85 if filled else 0.92) * (0.6 + 0.4 * e if not filled else 0.75 + 0.25 * e)
		draw_colored_polygon(fill, c)
		if selected:
			var pulse := 0.5 + 0.5 * sin(_t * 5.0)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(1, 1, 1, 0.35 + 0.4 * pulse), 2.0, true)
	# left accent bar + outline
	var bar := PackedVector2Array([Vector2(k, 0), Vector2(k + 6, 0), Vector2(6, h), Vector2(0, h)])
	draw_colored_polygon(bar, accent if not disabled else Color(0.3, 0.3, 0.3))
	var oc := accent
	oc.a = 0.35 + 0.4 * e
	if disabled:
		oc = Color(1, 1, 1, 0.1)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), oc, 1.5, true)
	# text
	var on_fill := e > 0.5 or filled
	var tc := UI.INK if on_fill else UI.TEXT
	if disabled:
		tc = Color(0.5, 0.5, 0.55)
	var f := UI.title_font()
	var fs := font_size
	var tw := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var max_w := w - k - 34.0 - (30.0 if swatch.a > 0.0 else 0.0)
	while tw > max_w and fs > 10:
		fs -= 1
		tw = f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := k * 0.5 + 22.0 + e * 8.0
	if not align_left:
		x = (w - tw) * 0.5
	if swatch.a > 0.0:
		draw_rect(Rect2(x, h * 0.5 - 10, 20, 20), swatch)
		draw_rect(Rect2(x, h * 0.5 - 10, 20, 20), Color(1, 1, 1, 0.6), false, 1.0)
		x += 30.0
	var ty := h * 0.5 + fs * 0.35
	if sub != "":
		ty = h * 0.42 + fs * 0.3
	draw_string(f, Vector2(x, ty), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
	if sub != "":
		var sc := (UI.INK if on_fill else accent)
		sc.a = 0.9
		draw_string(UI.body_font(true), Vector2(x, h * 0.42 + fs * 0.3 + 18), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, sc)
