class_name EngineProfiles
## Engine sound catalogue. Each profile points at a set of loops recorded (here:
## synthesized by tools/gen_engines.py) at fixed RPM points, on and off load.
##
## Adding an engine or swapping in real recordings needs no code changes:
##   1. put loops in res://audio/engines/ named <id>_<rpm>_on.wav / _off.wav
##      (plus optional <id>_intake.wav and <id>_start.wav),
##   2. list the RPM points here,
##   3. reference the id from a car in CarDB.

const DIR := "res://audio/engines/"

const P := {
	"i4": {"label": "INLINE 4", "rpms": [900, 2000, 3400, 5000, 7000], "idle": 900, "redline": 7600,
		"gain": 0.0, "pops": 0.35, "idle_shake": 0.012, "rev_rate": 9.0},
	"i6": {"label": "INLINE 6", "rpms": [800, 1900, 3300, 5000, 7000], "idle": 800, "redline": 7400,
		"gain": 0.0, "pops": 0.3, "idle_shake": 0.006, "rev_rate": 8.0},
	"v6": {"label": "V6", "rpms": [800, 1900, 3300, 4900, 6800], "idle": 800, "redline": 7200,
		"gain": 0.0, "pops": 0.3, "idle_shake": 0.01, "rev_rate": 8.0},
	"v8": {"label": "V8", "rpms": [750, 1700, 2900, 4400, 6200], "idle": 750, "redline": 6600,
		"gain": 1.5, "pops": 0.55, "idle_shake": 0.05, "rev_rate": 6.5},
	"v8sc": {"label": "SUPERCHARGED V8", "rpms": [800, 1800, 3000, 4600, 6500], "idle": 800, "redline": 6900,
		"gain": 1.5, "pops": 0.5, "idle_shake": 0.035, "rev_rate": 7.5},
	"v8tt": {"label": "TWIN-TURBO V8", "rpms": [750, 1800, 3100, 4800, 6800], "idle": 750, "redline": 7200,
		"gain": 1.0, "pops": 0.25, "idle_shake": 0.012, "rev_rate": 7.0},
	"rotary": {"label": "ROTARY", "rpms": [1000, 2400, 4200, 6400, 8600], "idle": 1000, "redline": 9000,
		"gain": 0.0, "pops": 0.8, "idle_shake": 0.045, "rev_rate": 11.0},
	"exotic": {"label": "V12", "rpms": [1000, 2500, 4300, 6300, 8400], "idle": 1000, "redline": 8800,
		"gain": 0.5, "pops": 0.45, "idle_shake": 0.006, "rev_rate": 12.0},
}


static func get_profile(id: String) -> Dictionary:
	return P.get(id, P["i4"])


static func layer_path(id: String, rpm: int, on_load: bool) -> String:
	return "%s%s_%d_%s.wav" % [DIR, id, rpm, "on" if on_load else "off"]


## Real RPM for a normalized 0..1 engine speed.
static func to_rpm(id: String, rpm01: float) -> float:
	var p := get_profile(id)
	return lerpf(float(p.idle), float(p.redline), clampf((rpm01 - 0.14) / 0.86, 0.0, 1.0))
