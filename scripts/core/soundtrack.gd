class_name Soundtrack
## The game's music catalogue. The radio, the music states and the "now playing"
## toast all read from here. To add a track, put an .ogg in audio/music/ and add a
## row; `radio: true` puts it in the free-roam / race rotation.
##
## Every track listed is original to this project (see tools/gen_music.py and
## docs/AUDIO.md for where each file came from). Commercial songs must not be
## added without sync + master-use + distribution licences.

const STATION := "NIGHT RIDE FM 99.1"

const TRACKS := [
	# v0.13: generated full songs (ElevenLabs Music via Higgsfield, approved by Hamad 2026-11-13)
	{"id": "midnight_cruise", "title": "Midnight Cruise", "artist": "Big Rel & The Night Crew", "radio": true},
	{"id": "break_point", "title": "Break Point", "artist": "DJ Static", "radio": true},
	{"id": "desert_highway", "title": "Desert Highway", "artist": "Sahra Kings", "radio": true},
	# older synth loop, off the radio
	{"id": "main_theme", "title": "After Hours", "artist": "Syndicate Sound", "radio": false},
]

## Which track each fixed state plays (free roam and races use the radio rotation).
const STATE_TRACK := {"intro": "midnight_cruise", "menu": "midnight_cruise"}


static func path(id: String) -> String:
	return "res://audio/music/%s.ogg" % id


static func info(id: String) -> Dictionary:
	for t in TRACKS:
		if t.id == id:
			return t
	return {}


static func radio_ids() -> Array:
	var out := []
	for t in TRACKS:
		if t.radio and ResourceLoader.exists(path(t.id)):
			out.append(t.id)
	return out
