class_name EventDB
## Race events of Halcyon Bay. Routes are written in grid units (x: 0..12,
## z: 0..9, whole numbers are intersections) so they read like directions:
##   Vector2(6, 4.6)  a point on the avenue x=6, a bit south of the 4th cross street
##   "hw+" / "hw-"    join the expressway and follow it clockwise / anticlockwise
##                    until level with the next point
##   "hwloop+"        one full clockwise lap of the expressway
## To add an event, append an entry; the marker, card, AI and results all follow.

const TYPE_LABEL := {
	"checkpoint": "CHECKPOINT RACE", "circuit": "CIRCUIT", "sprint": "SPRINT",
	"trial": "TIME TRIAL", "duel": "HEAD TO HEAD",
}
const TYPE_COLOR := {
	"checkpoint": Color(1.0, 0.69, 0.0), "circuit": Color(0.1, 0.85, 1.0), "sprint": Color(1.0, 0.2, 0.45),
	"trial": Color(0.3, 1.0, 0.4), "duel": Color(0.7, 0.35, 1.0),
}
const RIVALS := ["VIPER", "KOJI", "DESTINY", "BRICK", "LUXE", "NOVA", "REZ", "TORQUE", "MIDAS", "ECHO"]

const EVENTS := [
	{"id": "midnight_loop", "name": "MIDNIGHT LOOP", "type": "checkpoint", "opponents": 3, "reward": 2500, "rep": 0, "level": 0,
		"blurb": "The run that started it all. Tight downtown corners.",
		"route": [Vector2(6, 4.6), Vector2(6, 3), Vector2(8, 3), Vector2(8, 5), Vector2(7, 5), Vector2(7, 7), Vector2(5, 7), Vector2(5, 5.35)]},
	{"id": "palm_duel", "name": "PALM HEIGHTS CALL-OUT", "type": "duel", "opponents": 1, "reward": 2000, "rep": 0, "level": 0,
		"blurb": "One rival, narrow streets, parked cars. Don't blink.",
		"route": [Vector2(2, 6.5), Vector2(2, 3), Vector2(0, 3), Vector2(0, 1), Vector2(3, 1), Vector2(3, 5), Vector2(1, 5), Vector2(1, 6.4)]},
	{"id": "tunnel_run", "name": "TUNNEL RUN", "type": "trial", "opponents": 0, "reward": 1800, "rep": 0, "level": 0,
		"blurb": "Against the clock: up the ramp, through the tunnel and back into town.",
		"route": [Vector2(6, 1.5), Vector2(6, 0), "hw+", Vector2(10, 0), Vector2(10, 2), Vector2(8, 2), Vector2(8, 1.4)]},
	{"id": "ironworks_dash", "name": "IRONWORKS DASH", "type": "checkpoint", "opponents": 3, "reward": 3200, "rep": 2, "level": 1,
		"blurb": "Warehouse row and a cut through the container yard.",
		"route": [Vector2(9, 3.6), Vector2(9, 6), Vector2(10, 6), Vector2(10, 6.61), Vector2(11, 6.61), Vector2(11, 5), Vector2(12, 5), Vector2(12, 2), Vector2(10, 2), Vector2(10, 3.4)]},
	{"id": "downtown_circuit", "name": "DOWNTOWN CIRCUIT", "type": "circuit", "laps": 3, "opponents": 4, "reward": 4200, "rep": 4, "level": 1,
		"blurb": "Three laps of the financial core. Traffic does not care.",
		"route": [Vector2(5, 4.5), Vector2(5, 2), Vector2(8, 2), Vector2(8, 6), Vector2(5, 6)]},
	{"id": "bayshore_sprint", "name": "BAYSHORE SPRINT", "type": "sprint", "opponents": 5, "reward": 5500, "rep": 7, "level": 2,
		"blurb": "West ramp to east ramp, flat out across the bay bridge.",
		"route": [Vector2(0.45, 4), Vector2(0, 4), "hw-", Vector2(12, 4), Vector2(11.5, 4)]},
	{"id": "ocean_circuit", "name": "OCEAN STRIP CIRCUIT", "type": "circuit", "laps": 2, "opponents": 5, "reward": 6500, "rep": 10, "level": 2,
		"blurb": "Two laps of the beachfront under the neon.",
		"route": [Vector2(4, 9), Vector2(9, 9), Vector2(9, 8), Vector2(3, 8), Vector2(3, 9)]},
	{"id": "full_ring", "name": "THE FULL RING", "type": "sprint", "opponents": 5, "reward": 9000, "rep": 14, "level": 3, "rating": 520,
		"blurb": "One complete lap of the expressway. Bring power.",
		"route": [Vector2(6, 0.6), Vector2(6, 0), "hwloop+"]},
]


static func get_event(id: String) -> Dictionary:
	for e in EVENTS:
		if e.id == id:
			return e
	return {}


static func _gp(w: OpenWorld, g: Vector2) -> Vector3:
	return Vector3(w.x0 + g.x * City.PITCH, 0, w.z0 + g.y * City.PITCH)


static func _nearest_hw(w: OpenWorld, p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in w.hw_path.size():
		var d := Vector2(w.hw_path[i].x - p.x, w.hw_path[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


static func _hw_point(w: OpenWorld, i: int, dir: int) -> Vector3:
	# racers keep to the half of the carriageway that flows their way
	var n := w.hw_path.size()
	var a := w.hw_path[i]
	var b := w.hw_path[(i + 1) % n]
	var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var out := Vector3(d.z, 0, -d.x)
	return a + out * (-5.5 if dir > 0 else 5.5)


## World-space route points for an event.
static func build_points(w: OpenWorld, ev: Dictionary) -> PackedVector3Array:
	var out: PackedVector3Array = []
	var route: Array = ev.route
	var n := w.hw_path.size()
	for k in route.size():
		var tok = route[k]
		if tok is Vector2:
			out.append(_gp(w, tok))
			continue
		var s: String = tok
		var dir := 1 if s.ends_with("+") else -1
		var i0 := _nearest_hw(w, out[out.size() - 1])
		if s.begins_with("hwloop"):
			for m in n - 2:
				out.append(_hw_point(w, (i0 + dir * (m + 1) + n * 2) % n, dir))
			continue
		var i1 := _nearest_hw(w, _gp(w, route[k + 1]))
		var i := i0
		var guard := 0
		while guard < n:
			out.append(_hw_point(w, i, dir))
			if i == i1:
				break
			i = (i + dir + n) % n
			guard += 1
	for i in out.size():
		out[i].y = 0.0
	return out


static func is_closed(ev: Dictionary) -> bool:
	return ev.type == "circuit"


## Checkpoint positions along a path: every real corner plus fill-ins on long straights.
static func checkpoints(path: RacePath) -> PackedVector3Array:
	var out: PackedVector3Array = []
	var last_s := 0.0
	var n := path.pts.size()
	for i in range(1, n):
		var s := path.cum[i]
		var corner := path.vlim[i] < 4.2 and (i + 1 >= n or path.vlim[mini(i + 1, n - 1)] >= path.vlim[i])
		if (corner and s - last_s > 45.0) or s - last_s > 330.0:
			out.append(path.pts[i])
			last_s = s
	if path.closed:
		out.append(path.pts[0])
	else:
		if out.size() > 0 and path.total - last_s < 40.0:
			out.remove_at(out.size() - 1)
		out.append(path.pts[n - 1])
	return out


## Target times for a time trial, from the route length.
static func trial_times(path: RacePath) -> Array:
	var t := path.total / 30.0
	return [t, t * 1.14, t * 1.32]
