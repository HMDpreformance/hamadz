class_name Police
extends Node3D
## Arcade police: a heat level that rises when the player drives dirty (ramming
## cars, long overspeeding) in free roam. At heat >= 1 cruisers spawn and chase.
## Lose them by breaking line of sight and distance for a few seconds; the heat
## then cools. No pursuit during a race. Cruisers are PlayerCars driven by a
## simple pursuit controller, with a flashing lightbar and siren.

const MAX_UNITS := 3
const SPAWN_DIST := 95.0
const GIVE_UP_DIST := 240.0
const COOL_TIME := 6.0        # seconds out of range before a unit peels off

var world: OpenWorld
var player: PlayerCar
var ground_fn: Callable
var units: Array = []          # [{car, light, t_far}]
var heat := 0.0                # 0..4
var active := false
var _rng := RandomNumberGenerator.new()
var _spawn_cd := 0.0
var _siren: AudioStreamPlayer
var enabled := true

signal heat_changed(level: float, busted: bool)


func setup(w: OpenWorld, p: PlayerCar) -> void:
	world = w
	player = p
	ground_fn = w.ground_height
	_rng.randomize()


func add_heat(v: float) -> void:
	if not enabled:
		return
	var was := int(ceil(heat))
	heat = clampf(heat + v, 0.0, 4.0)
	if int(ceil(heat)) != was:
		heat_changed.emit(heat, false)


func wanted() -> bool:
	return heat >= 1.0


## Called when the player starts a race or leaves free roam: clear the chase.
func stand_down() -> void:
	for u in units:
		if is_instance_valid(u.car):
			u.car.queue_free()
	units.clear()
	heat = 0.0
	active = false
	if _siren:
		_siren.stop()
	heat_changed.emit(0.0, false)


func _ready() -> void:
	_siren = AudioStreamPlayer.new()
	_siren.bus = "SFX"
	add_child(_siren)


func _physics_process(dt: float) -> void:
	if not enabled or player == null:
		return
	# cool the heat when there are no units in sight and the player is driving clean
	if heat > 0.0 and units.is_empty():
		heat = maxf(heat - dt * 0.25, 0.0)
	var target_units := 0
	if wanted():
		target_units = clampi(int(ceil(heat)), 1, MAX_UNITS)
	# spawn
	_spawn_cd -= dt
	if units.size() < target_units and _spawn_cd <= 0.0:
		_spawn_cd = 2.2
		_spawn_unit()
	# drive the units and retire the ones that lost the player
	var pp := player.global_position
	for i in range(units.size() - 1, -1, -1):
		var u: Dictionary = units[i]
		if not is_instance_valid(u.car):
			units.remove_at(i)
			continue
		_drive(u, dt)
		var d: float = u.car.global_position.distance_to(pp)
		if d > GIVE_UP_DIST:
			u.t_far += dt
		else:
			u.t_far = 0.0
		if u.t_far > COOL_TIME or (not wanted()):
			u.car.queue_free()
			units.remove_at(i)
	var busy := not units.is_empty()
	if busy != active:
		active = busy
		if active:
			heat_changed.emit(heat, true)
		else:
			heat_changed.emit(heat, false)
	# siren follows the nearest unit
	if busy:
		if not _siren.playing:
			_siren.stream = _make_siren()
			_siren.play()
		var nearest := 9999.0
		for u in units:
			nearest = minf(nearest, u.car.global_position.distance_to(pp))
		_siren.volume_db = clampf(-6.0 - (nearest - 20.0) * 0.14, -40.0, -3.0)
	elif _siren.playing:
		_siren.stop()


func _spawn_unit() -> void:
	# spawn behind the player, on the road, out of view
	var fwd := player.forward()
	var back := -fwd
	var ang := _rng.randf_range(-0.6, 0.6)
	var dir := back.rotated(Vector3.UP, ang)
	var pos := player.global_position + dir * SPAWN_DIST
	pos.x = clampf(pos.x, world.x0 + 6.0, world.x1 - 6.0)
	pos.z = clampf(pos.z, world.z0 + 6.0, world.z1 - 6.0)
	pos.y = ground_fn.call(pos)
	var c := PlayerCar.new()
	add_child(c)
	var cfg := CarDB.default_config("sedan")
	cfg["paint"] = 1            # black
	cfg["finish"] = 1
	cfg["engine"] = 2
	cfg["tint"] = 3
	c.setup("sedan", cfg)
	c.ground_fn = ground_fn
	c.ai = true
	c.top_scale = 1.04
	c.reset_to(pos, atan2(-fwd.x, -fwd.z))
	_add_lightbar(c)
	units.append({"car": c, "t_far": 0.0, "phase": _rng.randf() * TAU})


func _drive(u: Dictionary, dt: float) -> void:
	var c: PlayerCar = u.car
	var pp := player.global_position
	var to := pp - c.global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := c.forward()
	var ang := atan2(to.dot(c.global_transform.basis.x), to.dot(fwd))
	c.in_steer = clampf(ang * 1.6, -1.0, 1.0)
	c.in_throttle = 1.0 if dist > 12.0 else 0.35
	c.in_brake = 0.0
	# ease off / handbrake a sharp turn so they drift round corners instead of ploughing
	if absf(ang) > 1.2 and c.speed > 16.0:
		c.in_hand = true
		c.in_throttle = 0.5
	else:
		c.in_hand = false
	c.in_nitro = dist > 60.0
	# flash the lightbar
	u.phase += dt * 9.0
	var lb = c.get_node_or_null("Lightbar")
	if lb:
		var red: OmniLight3D = lb.get_node("R")
		var blue: OmniLight3D = lb.get_node("B")
		var on := int(u.phase) % 2 == 0
		red.light_energy = 6.0 if on else 0.0
		blue.light_energy = 0.0 if on else 6.0
		(lb.get_node("RM") as MeshInstance3D).get_surface_override_material(0).emission_energy_multiplier = 8.0 if on else 0.4
		(lb.get_node("BM") as MeshInstance3D).get_surface_override_material(0).emission_energy_multiplier = 0.4 if on else 8.0


func _add_lightbar(c: PlayerCar) -> void:
	var bar := Node3D.new()
	bar.name = "Lightbar"
	bar.position = Vector3(0, c.visual.height() + 0.08, -0.1)
	c.add_child(bar)
	for d in [["R", -0.22, Color(1.0, 0.1, 0.1)], ["B", 0.22, Color(0.15, 0.3, 1.0)]]:
		var o := OmniLight3D.new()
		o.name = d[0]
		o.position = Vector3(d[1], 0.08, 0)
		o.light_color = d[2]
		o.omni_range = 14.0
		o.light_energy = 0.0
		bar.add_child(o)
		var m := MeshInstance3D.new()
		m.name = d[0] + "M"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.36, 0.1, 0.22)
		m.mesh = bm
		m.position = Vector3(d[1], 0.05, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = d[2]
		mat.emission_enabled = true
		mat.emission = d[2]
		mat.emission_energy_multiplier = 1.0
		m.set_surface_override_material(0, mat)
		bar.add_child(m)
	# a dark base so the bar reads as hardware
	var base := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = Vector3(0.9, 0.08, 0.26)
	base.mesh = bbm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.05, 0.05, 0.06)
	base.set_surface_override_material(0, bmat)
	bar.add_child(base)


## Short synthesized two-tone wail (no asset needed).
func _make_siren() -> AudioStream:
	var sr := 22050
	var secs := 1.4
	var frames := int(sr * secs)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	for i in frames:
		var t := float(i) / sr
		var f := 700.0 if fmod(t, 0.7) < 0.35 else 460.0
		phase += TAU * f / sr
		var s := sin(phase) * 0.28
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = sr
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = frames - 1
	return st
