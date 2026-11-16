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
	# v0.17: full original station set (ElevenLabs Music v2.5 via Higgsfield, Ultra, 2026-11-16)
	{"id": "night_rollin", "title": "Night Rollin'", "artist": "Big Rel", "radio": true, "station": "night"},
	{"id": "redline", "title": "Redline", "artist": "808 Mob", "radio": true, "station": "night"},
	{"id": "neon_mirage", "title": "Neon Mirage", "artist": "VHS Dreams", "radio": true, "station": "night"},
	{"id": "midnight_lane", "title": "Midnight Lane", "artist": "Deep Sector", "radio": true, "station": "night"},
	{"id": "afterburner", "title": "Afterburner", "artist": "Breakstate", "radio": true, "station": "rock"},
	{"id": "full_throttle", "title": "Full Throttle", "artist": "Gearhead", "radio": true, "station": "rock"},
	{"id": "tyre_smoke", "title": "Tyre Smoke", "artist": "Driftking", "radio": true, "station": "rock"},
	{"id": "getaway", "title": "Getaway", "artist": "The Pursuit", "radio": true, "station": "rock"},
	# v1.0: harder street set (ElevenLabs Music v2.5 via Higgsfield, 2026-11-16)
	{"id": "block_shaker", "title": "Block Shaker", "artist": "808 Mob", "radio": true, "station": "night"},
	{"id": "wet_neon", "title": "Wet Neon", "artist": "Deep Sector", "radio": true, "station": "night"},
	{"id": "overdrive", "title": "Overdrive", "artist": "Breakstate", "radio": true, "station": "rock"},
	{"id": "burnout", "title": "Burnout", "artist": "Gearhead", "radio": true, "station": "rock"},
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
