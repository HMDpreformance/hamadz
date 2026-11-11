extends Node
## Audio manager (autoload "Audio"): music with crossfade, looping ambience,
## one-shot SFX pool and helpers to create looping players for engines.

const MUSIC := {
	"menu": "res://audio/music_menu.ogg",
	"intro": "res://audio/music_intro.ogg",
	"drive": "res://audio/music_drive.ogg",
}
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
var _music_gain := 1.0
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
	_music_a = _mk("Music")
	_music_b = _mk("Music")
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


func play_music(id: String, fade := 1.0, gain_db := -4.0) -> void:
	if id == _current_music:
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
	_music_a.stream = stream(MUSIC[id], true)
	_music_a.volume_db = -40.0
	_music_a.play()
	var tw2 := create_tween()
	tw2.tween_property(_music_a, "volume_db", gain_db, fade)


func duck_music(db: float, time := 0.4) -> void:
	if _music_a.playing:
		create_tween().tween_property(_music_a, "volume_db", db, time)


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
