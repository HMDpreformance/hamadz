extends CanvasLayer
## Scene manager (autoload "Nav"): fades to a loading screen, swaps the scene
## (freeing the old one and its procedurally generated resources), then fades in.

signal scene_ready(id: String)

const SCENES := {
	"intro": "res://scenes/intro.tscn",
	"menu": "res://scenes/menu.tscn",
	"garage": "res://scenes/garage.tscn",
	"drive": "res://scenes/drive.tscn",
	"dev_show": "res://scenes/dev_show.tscn",
}
const TIPS := [
	"Tap the handbrake mid-corner to kick the tail out, then steer into the slide.",
	"Nitro refills on its own. Save it for the long straights.",
	"Race coilovers and a GT wing make any car stick harder.",
	"Every part you buy is saved to your car automatically.",
	"Drag to orbit the car in the garage. Pinch to zoom in on the details.",
	"Beat the checkpoint run to earn cash for upgrades.",
	"Bigger turbos mean more power and a louder blow-off.",
]

var busy := false
var current := "intro"
var args := {}
var _root: Control
var _bar: ColorRect
var _tip: Label
var _title: Label
var _spin: Control
var _fps: Label


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = UI.full(Control.new())
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)
	var bg := UI.full(UI.rect(Color(0.01, 0.012, 0.02)))
	_root.add_child(bg)
	# diagonal speed stripes
	var stripes := UI.full(ColorRect.new())
	stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 p = FRAGCOORD.xy;
	float d = fract((p.x + p.y * 0.6) / 90.0 - TIME * 0.6);
	float s = smoothstep(0.0, 0.08, d) * (1.0 - smoothstep(0.42, 0.5, d));
	float fade = smoothstep(0.2, 1.0, UV.y);
	COLOR = vec4(1.0, 0.69, 0.0, s * 0.07 * fade);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	stripes.material = sm
	_root.add_child(stripes)
	_title = UI.label("LOADING", 54, UI.AMBER, true)
	UI.place(_title, Vector2(0, 1), Vector2(60, -190), Vector2(800, 70))
	_root.add_child(_title)
	_tip = UI.label("", 24, UI.TEXT)
	UI.place(_tip, Vector2(0, 1), Vector2(64, -118), Vector2(1000, 34))
	_root.add_child(_tip)
	var track := UI.rect(Color(1, 1, 1, 0.12))
	track.anchor_left = 0
	track.anchor_right = 1
	track.anchor_top = 1
	track.anchor_bottom = 1
	track.offset_left = 60
	track.offset_right = -60
	track.offset_top = -70
	track.offset_bottom = -64
	_root.add_child(track)
	_bar = UI.rect(UI.AMBER)
	_bar.anchor_bottom = 1
	_bar.anchor_right = 0.0
	track.add_child(_bar)
	_spin = _Spinner.new()
	UI.place(_spin, Vector2(1, 1), Vector2(-150, -200), Vector2(90, 90))
	_root.add_child(_spin)
	_fps = UI.label("", 18, UI.GREEN)
	_fps.position = Vector2(8, 4)
	add_child(_fps)


func _notification(what: int) -> void:
	# Android back button behaves like Escape (ui_cancel) in every scene
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)


func _process(_d: float) -> void:
	if Game.setting("show_fps", false):
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	elif _fps.text != "":
		_fps.text = ""


func goto(id: String, scene_args := {}, label := "LOADING") -> void:
	if busy:
		return
	busy = true
	args = scene_args
	_title.text = label
	_tip.text = TIPS[randi() % TIPS.size()]
	_bar.anchor_right = 0.0
	_root.visible = true
	Audio.sfx("whoosh", -6.0)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.3)
	await tw.finished
	get_tree().paused = false
	create_tween().tween_property(_bar, "anchor_right", 0.6, 0.25)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(SCENES[id])
	current = id
	# the new scene builds its world in _ready; give it frames to upload meshes
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_bar, "anchor_right", 1.0, 0.3)
	await tw2.finished
	await get_tree().create_timer(0.25).timeout
	scene_ready.emit(id)
	var tw3 := create_tween()
	tw3.tween_property(_root, "modulate:a", 0.0, 0.45)
	await tw3.finished
	_root.visible = false
	busy = false


class _Spinner extends Control:
	var t := 0.0

	func _process(d: float) -> void:
		t += d
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.42
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.12), 6.0, true)
		draw_arc(c, r, t * 5.0, t * 5.0 + 1.6, 24, UI.AMBER, 6.0, true)
		# tach needle
		var a := -2.4 + (sin(t * 3.0) * 0.5 + 0.5) * 3.2
		draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.8, UI.RED, 3.0, true)
		draw_circle(c, 5.0, UI.TEXT)
