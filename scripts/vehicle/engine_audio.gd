class_name EngineAudio
extends Node
## Everything you hear from the player's car, driven by PlayerCar state each frame.
##   EngineVoice ......... RPM-layered engine, on/off load, intake
##   induction ........... turbo spool, wastegate, blow-off / flutter, supercharger whine
##   exhaust events ...... overrun pops, backfires on shifts, rev limiter cut
##   drivetrain / tyres .. gearbox whine, squeal, drift scrub, brake squeal
##   road + wind ......... speed dependent beds
## Camera view and the acoustic space retune the mix through the Audio autoload.
## Every one-shot is triggered by a car condition, never at random on a timer.

signal backfire

const CAR := "res://audio/car/"
const VIEWS := {
	# cutoff Hz, engine dB, intake dB, induction dB, cabin beds dB (road/wind/gearbox)
	"chase": [9500.0, 0.0, -9.0, 0.0, 0.0],
	"hood": [15000.0, 2.0, -1.5, 3.5, -2.0],
	"cabin": [1500.0, -3.0, -6.0, -3.0, 4.0],
}

var car: PlayerCar
var voice: EngineVoice
var muted := false
var view := "chase"

var _spool: AudioStreamPlayer
var _gate: AudioStreamPlayer
var _sc: AudioStreamPlayer
var _trans: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _scrub: AudioStreamPlayer
var _brake: AudioStreamPlayer
var _road: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _nitro: AudioStreamPlayer
var _was_nitro := false
var _prev_load := 0.0
var _peak_boost := 0.0
var _pop_time := 0.0          # remaining overrun window
var _pop_next := 0.0
var _pop_chance := 0.0
var _gate_hold := 0.0
var _lim_was := 0.0
var _vent_cd := 0.0
var _exh_db := 0.0
var _mute_k := 1.0


func attach(c: PlayerCar) -> void:
	car = c
	voice = EngineVoice.new()
	add_child(voice)
	voice.setup(c.engine_profile)
	if c.induction == "turbo":
		_spool = _loop("turbo_spool_big" if c.has_turbo >= 2 else "turbo_spool")
		_gate = _loop("wastegate")
	elif c.induction == "sc":
		_sc = _loop("sc_whine")
	_trans = _loop("trans_whine")
	_squeal = _loop("tire_squeal")
	_scrub = _loop("tire_scrub")
	_brake = _loop("brake_squeal")
	_road = _loop("road")
	_wind = _loop("wind")
	_nitro = Audio.make_loop(self, "nitro_loop")
	_exh_db = c.exhaust_level * 2.2
	var p := EngineProfiles.get_profile(c.engine_profile)
	_pop_chance = float(p.pops) * [0.25, 0.7, 1.0][clampi(c.exhaust_level, 0, 2)]
	c.shifted.connect(_on_shift)
	set_view("chase")


func _loop(id: String) -> AudioStreamPlayer:
	var pl := AudioStreamPlayer.new()
	pl.stream = Audio.stream(CAR + id + ".wav", true)
	pl.bus = "Engine"
	pl.volume_db = -80.0
	add_child(pl)
	pl.play()
	pl.stream_paused = true
	return pl


func set_view(id: String) -> void:
	view = id if VIEWS.has(id) else "chase"
	_retune()


func _retune() -> void:
	if car == null:
		return
	var v: Array = VIEWS[view]
	# a stock exhaust is muffled, a straight pipe lets everything through
	var ex: float = [0.62, 0.85, 1.15][clampi(car.exhaust_level, 0, 2)]
	var turbo_muffle := 0.85 if car.induction == "turbo" else 1.0
	Audio.set_engine_cutoff(clampf(v[0] * ex * turbo_muffle, 700.0, 16000.0))


## Starter + catch, then the loops fade in. Call when the car comes to life.
func start_engine() -> void:
	voice.silence()
	var sp := voice.start_sound_path()
	if ResourceLoader.exists(sp):
		Audio.sfx(sp, -3.0 + _exh_db * 0.5, 1.0, "Engine")
	get_tree().create_timer(0.95).timeout.connect(func(): voice.start(0.6))


func stop_engine() -> void:
	voice.stop(1.0)


## Immediate silence (pause menu, leaving the scene): the tree may be paused,
## so players are paused directly instead of waiting for a fade.
func hush(on: bool) -> void:
	muted = on
	_mute_k = 0.0 if on else _mute_k
	for n in [self, voice]:
		for c in n.get_children():
			if c is AudioStreamPlayer:
				if on:
					c.stream_paused = true
				elif c == _nitro:
					c.stream_paused = false
	if on:
		_nitro.volume_db = -70.0


static func _db(v: float) -> float:
	return linear_to_db(clampf(v, 0.0001, 4.0))


func _drive_loop(pl: AudioStreamPlayer, lin: float, pitch: float, extra_db := 0.0) -> void:
	lin *= _mute_k
	if lin < 0.004:
		if not pl.stream_paused:
			pl.stream_paused = true
		return
	if pl.stream_paused:
		pl.stream_paused = false
	pl.volume_db = lerpf(pl.volume_db, linear_to_db(lin) + extra_db, 0.35)
	pl.pitch_scale = pitch


func _shot(id: String, db: float, pitch := 1.0) -> void:
	if _mute_k > 0.5:
		Audio.sfx(CAR + id + ".wav", db, pitch, "Engine")


func _on_shift(g: int) -> void:
	# a hard upshift on an open exhaust lights the unburnt fuel
	if car.exhaust_level >= 2 and car.rpm > 0.8 and _prev_load > 0.7 and g > 0 and randf() < _pop_chance:
		_shot("backfire_%d" % (1 + randi() % 2), -4.0, randf_range(0.9, 1.1))
		backfire.emit()
	elif _prev_load > 0.7 and car.rpm > 0.7 and randf() < _pop_chance * 0.6:
		_shot("pop_%d" % (1 + randi() % 5), -7.0, randf_range(0.85, 1.15))
	_vent()


## Charge air has to go somewhere when the throttle shuts under boost.
func _vent() -> void:
	if car.induction != "turbo" or _vent_cd > 0.0 or _peak_boost < 0.3:
		return
	_vent_cd = 0.7
	var big := car.has_turbo >= 2
	if _peak_boost > 0.72:
		_shot("bov_big" if big else "bov_small", -6.0 + car.has_turbo, randf_range(0.94, 1.06))
	else:
		# part boost: the compressor surges and chatters instead of venting cleanly
		_shot("flutter_1" if big else "flutter_2", -7.0 + car.has_turbo, randf_range(0.92, 1.08))
	_peak_boost = 0.0


func _process(dt: float) -> void:
	if car == null:
		return
	_mute_k = move_toward(_mute_k, 0.0 if muted else 1.0, dt * 4.0)
	var v: Array = VIEWS[view]
	var rpm := car.rpm
	var load := car.load
	# idle is never perfectly steady, a lumpy cam hunts audibly
	var p := EngineProfiles.get_profile(car.engine_profile)
	var wob := sin(Time.get_ticks_msec() * 0.011) * float(p.idle_shake) * clampf((0.3 - rpm) / 0.16, 0.0, 1.0)
	voice.gain_db = v[1] + _exh_db - 5.0 + _db(maxf(_mute_k, 0.001))
	voice.intake_db = v[2]
	voice.update(rpm + wob, load, dt)

	# ---- induction
	_vent_cd = maxf(_vent_cd - dt, 0.0)
	if car.induction == "turbo":
		var b := car.boost
		_peak_boost = maxf(_peak_boost * (1.0 - dt * 0.8), b)
		_drive_loop(_spool, b * b * 0.5, 0.5 + b * 0.75 + rpm * 0.25, v[3] - 4.0 + car.has_turbo * 1.5)
		if _prev_load > 0.5 and car.throttle < 0.15:
			_vent()
		_gate_hold = _gate_hold + dt if (b > 0.94 and car.throttle > 0.9) else 0.0
		_drive_loop(_gate, 0.22 if _gate_hold > 0.5 else 0.0, 1.0, v[3] - 6.0)
	elif car.induction == "sc":
		# belt driven: follows the crank exactly, howls under load
		_drive_loop(_sc, (0.12 + 0.5 * load) * clampf(rpm * 1.4, 0.2, 1.0), 0.42 + rpm * 1.25, v[3] - 3.0)

	# ---- exhaust events: overrun pops while the revs fall with the throttle shut
	if _prev_load > 0.6 and car.throttle < 0.1 and rpm > 0.5:
		_pop_time = 0.35 + 0.9 * _pop_chance
		_pop_next = randf_range(0.05, 0.16)
	if _pop_time > 0.0:
		_pop_time -= dt
		_pop_next -= dt
		if car.throttle > 0.15 or rpm < 0.3:
			_pop_time = 0.0
		elif _pop_next <= 0.0:
			_pop_next = randf_range(0.06, 0.28) / maxf(_pop_chance, 0.15)
			if randf() < _pop_chance:
				_shot("pop_%d" % (1 + randi() % 5), -11.0 + car.exhaust_level * 2.0 + rpm * 3.0, randf_range(0.8, 1.2))
	# rev limiter: each ignition cut is a thud, sometimes with a pop behind it
	if car.limiter:
		var ph: float = car._lim_phase
		if ph < _lim_was:
			_shot("limiter", -8.0, randf_range(0.95, 1.05))
			if randf() < _pop_chance * 0.5:
				_shot("pop_%d" % (1 + randi() % 5), -9.0, randf_range(0.9, 1.2))
		_lim_was = ph
	_prev_load = load

	# ---- drivetrain
	var spd := absf(car.speed)
	var spn := clampf(spd / 60.0, 0.0, 1.0)
	_drive_loop(_trans, clampf(spd / 25.0, 0.0, 1.0) * (0.1 + 0.14 * load), 0.5 + rpm * 1.1, v[4] - 6.0)

	# ---- tyres
	var sl := clampf((absf(car.slip) - 2.2) / 8.0, 0.0, 1.0)
	var lock := 0.0
	if car.braking and spd > 16.0:
		lock = 0.3
	if spd < 3.0 and car.throttle > 0.9 and car.gear == 0:
		lock = maxf(lock, 0.35)        # wheelspin off the line
	var squeal := maxf(sl * (1.0 - sl * 0.45), lock)
	_drive_loop(_squeal, squeal * 0.75, 0.86 + 0.22 * sl + spn * 0.08)
	_drive_loop(_scrub, clampf((absf(car.slip) - 4.5) / 7.0, 0.0, 1.0) * 0.8, 0.8 + spn * 0.4)
	var bq := 0.0
	if car.braking and spd > 1.5 and spd < 13.0:
		bq = clampf((13.0 - spd) / 9.0, 0.0, 1.0) * 0.22
	_drive_loop(_brake, bq, 0.9 + spd * 0.012)

	# ---- beds
	_drive_loop(_road, spn * 0.55, 0.65 + spn * 0.75, v[4] - 3.0)
	_drive_loop(_wind, spn * spn * 0.6, 0.75 + spn * 0.55, v[4] - 2.0)
	if car.using_nitro and not _was_nitro:
		Audio.sfx("nitro_start", -2.0)
	_was_nitro = car.using_nitro
	_nitro.volume_db = lerpf(_nitro.volume_db, -8.0 if (car.using_nitro and not muted) else -70.0, 0.3)
