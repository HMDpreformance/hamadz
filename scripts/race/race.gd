class_name Race
extends Node
## One running race event: builds the route, puts the field on the grid, runs
## the countdown, tracks checkpoints / laps / positions and produces the result.
## The Drive scene owns presentation (camera, HUD); this node owns the rules.

signal countdown(n: int)          # 3, 2, 1
signal go
signal checkpoint_hit(index: int, total: int)
signal lap_done(lap: int, laps: int)
signal finished(result: Dictionary)

const CP_RADIUS := 13.0
const PAY := [1.0, 0.5, 0.25]

var ev: Dictionary
var world: OpenWorld
var path: RacePath
var cps: PackedVector3Array = []
var laps := 1
var player: PlayerCar
var rivals: Array = []            # [{car, driver, name, voice, finish_time}]
var state := "grid"               # grid | countdown | race | done
var time := 0.0
var cp_index := 0
var lap := 0
var trial_times: Array = []
var start_pos := Vector3.ZERO
var start_yaw := 0.0
var _p_s := 0.0
var _p_wraps := 0
var _finished_before := 0
var _holder: Node3D


func setup(w: OpenWorld, event: Dictionary, p: PlayerCar, traffic: Traffic, holder: Node3D) -> void:
	world = w
	ev = event
	player = p
	_holder = holder
	laps = int(ev.get("laps", 1))
	path = RacePath.make(EventDB.build_points(w, ev), EventDB.is_closed(ev))
	cps = EventDB.checkpoints(path)
	if ev.type == "trial":
		trial_times = EventDB.trial_times(path)
	var d := path.dir_at(0.0)
	var side := Vector3(-d.z, 0, d.x)
	start_yaw = atan2(-d.x, -d.z)
	var n_opp := int(ev.opponents)
	# grid: two columns, the player starts on the last row
	var slots := []
	for k in n_opp + 1:
		var row := k / 2
		var col := -1.0 if k % 2 == 0 else 1.0
		slots.append(path.pts[0] - d * (5.0 + row * 8.5) + side * col * 2.7)
	start_pos = slots[n_opp]
	start_pos.y = w.ground_height(start_pos)
	player.reset_to(start_pos, start_yaw)
	player.hold = true
	player.nitro = 1.0
	_p_s = path.project(start_pos, 0.0, 100.0)
	if path.closed and _p_s > path.total * 0.5:
		_p_wraps = -1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ev.id) + int(Game.event_record(ev.id).runs)
	var diff := int(Game.setting("difficulty", 1))
	var level := int(ev.level)
	var names := EventDB.RIVALS.duplicate()
	for k in n_opp:
		var id: String = CarDB.CAR_ORDER[rng.randi() % CarDB.CAR_ORDER.size()]
		var cfg := CarDB.default_config(id)
		cfg["paint"] = rng.randi() % CarDB.PAINTS.size()
		cfg["finish"] = rng.randi() % 3
		cfg["rims"] = rng.randi() % 6
		cfg["spoiler"] = rng.randi() % 4
		cfg["front"] = rng.randi() % 3
		cfg["glow"] = rng.randi() % CarDB.UNDERGLOW.size()
		# rivals get faster parts as the events get harder
		cfg["engine"] = clampi(level + (1 if diff == 2 else 0) - (1 if diff == 0 else 0), 0, 3)
		cfg["exhaust"] = clampi(level, 0, 2)
		cfg["suspension"] = clampi(level, 0, 2)
		if level >= 2:
			cfg["turbo"] = 1 if id != "muscle" else 3
		var c := PlayerCar.new()
		holder.add_child(c)
		c.setup(id, cfg)
		c.ground_fn = w.ground_height
		var sp: Vector3 = slots[k]
		sp.y = w.ground_height(sp)
		c.reset_to(sp, start_yaw)
		c.hold = true
		var drv := RaceDriver.new()
		c.add_child(drv)
		drv.attach(c, path)
		drv.world = w
		drv.player = p
		drv.skill = [0.8, 0.9, 0.99][diff] + level * 0.012 + rng.randf_range(-0.035, 0.035)
		drv.lane = [-2.6, 2.6, 0.0, -1.3, 1.3][k % 5]
		var voice := EngineVoice.new()
		c.add_child(voice)
		voice.position = Vector3(0, 0.6, 1.2)
		voice.setup(c.engine_profile, true, "World")
		voice.gain_db = 1.0 + c.exhaust_level * 1.5
		var nm: String = names[rng.randi() % names.size()]
		names.erase(nm)
		rivals.append({"car": c, "driver": drv, "name": nm, "voice": voice, "finish_time": -1.0})
	# everyone watches everyone
	var obs: Array = [p]
	for r in rivals:
		obs.append(r.car)
	if traffic:
		for t in traffic.cars:
			obs.append(t)
	for r in rivals:
		r.driver.obstacles = obs


func run_countdown() -> void:
	state = "countdown"
	for n in [3, 2, 1]:
		countdown.emit(n)
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree() or state != "countdown":
			return
	state = "race"
	time = 0.0
	player.hold = false
	for r in rivals:
		r.car.hold = false
		r.driver.active = true
	go.emit()


func next_checkpoint() -> Vector3:
	return cps[mini(cp_index, cps.size() - 1)]


func is_last_checkpoint() -> bool:
	return cp_index == cps.size() - 1 and lap == laps - 1


func player_progress() -> float:
	return _p_wraps * path.total + _p_s


## 1-based position of the player in the field right now.
func position() -> int:
	var pp := player_progress()
	var place := 1 + _finished_before
	for r in rivals:
		if r.finish_time < 0.0 and r.driver.progress() > pp:
			place += 1
	return place


func field_size() -> int:
	return rivals.size() + 1


func _process(dt: float) -> void:
	for r in rivals:
		var c: PlayerCar = r.car
		r.voice.update(c.rpm, c.load, dt)


func _physics_process(dt: float) -> void:
	if state != "race":
		return
	time += dt
	var pp := player.global_position
	var prev := _p_s
	_p_s = path.project(pp, _p_s)
	if path.closed:
		if _p_s < prev - path.total * 0.5:
			_p_wraps += 1
		elif _p_s > prev + path.total * 0.5:
			_p_wraps -= 1
	var ppr := player_progress()
	for r in rivals:
		r.driver.player_s = ppr
		if r.finish_time < 0.0:
			var done: bool = (r.driver.lap >= laps) if path.closed else (r.driver.s >= path.total - 4.0)
			if done:
				r.finish_time = time
				r.driver.active = false
				r.driver.finished = true
				_finished_before += 1
	var cp := cps[cp_index]
	if Vector2(pp.x - cp.x, pp.z - cp.z).length() < CP_RADIUS:
		cp_index += 1
		if cp_index >= cps.size():
			lap += 1
			if lap >= laps:
				cp_index = cps.size() - 1
				_finish()
				return
			cp_index = 0
			lap_done.emit(lap, laps)
		else:
			checkpoint_hit.emit(cp_index, cps.size())


func _finish() -> void:
	state = "done"
	var place := 1 + _finished_before
	var reward := int(ev.reward)
	var pay := 0
	var rep := 0
	var medal := ""
	if ev.type == "trial":
		place = 4
		for i in 3:
			if time <= float(trial_times[i]):
				place = i + 1
				break
		medal = ["GOLD", "SILVER", "BRONZE", "NO MEDAL"][place - 1]
		pay = int(reward * [1.0, 0.6, 0.35, 0.1][place - 1])
		rep = [2, 1, 0, 0][place - 1]
	else:
		pay = int(reward * (PAY[place - 1] if place <= 3 else 0.1))
		if ev.type == "duel" and place > 1:
			pay = int(reward * 0.1)
		rep = [3, 2, 1][place - 1] if place <= 3 else 0
	var rec := Game.record_event(ev.id, place, time, rep)
	if rec.first_win:
		pay += int(reward * 0.5)
	Game.add_money(pay)
	# standings: finished rivals in order, then the player, then the rest by distance
	var table := []
	for r in rivals:
		if r.finish_time >= 0.0:
			table.append([r.name, r.finish_time])
	table.sort_custom(func(a, b): return a[1] < b[1])
	table.append(["YOU", time])
	var rest := []
	for r in rivals:
		if r.finish_time < 0.0:
			rest.append([r.name, -r.driver.progress()])
	rest.sort_custom(func(a, b): return a[1] < b[1])
	for x in rest:
		table.append([x[0], -1.0])
	finished.emit({"place": place, "time": time, "pay": pay, "rep": rep, "medal": medal, "best": rec.best,
		"first_win": rec.first_win, "table": table, "field": field_size()})


func cleanup() -> void:
	player.hold = false
	for r in rivals:
		r.car.queue_free()
	rivals.clear()
	state = "done"
