class_name Soundtrack
## The game's music catalogue. The radio, the music states and the "now playing"
## toast all read from here. To add a track, put an .ogg in audio/music/ and add a
## row; `radio: true` puts it in the free-roam / race rotation.
##
## Every track listed is original to this project (see tools/gen_music.py and
## docs/AUDIO.md for where each file came from). Commercial songs must not be
## added without sync + master-use + distribution licences.

const STATION := "SYNDICATE FM 99.1"

const TRACKS := [
	{"id": "main_theme", "title": "After Hours", "artist": "Syndicate Sound", "radio": true},
	{"id": "night_shift", "title": "Night Shift", "artist": "Low Tide", "radio": true},
	{"id": "redline", "title": "Redline", "artist": "Kanji Kid", "radio": true},
	{"id": "halcyon", "title": "Halcyon Nights", "artist": "DJ Bayside", "radio": true},
	{"id": "overpass", "title": "Overpass", "artist": "Kanji Kid", "radio": true},
	{"id": "chrome_heart", "title": "Chrome Heart", "artist": "Low Tide", "radio": true},
]

## Which track each fixed state plays (free roam and races use the radio rotation).
const STATE_TRACK := {"intro": "main_theme", "menu": "main_theme"}


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
