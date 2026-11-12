class_name OptionsPanel
extends Control
## Options screen: graphics preset, volumes, steering mode, FPS counter, save reset.
## Self-contained so any scene can add it and listen for `closed`.

signal closed

var _rows := {}
var _reset_armed := false
var _reset_btn: NeonButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(box, Vector2(0.5, 0.5), Vector2(-430, -290), Vector2(860, 580))
	add_child(box)
	var bg := UI.panel(Color(0.02, 0.03, 0.05, 0.9), Color(1.0, 0.69, 0.0, 0.5))
	UI.full(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(bg)
	var bar := UI.rect(UI.AMBER)
	bar.size = Vector2(860, 5)
	box.add_child(bar)
	var title := UI.label("OPTIONS", 48, Color.WHITE, true)
	UI.chrome(title, Color(1, 1, 1), Color(1.0, 0.75, 0.1), Color(0.8, 0.25, 0.0), 58.0)
	title.position = Vector2(34, 18)
	box.add_child(title)

	var y := 92.0
	_choice_row(box, y, "GRAPHICS", "preset", ["PERFORMANCE", "BALANCED", "QUALITY"])
	y += 62.0
	_choice_row(box, y, "RIVALS", "difficulty", ["EASY", "NORMAL", "HARD"])
	y += 62.0
	_slider_row(box, y, "MUSIC", "music")
	y += 62.0
	_slider_row(box, y, "SOUND FX", "sfx")
	y += 62.0
	_choice_row(box, y, "STEERING", "steer_mode", ["BUTTONS", "TILT"])
	y += 62.0
	_choice_row(box, y, "FPS COUNTER", "show_fps", ["OFF", "ON"])
	y += 76.0
	var note := UI.label("Graphics presets change resolution, bloom, reflections, shadows and effects. Progress saves automatically.", 16, UI.DIM)
	note.position = Vector2(36, y - 14)
	note.size = Vector2(790, 22)
	box.add_child(note)
	_reset_btn = NeonButton.make("RESET SAVE DATA", Vector2(330, 54), UI.RED, 22)
	_reset_btn.position = Vector2(34, 506)
	_reset_btn.click_sound = "ui_move"
	_reset_btn.pressed.connect(_on_reset)
	box.add_child(_reset_btn)
	var back := NeonButton.make("DONE", Vector2(240, 54), UI.GREEN, 26)
	back.align_left = false
	back.filled = true
	back.position = Vector2(586, 506)
	back.click_sound = "ui_back"
	back.pressed.connect(func(): closed.emit())
	box.add_child(back)
	_refresh()


func _row_label(box: Control, y: float, text: String) -> void:
	var l := UI.label(text, 24, UI.TEXT, true)
	l.position = Vector2(36, y + 12)
	box.add_child(l)


func _choice_row(box: Control, y: float, text: String, key: String, choices: Array) -> void:
	_row_label(box, y, text)
	var btns := []
	var w := 560.0 / choices.size()
	for i in choices.size():
		var b := NeonButton.make(choices[i], Vector2(w - 6, 54), UI.AMBER, 20)
		b.align_left = false
		b.position = Vector2(270 + i * w, y)
		b.click_sound = "ui_move"
		b.pressed.connect(_set_choice.bind(key, i))
		box.add_child(b)
		btns.append(b)
	_rows[key] = btns


func _slider_row(box: Control, y: float, text: String, key: String) -> void:
	_row_label(box, y, text)
	var minus := NeonButton.make("-", Vector2(70, 54), UI.CYAN, 30)
	minus.align_left = false
	minus.position = Vector2(270, y)
	minus.click_sound = "ui_move"
	minus.pressed.connect(_nudge.bind(key, -0.1))
	box.add_child(minus)
	var plus := NeonButton.make("+", Vector2(70, 54), UI.CYAN, 30)
	plus.align_left = false
	plus.position = Vector2(754, y)
	plus.click_sound = "ui_move"
	plus.pressed.connect(_nudge.bind(key, 0.1))
	box.add_child(plus)
	var bar := _Bar.new()
	bar.position = Vector2(352, y + 8)
	bar.size = Vector2(392, 38)
	box.add_child(bar)
	_rows[key] = bar


class _Bar extends Control:
	var value := 0.5

	func _draw() -> void:
		var n := 10
		var sw := size.x / n
		for i in n:
			var on := (i + 0.5) / n <= value + 0.001
			var x := i * sw
			var k := 10.0
			draw_colored_polygon(PackedVector2Array([Vector2(x + k, 0), Vector2(x + sw - 3, 0), Vector2(x + sw - 3 - k, size.y), Vector2(x, size.y)]),
				UI.CYAN if on else Color(1, 1, 1, 0.1))


func _set_choice(key: String, i: int) -> void:
	match key:
		"preset":
			Game.set_setting("preset", i)
			GFX.set_preset(i)
		"steer_mode":
			Game.set_setting("steer_mode", i)
		"difficulty":
			Game.set_setting("difficulty", i)
		"show_fps":
			Game.set_setting("show_fps", i == 1)
	_refresh()


func _nudge(key: String, d: float) -> void:
	var v := clampf(snappedf(float(Game.setting(key, 0.8)) + d, 0.1), 0.0, 1.0)
	Game.set_setting(key, v)
	Audio.apply_volumes()
	_refresh()


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_btn.set_caption("TAP AGAIN TO CONFIRM")
		get_tree().create_timer(3.0).timeout.connect(func():
			_reset_armed = false
			if is_instance_valid(_reset_btn):
				_reset_btn.set_caption("RESET SAVE DATA"))
		return
	_reset_armed = false
	Game.reset_progress()
	Audio.sfx("install")
	_reset_btn.set_caption("SAVE DATA RESET")


func _refresh() -> void:
	var sel := {"preset": int(Game.setting("preset", 1)), "difficulty": int(Game.setting("difficulty", 1)), "steer_mode": int(Game.setting("steer_mode", 0)), "show_fps": 1 if Game.setting("show_fps", false) else 0}
	for key in sel:
		var btns: Array = _rows[key]
		for i in btns.size():
			btns[i].selected = i == sel[key]
	for key in ["music", "sfx"]:
		_rows[key].value = float(Game.setting(key, 0.8))
		_rows[key].queue_redraw()
