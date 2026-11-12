extends Node
## Audio manager (autoload "Audio"): music with crossfade, looping ambience,
## one-shot SFX pool and helpers to create looping players for engines.

signal track_changed(title: String, artist: String)

const AMBIENCE := {
	"garage": "res://audio/amb_garage.ogg",
	"city": "res://audio/amb_city.ogg",
}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _cache := {}
var _current_music := ""
var _current_amb := ""
var _state := ""               # intro | menu | garage | roam | race | ""
var _playlist: Array = []      # shuffled radio order
var _pl_index := -1
var _music_db := -8.0          # level the current state wants
var _duck_db := 0.0            # temporary offset (countdown, stings, pause)
var _mlp: AudioEffectLowPassFilter
var _mlp_target := 20000.0
var _eng_bus := 0
var _lp: AudioEffectLowPassFilter
var _reverbs: Array[AudioEffectReverb] = []
var _lp_target := 9000.0
var _wet_target := 0.06
var _room_target := 0.5

const SPACES := {
	"open": [0.03, 0.3], "street": [0.09, 0.55], "tunnel": [0.42, 0.85], "garage": [0.28, 0.7], "none": [0.0, 0.3],
}


## Tone of the player's own engine: set from camera view and exhaust (see EngineAudio).
func set_engine_cutoff(hz: float) -> void:
	_lp_target = hz


## Acoustic space the cars are in: open, street, tunnel, garage.
func set_space(id: String) -> void:
	var sp: Array = SPACES.get(id, SPACES["street"])
	_wet_target = sp[0]
	_room_target = sp[1]


func _process(dt: float) -> void:
	var k := clampf(dt * 5.0, 0.0, 1.0)
	_lp.cutoff_hz = lerpf(_lp.cutoff_hz, _lp_target, k)
	for rv in _reverbs:
		rv.wet = lerpf(rv.wet, _wet_target, k)
		rv.room_size = lerpf(rv.room_size, _room_target, k)
	# music filter moves on a log scale so sweeps sound even
	_mlp.cutoff_hz = exp(lerpf(log(_mlp.cutoff_hz), log(_mlp_target), clampf(dt * 4.0, 0.0, 1.0)))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Master <- Music, SFX <- Engine (player car, camera filter + space reverb)
	#                      <- World  (other cars, positional, space reverb only)
	for bus_name in ["Music", "SFX", "Engine", "World"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "SFX" if bus_name in ["Engine", "World"] else "Master")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -12.0
	comp.ratio = 3.0
	comp.attack_us = 8000.0
	comp.release_ms = 180.0
	comp.gain = 3.0
	AudioServer.add_bus_effect(0, comp)
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	_eng_bus = AudioServer.get_bus_index("Engine")
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = 9000.0
	_lp.resonance = 0.6
	AudioServer.add_bus_effect(_eng_bus, _lp)
	for b in ["Engine", "World"]:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.5
		rv.damping = 0.6
		rv.wet = 0.06
		rv.dry = 1.0
		rv.hipass = 0.2
		AudioServer.add_bus_effect(AudioServer.get_bus_index(b), rv)
		_reverbs.append(rv)
	_mlp = AudioEffectLowPassFilter.new()
	_mlp.cutoff_hz = 20000.0
	_mlp.resonance = 0.5
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), _mlp)
	_music_a = _mk("Music")
	_music_b = _mk("Music")
	_music_a.finished.connect(_on_track_finished.bind(_music_a))
	_music_b.finished.connect(_on_track_finished.bind(_music_b))
	_amb = _mk("SFX")
	for i in 14:
		_pool.append(_mk("SFX"))
	apply_volumes()


func _mk(bus: String) -> AudioStreamPlayer:
	var pl := AudioStreamPlayer.new()
	pl.bus = bus
	add_child(pl)
	return pl


func apply_volumes() -> void:
	_set_bus("Music", float(Game.setting("music", 0.8)))
	_set_bus("SFX", float(Game.setting("sfx", 0.9)))


func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(i, v <= 0.01)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func stream(path: String, loop := false) -> AudioStream:
	var key := path + ("#l" if loop else "")
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = load(path)
	if loop:
		s = s.duplicate()
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		elif s is AudioStreamOggVorbis:
			s.loop = true
	_cache[key] = s
	return s


func sfx(sfx_name: String, volume_db := 0.0, pitch := 1.0, bus := "SFX") -> void:
	var path := sfx_name if sfx_name.begins_with("res://") else "res://audio/%s.wav" % sfx_name
	for pl in _pool:
		if not pl.playing:
			pl.bus = bus
			pl.stream = stream(path)
			pl.volume_db = volume_db
			pl.pitch_scale = pitch
			pl.play()
			return
	var p0 := _pool[0]
	p0.bus = bus
	p0.stream = stream(path)
	p0.volume_db = volume_db
	p0.pitch_scale = pitch
	p0.play()


# ====================================================================== music
## The soundtrack follows the game state:
##   intro / menu   the main theme (looping)
##   garage         the radio, quiet and slightly muffled, like shop speakers
##   roam / race    the radio: a shuffled rotation that moves on when a track ends
##   ""             silence
## Countdown, pause and stings shape it with duck_music() and music_filter().
func music_state(st: String, fade := 1.2) -> void:
	if st == _state:
		return
	var was := _state
	_state = st
	_duck_db = 0.0
	_mlp_target = 20000.0
	match st:
		"":
			_fade_to("", fade)
		"intro", "menu":
			_music_db = -4.0 if st == "intro" else -6.0
			_fade_to(Soundtrack.STATE_TRACK[st], fade, true)
		"garage":
			_music_db = -12.0
			_mlp_target = 5200.0
			_radio_resume(fade, was)
		"roam":
			_music_db = -10.0
			_radio_resume(fade, was)
		"race":
			_music_db = -7.5
			_radio_resume(fade, was)
	_apply_level(fade)


func music_state_id() -> String:
	return _state


func radio_on() -> bool:
	return bool(Game.setting("radio", true))


func radio_set(on: bool) -> void:
	Game.set_setting("radio", on)
	if _state in ["garage", "roam", "race"]:
		if on:
			_radio_resume(0.6, "")
		else:
			_fade_to("", 0.4)


func radio_next(step := 1) -> void:
	if not radio_on() or not (_state in ["garage", "roam", "race"]):
		return
	_radio_step(step, 0.35)


func now_playing() -> Dictionary:
	return Soundtrack.info(_current_music)


## Temporary level change on top of the state's own level (0 restores it).
func duck_music(db: float, time := 0.4) -> void:
	_duck_db = db
	_apply_level(time)


## Low-pass on the music bus: 20000 = open, 400 = "heard through a wall".
func music_filter(hz: float) -> void:
	_mlp_target = clampf(hz, 200.0, 20000.0)


## Victory / defeat sting: the radio drops away, the sting plays, the radio returns.
func sting(win: bool) -> void:
	duck_music(-22.0, 0.25)
	sfx("sting_win" if win else "sting_lose", -3.0, 1.0, "Music")
	await get_tree().create_timer(4.2).timeout
	if _duck_db <= -20.0:
		duck_music(-6.0, 1.5)


## A spoken line from audio/voice/<id>.ogg, if that file ships with the build.
## The music steps back while the line plays.
func voice(id: String, db := 0.0) -> bool:
	var path := "res://audio/voice/%s.ogg" % id
	if not ResourceLoader.exists(path):
		return false
	sfx(path, db, 1.0, "SFX")
	return true


func _radio_resume(fade: float, was: String) -> void:
	if not radio_on():
		_fade_to("", fade)
		return
	if _playlist.is_empty():
		_playlist = Soundtrack.radio_ids()
		_playlist.shuffle()
		# the first thing the radio plays after the menu should not be the menu theme again
		if _playlist.size() > 1 and _playlist[0] == Soundtrack.STATE_TRACK["menu"]:
			_playlist.push_back(_playlist.pop_front())
		_pl_index = -1
	if _playlist.is_empty():
		_fade_to("", fade)
		return
	if was in ["garage", "roam", "race"] and _music_a.playing and _playlist.has(_current_music):
		return                       # same radio, keep the song going across scenes
	_radio_step(1, fade)


func _radio_step(step: int, fade: float) -> void:
	if _playlist.is_empty():
		return
	_pl_index = posmod(_pl_index + step, _playlist.size())
	_fade_to(_playlist[_pl_index], fade, false)
	var inf := Soundtrack.info(_playlist[_pl_index])
	track_changed.emit(inf.get("title", ""), inf.get("artist", ""))


func _on_track_finished(pl: AudioStreamPlayer) -> void:
	if pl == _music_a and _state in ["garage", "roam", "race"] and radio_on():
		_radio_step(1, 0.05)


func _apply_level(time: float) -> void:
	if _music_a.playing:
		create_tween().tween_property(_music_a, "volume_db", _music_db + _duck_db, maxf(time, 0.02))


func _fade_to(id: String, fade: float, loop := false) -> void:
	if id == _current_music and (id == "" or _music_a.playing):
		return
	_current_music = id
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -50.0, fade)
		tw.tween_callback(old.stop)
	if id == "":
		return
	_music_a.stream = stream(Soundtrack.path(id), loop)
	_music_a.volume_db = -40.0
	_music_a.play()
	create_tween().tween_property(_music_a, "volume_db", _music_db + _duck_db, fade)


func play_ambience(id: String, gain_db := -6.0) -> void:
	if has_meta("solo"):
		id = ""
	if id == _current_amb:
		return
	_current_amb = id
	if id == "":
		_amb.stop()
		return
	_amb.stream = stream(AMBIENCE[id], true)
	_amb.volume_db = gain_db
	_amb.play()


## Looping player owned by `parent` (engine layers, tire screech, turbo...).
func make_loop(parent: Node, sfx_name: String, bus := "Engine") -> AudioStreamPlayer:
	var pl := AudioStreamPlayer.new()
	pl.stream = stream("res://audio/%s.wav" % sfx_name, true)
	pl.bus = bus
	pl.volume_db = -60.0
	parent.add_child(pl)
	pl.play()
	return pl
