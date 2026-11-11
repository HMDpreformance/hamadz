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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name in ["Music", "SFX", "Engine"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "SFX" if bus_name == "Engine" else "Master")
	_music_a = _mk("Music")
	_music_b = _mk("Music")
	_amb = _mk("SFX")
	for i in 10:
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


func sfx(sfx_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var path := "res://audio/%s.wav" % sfx_name
	for pl in _pool:
		if not pl.playing:
			pl.stream = stream(path)
			pl.volume_db = volume_db
			pl.pitch_scale = pitch
			pl.play()
			return
	var p0 := _pool[0]
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
