class_name StoryDialog
extends Control
## In-game cutscene dialogue: a speaker badge, name plate and typewriter text
## along the bottom of the screen (the Drive scene adds the letterbox bars and
## the orbiting camera). Tap to finish a line, tap again for the next one.
## DESTINY's lines arrive as phone texts.
##   await dialog.play(StoryDB.CHAPTERS[0].intro)

signal finished

const CPS := 52.0                # typewriter speed, characters per second

var auto_advance := false        # dev/headless runs: lines move on by themselves
var _lines: Array = []
var _i := 0
var _shown := 0.0
var _box: Control
var _badge: _Badge
var _name: Label
var _title: Label
var _text: Label
var _hint: Label
var _chapter: Control
var _ch_sub: Label
var _ch_title: Label
var _ch_crew: Label
var _hold := 0.0
var _playing := false


func _ready() -> void:
	UI.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_box = Control.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_box, Vector2(0.5, 1), Vector2(-600, -268), Vector2(1200, 186))
	add_child(_box)
	var bg := UI.panel(Color(0.015, 0.02, 0.035, 0.9), Color(1, 1, 1, 0.14), 0.12)
	UI.full(bg)
	_box.add_child(bg)
	_badge = _Badge.new()
	_badge.position = Vector2(26, 22)
	_badge.size = Vector2(142, 142)
	_box.add_child(_badge)
	_name = UI.label("", 34, Color.WHITE, true)
	UI.outline(_name, 6)
	_name.position = Vector2(196, 14)
	_box.add_child(_name)
	_title = UI.label("", 17, UI.DIM)
	_title.position = Vector2(200, 56)
	_box.add_child(_title)
	_text = UI.label("", 25, UI.TEXT, false)
	_text.position = Vector2(198, 82)
	_text.size = Vector2(970, 96)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_box.add_child(_text)
	_hint = UI.label("TAP  ▶", 17, UI.AMBER)
	_hint.position = Vector2(1100, 150)
	_box.add_child(_hint)
	var skip := NeonButton.make("SKIP", Vector2(150, 50), UI.DIM, 20)
	skip.align_left = false
	skip.click_sound = "ui_back"
	UI.place(skip, Vector2(1, 0), Vector2(-178, 92), Vector2(150, 50))
	skip.pressed.connect(_finish)
	add_child(skip)
	# chapter title card (big chrome type, top left)
	_chapter = Control.new()
	_chapter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_chapter, Vector2(0, 0), Vector2(70, 96), Vector2(1000, 200))
	_chapter.modulate.a = 0.0
	add_child(_chapter)
	_ch_sub = UI.label("", 26, UI.AMBER)
	UI.outline(_ch_sub, 6)
	_chapter.add_child(_ch_sub)
	_ch_title = UI.label("", 84, Color.WHITE, true)
	UI.chrome(_ch_title, Color(1, 1, 1), Color(1.0, 0.8, 0.15), Color(0.85, 0.25, 0.0), 98.0)
	UI.outline(_ch_title, 12)
	_ch_title.position = Vector2(0, 30)
	_chapter.add_child(_ch_title)
	_ch_crew = UI.label("", 22, UI.TEXT)
	UI.outline(_ch_crew, 6)
	_ch_crew.position = Vector2(4, 132)
	_chapter.add_child(_ch_crew)


## Shows the big chapter title for a moment (call before play()).
func show_chapter(sub: String, title: String, line: String, color: Color) -> void:
	_ch_sub.text = sub
	_ch_sub.add_theme_color_override("font_color", color)
	_ch_title.text = title
	_ch_crew.text = line
	visible = true
	var tw := create_tween()
	tw.tween_property(_chapter, "modulate:a", 1.0, 0.4)
	tw.tween_interval(3.2)
	tw.tween_property(_chapter, "modulate:a", 0.0, 0.6)


func play(lines: Array) -> void:
	if lines.is_empty():
		return
	_lines = lines
	_i = 0
	_playing = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box.modulate.a = 0.0
	create_tween().tween_property(_box, "modulate:a", 1.0, 0.25)
	_show_line()
	await finished


func is_playing() -> bool:
	return _playing


func _show_line() -> void:
	var ln: Array = _lines[_i]
	var who: Dictionary = StoryDB.CAST.get(ln[0], {"name": str(ln[0]).to_upper(), "title": "", "color": UI.TEXT})
	var phone: bool = who.get("phone", false)
	_badge.color = who.color
	_badge.initial = who.name.substr(0, 1)
	_badge.phone = phone
	_badge.reward = ln[0] == "reward"
	_badge.queue_redraw()
	_name.text = who.name
	_name.add_theme_color_override("font_color", who.color.lerp(Color.WHITE, 0.35))
	_title.text = ("TEXT MESSAGE  •  " + who.title) if phone else who.title
	_text.text = ln[1]
	_text.visible_characters = 0
	_shown = 0.0
	_hold = 0.0
	_hint.visible = false
	if ln.size() > 2:
		Audio.voice(ln[2], 1.0, 2)
	Audio.sfx("ui_move" if not phone else "beep_hi", -8.0, 1.3 if phone else 1.0)


func _process(dt: float) -> void:
	if not _playing:
		return
	var total := _text.get_total_character_count()
	if _shown < total:
		_shown = minf(_shown + dt * CPS, total)
		_text.visible_characters = int(_shown)
	else:
		_hint.visible = fmod(Time.get_ticks_msec() * 0.002, 1.0) < 0.7
		_hold += dt
		if auto_advance and _hold > 0.2:
			_next()
	if auto_advance and _shown < total:
		_shown = total
		_text.visible_characters = -1


func _gui_input(event: InputEvent) -> void:
	if not _playing:
		return
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tap:
		accept_event()
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if _playing and (event.is_action_pressed("ui_accept") or event.is_action_pressed("gas")):
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	if _shown < _text.get_total_character_count():
		_shown = _text.get_total_character_count()
		_text.visible_characters = -1
	else:
		_next()


func _next() -> void:
	_i += 1
	if _i >= _lines.size():
		_finish()
	else:
		_show_line()


func _finish() -> void:
	if not _playing:
		return
	_playing = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(_box, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		if not _playing:
			visible = false)
	Audio.sfx("ui_select", -6.0)
	finished.emit()


## Speaker badge: a glowing ring in the character's colour with their initial,
## a phone glyph for text messages, a star for rewards.
class _Badge extends Control:
	var color := Color.WHITE
	var initial := "?"
	var phone := false
	var reward := false

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.46
		draw_circle(c, r, Color(color.r * 0.18, color.g * 0.18, color.b * 0.18, 0.95))
		draw_arc(c, r, 0, TAU, 64, color, 5.0, true)
		draw_arc(c, r - 9.0, 0, TAU, 64, Color(color.r, color.g, color.b, 0.3), 2.0, true)
		var f := UI.title_font()
		if reward:
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI * 0.5 + k * TAU / 10.0
				var rr := r * (0.62 if k % 2 == 0 else 0.27)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, color)
			return
		if phone:
			var w := r * 0.75
			var h := r * 1.15
			var rc := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
			draw_rect(rc, color, false, 4.0)
			draw_rect(Rect2(rc.position + Vector2(6, 10), Vector2(w - 12, h - 26)), Color(color.r, color.g, color.b, 0.35))
			draw_circle(Vector2(c.x, rc.end.y - 8.0), 3.0, color)
			return
		var fs := 74
		var tw := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color.lerp(Color.WHITE, 0.3))
