extends Node
## Input manager (autoload "Controls"). Registers the game's actions with
## keyboard/gamepad defaults; touch buttons press the same actions, and tilt
## steering is blended in when enabled. Gameplay code only reads this node.

const ACTIONS := {
	"gas": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"nitro": [KEY_SHIFT, KEY_N],
	"camera": [KEY_C],
	"pause": [KEY_P],
}
const PAD := {
	"gas": JOY_BUTTON_A, "brake": JOY_BUTTON_X, "handbrake": JOY_BUTTON_B, "nitro": JOY_BUTTON_Y,
	"camera": JOY_BUTTON_RIGHT_SHOULDER, "pause": JOY_BUTTON_START,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.3)
		for k in ACTIONS[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
		if PAD.has(a):
			var jb := InputEventJoypadButton.new()
			jb.button_index = PAD[a]
			InputMap.action_add_event(a, jb)
	for d in [["steer_left", -1.0], ["steer_right", 1.0]]:
		var jm := InputEventJoypadMotion.new()
		jm.axis = JOY_AXIS_LEFT_X
		jm.axis_value = d[1]
		InputMap.action_add_event(d[0], jm)


func steer() -> float:
	var s := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	if int(Game.setting("steer_mode", 0)) == 1:
		var acc := Input.get_accelerometer()
		if acc.length() > 1.0:
			# landscape: tilting the phone like a wheel moves gravity along the screen's x axis
			s += clampf(acc.x / 4.5, -1.0, 1.0)
	return clampf(s, -1.0, 1.0)


func throttle() -> float:
	return Input.get_action_strength("gas")


func brake() -> float:
	return Input.get_action_strength("brake")


func handbrake() -> bool:
	return Input.is_action_pressed("handbrake")


func nitro() -> bool:
	return Input.is_action_pressed("nitro")


func release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)
