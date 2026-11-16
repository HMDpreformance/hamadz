class_name GarageBuilding
extends Node3D
## LSXmotorsport — the player's home garage as a building in the open world.
## A lit workshop with a roll-up shutter door that rolls up as the car pulls in,
## and a glowing "ENTER" pad on the forecourt. drive.gd drives the door open/shut
## from the player's distance and handles entering the tune/dyno interior.

const W := 9.0           # half building width (x)
const D := 7.0           # half depth (z)
const HGT := 5.6         # wall height
const DOOR_W := 8.2      # shutter opening width
const DOOR_H := 4.6      # shutter opening height

var face := 1.0          # door faces +z (toward the street / player) by default
var entry_pos: Vector3   # stand here to enter
var _door: Node3D        # roll-up shutter pivot (rolls up when opened)
var _open := 0.0         # 0 shut .. 1 fully up
var _sign_lights: Array[OmniLight3D] = []
var _pad: MeshInstance3D
var _pad_mat: StandardMaterial3D


func build() -> void:
	var dz := D * face
	entry_pos = global_position + Vector3(0, 0, (D + 6.0) * face)

	# cream corrugated steel over a black band, like the real LSX workshop
	var wall := W3D.pbr("corrugated_iron", 2.4, Color(1.0, 0.95, 0.82), 0.95).duplicate() as StandardMaterial3D
	wall.uv1_triplanar = true
	wall.uv1_world_triplanar = true
	wall.uv1_scale = Vector3(1.0 / 2.4, 1.0 / 2.4, 1.0 / 2.4)
	var band := _mat(Color(0.03, 0.03, 0.035), 0.7)
	EnvKit.box(self, Vector3(W * 2 + 0.5, 1.25, 0.5), Vector3(0, 0.625, -dz), band)
	EnvKit.box(self, Vector3(0.5, 1.25, D * 2 + 0.1), Vector3(-W, 0.625, 0), band)
	EnvKit.box(self, Vector3(0.5, 1.25, D * 2 + 0.1), Vector3(W, 0.625, 0), band)
	var trim := EnvKit.solid(Color(0.05, 0.05, 0.06), 0.5, 0.4)
	var steel := EnvKit.solid(Color(0.3, 0.31, 0.34), 0.35, 0.85)

	# shell: back + two sides + roof, front wall only above/around the door
	EnvKit.box(self, Vector3(W * 2, HGT, 0.4), Vector3(0, HGT * 0.5, -dz), wall)
	EnvKit.box(self, Vector3(0.4, HGT, D * 2), Vector3(-W, HGT * 0.5, 0), wall)
	EnvKit.box(self, Vector3(0.4, HGT, D * 2), Vector3(W, HGT * 0.5, 0), wall)
	EnvKit.box(self, Vector3(W * 2, 0.4, D * 2), Vector3(0, HGT, 0), _mat(Color(0.08, 0.08, 0.09), 0.9))
	# front wall: lintel above the door + narrow jambs beside it
	EnvKit.box(self, Vector3(W * 2, HGT - DOOR_H, 0.4), Vector3(0, DOOR_H + (HGT - DOOR_H) * 0.5, dz), wall)
	var jamb := (W * 2 - DOOR_W) * 0.5
	EnvKit.box(self, Vector3(jamb + 0.05, 1.25, 0.5), Vector3(-(DOOR_W + jamb) * 0.5, 0.625, dz), band)
	EnvKit.box(self, Vector3(jamb + 0.05, 1.25, 0.5), Vector3((DOOR_W + jamb) * 0.5, 0.625, dz), band)
	EnvKit.box(self, Vector3(jamb, DOOR_H, 0.4), Vector3(-(DOOR_W + jamb) * 0.5, DOOR_H * 0.5, dz), wall)
	EnvKit.box(self, Vector3(jamb, DOOR_H, 0.4), Vector3((DOOR_W + jamb) * 0.5, DOOR_H * 0.5, dz), wall)
	# hazard frame around the opening
	var frame := EnvKit.solid(Color(0.03, 0.03, 0.035), 0.5, 0.4)
	EnvKit.box(self, Vector3(0.28, DOOR_H + 0.3, 0.5), Vector3(-DOOR_W * 0.5 - 0.1, DOOR_H * 0.5, dz + 0.05 * face), frame)
	EnvKit.box(self, Vector3(0.28, DOOR_H + 0.3, 0.5), Vector3(DOOR_W * 0.5 + 0.1, DOOR_H * 0.5, dz + 0.05 * face), frame)
	EnvKit.box(self, Vector3(DOOR_W + 0.6, 0.3, 0.5), Vector3(0, DOOR_H + 0.15, dz + 0.05 * face), frame)

	_build_door(dz)
	_build_sign(dz)
	_interior_glimpse()
	_forecourt()
	_lights(dz)


func _build_door(dz: float) -> void:
	# pivot at the top of the opening; slats hang down in local -y, so scaling
	# the pivot's y toward 0 rolls the shutter up into the lintel.
	_door = Node3D.new()
	_door.position = Vector3(0, DOOR_H, dz - 0.12 * face)
	add_child(_door)
	var a := EnvKit.solid(Color(0.22, 0.23, 0.25), 0.35, 0.8)
	var b := EnvKit.solid(Color(0.14, 0.15, 0.16), 0.4, 0.8)
	var n := int(DOOR_H / 0.2)
	for k in n:
		EnvKit.box(_door, Vector3(DOOR_W, 0.19, 0.06), Vector3(0, -0.12 - k * 0.2, 0), a if k % 2 == 0 else b)
	# handle bar near the bottom
	EnvKit.box(_door, Vector3(DOOR_W * 0.5, 0.1, 0.1), Vector3(0, -DOOR_H + 0.25, 0.04 * face), EnvKit.emissive(Color(1.0, 0.5, 0.05), 0.6))
	_apply_open()


func _build_sign(dz: float) -> void:
	# backing board over the door with the real LSXmotorsport logo, lit
	EnvKit.box(self, Vector3(7.4, 2.9, 0.16), Vector3(0, DOOR_H + 1.85, dz + 0.12 * face), EnvKit.solid(Color(0.03, 0.03, 0.04), 0.4, 0.5))
	var logo := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(7.0, 7.0 * 384.0 / 1024.0)
	logo.mesh = qm
	var lm := StandardMaterial3D.new()
	lm.albedo_texture = load("res://w3d/gen/lsx_sign.jpg")
	lm.emission_enabled = true
	lm.emission_texture = lm.albedo_texture
	lm.emission_energy_multiplier = 1.6
	lm.roughness = 0.5
	logo.material_override = lm
	logo.position = Vector3(0, DOOR_H + 1.85, dz + 0.22 * face)
	logo.rotation.y = 0.0 if face > 0.0 else PI
	add_child(logo)
	# neon tube underline
	EnvKit.box(self, Vector3(W * 1.9, 0.06, 0.06), Vector3(0, DOOR_H + 0.3, dz + 0.26 * face), EnvKit.emissive(Color(1.0, 0.1, 0.08), 3.0))


func _interior_glimpse() -> void:
	# a lift and a glow inside so the open door reveals a real workshop
	var blue := EnvKit.solid(Color(0.05, 0.16, 0.5), 0.4, 0.5)
	for sx in [-1.4, 1.4]:
		EnvKit.box(self, Vector3(0.3, 3.2, 0.34), Vector3(sx, 1.6, -D + 1.6), blue)
	EnvKit.box(self, Vector3(3.2, 0.14, 0.2), Vector3(0, 3.2, -D + 1.6), blue)
	var back := OmniLight3D.new()
	back.position = Vector3(0, 2.6, -D + 2.0)
	back.light_color = Color(0.5, 0.8, 1.0)
	back.light_energy = 2.4
	back.omni_range = 11.0
	add_child(back)
	# workbench strip
	EnvKit.box(self, Vector3(0.05, 1.4, D * 1.4), Vector3(-W + 0.1, 2.3, 0.0), EnvKit.emissive(Color(0.9, 0.95, 1.0), 2.0))


func _forecourt() -> void:
	# glowing entry pad on the ground in front of the door
	_pad = MeshInstance3D.new()
	var cyl := TorusMesh.new()
	cyl.inner_radius = 3.0
	cyl.outer_radius = 3.25
	cyl.rings = 48
	cyl.ring_segments = 4
	_pad.mesh = cyl
	_pad.scale = Vector3(1, 0.06, 1)
	_pad_mat = EnvKit.emissive(Color(1.0, 0.12, 0.1), 1.4)
	_pad.material_override = _pad_mat
	_pad.position = to_local(entry_pos) + Vector3(0, 0.05, 0)
	add_child(_pad)
	# painted lane lines leading in
	var ln := EnvKit.solid(Color(0.95, 0.85, 0.1), 0.6)
	for k in 5:
		EnvKit.box(self, Vector3(0.18, 0.02, 1.1), to_local(entry_pos) + Vector3(-1.6, 0.03, (3.0 + k * 1.6) * face), ln)
		EnvKit.box(self, Vector3(0.18, 0.02, 1.1), to_local(entry_pos) + Vector3(1.6, 0.03, (3.0 + k * 1.6) * face), ln)


func _lights(dz: float) -> void:
	for sx in [-W * 0.6, W * 0.6]:
		var o := OmniLight3D.new()
		o.position = Vector3(sx, DOOR_H + 1.0, dz + 1.2 * face)
		o.light_color = Color(0.95, 0.97, 1.0)
		o.light_energy = 3.0
		o.omni_range = 12.0
		add_child(o)
		_sign_lights.append(o)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, DOOR_H + 1.6, dz + 3.0 * face)
	spot.rotation_degrees = Vector3(-60, 0.0 if face > 0 else 180.0, 0)
	spot.spot_range = 24.0
	spot.spot_angle = 62.0
	spot.light_energy = 6.0
	spot.light_color = Color(1.0, 0.95, 0.85)
	spot.shadow_enabled = false
	add_child(spot)


# --------------------------------------------------------------- door control
## Called every frame by drive.gd with the player's distance to the entry pad.
## Rolls the door open within `near`, shut outside it, and pulses the pad.
func update_near(dist: float, near := 24.0) -> void:
	var want := 1.0 if dist < near else 0.0
	_open = move_toward(_open, want, get_process_delta_time() * 1.6)
	_apply_open()
	if _pad_mat:
		var t := clampf(1.0 - dist / near, 0.0, 1.0)
		var pulse := 0.8 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		_pad_mat.emission_energy_multiplier = 0.8 + t * pulse * 2.2


func _apply_open() -> void:
	if _door == null:
		return
	# ease the roll-up and tuck the shutter into the lintel
	var e := _open * _open * (3.0 - 2.0 * _open)
	_door.scale.y = maxf(1.0 - e, 0.03)


func is_open() -> bool:
	return _open > 0.85


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = 0.1
	return m
