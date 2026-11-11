class_name CarSpecs
## Shape definitions for the procedurally lofted car bodies.
## u runs 0 (nose) -> 1 (tail). All sizes in metres; heights measured from the road.
##   top/belt/bot/hw : side-profile and plan-view curves as [u, value] keys
##   ws / rw / side  : u ranges of windshield, rear window and side glass
##   patches         : body-conforming light/trim panels  {mat, u0, u1, j0, j1}  (j = ring index 0..12)
##   lamps           : round lamps sitting on the surface {mat, u, j, r}
##   front / rear    : details on the flat end faces      {kind: panel|round, mat, x, y, w, h, r, mirror}

const R0 := 0.315  # reference tyre radius the bodies are modelled around

const SPECS := {
	"tuner": {
		"L": 4.45, "front_axle": -1.30, "rear_axle": 1.26, "tire_w": 0.235, "arch": 0.385,
		"top": [[0, 0.50], [0.02, 0.585], [0.06, 0.655], [0.18, 0.735], [0.30, 0.795], [0.33, 0.86], [0.47, 1.245], [0.55, 1.27], [0.63, 1.25], [0.80, 0.985], [0.84, 0.95], [0.96, 0.93], [1.0, 0.86]],
		"belt": [[0, 0.47], [0.03, 0.56], [0.1, 0.66], [0.3, 0.765], [0.5, 0.83], [0.8, 0.90], [0.95, 0.89], [1, 0.80]],
		"bot": [[0, 0.24], [0.03, 0.18], [0.1, 0.165], [0.9, 0.175], [0.97, 0.20], [1, 0.30]],
		"hw": [[0, 0.68], [0.025, 0.79], [0.07, 0.85], [0.2, 0.88], [0.8, 0.885], [0.94, 0.85], [0.985, 0.79], [1, 0.70]],
		"tumble": 0.62,
		"ws": [0.318, 0.462], "rw": [0.64, 0.80], "side": [0.375, 0.765], "bpillar": [0.555, 0.578],
		"seams": [0.365, 0.60], "hood": [0.075, 0.30], "scoop": [0.13, 0.27], "spoiler_u": 0.955, "mirror_u": 0.385,
		"patches": [
			{"mat": "head", "u0": 0.014, "u1": 0.056, "j0": 7, "j1": 9},
			{"mat": "signal", "u0": 0.012, "u1": 0.03, "j0": 6, "j1": 7},
		],
		"lamps": [],
		"front": [
			{"kind": "panel", "mat": "grille", "x": 0.0, "y": 0.335, "w": 0.86, "h": 0.14},
			{"kind": "round", "mat": "head", "x": 0.555, "y": 0.34, "r": 0.045, "mirror": true},
		],
		"rear": [
			{"kind": "panel", "mat": "trim", "x": 0.0, "y": 0.70, "w": 1.26, "h": 0.2},
			{"kind": "round", "mat": "tail", "x": 0.30, "y": 0.70, "r": 0.07, "mirror": true},
			{"kind": "round", "mat": "tail", "x": 0.49, "y": 0.70, "r": 0.07, "mirror": true},
			{"kind": "panel", "mat": "plate", "x": 0.0, "y": 0.70, "w": 0.34, "h": 0.11},
			{"kind": "panel", "mat": "trim", "x": 0.0, "y": 0.40, "w": 1.0, "h": 0.09},
		],
		"exhaust": {"x": [0.42], "y": 0.30, "r": 0.045, "mirror": false},
	},
	"muscle": {
		"L": 4.85, "front_axle": -1.42, "rear_axle": 1.38, "tire_w": 0.255, "arch": 0.39,
		"top": [[0, 0.745], [0.015, 0.80], [0.05, 0.835], [0.33, 0.90], [0.355, 0.94], [0.48, 1.30], [0.56, 1.325], [0.64, 1.30], [0.86, 0.96], [0.97, 0.93], [1, 0.885]],
		"belt": [[0, 0.72], [0.03, 0.785], [0.3, 0.845], [0.55, 0.87], [0.72, 0.925], [0.9, 0.915], [1, 0.86]],
		"bot": [[0, 0.27], [0.03, 0.20], [0.1, 0.18], [0.9, 0.19], [0.97, 0.22], [1, 0.32]],
		"hw": [[0, 0.87], [0.02, 0.92], [0.06, 0.945], [0.5, 0.95], [0.72, 0.962], [0.94, 0.94], [0.985, 0.905], [1, 0.85]],
		"tumble": 0.66,
		"ws": [0.348, 0.472], "rw": [0.65, 0.85], "side": [0.395, 0.745], "bpillar": [0.56, 0.582],
		"seams": [0.385, 0.615], "hood": [0.06, 0.335], "scoop": [0.12, 0.30], "spoiler_u": 0.955, "mirror_u": 0.405,
		"patches": [],
		"lamps": [],
		"front": [
			{"kind": "panel", "mat": "grille", "x": 0.0, "y": 0.60, "w": 1.60, "h": 0.2},
			{"kind": "round", "mat": "head", "x": 0.66, "y": 0.60, "r": 0.075, "mirror": true},
			{"kind": "round", "mat": "head", "x": 0.485, "y": 0.60, "r": 0.065, "mirror": true},
			{"kind": "panel", "mat": "chrome", "x": 0.0, "y": 0.435, "w": 1.66, "h": 0.07},
			{"kind": "panel", "mat": "signal", "x": 0.6, "y": 0.34, "w": 0.16, "h": 0.045, "mirror": true},
			{"kind": "panel", "mat": "grille", "x": 0.0, "y": 0.335, "w": 0.7, "h": 0.07},
		],
		"rear": [
			{"kind": "panel", "mat": "trim", "x": 0.0, "y": 0.72, "w": 1.58, "h": 0.2},
			{"kind": "panel", "mat": "tail", "x": 0.39, "y": 0.72, "w": 0.085, "h": 0.15, "mirror": true},
			{"kind": "panel", "mat": "tail", "x": 0.51, "y": 0.72, "w": 0.085, "h": 0.15, "mirror": true},
			{"kind": "panel", "mat": "tail", "x": 0.63, "y": 0.72, "w": 0.085, "h": 0.15, "mirror": true},
			{"kind": "panel", "mat": "plate", "x": 0.0, "y": 0.72, "w": 0.34, "h": 0.11},
			{"kind": "panel", "mat": "chrome", "x": 0.0, "y": 0.50, "w": 1.64, "h": 0.07},
		],
		"exhaust": {"x": [0.5], "y": 0.29, "r": 0.05, "mirror": true},
	},
	"euro": {
		"L": 4.40, "front_axle": -1.25, "rear_axle": 1.12, "tire_w": 0.245, "arch": 0.385,
		"top": [[0, 0.46], [0.02, 0.555], [0.06, 0.635], [0.2, 0.725], [0.29, 0.785], [0.32, 0.85], [0.45, 1.25], [0.52, 1.285], [0.6, 1.26], [0.8, 0.985], [0.93, 0.80], [0.98, 0.70], [1, 0.62]],
		"belt": [[0, 0.44], [0.03, 0.55], [0.08, 0.65], [0.2, 0.735], [0.3, 0.77], [0.5, 0.82], [0.75, 0.86], [0.9, 0.775], [0.97, 0.68], [1, 0.59]],
		"bot": [[0, 0.23], [0.03, 0.17], [0.1, 0.16], [0.9, 0.17], [0.97, 0.21], [1, 0.30]],
		"hw": [[0, 0.66], [0.03, 0.79], [0.08, 0.86], [0.2, 0.885], [0.5, 0.875], [0.75, 0.915], [0.92, 0.875], [0.98, 0.80], [1, 0.71]],
		"tumble": 0.66,
		"ws": [0.308, 0.442], "rw": [0.61, 0.80], "side": [0.365, 0.725], "bpillar": [0.545, 0.56],
		"seams": [0.355, 0.585], "hood": [0.07, 0.285], "scoop": [0.12, 0.25], "spoiler_u": 0.925, "mirror_u": 0.375,
		"patches": [
			{"mat": "tail", "u0": 0.95, "u1": 0.972, "j0": 7, "j1": 12},
			{"mat": "grille", "u0": 0.83, "u1": 0.91, "j0": 10, "j1": 12},
		],
		"lamps": [
			{"mat": "head", "u": 0.058, "j": 8.3, "r": 0.092},
		],
		"front": [
			{"kind": "panel", "mat": "grille", "x": 0.0, "y": 0.315, "w": 0.5, "h": 0.11},
			{"kind": "panel", "mat": "grille", "x": 0.47, "y": 0.315, "w": 0.26, "h": 0.11, "mirror": true},
			{"kind": "panel", "mat": "signal", "x": 0.47, "y": 0.39, "w": 0.24, "h": 0.022, "mirror": true},
		],
		"rear": [
			{"kind": "panel", "mat": "plate", "x": 0.0, "y": 0.50, "w": 0.34, "h": 0.11},
			{"kind": "panel", "mat": "trim", "x": 0.0, "y": 0.37, "w": 1.1, "h": 0.1},
		],
		"exhaust": {"x": [0.1], "y": 0.30, "r": 0.042, "mirror": true},
	},
}


static func get_spec(id: String) -> Dictionary:
	return SPECS[id]
