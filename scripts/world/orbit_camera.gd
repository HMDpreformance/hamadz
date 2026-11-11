class_name OrbitCamera
extends Camera3D
## Smooth orbit camera with touch-drag rotate, pinch zoom and named focus presets.

const PRESETS := {
	"default": {"yaw": 35.0, "pitch": 11.0, "dist": 6.6, "target": Vector3(0, 0.62, 0)},
	"side": {"yaw": 88.0, "pitch": 7.0, "dist": 6.4, "target": Vector3(0, 0.6, 0)},
	"front": {"yaw": 22.0, "pitch": 9.0, "dist": 5.4, "target": Vector3(0, 0.5, -0.9)},
	"rear": {"yaw": 157.0, "pitch": 15.0, "dist": 5.8, "target": Vector3(0, 0.7, 0.9)},
	"hood": {"yaw": 28.0, "pitch": 30.0, "dist": 4.4, "target": Vector3(0, 0.75, -0.9)},
	"wheel": {"yaw": 62.0, "pitch": 4.0, "dist": 3.1, "target": Vector3(0.7, 0.36, -1.1)},
	"low": {"yaw": 72.0, "pitch": 2.0, "dist": 5.2, "target": Vector3(0, 0.3, 0)},
	"badge": {"yaw": 70.0, "pitch": 8.0, "dist": 2.9, "target": Vector3(0.7, 0.6, -0.6)},
	"showcase": {"yaw": -40.0, "pitch": 9.0, "dist": 7.2, "target": Vector3(0, 0.6, 0)},
}

var yaw := 35.0
var pitch := 11.0
var dist := 6.6
var target := Vector3(0, 0.62, 0)
var min_dist := 2.4
var max_dist := 9.0
var min_pitch := 1.5
var max_pitch := 55.0
var auto_rotate := 4.0          # deg/s after idle
var idle_delay := 5.0
var enabled := true

var _yaw := 35.0
var _pitch := 11.0
var _dist := 6.6
var _target := Vector3(0, 0.62, 0)
var _touches := {}
var _pinch_start := 0.0
var _pinch_dist := 0.0
var _idle := 0.0
var _tween: Tween


func _ready() -> void:
	fov = 42.0
	near = 0.1
	far = 120.0
	_apply()


func snap(preset: String) -> void:
	var p: Dictionary = PRESETS[preset]
	yaw = p.yaw; pitch = p.pitch; dist = p.dist; target = p.target
	_yaw = yaw; _pitch = pitch; _dist = dist; _target = target
	_apply()


func focus(preset: String, time := 0.9) -> void:
	var p: Dictionary = PRESETS.get(preset, PRESETS["default"])
	if _tween:
		_tween.kill()
	# take the short way around
	var y: float = p.yaw
	while y - yaw > 180.0:
		y -= 360.0
	while y - yaw < -180.0:
		y += 360.0
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "yaw", y, time)
	_tween.tween_property(self, "pitch", p.pitch, time)
	_tween.tween_property(self, "dist", p.dist, time)
	_tween.tween_property(self, "target", p.target, time)
	_idle = 0.0


func handle_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var k := _touches.keys()
			_pinch_start = (_touches[k[0]] as Vector2).distance_to(_touches[k[1]])
			_pinch_dist = dist
		_idle = 0.0
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		_touches[event.index] = event.position
		if _tween:
			_tween.kill()
		if _touches.size() == 1:
			yaw -= event.relative.x * 0.32
			pitch = clampf(pitch + event.relative.y * 0.22, min_pitch, max_pitch)
		elif _touches.size() >= 2 and _pinch_start > 1.0:
			var k := _touches.keys()
			var d := (_touches[k[0]] as Vector2).distance_to(_touches[k[1]])
			dist = clampf(_pinch_dist * _pinch_start / maxf(d, 1.0), min_dist, max_dist)
		_idle = 0.0
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist * 0.9, min_dist, max_dist)
			_idle = 0.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist * 1.1, min_dist, max_dist)
			_idle = 0.0


func _process(delta: float) -> void:
	_idle += delta
	if auto_rotate != 0.0 and _idle > idle_delay and _touches.is_empty():
		yaw += auto_rotate * delta
	var k := 1.0 - exp(-delta * 9.0)
	_yaw = lerpf(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, dist, k)
	_target = _target.lerp(target, k)
	_apply()


func _apply() -> void:
	var y := deg_to_rad(_yaw)
	var p := deg_to_rad(_pitch)
	position = _target + Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p)) * _dist
	if position.y < 0.12:
		position.y = 0.12
	look_at(_target, Vector3.UP)
