class_name RaceDriver
extends Node
## AI racer. Drives a PlayerCar through the same physics as the player by
## writing its inputs. It follows a RacePath but is not on rails:
##   * brakes for corners from the route's curvature and its own grip,
##   * moves across the road to pass traffic, rivals and the player,
##   * backs out and rejoins after a crash, and resets if hopelessly stuck,
##   * eases off when far ahead of the player and pushes (nitro) when behind,
##   * difficulty sets how late it brakes and how hard it corners.

var car: PlayerCar
var path: RacePath
var skill := 0.9              # 0.75 cautious .. 1.05 aggressive
var lane := 0.0               # preferred offset from the racing line (m)
var road_half := 6.5
var obstacles: Array = []     # Node3D: traffic, rivals, the player
var player: PlayerCar
var player_s := 0.0           # filled by Race for catch-up logic
var s := 0.0                  # arc length along the route
var lap := 0
var active := false
var finished := false
var world: OpenWorld

var _avoid := 0.0
var _stuck := 0.0
var _reverse := 0.0
var _off := 0.0
var _nitro_cd := 0.0
var _mark_t := 0.0
var _mark_s := 0.0


func attach(c: PlayerCar, p: RacePath) -> void:
	car = c
	path = p
	c.ai = true
	s = path.project(c.global_position, 0.0, 200.0)
	if path.closed and s > path.total * 0.5:
		lap = -1          # the grid sits behind the start line, which is the end of the lap


func progress() -> float:
	return lap * path.total + s


func _physics_process(dt: float) -> void:
	if car == null or path == null:
		return
	if not active:
		car.in_throttle = 0.0
		car.in_brake = 1.0 if finished else 0.0
		car.in_steer = 0.0
		car.in_nitro = false
		return
	var pos := car.global_position
	var prev := s
	s = path.project(pos, s)
	if path.closed and s < prev - path.total * 0.5:
		lap += 1
	var v := maxf(car.speed, 0.0)
	var on_hw := world != null and world.on_highway(pos)
	road_half = 9.5 if on_hw else 6.3

	# ---- obstacles: slide sideways to pass, brake only if there is no room
	var fwd := car.forward()
	var right := car.global_transform.basis.x
	var want_avoid := 0.0
	var must_brake := false
	var reach := 9.0 + v * 0.9
	for o in obstacles:
		if o == car or not is_instance_valid(o):
			continue
		var rel: Vector3 = o.global_position - pos
		if absf(rel.y) > 3.0:
			continue
		var ah := rel.dot(fwd)
		if ah < -2.0 or ah > reach:
			continue
		var lat := rel.dot(right)
		if absf(lat) > 3.4:
			continue
		var ov := 0.0
		if o is PlayerCar:
			ov = o.speed * o.forward().dot(fwd)
		elif o is TrafficCar:
			ov = o.speed() * (-o.global_transform.basis.z).dot(fwd)
		if ov > v - 1.0 and ah > 3.0:
			continue               # it is pulling away, nothing to do
		var side := -signf(lat) if absf(lat) > 0.3 else (1.0 if lane + _avoid < 0.0 else -1.0)
		want_avoid = side * 3.4
		if ah < 5.0 + v * 0.25 and absf(lat) < 1.9:
			must_brake = true
	_avoid = move_toward(_avoid, want_avoid, dt * (9.0 if want_avoid != 0.0 else 3.0))
	var offset := clampf(lane + _avoid, -road_half, road_half)

	# ---- steering: aim at a point ahead on the (offset) racing line
	var look := 7.0 + v * 0.42
	var tp := path.pos_at(s + look)
	var td := path.dir_at(s + look)
	tp += Vector3(-td.z, 0, td.x) * offset
	var to := tp - pos
	to.y = 0.0
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	car.in_steer = clampf(-ang * 2.6, -1.0, 1.0)

	# ---- speed
	var a_lat := (14.0 + car.grip_base) * 0.62 * skill
	var lim := path.speed_limit(s, 30.0 + v * 2.4, a_lat, 15.0 * skill)
	# catch-up: never let the race fall apart in either direction
	var gap := (lap * path.total + s) - player_s
	car.top_scale = clampf(1.0 - gap * 0.0012, 0.9, 1.1) * lerpf(0.94, 1.03, clampf((skill - 0.75) / 0.3, 0.0, 1.0))
	if gap > 120.0:
		lim *= 0.92
	var thr := 1.0
	var brk := 0.0
	if v > lim + 1.5:
		thr = 0.0
		brk = clampf((v - lim) / 6.0, 0.25, 1.0)
	elif v > lim - 1.0:
		thr = 0.45
	if must_brake:
		thr = 0.0
		brk = maxf(brk, 0.7)
	if absf(ang) > 0.9 and v > 12.0:
		thr = minf(thr, 0.3)
	# the handbrake helps rotate in tight corners, the way the player uses it
	car.in_hand = absf(ang) > 0.55 and v > 15.0 and v < 34.0
	_nitro_cd = maxf(_nitro_cd - dt, 0.0)
	var straight := lim > v + 12.0 and absf(ang) < 0.08
	car.in_nitro = straight and car.nitro > 0.5 and _nitro_cd <= 0.0 and (gap < -15.0 or skill > 0.98)
	if car.in_nitro and car.nitro < 0.55:
		_nitro_cd = 6.0

	# ---- recovery
	var off_line := Vector2(pos.x - path.pos_at(s).x, pos.z - path.pos_at(s).z).length()
	_off = _off + dt if off_line > 26.0 else 0.0
	if _reverse > 0.0:
		_reverse -= dt
		car.in_throttle = 0.0
		car.in_brake = 1.0          # brake at rest is reverse in this car model
		car.in_steer = clampf(ang * 2.0, -1.0, 1.0)
		car.in_hand = false
		car.in_nitro = false
		if _reverse <= 0.0:
			_stuck = 0.0
		return
	if v < 1.5 and thr > 0.5:
		_stuck += dt
	else:
		_stuck = maxf(_stuck - dt * 2.0, 0.0)
	if _stuck > 1.1:
		_reverse = 1.0
	# no real progress for a while (scraping a wall, wedged on a rival): start over from the line
	_mark_t += dt
	if _mark_t > 5.0:
		if absf(progress() - _mark_s) < 8.0:
			_stuck = 99.0
		_mark_t = 0.0
		_mark_s = progress()
	if _stuck > 4.5 or _off > 5.0:
		reset_to_route()
	car.in_throttle = thr
	car.in_brake = brk


## Put the car back on the route, facing the right way (after an unrecoverable crash).
func reset_to_route() -> void:
	var d := path.dir_at(s + 6.0)
	var p := path.pos_at(s + 6.0) + Vector3(-d.z, 0, d.x) * lane
	if world:
		p.y = world.ground_height(p)
	car.reset_to(p, atan2(-d.x, -d.z))
	_stuck = 0.0
	_off = 0.0
	_reverse = 0.0
