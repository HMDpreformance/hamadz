class_name EngineAudio
extends Node
## Engine / drivetrain sound driven by the PlayerCar state every frame:
## two crossfaded engine layers pitched by RPM, turbo whine + blow-off,
## tyre screech from lateral slip, road/wind noise and nitro.

var car: PlayerCar
var _on: AudioStreamPlayer
var _off: AudioStreamPlayer
var _turbo: AudioStreamPlayer
var _tire: AudioStreamPlayer
var _road: AudioStreamPlayer
var _nitro: AudioStreamPlayer
var _was_boost := 0.0
var _was_nitro := false
var _exhaust_gain := 0.0
var _pitch_mul := 1.0
var muted := false


func attach(c: PlayerCar) -> void:
	car = c
	var eng: String = CarDB.CARS[c.car_id].engine
	_on = Audio.make_loop(self, "eng_%s_on" % eng)
	_off = Audio.make_loop(self, "eng_%s_off" % eng)
	_turbo = Audio.make_loop(self, "turbo_whine")
	_tire = Audio.make_loop(self, "tire_screech")
	_road = Audio.make_loop(self, "road_wind")
	_nitro = Audio.make_loop(self, "nitro_loop")
	var ex := int(c.cfg.get("exhaust", 0))
	_exhaust_gain = ex * 2.0
	_pitch_mul = 1.0 - ex * 0.03 + int(c.cfg.get("engine", 0)) * 0.02
	c.shifted.connect(_on_shift)


static func _db(v: float) -> float:
	return linear_to_db(clampf(v, 0.0001, 4.0))


func _on_shift(_g: int) -> void:
	if car.has_turbo > 0 and _was_boost > 0.45:
		Audio.sfx("blowoff", -7.0 + car.has_turbo * 1.5, randf_range(0.92, 1.08))


func _process(dt: float) -> void:
	if car == null:
		return
	if muted:
		for p in [_on, _off, _turbo, _tire, _road, _nitro]:
			p.volume_db = -70.0
		return
	var pitch := (0.42 + car.rpm * 1.15) * _pitch_mul
	_on.pitch_scale = pitch
	_off.pitch_scale = pitch
	var load_v := car.throttle
	if car.using_nitro:
		load_v = 1.0
	_on.volume_db = lerpf(_on.volume_db, _db(0.08 + 0.92 * load_v) - 5.0 + _exhaust_gain, 0.25)
	_off.volume_db = lerpf(_off.volume_db, _db(0.75 - 0.6 * load_v) - 8.0 + _exhaust_gain * 0.5, 0.25)
	# turbo
	if car.has_turbo > 0:
		_turbo.pitch_scale = 0.55 + car.boost * 0.9
		_turbo.volume_db = lerpf(_turbo.volume_db, _db(car.boost * car.boost) - 17.0 + car.has_turbo * 2.0, 0.2)
		if _was_boost > 0.55 and car.throttle < 0.1 and car.boost < _was_boost - 0.02 and _was_boost - car.boost < 0.2:
			if not Audio.get_meta("bov_cd", false):
				Audio.set_meta("bov_cd", true)
				Audio.sfx("blowoff", -6.0 + car.has_turbo * 1.5, randf_range(0.95, 1.05))
				get_tree().create_timer(0.8).timeout.connect(func(): Audio.set_meta("bov_cd", false))
		_was_boost = car.boost
	# tyres
	var sl := clampf((absf(car.slip) - 2.5) / 9.0, 0.0, 1.0)
	if car.braking and car.speed > 14.0:
		sl = maxf(sl, 0.35)
	if absf(car.speed) < 3.0 and car.throttle > 0.9 and car.gear == 0:
		sl = maxf(sl, 0.3)
	_tire.volume_db = lerpf(_tire.volume_db, _db(sl) - 8.0, 0.3)
	_tire.pitch_scale = 0.85 + 0.25 * sl
	# road + wind
	var sp := clampf(absf(car.speed) / 60.0, 0.0, 1.0)
	_road.volume_db = lerpf(_road.volume_db, _db(sp) - 9.0, 0.2)
	_road.pitch_scale = 0.7 + sp * 0.8
	# nitro
	if car.using_nitro and not _was_nitro:
		Audio.sfx("nitro_start", -2.0)
	_was_nitro = car.using_nitro
	_nitro.volume_db = lerpf(_nitro.volume_db, -8.0 if car.using_nitro else -70.0, 0.3)
