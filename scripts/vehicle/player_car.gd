class_name PlayerCar
extends CharacterBody3D
## Arcade vehicle controller. Flat-ground kinematic model: longitudinal speed
## from an engine/brake curve, lateral grip that the handbrake breaks loose
## (drifts), speed-sensitive steering, automatic gearbox for RPM/audio.
## Reads input from the Controls autoload, so touch/keyboard/pad all work.

signal crashed(force: float)
signal shifted(gear: int)

const GEAR_TOPS := [0.2, 0.36, 0.53, 0.7, 0.86, 1.06]

var car_id := "tuner"
var cfg := {}
var visual: CarVisual
var input_enabled := true
var ground_fn: Callable

# tuning (derived from stats in setup)
var vmax := 65.0
var a0 := 9.0
var grip_base := 9.0
var wheelbase := 2.55
var has_turbo := 0            # 0 none, 1 small frame, 2 big single
var induction := "na"        # na | turbo | sc
var engine_profile := "i4"
var exhaust_level := 0
var load := 0.0              # engine load 0..1 (what the audio hears)
var limiter := false         # bouncing off the rev limiter
var engine_on := true
# inputs: read from Controls for the player, written by a RaceDriver for AI cars
var ai := false
var in_steer := 0.0
var in_throttle := 0.0
var in_brake := 0.0
var in_hand := false
var in_nitro := false
var hold := false            # on the grid: engine revs freely, car stays put
var top_scale := 1.0         # AI catch-up / difficulty

# state
var steer := 0.0
var speed := 0.0            # forward m/s
var slip := 0.0             # lateral m/s (signed)
var rpm := 0.1              # 0..1
var gear := 0
var nitro := 1.0
var using_nitro := false
var throttle := 0.0
var braking := false
var handbraking := false
var boost := 0.0            # turbo spool 0..1
var accel_g := 0.0
var _grip := 9.0
var _shift_cut := 0.0
var _crash_cd := 0.0
var _pitch := 0.0
var _roll := 0.0
var _yaw_rate := 0.0
var _lim_phase := 0.0


func setup(id: String, config: Dictionary) -> void:
	car_id = id
	cfg = config.duplicate()
	var st := CarDB.stats(id, cfg)
	vmax = st.top * 0.447
	a0 = 26.8 / st.accel * 1.55
	grip_base = lerpf(6.0, 12.5, st.handling / 100.0)
	_grip = grip_base
	var au := CarDB.audio_setup(id, cfg)
	engine_profile = au.profile
	induction = au.induction
	has_turbo = au.turbo
	exhaust_level = au.exhaust
	visual = CarVisual.new()
	add_child(visual)
	visual.setup(id, cfg)
	wheelbase = absf(visual.axle_z(false) - visual.axle_z(true))
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(visual.half_width() * 2.0 - 0.1, 1.0, visual.length() - 0.3)
	cs.shape = bs
	cs.position.y = 0.7
	add_child(cs)


func forward() -> Vector3:
	return -global_transform.basis.z


func speed_mph() -> float:
	return absf(speed) * 2.237


func reset_to(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO
	speed = 0.0
	slip = 0.0
	gear = 0
	steer = 0.0


func _physics_process(dt: float) -> void:
	var steer_in := 0.0
	throttle = 0.0
	var brk := 0.0
	handbraking = false
	var want_nitro := false
	if ai:
		steer_in = in_steer
		throttle = in_throttle
		brk = in_brake
		handbraking = in_hand
		want_nitro = in_nitro
	elif input_enabled:
		steer_in = Controls.steer()
		throttle = Controls.throttle()
		brk = Controls.brake()
		handbraking = Controls.handbrake()
		want_nitro = Controls.nitro()
	steer = move_toward(steer, steer_in, (4.5 if absf(steer_in) > absf(steer) else 9.0) * dt)

	# ---- yaw from current forward speed
	var sp := clampf(absf(speed) / vmax, 0.0, 1.0)
	var max_ang := lerpf(0.58, 0.085, pow(sp, 0.55))
	_yaw_rate = (speed / wheelbase) * tan(steer * max_ang)
	# cap by lateral g so high-speed steering stays stable; the handbrake lifts the cap
	var lat_cap := (14.0 + grip_base) / maxf(absf(speed), 4.0)
	if handbraking and absf(speed) > 6.0:
		_yaw_rate *= 1.3
		lat_cap *= 1.4
	elif absf(slip) > 4.0:
		lat_cap *= 1.25
	_yaw_rate = clampf(_yaw_rate, -lat_cap, lat_cap)
	transform.basis = transform.basis.orthonormalized()
	rotate_y(-_yaw_rate * dt)

	var fwd := forward()
	var right := global_transform.basis.x
	var hv := Vector3(velocity.x, 0, velocity.z)
	var vf := hv.dot(fwd)
	var vl := hv.dot(right)

	# ---- nitro
	using_nitro = want_nitro and nitro > 0.02 and vf > 3.0
	if using_nitro:
		nitro = maxf(nitro - dt / 4.5, 0.0)
	else:
		nitro = minf(nitro + dt / 16.0, 1.0)

	# ---- longitudinal
	var top := vmax * (1.2 if using_nitro else 1.0) * top_scale
	var acc := 0.0
	_shift_cut = maxf(_shift_cut - dt, 0.0)
	if throttle > 0.0 and _shift_cut <= 0.0:
		if vf > -0.5:
			# turbo cars make their power on boost: soft off boost, harder once it comes in
			var pw := 1.0
			if induction == "turbo":
				pw = lerpf(0.86, 1.05, boost) if has_turbo < 2 else lerpf(0.72, 1.12, boost)
			acc += a0 * pw * throttle * clampf(1.0 - pow(maxf(vf, 0.0) / top, 2.4), 0.0, 1.0)
		else:
			acc += 20.0 * throttle
	if using_nitro:
		acc += 9.0 * clampf(1.0 - vf / top, 0.0, 1.0) + 1.5
	braking = brk > 0.05
	if braking:
		if vf > 1.0:
			acc -= 26.0 * brk
		else:
			acc -= 8.0 * brk * clampf(1.0 + vf / 13.0, 0.0, 1.0)
	var res := 0.3 + 0.0009 * vf * vf
	if throttle < 0.05:
		res += 0.8 + 1.4 * rpm          # engine braking, stronger at high revs
	if handbraking:
		res += 7.0
	if absf(vf) > 0.05:
		var dv := res * dt
		if dv > absf(vf) and absf(acc) < 0.01:
			vf = 0.0
		else:
			acc -= signf(vf) * res
	var vf_before := vf
	if hold:
		acc = 0.0
		vf = 0.0
		vl = 0.0
	vf += acc * dt
	accel_g = lerpf(accel_g, (vf - vf_before) / dt / 9.8, 1.0 - exp(-dt * 6.0))

	# ---- lateral grip
	var target_grip := grip_base
	if handbraking:
		target_grip = 1.2
	elif absf(vl) > 4.5 and absf(vf) > 8.0:
		target_grip = grip_base * (0.5 if throttle > 0.5 else 0.75)   # power keeps the slide alive
	_grip = move_toward(_grip, target_grip, (30.0 if target_grip < _grip else 7.0) * dt)
	vl *= exp(-_grip * dt)
	# sliding scrubs speed
	vf -= signf(vf) * minf(absf(vl) * 0.35 * dt, absf(vf))

	speed = vf
	slip = vl
	var pre := fwd * vf + right * vl
	velocity = pre
	move_and_slide()
	_crash_cd = maxf(_crash_cd - dt, 0.0)
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.01:
			continue
		n = n.normalized()
		var impact := -pre.dot(n)
		if impact > 1.0:
			velocity += n * impact * 0.25
			velocity *= clampf(1.0 - impact * 0.012, 0.5, 1.0)
			if impact > 4.0 and _crash_cd <= 0.0:
				_crash_cd = 0.4
				crashed.emit(impact)
		velocity *= 0.992
		# glance off walls: swing the nose along the surface instead of sticking to it
		var into := fwd.dot(n)
		if into < -0.05 and absf(speed) > 1.0:
			var tangent := fwd - n * into
			if tangent.length_squared() > 0.0004:
				tangent = tangent.normalized()
				var turn := fwd.signed_angle_to(tangent, Vector3.UP)
				rotate_y(clampf(turn, -1.0, 1.0) * minf(dt * (5.0 + absf(speed) * 0.15), 1.0))
			else:
				velocity += n * 2.0
	velocity.y = 0.0
	speed = velocity.dot(forward())
	var gy := 0.0
	if ground_fn.is_valid():
		gy = ground_fn.call(global_position)
	global_position.y = lerpf(global_position.y, gy, 1.0 - exp(-dt * 14.0))

	_gearbox(dt)
	# boost: big turbos need revs before they wake up and spool slower
	var bt := 0.0
	if induction == "turbo":
		var thr := 0.18 if has_turbo < 2 else 0.36
		bt = throttle * clampf((rpm - thr) / 0.3, 0.0, 1.0)
		if _shift_cut > 0.0:
			bt = 0.0
	boost = move_toward(boost, bt, dt * ((1.9 if has_turbo < 2 else 1.15) if bt > boost else 3.2))
	var want_load := 1.0 if using_nitro else throttle
	if _shift_cut > 0.0 or limiter and _lim_phase > 0.5:
		want_load = 0.0
	load = move_toward(load, want_load, dt * 14.0)


func _gearbox(dt: float) -> void:
	var v := absf(speed)
	var old := gear
	if speed < -0.5:
		gear = 0
		rpm = lerpf(rpm, 0.12 + 0.6 * clampf(v / 13.0, 0.0, 1.0), 1.0 - exp(-dt * 10.0))
		return
	while gear < GEAR_TOPS.size() - 1 and v > vmax * GEAR_TOPS[gear] * 0.97:
		gear += 1
	while gear > 0 and v < vmax * GEAR_TOPS[gear - 1] * 0.68:
		gear -= 1
	if gear != old:
		shifted.emit(gear)
		if gear > old:
			_shift_cut = 0.12
	var lo: float = 0.0 if gear == 0 else vmax * GEAR_TOPS[gear - 1] * 0.55
	var hi: float = vmax * GEAR_TOPS[gear]
	var target := 0.14 + 0.86 * clampf((v - lo) / (hi - lo), 0.0, 1.0)
	if v < 2.0:
		target = maxf(target, 0.14 + throttle * (0.8 if hold else 0.45))   # free revving at standstill
	# rev limiter: flat out at the top of the last gear (or held past it on nitro)
	limiter = throttle > 0.6 and gear == GEAR_TOPS.size() - 1 and target > 0.985
	if limiter:
		_lim_phase = fmod(_lim_phase + dt * 13.0, 1.0)
		target = 1.0 - 0.05 * _lim_phase
	rpm = lerpf(rpm, target, 1.0 - exp(-dt * 12.0))


func _process(dt: float) -> void:
	if visual == null:
		return
	visual.spin_wheels(speed * dt / visual.wheel_radius)
	visual.set_steer(-steer * 0.45)
	var pt := clampf(accel_g * 0.035, -0.04, 0.03)
	var rl := clampf(_yaw_rate * speed * 0.0016 + slip * 0.008, -0.07, 0.07)
	_pitch = lerpf(_pitch, pt, 1.0 - exp(-dt * 8.0))
	_roll = lerpf(_roll, rl, 1.0 - exp(-dt * 8.0))
	visual.set_body_tilt(_pitch, _roll)
	visual.set_brake(braking)
