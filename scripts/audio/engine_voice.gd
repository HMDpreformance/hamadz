class_name EngineVoice
extends Node3D
## One engine's sound: RPM layers crossfaded by engine speed and blended between
## on-load and off-load sets, so no sample is pitched far from where it was made.
## Full mode (the player's car) uses every layer through non-positional players.
## Lite mode (opponents, traffic) uses two positional layers with distance
## attenuation and Doppler, to keep the number of active voices low on phones.

var profile_id := "i4"
var lite := false
var gain_db := 0.0           # set by the owner (exhaust, camera, distance)
var intake_db := -8.0
var running := true

var _p: Dictionary
var _rpms: Array = []
var _on: Array = []
var _off: Array = []
var _intake: Node
var _vol_on: Array = []
var _vol_off: Array = []
var _fade := 1.0             # start-up / shut-down envelope
var _fade_target := 1.0
var _fade_rate := 2.0
var _stall_pitch := 1.0


func setup(id: String, lite_mode := false, bus := "Engine") -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_on.clear()
	_off.clear()
	_vol_on.clear()
	_vol_off.clear()
	profile_id = id if EngineProfiles.P.has(id) else "i4"
	lite = lite_mode
	_p = EngineProfiles.get_profile(profile_id)
	var all: Array = _p.rpms
	_rpms = [all[1], all[3]] if lite else all.duplicate()
	for r in _rpms:
		_on.append(_make(EngineProfiles.layer_path(profile_id, r, true), bus))
		_vol_on.append(0.0)
		if not lite:
			_off.append(_make(EngineProfiles.layer_path(profile_id, r, false), bus))
			_vol_off.append(0.0)
	if not lite:
		var ip := "%s%s_intake.wav" % [EngineProfiles.DIR, profile_id]
		if ResourceLoader.exists(ip):
			_intake = _make(ip, bus)


func _make(path: String, bus: String) -> Node:
	var pl: Node
	if lite:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 9.0
		p3.max_distance = 110.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		p3.attenuation_filter_cutoff_hz = 6000.0
		p3.max_polyphony = 1
		pl = p3
	else:
		pl = AudioStreamPlayer.new()
	pl.stream = Audio.stream(path, true)
	pl.bus = bus
	pl.volume_db = -80.0
	add_child(pl)
	pl.play(randf() * 0.5)
	pl.stream_paused = true
	return pl


func start(time := 0.5) -> void:
	running = true
	_fade_target = 1.0
	_fade_rate = 1.0 / maxf(time, 0.01)


func stop(time := 0.9) -> void:
	running = false
	_fade_target = 0.0
	_fade_rate = 1.0 / maxf(time, 0.01)


func silence() -> void:
	_fade = 0.0
	_fade_target = 0.0
	running = false


func start_sound_path() -> String:
	return "%s%s_start.wav" % [EngineProfiles.DIR, profile_id]


## rpm01: normalized engine speed (0.14 idle .. 1 redline). load: 0 overrun .. 1 full throttle.
func update(rpm01: float, load: float, dt: float) -> void:
	_fade = move_toward(_fade, _fade_target, _fade_rate * dt)
	# a dying engine drops in pitch as it spins down
	_stall_pitch = lerpf(0.55, 1.0, _fade) if not running else 1.0
	var rpm := EngineProfiles.to_rpm(profile_id, rpm01) * _stall_pitch
	var n := _rpms.size()
	var k := clampf(dt * 18.0, 0.0, 1.0)
	var lo := 0
	while lo < n - 2 and rpm > float(_rpms[lo + 1]):
		lo += 1
	var t := clampf((rpm - float(_rpms[lo])) / (float(_rpms[lo + 1]) - float(_rpms[lo])), 0.0, 1.0)
	var load_s := clampf(load, 0.0, 1.0)
	var on_g := sqrt(load_s) * lerpf(0.62, 1.0, load_s) * lerpf(0.7, 1.0, rpm01)
	var off_g := sqrt(1.0 - load_s) * lerpf(0.5, 0.72, rpm01)
	if lite:
		on_g = lerpf(0.45, 1.0, load_s) * lerpf(0.7, 1.0, rpm01)
	for i in n:
		var w := 0.0
		if i == lo:
			w = cos(t * PI * 0.5)
		elif i == lo + 1:
			w = sin(t * PI * 0.5)
		var pitch := clampf(rpm / float(_rpms[i]), 0.3, 3.0)
		_vol_on[i] = lerpf(_vol_on[i], w * on_g * _fade, k)
		_apply(_on[i], _vol_on[i], pitch)
		if not lite:
			_vol_off[i] = lerpf(_vol_off[i], w * off_g * _fade, k)
			_apply(_off[i], _vol_off[i], pitch)
	if _intake:
		var iv := load_s * load_s * lerpf(0.35, 1.0, rpm01) * _fade * db_to_linear(intake_db)
		var pl: AudioStreamPlayer = _intake
		if iv < 0.004:
			pl.stream_paused = true
		else:
			pl.stream_paused = false
			pl.volume_db = linear_to_db(iv) + gain_db
			pl.pitch_scale = clampf(rpm / float(_p.rpms[2]), 0.4, 2.2)


func _apply(pl: Node, v: float, pitch: float) -> void:
	if v < 0.004:
		if not pl.stream_paused:
			pl.stream_paused = true
		return
	if pl.stream_paused:
		pl.stream_paused = false
	pl.volume_db = linear_to_db(v) + gain_db + float(_p.gain)
	pl.pitch_scale = pitch
