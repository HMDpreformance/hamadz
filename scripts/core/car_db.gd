class_name CarDB
## Static catalogue: vehicles, upgrade categories, prices and stat math.
## To add a car, add an entry to CARS (shape lives in CarSpecs). To add a part,
## append an option to PARTS and handle its index in CarVisual.

const CAR_ORDER := ["tuner", "classic", "muscle", "sedan", "rotary", "euro", "suv", "exotic"]

const CARS := {
	"tuner": {
		"name": "KAIDO RS-7", "tag": "JAPANESE TUNER COUPE", "price": 0,
		"blurb": "Twin-cam turbo four. Light, sharp and built to be modified.",
		"hp": 276, "torque": 260, "top": 152, "accel": 5.6, "handling": 78, "weight": 1280,
		"engine": "i4", "factory_turbo": 1, "cyl": "2.0L TURBO I4", "drive": "RWD",
		"default_color": 1,
	},
	"muscle": {
		"name": "BRAWLER 427", "tag": "AMERICAN MUSCLE", "price": 18500,
		"blurb": "Seven litres of big-block thunder. Straight-line king.",
		"hp": 390, "torque": 460, "top": 158, "accel": 5.1, "handling": 58, "weight": 1620,
		"engine": "v8", "cyl": "7.0L V8", "drive": "RWD",
		"default_color": 0,
	},
	"euro": {
		"name": "VERANO GT", "tag": "EUROPEAN PERFORMANCE", "price": 32000,
		"blurb": "Rear-engined flat six. Precision at any speed.",
		"hp": 340, "torque": 310, "top": 171, "accel": 4.7, "handling": 88, "weight": 1390,
		"engine": "i6", "cyl": "3.6L FLAT 6", "drive": "RWD",
		"default_color": 6,
	},
	"classic": {
		"name": "CORONADO '64", "tag": "CLASSIC LOWRIDER", "price": 14000,
		"blurb": "Five metres of chrome and steel. Slow, low and impossible to ignore.",
		"hp": 250, "torque": 350, "top": 122, "accel": 7.6, "handling": 46, "weight": 1760,
		"engine": "v8", "cyl": "5.4L V8", "drive": "RWD",
		"default_color": 7,
	},
	"sedan": {
		"name": "VANTA S6", "tag": "LUXURY SPORT SEDAN", "price": 21000,
		"blurb": "Quad-cam V6 in a tailored suit. Four doors, no excuses.",
		"hp": 305, "torque": 290, "top": 155, "accel": 5.8, "handling": 70, "weight": 1640,
		"engine": "v6", "cyl": "3.5L V6", "drive": "RWD",
		"default_color": 10,
	},
	"rotary": {
		"name": "AKAGI RZ-8", "tag": "ROTARY SPORTS COUPE", "price": 26000,
		"blurb": "Twin-rotor, sequential turbos and a redline that never seems to come.",
		"hp": 265, "torque": 220, "top": 158, "accel": 5.2, "handling": 85, "weight": 1240,
		"engine": "rotary", "factory_turbo": 1, "cyl": "1.3L TWIN-ROTOR TURBO", "drive": "RWD",
		"default_color": 2,
	},
	"suv": {
		"name": "TITAN LX", "tag": "LUXURY SUV", "price": 38000,
		"blurb": "Two and a half tonnes on a supercharged V8. Rolls on anything you can fit.",
		"hp": 410, "torque": 520, "top": 138, "accel": 6.3, "handling": 50, "weight": 2480,
		"engine": "v8sc", "induction": "sc", "cyl": "6.2L SUPERCHARGED V8", "drive": "AWD",
		"default_color": 11,
	},
	"exotic": {
		"name": "ARDENTE V12", "tag": "ITALIAN EXOTIC", "price": 125000,
		"blurb": "Mid-engined, twelve cylinders, nine thousand rpm. The top of the food chain.",
		"hp": 580, "torque": 470, "top": 205, "accel": 3.6, "handling": 92, "weight": 1480,
		"engine": "exotic", "cyl": "6.0L V12", "drive": "AWD",
		"default_color": 0,
	},
}

const VINYL_COLORS := [
	{"name": "White", "c": Color(0.93, 0.93, 0.9)},
	{"name": "Black", "c": Color(0.02, 0.02, 0.025)},
	{"name": "Red", "c": Color(0.8, 0.04, 0.04)},
	{"name": "Gold", "c": Color(0.95, 0.68, 0.12)},
	{"name": "Silver", "c": Color(0.7, 0.72, 0.75)},
	{"name": "Blue", "c": Color(0.05, 0.25, 0.9)},
	{"name": "Lime", "c": Color(0.45, 0.95, 0.1)},
	{"name": "Pink", "c": Color(0.95, 0.15, 0.55)},
]

const PAINTS := [
	{"name": "Inferno Red", "c": Color(0.78, 0.03, 0.03)},
	{"name": "Sunset Orange", "c": Color(1.0, 0.33, 0.02)},
	{"name": "Hornet Yellow", "c": Color(1.0, 0.78, 0.03)},
	{"name": "Venom Green", "c": Color(0.22, 0.85, 0.08)},
	{"name": "Aqua Teal", "c": Color(0.02, 0.62, 0.6)},
	{"name": "Bayside Blue", "c": Color(0.03, 0.2, 0.85)},
	{"name": "Sterling Silver", "c": Color(0.72, 0.74, 0.77)},
	{"name": "Midnight Purple", "c": Color(0.3, 0.05, 0.6)},
	{"name": "Hot Magenta", "c": Color(0.9, 0.05, 0.5)},
	{"name": "Pearl White", "c": Color(0.93, 0.93, 0.9)},
	{"name": "Gunmetal", "c": Color(0.16, 0.17, 0.19)},
	{"name": "Jet Black", "c": Color(0.02, 0.02, 0.025)},
]

const RIM_COLORS := [
	{"name": "Chrome", "c": Color(0.92, 0.93, 0.95), "metal": 1.0, "rough": 0.08},
	{"name": "Gunmetal", "c": Color(0.2, 0.21, 0.23), "metal": 0.9, "rough": 0.3},
	{"name": "Gloss Black", "c": Color(0.02, 0.02, 0.02), "metal": 0.4, "rough": 0.15},
	{"name": "Bronze", "c": Color(0.62, 0.4, 0.16), "metal": 0.95, "rough": 0.28},
	{"name": "Gold", "c": Color(0.95, 0.7, 0.15), "metal": 1.0, "rough": 0.18},
	{"name": "Race White", "c": Color(0.92, 0.92, 0.9), "metal": 0.1, "rough": 0.3},
	{"name": "Signal Red", "c": Color(0.8, 0.04, 0.04), "metal": 0.5, "rough": 0.25},
]

const UNDERGLOW := [
	{"name": "None", "c": Color(0, 0, 0)},
	{"name": "Ice Blue", "c": Color(0.1, 0.5, 1.0)},
	{"name": "Toxic Green", "c": Color(0.2, 1.0, 0.2)},
	{"name": "Hot Pink", "c": Color(1.0, 0.1, 0.6)},
	{"name": "Ultra Violet", "c": Color(0.55, 0.15, 1.0)},
	{"name": "Amber", "c": Color(1.0, 0.5, 0.05)},
]

## Each slot: label, group, camera focus preset and a list of options.
## Option fields: name, price and optional stat deltas (hp, tq, top, acc, hnd).
const SLOT_ORDER := ["paint", "finish", "vinyl", "vinyl_color", "decal",
	"front", "rear", "spoiler", "skirts", "hood", "widebody",
	"headlights", "taillights", "tint", "glow",
	"rims", "rim_color", "wheel_size", "tires", "ride", "camber",
	"engine", "turbo", "exhaust", "ecu", "nitro",
	"trans", "final", "suspension", "brakes", "weight"]

const GROUPS := [
	{"id": "paint", "label": "PAINT + VINYL", "slots": ["paint", "finish", "vinyl", "vinyl_color", "decal"]},
	{"id": "body", "label": "BODY KIT", "slots": ["front", "rear", "spoiler", "skirts", "hood", "widebody"]},
	{"id": "lights", "label": "LIGHTS + GLASS", "slots": ["headlights", "taillights", "tint", "glow"]},
	{"id": "wheels", "label": "WHEELS + STANCE", "slots": ["rims", "rim_color", "wheel_size", "tires", "ride", "camber"]},
	{"id": "perf", "label": "ENGINE", "slots": ["engine", "turbo", "exhaust", "ecu", "nitro"]},
	{"id": "chassis", "label": "DRIVETRAIN", "slots": ["trans", "final", "suspension", "brakes", "weight"]},
]

static var _parts := {}


static func parts() -> Dictionary:
	if not _parts.is_empty():
		return _parts
	var paint := []
	for i in PAINTS.size():
		paint.append({"name": PAINTS[i].name, "price": 0 if i < 2 else 350, "swatch": PAINTS[i].c})
	var rimc := []
	for i in RIM_COLORS.size():
		rimc.append({"name": RIM_COLORS[i].name, "price": 0 if i == 0 else 250, "swatch": RIM_COLORS[i].c})
	var glow := []
	for i in UNDERGLOW.size():
		glow.append({"name": UNDERGLOW[i].name, "price": 0 if i == 0 else 900, "swatch": UNDERGLOW[i].c})
	var vcol := []
	for i in VINYL_COLORS.size():
		vcol.append({"name": VINYL_COLORS[i].name, "price": 0 if i < 2 else 200, "swatch": VINYL_COLORS[i].c})
	_parts = {
		"vinyl": {"label": "VINYL", "cam": "default", "options": [
			{"name": "None", "price": 0},
			{"name": "Rally Stripes", "price": 700},
			{"name": "Centre Stripe", "price": 600},
			{"name": "Rocker Stripes", "price": 500},
			{"name": "Two-Tone", "price": 1400},
			{"name": "Blackout Hood", "price": 900},
		]},
		"vinyl_color": {"label": "VINYL COLOR", "cam": "default", "options": vcol},
		"decal": {"label": "DECALS", "cam": "side", "options": [
			{"name": "None", "price": 0},
			{"name": "Race Number", "price": 300},
			{"name": "Syndicate Crew", "price": 450},
			{"name": "Sponsor Stack", "price": 800},
		]},
		"widebody": {"label": "WIDEBODY", "cam": "default", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Bolt-On Flares", "price": 2800, "hnd": 3},
			{"name": "Full Widebody", "price": 6500, "hnd": 6, "top": -1},
		]},
		"headlights": {"label": "HEADLIGHTS", "cam": "front", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Xenon Ice", "price": 650},
			{"name": "Amber Rally", "price": 500},
			{"name": "Smoked", "price": 400},
		]},
		"taillights": {"label": "TAILLIGHTS", "cam": "rear", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Smoked", "price": 400},
			{"name": "Clear Euro", "price": 550},
			{"name": "LED Bright", "price": 900},
		]},
		"tint": {"label": "WINDOW TINT", "cam": "side", "options": [
			{"name": "Factory", "price": 0},
			{"name": "Light Smoke", "price": 250},
			{"name": "Limo Black", "price": 450},
			{"name": "Ice Blue", "price": 700},
			{"name": "Gold Mirror", "price": 1200},
		]},
		"tires": {"label": "TIRES", "cam": "wheel", "options": [
			{"name": "Street", "price": 0},
			{"name": "Sport Compound", "price": 900, "hnd": 3},
			{"name": "Wide Semi-Slick", "price": 2200, "hnd": 6, "acc": -0.1},
			{"name": "Drag Radials", "price": 1800, "hnd": -2, "acc": -0.35},
		]},
		"ride": {"label": "RIDE HEIGHT", "cam": "low", "options": [
			{"name": "Factory", "price": 0},
			{"name": "Lowered 25 mm", "price": 400, "hnd": 1},
			{"name": "Slammed 50 mm", "price": 800, "hnd": 2},
			{"name": "Lifted 40 mm", "price": 600, "hnd": -2},
		]},
		"camber": {"label": "CAMBER", "cam": "front", "options": [
			{"name": "Factory", "price": 0},
			{"name": "Street -3 deg", "price": 300, "hnd": 2},
			{"name": "Track -6 deg", "price": 600, "hnd": 3, "acc": 0.05},
			{"name": "Show -12 deg", "price": 900, "hnd": -3, "acc": 0.1},
		]},
		"ecu": {"label": "ECU", "cam": "hood", "options": [
			{"name": "Factory Map", "price": 0},
			{"name": "Street Tune", "price": 1500, "hp": 14, "tq": 12, "top": 1, "acc": -0.1},
			{"name": "Race Tune + Launch", "price": 3800, "hp": 30, "tq": 24, "top": 3, "acc": -0.25},
		]},
		"nitro": {"label": "NITROUS", "cam": "rear", "options": [
			{"name": "Single Bottle", "price": 0},
			{"name": "Twin Bottles", "price": 2400},
			{"name": "Direct Port", "price": 5200},
		]},
		"trans": {"label": "TRANSMISSION", "cam": "low", "options": [
			{"name": "Factory 5-Speed", "price": 0},
			{"name": "Short Shifter", "price": 1100, "acc": -0.1},
			{"name": "Close-Ratio 6-Speed", "price": 4200, "acc": -0.25, "top": 2},
			{"name": "Sequential Dog Box", "price": 8800, "acc": -0.45, "top": 3},
		]},
		"final": {"label": "FINAL DRIVE", "cam": "low", "options": [
			{"name": "Factory", "price": 0},
			{"name": "Short (Acceleration)", "price": 1400, "acc": -0.35, "top": -9},
			{"name": "Long (Top Speed)", "price": 1400, "acc": 0.25, "top": 10},
		]},
		"brakes": {"label": "BRAKES", "cam": "wheel", "options": [
			{"name": "Factory", "price": 0},
			{"name": "Sport Pads + Lines", "price": 900},
			{"name": "Big Brake Kit", "price": 3400, "hnd": 1},
		]},
		"weight": {"label": "WEIGHT REDUCTION", "cam": "side", "options": [
			{"name": "Factory", "price": 0, "kg": 0},
			{"name": "Stage 1 Strip-Out", "price": 1600, "acc": -0.15, "hnd": 2, "kg": -60},
			{"name": "Stage 2 Carbon Panels", "price": 4400, "acc": -0.3, "hnd": 4, "kg": -130},
			{"name": "Stage 3 Race Shell", "price": 8200, "acc": -0.5, "hnd": 6, "kg": -210},
		]},
		"paint": {"label": "COLOR", "cam": "side", "options": paint},
		"finish": {"label": "FINISH", "cam": "side", "options": [
			{"name": "Gloss", "price": 0},
			{"name": "Metallic", "price": 600},
			{"name": "Pearl", "price": 1200},
			{"name": "Matte", "price": 800},
			{"name": "Chrome", "price": 4500},
		]},
		"front": {"label": "FRONT BUMPER", "cam": "front", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Street Lip", "price": 950, "hnd": 1},
			{"name": "Race Splitter", "price": 2100, "hnd": 3, "top": 1},
		]},
		"rear": {"label": "REAR BUMPER", "cam": "rear", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Street Valance", "price": 900, "hnd": 1},
			{"name": "Race Diffuser", "price": 1900, "hnd": 3},
		]},
		"spoiler": {"label": "SPOILER", "cam": "rear", "options": [
			{"name": "None", "price": 0},
			{"name": "Ducktail", "price": 700, "hnd": 1},
			{"name": "Street Wing", "price": 1400, "hnd": 3},
			{"name": "GT Wing", "price": 2600, "hnd": 5, "top": -1},
		]},
		"skirts": {"label": "SIDE SKIRTS", "cam": "side", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Street", "price": 800, "hnd": 1},
			{"name": "Wide Aero", "price": 1500, "hnd": 2},
		]},
		"hood": {"label": "HOOD", "cam": "hood", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Ram Scoop", "price": 1100, "hp": 4},
			{"name": "Vented Carbon", "price": 2400, "hp": 6, "acc": -0.05},
		]},
		"glow": {"label": "UNDERGLOW", "cam": "low", "options": glow},
		"rims": {"label": "RIMS", "cam": "wheel", "options": [
			{"name": "Stock Five", "price": 0},
			{"name": "Kanji TE-6", "price": 1200},
			{"name": "Blade Twin", "price": 1600},
			{"name": "Deep Dish D5", "price": 2200},
			{"name": "Monarch Mesh", "price": 2800},
			{"name": "Turbine X", "price": 3400},
		]},
		"rim_color": {"label": "RIM COLOR", "cam": "wheel", "options": rimc},
		"wheel_size": {"label": "WHEEL SIZE", "cam": "wheel", "options": [
			{"name": "17 inch", "price": 0},
			{"name": "18 inch", "price": 600, "hnd": 1},
			{"name": "19 inch", "price": 1100, "hnd": 2},
			{"name": "20 inch", "price": 1800, "hnd": 2, "acc": 0.05},
		]},
		"engine": {"label": "ENGINE", "cam": "badge", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Stage 1 Intake + ECU", "price": 2500, "hp": 28, "tq": 22, "top": 4, "acc": -0.25},
			{"name": "Stage 2 Cams + Ported", "price": 5500, "hp": 62, "tq": 48, "top": 9, "acc": -0.5},
			{"name": "Stage 3 Forged Build", "price": 9800, "hp": 110, "tq": 85, "top": 15, "acc": -0.85},
		]},
		"turbo": {"label": "INDUCTION", "cam": "front", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Street Turbo Kit", "price": 4200, "hp": 55, "tq": 60, "top": 6, "acc": -0.35},
			{"name": "Big Single Turbo", "price": 8600, "hp": 120, "tq": 115, "top": 12, "acc": -0.6},
			{"name": "Supercharger Kit", "price": 7400, "hp": 95, "tq": 105, "top": 9, "acc": -0.55},
		]},
		"exhaust": {"label": "EXHAUST", "cam": "rear", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Cat-Back Sport", "price": 1300, "hp": 12, "tq": 8, "top": 2, "acc": -0.1},
			{"name": "Straight Pipe Titanium", "price": 3200, "hp": 26, "tq": 16, "top": 4, "acc": -0.2},
		]},
		"suspension": {"label": "SUSPENSION", "cam": "low", "options": [
			{"name": "Stock", "price": 0},
			{"name": "Sport Springs", "price": 1200, "hnd": 5},
			{"name": "Race Coilovers", "price": 3000, "hnd": 10},
			{"name": "Slammed Air Ride", "price": 4800, "hnd": 7},
		]},
	}
	return _parts


static func default_config(car_id: String) -> Dictionary:
	var c := {}
	for s in SLOT_ORDER:
		c[s] = 0
	c["paint"] = CARS[car_id].default_color
	return c


static func default_owned(car_id: String) -> Dictionary:
	var o := {}
	for s in SLOT_ORDER:
		o[s] = [0]
	o["paint"] = [0, 1]
	var dc: int = CARS[car_id].default_color
	if not o["paint"].has(dc):
		o["paint"].append(dc)
	return o


## Final stats for a car + config. Returns hp, torque, top (mph), accel (0-60 s), handling (0-100).
static func stats(car_id: String, cfg: Dictionary) -> Dictionary:
	var b: Dictionary = CARS[car_id]
	var s := {"hp": float(b.hp), "torque": float(b.torque), "top": float(b.top), "accel": float(b.accel), "handling": float(b.handling), "weight": float(b.weight)}
	var p := parts()
	for slot in SLOT_ORDER:
		var idx := int(cfg.get(slot, 0))
		var opts: Array = p[slot].options
		if idx < 0 or idx >= opts.size():
			continue
		var o: Dictionary = opts[idx]
		s.hp += o.get("hp", 0)
		s.torque += o.get("tq", 0)
		s.top += o.get("top", 0)
		s.accel += o.get("acc", 0.0)
		s.handling += o.get("hnd", 0)
		s.weight += o.get("kg", 0)
	s.accel = maxf(s.accel, 2.2)
	s.handling = clampf(s.handling, 20.0, 100.0)
	return s


## Behaviour that is not a headline stat: braking, shifting, nitrous.
static func tuning(cfg: Dictionary) -> Dictionary:
	var brakes := int(cfg.get("brakes", 0))
	var trans := int(cfg.get("trans", 0))
	var nos := int(cfg.get("nitro", 0))
	return {
		"brake": [26.0, 30.0, 35.0][clampi(brakes, 0, 2)],
		"shift": [0.12, 0.085, 0.07, 0.04][clampi(trans, 0, 3)],
		"gears": 6 if trans >= 2 else 5,
		"nitro_cap": [1.0, 1.7, 1.7][clampi(nos, 0, 2)],
		"nitro_power": [1.0, 1.0, 1.4][clampi(nos, 0, 2)],
	}


## What the audio engine needs to know about a car + config.
## profile: EngineProfiles id; induction: na | turbo | sc; turbo: 0 none, 1 small, 2 big; exhaust: 0..2.
static func audio_setup(car_id: String, cfg: Dictionary) -> Dictionary:
	var b: Dictionary = CARS[car_id]
	var profile: String = b.engine
	var kit := int(cfg.get("turbo", 0))
	var induction: String = b.get("induction", "na")
	var size := int(b.get("factory_turbo", 0))
	if size > 0:
		induction = "turbo"
	if kit == 3:
		induction = "sc"
		size = 0
	elif kit > 0:
		induction = "turbo"
		size = maxi(size, kit)
	# forced induction changes the voice of a V8 completely
	if profile == "v8" and induction == "sc":
		profile = "v8sc"
	elif (profile == "v8" or profile == "v8sc") and induction == "turbo":
		profile = "v8tt"
	return {"profile": profile, "induction": induction, "turbo": size,
		"exhaust": int(cfg.get("exhaust", 0)), "stage": int(cfg.get("engine", 0))}


## Single performance number shown on event cards and used for entry requirements.
static func rating(car_id: String, cfg: Dictionary) -> int:
	var s := stats(car_id, cfg)
	return int(round(s.hp * 0.45 + s.top * 0.9 + s.handling * 1.6 + (8.0 - s.accel) * 28.0))


static func money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if v < 0 else "$") + s + out
