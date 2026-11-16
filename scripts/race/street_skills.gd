class_name StreetSkills
extends Node
## The small skill moments of an open-city street racer, plus the special
## abilities won in the story:
##   NEAR MISS       pass a car at speed with a hand's width to spare: nitro + meter
##   SLIPSTREAM      tuck in behind a car until the draft meter fills: a speed shove
##   PERFECT LAUNCH  hold the revs in the green band on the grid: a shove at GO
##   DRIFT           long slides fill the meter
##   FOCUS / RAM / ROAR  one ability per car family (StoryDB.FAMILY_ABILITY), used
##                   when the meter is full and the ability has been won.
## Owns its own HUD bits (pop-up words, the ability button with its meter ring).

signal popped(text: String)

const NEAR_MIN := 2.05        # centre-to-centre lateral gap that still counts (closer = contact)
const NEAR_MAX := 3.7
const NEAR_SPEED := 17.0      # m/s (~38 mph)
const FOCUS_TIME := 3.2       # real seconds
const FOCUS_SCALE := 0.45
const RAM_TIME := 4.0

var car: PlayerCar
var traffic: Traffic
var cam: ChaseCamera
var rivals_fn: Callable       # returns the race rivals' PlayerCars (empty in free roam)
var env: Environment
var unlock_all := false       # dev runs

var meter := 0.0              # ability meter 0..1
var draft := 0.0              # slipstream fill 0..1
var ability := "focus"
var active := ""              # ability running right now
var near_count := 0
var _prev := {}               # instance id -> last longitudinal offset (metres, + = ahead)
var _crash_cd := 0.0
var _drift_t := 0.0
var _draft_cd := 0.0
var _active_t := 0.0
var _sat0 := 1.0

var _hud: Control
var _pop: Label
var _pop_tw: Tween
var _key: TouchKey
var _ring: _Ring
var _draft_bar: _DraftBar


func setup(p: PlayerCar, t: Traffic, c: ChaseCamera, hud: Control, e: Environment) -> void:
	car = p
	traffic = t
	cam = c
	env = e
	_sat0 = env.adjustment_saturation
	ability = StoryDB.ability_for(car.car_id)
	car.crashed.connect(func(_f): _crash_cd = 1.0)
	_build_hud(hud)


func unlocked() -> bool:
	return unlock_all or Game.has_ability(ability)


# ====================================================================== HUD
func _build_hud(hud: Control) -> void:
	_hud = hud
	_pop = UI.label("", 46, Color.WHITE, true)
	UI.outline(_pop, 10)
	UI.place(_pop, Vector2(0.5, 0.5), Vector2(-400, 40), Vector2(800, 60))
	_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pop.modulate.a = 0.0
	hud.add_child(_pop)
	var info: Dictionary = StoryDB.ABILITIES[ability]
	_key = TouchKey.make("", info.name, info.color, Vector2(98, 98))
	_key.toggle_only = true
	UI.place(_key, Vector2(1, 1), Vector2(-128, -396), Vector2(98, 98))
	_key.tapped.connect(activate)
	hud.add_child(_key)
	_ring = _Ring.new()
	_ring.skills = self
	_ring.color = info.color
	UI.place(_ring, Vector2(1, 1), Vector2(-138, -406), Vector2(118, 118))
	hud.add_child(_ring)
	_draft_bar = _DraftBar.new()
	_draft_bar.skills = self
	UI.place(_draft_bar, Vector2(0.5, 0.5), Vector2(-110, 110), Vector2(220, 30))
	hud.add_child(_draft_bar)


## Drive scene hides these with the rest of the driving HUD.
func hud_nodes() -> Array:
	return [_key, _ring, _draft_bar]


func pop(text: String, color := UI.AMBER, big := false) -> void:
	_pop.text = text
	_pop.add_theme_color_override("font_color", color)
	_pop.add_theme_font_size_override("font_size", 58 if big else 42)
	_pop.pivot_offset = _pop.size * 0.5
	_pop.scale = Vector2(1.4, 1.4)
	if _pop_tw:
		_pop_tw.kill()
	_pop_tw = create_tween()
	_pop_tw.tween_property(_pop, "modulate:a", 1.0, 0.08)
	_pop_tw.parallel().tween_property(_pop, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tw.tween_interval(0.8)
	_pop_tw.tween_property(_pop, "modulate:a", 0.0, 0.35)
	popped.emit(text)


func _add_meter(v: float) -> void:
	var was_full := meter >= 1.0
	meter = clampf(meter + v, 0.0, 1.0)
	if meter >= 1.0 and not was_full and unlocked():
		Audio.sfx("nitro_start", -8.0, 1.4)
		pop(StoryDB.ABILITIES[ability].name + " READY", StoryDB.ABILITIES[ability].color)


# ====================================================================== launch
## Called by the Drive scene on GO. Returns the launch grade.
func launch() -> String:
	if car.throttle < 0.5:
		return ""
	if car.rpm >= 0.5 and car.rpm <= 0.86:
		car.push_time = 1.6
		pop("PERFECT LAUNCH", UI.GREEN, true)
		Audio.sfx("nitro_start", -6.0, 1.2)
		_add_meter(0.15)
		return "perfect"
	pop("GOOD LAUNCH", UI.AMBER)
	car.push_time = 0.5
	return "good"


# ====================================================================== tick
func _physics_process(dt: float) -> void:
	if car == null:
		return
	_crash_cd = maxf(_crash_cd - dt, 0.0)
	_draft_cd = maxf(_draft_cd - dt, 0.0)
	var v := absf(car.speed)
	var fwd := car.forward()
	var right := car.global_transform.basis.x
	var p := car.global_position
	var others: Array = []
	if traffic:
		others.append_array(traffic.cars)
	if rivals_fn.is_valid():
		others.append_array(rivals_fn.call())
	var drafting := false
	var seen := {}
	for o in others:
		if not is_instance_valid(o) or o == car:
			continue
		var d: Vector3 = (o as Node3D).global_position - p
		d.y = 0.0
		if d.length_squared() > 900.0:
			continue
		var id: int = o.get_instance_id()
		seen[id] = true
		var lon := d.dot(fwd)
		var lat := absf(d.dot(right))
		# near miss: it was ahead of our nose last tick and is now beside/behind us, close but not touching
		if _prev.has(id) and _prev[id] > 0.0 and lon <= 0.0 and lat > NEAR_MIN and lat < NEAR_MAX \
				and v > NEAR_SPEED and _crash_cd <= 0.0 and not car.ai:
			if not (o is TrafficCar and (o as TrafficCar).knocked()):
				_near_miss(lat)
		_prev[id] = lon
		# slipstream: right behind something moving in the same direction
		if lon > 3.0 and lon < 24.0 and lat < 1.5 and v > 15.0:
			var ofwd := -(o as Node3D).global_transform.basis.z
			if ofwd.dot(fwd) > 0.8:
				drafting = true
	for id in _prev.keys():
		if not seen.has(id):
			_prev.erase(id)
	if drafting and _draft_cd <= 0.0:
		draft = minf(draft + dt / 1.7, 1.0)
		if draft >= 1.0:
			draft = 0.0
			_draft_cd = 2.0
			car.push_time = 2.2
			_add_meter(0.15)
			pop("SLIPSTREAM", UI.CYAN, true)
			Audio.sfx("whoosh", -4.0, 1.2)
	else:
		draft = maxf(draft - dt * 0.8, 0.0)
	# drifts fill the meter
	if absf(car.slip) > 4.0 and v > 12.0:
		_drift_t += dt
		_add_meter(dt * 0.07)
		if _drift_t > 1.4 and _drift_t - dt <= 1.4:
			pop("DRIFT", UI.MAGENTA)
	else:
		_drift_t = 0.0
	if Input.is_action_just_pressed("ability"):
		activate()


func _process(dt: float) -> void:
	if active == "":
		if _key:
			_key.modulate.a = 1.0 if (unlocked() and meter >= 1.0) else (0.55 if unlocked() else 0.25)
		return
	# abilities run on real time even while FOCUS slows the world down
	var real := dt / maxf(Engine.time_scale, 0.01)
	_active_t -= real
	if active == "focus":
		env.adjustment_saturation = lerpf(env.adjustment_saturation, 0.45, 0.2)
	if _active_t <= 0.0:
		_end_ability()


func _near_miss(lat: float) -> void:
	near_count += 1
	var close := lat < 2.6
	car.nitro = minf(car.nitro + (0.16 if close else 0.1), 1.0)
	_add_meter(0.2 if close else 0.12)
	pop("NEAR MISS!" if close else "NEAR MISS", Color(1.0, 0.85, 0.2) if close else UI.AMBER, close)
	Audio.sfx("whoosh", -2.0, randf_range(1.15, 1.35))


# ====================================================================== abilities
func activate() -> void:
	if active != "" or car == null or not car.input_enabled:
		return
	if not unlocked():
		Audio.sfx("ui_deny", -6.0)
		pop("WIN %s IN THE STORY" % StoryDB.ABILITIES[ability].name, UI.DIM)
		return
	if meter < 1.0:
		Audio.sfx("ui_deny", -6.0)
		return
	meter = 0.0
	active = ability
	var info: Dictionary = StoryDB.ABILITIES[ability]
	pop(info.name + "!", info.color, true)
	match ability:
		"focus":
			_active_t = FOCUS_TIME
			Engine.time_scale = FOCUS_SCALE
			AudioServer.playback_speed_scale = 0.72
			Audio.sfx("whoosh", 0.0, 0.6)
		"ram":
			_active_t = RAM_TIME
			car.ram_time = RAM_TIME
			car.push_time = 1.0
			Audio.sfx("nitro_start", 0.0, 0.8)
		"roar":
			_active_t = 0.8
			_roar()


func _roar() -> void:
	Audio.sfx("crash", 0.0, 0.55)
	Audio.sfx("whoosh", 2.0, 0.7)
	if cam:
		cam.shake(0.4)
	var p := car.global_position
	var fwd := car.forward()
	if traffic:
		for t: TrafficCar in traffic.cars:
			var d: Vector3 = t.global_position - p
			d.y = 0.0
			var dist: float = d.length()
			if dist < 48.0 and dist > 0.1 and d.normalized().dot(fwd) > 0.2:
				var side := car.global_transform.basis.x * signf(d.dot(car.global_transform.basis.x) + 0.01)
				t.knock((side * 16.0 + fwd * 6.0) * clampf(1.4 - dist / 48.0, 0.4, 1.2))
	if rivals_fn.is_valid():
		for r in rivals_fn.call():
			var d: Vector3 = (r as PlayerCar).global_position - p
			if d.length() < 34.0 and d.normalized().dot(fwd) > 0.2:
				(r as PlayerCar).velocity *= 0.55
				(r as PlayerCar).speed *= 0.55


func _end_ability() -> void:
	if active == "focus":
		Engine.time_scale = 1.0
		AudioServer.playback_speed_scale = 1.0
		env.adjustment_saturation = _sat0
	active = ""


## Called when the scene ends or a race resets, so nothing stays slowed down.
func reset() -> void:
	if active != "":
		_end_ability()
	draft = 0.0
	_prev.clear()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0


class _Ring extends Control:
	var skills: StreetSkills
	var color := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5 - 4.0
		draw_arc(c, r, 0, TAU, 48, Color(0, 0, 0, 0.5), 7.0, true)
		var m := skills.meter
		if skills.active != "":
			m = 1.0
		var col := color if skills.unlocked() else UI.DIM
		if m > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * m, 48, col, 6.0, true)
		if m >= 1.0 and skills.unlocked():
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
			draw_arc(c, r + 4.0, 0, TAU, 48, Color(col.r, col.g, col.b, 0.35 * pulse), 4.0, true)


class _DraftBar extends Control:
	var skills: StreetSkills

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var d := skills.draft
		if d <= 0.02:
			return
		var f := UI.body_font(true)
		draw_string(f, Vector2(0, 12), "SLIPSTREAM", HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(UI.CYAN, 0.9))
		draw_rect(Rect2(0, 18, size.x, 8), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(0, 18, size.x * d, 8), UI.CYAN)
