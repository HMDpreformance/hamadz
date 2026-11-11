class_name Traffic
extends Node3D
## Pooled civilian traffic for the open world. A fixed number of cars is kept
## around the player: cars that fall far behind are recycled onto a lane near
## (but not next to) the player, so the streets always feel busy without ever
## simulating the whole city. Street cars wander the grid, turning at random and
## obeying the lights; highway cars lap the expressway in both directions.

const LANE := 5.6             # lane centre, metres from the road centre line
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # N E S W
const RECYCLE := 300.0

var world: OpenWorld
var player: Node3D
var cars: Array[TrafficCar] = []
var _rng := RandomNumberGenerator.new()
var _hw_lanes := [PackedVector3Array(), PackedVector3Array()]
var _t := 0.0


func setup(w: OpenWorld, p: Node3D, street: int, highway: int) -> void:
	world = w
	player = p
	_rng.seed = 5
	# highway lanes: offset the centre line to the right of each direction of travel
	var n := world.hw_path.size()
	for i in n:
		var a := world.hw_path[i]
		var b := world.hw_path[(i + 1) % n]
		var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var out := Vector3(d.z, 0, -d.x)
		_hw_lanes[0].append(a - out * 6.0)     # clockwise traffic keeps to the inner half
		_hw_lanes[1].append(a + out * 6.0)
	for k in street + highway:
		var c := TrafficCar.new()
		c.manager = self
		add_child(c)
		c.setup(CarDB.CAR_ORDER[_rng.randi() % CarDB.CAR_ORDER.size()], [6, 9, 10, 11, 5, 4, 0, 2][_rng.randi() % 8])
		cars.append(c)
		if k < street:
			c.cruise = _rng.randf_range(10.0, 14.0)
			_spawn_street(c, 60.0, 260.0)
		else:
			c.cruise = _rng.randf_range(24.0, 31.0)
			c.hw_sign = 1 if k % 2 == 0 else -1
			_spawn_highway(c)


func green(axis: int) -> bool:
	return world.ns_green() if axis == 1 else world.ew_green()


func height_at(p: Vector3) -> float:
	if world.on_highway(p):
		return world.hw_height(p.z)
	return 0.0


func _node_pos(nd: Vector2i) -> Vector3:
	return Vector3(world.road_x(nd.x), 0, world.road_z(nd.y))


func _valid(nd: Vector2i) -> bool:
	return nd.x >= 0 and nd.x <= OpenWorld.NX and nd.y >= 0 and nd.y <= OpenWorld.NZ


func _segment(c: TrafficCar, from: Vector2i, dir: int) -> void:
	var dv: Vector2i = DIRS[dir]
	var to := from + dv
	var d3 := Vector3(dv.x, 0, dv.y)
	var right := Vector3(-d3.z, 0, d3.x)
	var hr := City.ROAD * 0.5
	c.seg_a = _node_pos(from) + d3 * (hr + 2.0) + right * LANE
	c.seg_b = _node_pos(to) - d3 * (hr + 3.0) + right * LANE
	c.grid_node = to
	c.grid_dir = dir
	var interior := to.x > 0 and to.x < OpenWorld.NX and to.y > 0 and to.y < OpenWorld.NZ
	c.stop_at_end = 0 if not interior else (1 if dir % 2 == 0 else 2)


func next_segment(c: TrafficCar) -> void:
	if c.hw_index >= 0:
		var lane: PackedVector3Array = _hw_lanes[0 if c.hw_sign > 0 else 1]
		var n := lane.size()
		c.hw_index = (c.hw_index + c.hw_sign + n) % n
		c.seg_a = c.seg_b
		c.seg_b = lane[(c.hw_index + c.hw_sign + n) % n]
		return
	# at a junction: mostly straight on, sometimes a turn, never a U-turn unless boxed in
	var opts := []
	for turn: int in [0, 0, 0, 1, 3]:
		var nd := (c.grid_dir + turn) % 4
		if _valid(c.grid_node + DIRS[nd]):
			opts.append(nd)
	if opts.is_empty():
		opts.append((c.grid_dir + 2) % 4)
	_segment(c, c.grid_node, opts[_rng.randi() % opts.size()])


func _spawn_street(c: TrafficCar, rmin: float, rmax: float) -> void:
	var pp := player.global_position if player else Vector3.ZERO
	for attempt in 24:
		var nd := Vector2i(_rng.randi_range(0, OpenWorld.NX), _rng.randi_range(0, OpenWorld.NZ))
		var dir := _rng.randi() % 4
		if not _valid(nd + DIRS[dir]):
			continue
		var mid := (_node_pos(nd) + _node_pos(nd + DIRS[dir])) * 0.5
		var d := Vector2(mid.x - pp.x, mid.z - pp.z).length()
		if d < rmin or d > rmax:
			continue
		var clear := true
		for o in cars:
			if o != c and o.global_position.distance_to(mid) < 40.0:
				clear = false
				break
		if not clear:
			continue
		c.hw_index = -1
		_segment(c, nd, dir)
		c.place(c.seg_a, c.seg_b, _rng.randf_range(0.25, 0.7))
		return
	# nowhere suitable this time: park it far away and try again on the next pass
	c.hw_index = -1
	_segment(c, Vector2i(0, 0), 1)
	c.place(c.seg_a, c.seg_b, 0.5)


func _spawn_highway(c: TrafficCar) -> void:
	var lane: PackedVector3Array = _hw_lanes[0 if c.hw_sign > 0 else 1]
	var n := lane.size()
	var pp := player.global_position if player else Vector3.ZERO
	var best := -1
	for attempt in 30:
		var i := _rng.randi() % n
		var d := lane[i].distance_to(pp)
		if d > 120.0 and d < 420.0:
			best = i
			break
	if best < 0:
		best = _rng.randi() % n
	c.hw_index = best
	c.place(lane[best], lane[(best + c.hw_sign + n) % n], 0.0)
	c.seg_a = lane[best]
	c.seg_b = lane[(best + c.hw_sign + n) % n]


func _physics_process(dt: float) -> void:
	# who is stuck behind whom (cheap n^2 over a dozen cars + the player)
	for c in cars:
		var fwd := -c.global_transform.basis.z
		var right := c.global_transform.basis.x
		var blocked := false
		var reach := 7.0 + c.speed() * 0.7
		if player:
			var rel := player.global_position - c.global_position
			var ah := rel.dot(fwd)
			if ah > 0.0 and ah < reach and absf(rel.dot(right)) < 2.0 and absf(rel.y) < 3.0:
				blocked = true
		if not blocked:
			for o in cars:
				if o == c:
					continue
				var rel2 := o.global_position - c.global_position
				var ah2 := rel2.dot(fwd)
				if ah2 > 0.0 and ah2 < reach and absf(rel2.dot(right)) < 2.0:
					blocked = true
					break
		c.blocked = blocked
	_t -= dt
	if _t <= 0.0 and player:
		_t = 1.0
		var pp := player.global_position
		for c in cars:
			var d := Vector2(c.global_position.x - pp.x, c.global_position.z - pp.z).length()
			if c.hw_index < 0 and d > RECYCLE:
				_spawn_street(c, 150.0, 270.0)
			elif c.hw_index >= 0 and d > 520.0 and absf(world.hw_dist(pp)) < 260.0:
				_spawn_highway(c)
