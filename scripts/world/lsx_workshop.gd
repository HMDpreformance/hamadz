class_name LsxWorkshop
extends Node3D
## The LSXmotorsport workshop as a real 3D room, modelled on Hamad's photos:
## cream corrugated-steel walls over a black lower band, black steel columns,
## white drop ceiling with square LED panels, worn concrete floor with yellow
## bay lines, red scissor lift, red tool chests, oil shelf, racing banners,
## and a dyno bay (rollers in the floor, fan, straps) with a wall TV.
## Drop-in replacement for PhotoStage in the garage scene.

const HX := 11.0          # half width (x)
const Z0 := -8.0          # back wall
const Z1 := 13.0          # wall behind the camera
const H := 4.7            # drop-ceiling height
const BAND := 1.25        # height of the black lower wall band
const DYNO := Vector3(6.3, 0.0, -2.4)       # where the car stands on the rollers (faces -z)
const DOOR_Z := 3.0       # roller door centre on the left wall
const DOOR_W := 5.0
const DOOR_H := 3.5
const TV_POS := Vector3(HX - 0.14, 2.75, -5.0)
const TV_SIZE := Vector2(2.6, 1.46)

var env: Environment
var mirror_root: Node3D
var tracked: Node3D
var key_light: SpotLight3D
var shutter: Node3D
var tv_view: SubViewport
var roll_f: Node3D
var roll_r: Node3D
var straps: Node3D
var fan_blades: Node3D
var _b: MeshBatch


func build() -> void:
	env = GFX.make_environment(Color(0.8, 0.82, 0.86), 0.85, Color.BLACK, 0.0)
	env.background_color = Color(0.01, 0.012, 0.02)
	env.tonemap_exposure = 1.0
	env.glow_intensity = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	mirror_root = Node3D.new()
	mirror_root.scale = Vector3(1, -1, 1)
	add_child(mirror_root)
	_b = MeshBatch.new()
	_floor()
	_shell()
	_door()
	_banners()
	_back_wall_props()
	_lift()
	_dyno_bay()
	_b.commit(self, false)
	_tv()
	_lights()


# ------------------------------------------------------------------ helpers
func _xf(pos: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


func _box(mat: Material, pos: Vector3, size: Vector3, yaw := 0.0, faces := 63) -> void:
	_b.box(mat, _xf(pos, yaw), size, faces)


func _rbox(mat: Material, pos: Vector3, size: Vector3, basis: Basis) -> void:
	_b.box(mat, Transform3D(basis, pos), size, 63)


## Photo-scanned prop standing on the floor at `pos`, scaled to `height`.
func _prop(file: String, pos: Vector3, yaw := 0.0, height := -1.0, basis := Basis.IDENTITY) -> void:
	var p := W3D.prop(file)
	var bb: AABB = p.aabb
	var s := 1.0 if height < 0.0 else height / bb.size.y
	var centre := Vector3(bb.position.x + bb.size.x * 0.5, bb.position.y, bb.position.z + bb.size.z * 0.5)
	var xf := Transform3D(Basis(Vector3.UP, yaw) * basis * Basis.from_scale(Vector3.ONE * s), pos) * Transform3D(Basis.IDENTITY, -centre)
	_b.add_prop(p, xf)


func _picture(path: String, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if energy > 0.0:
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = energy
	return m


## Flat picture on a wall. `n` = wall normal (points into the room).
func _hang(mat: Material, centre: Vector3, size: Vector2, n: Vector3) -> void:
	var right := Vector3.UP.cross(n).normalized()
	var hx := right * size.x * 0.5
	var hy := Vector3.UP * size.y * 0.5
	var c := centre + n * 0.03
	_b.quad_uv(mat, c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy,
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))


# ------------------------------------------------------------------ room
func _floor() -> void:
	var mirror: bool = GFX.p.mirror
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HX * 2.0, Z1 - Z0)
	fl.mesh = pm
	fl.position = Vector3(0, 0, (Z0 + Z1) * 0.5)
	var m := W3D.pbr("garage_floor", 1.0, Color(1.0, 1.0, 1.0), 0.55).duplicate() as StandardMaterial3D
	m.uv1_scale = Vector3(HX * 2.0 / 4.0, (Z1 - Z0) / 4.0, 1.0)
	m.metallic = 0.0
	if mirror:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.84
		var void_box := MeshInstance3D.new()
		var vb := BoxMesh.new()
		vb.size = Vector3(HX * 2.0, 0.1, Z1 - Z0)
		void_box.mesh = vb
		void_box.position = Vector3(0, -6.0, (Z0 + Z1) * 0.5)
		void_box.material_override = W3D.flat(Color(0, 0, 0), 1.0)
		add_child(void_box)
	fl.material_override = m
	add_child(fl)
	# worn yellow bay lines, like the photos
	var y := W3D.flat(Color(0.86, 0.66, 0.06), 0.6)
	for seg in [
			[Vector3(-3.4, 0, 3.6), Vector3(3.4, 0, 3.6)], [Vector3(3.4, 0, 3.6), Vector3(3.4, 0, -3.4)],
			[Vector3(-3.4, 0, 3.6), Vector3(-3.4, 0, -3.4)],
			[Vector3(DYNO.x - 2.3, 0, 1.6), Vector3(DYNO.x + 2.3, 0, 1.6)],
			[Vector3(DYNO.x - 2.3, 0, 1.6), Vector3(DYNO.x - 2.3, 0, -6.2)],
			[Vector3(-9.6, 0, -0.6), Vector3(-4.2, 0, -0.6)]]:
		_line(y, seg[0], seg[1], 0.11)


func _line(mat: Material, a: Vector3, b: Vector3, w: float) -> void:
	var d := (b - a).normalized()
	var s := Vector3(-d.z, 0, d.x) * w * 0.5
	var up := Vector3(0, 0.006, 0)
	_b.quad(mat, a - s + up, a + s + up, b + s + up, b - s + up)


func _wall(a: Vector3, b: Vector3) -> void:
	## Wall from floor point a to b; the front is on the left of a->b seen from above... the
	## quad helper's normal is (b-a) x up, so walk the room clockwise seen from above.
	var steel := W3D.pbr("corrugated_iron", 2.4, Color(1.0, 0.95, 0.82), 0.95)
	var black := W3D.pbr("concrete_wall_008", 3.0, Color(0.1, 0.1, 0.105), 1.0)
	var u := Vector3.UP
	_b.quad(black, a, b, b + u * BAND, a + u * BAND)
	_b.quad(steel, a + u * BAND, b + u * BAND, b + u * H, a + u * H)
	# rail on top of the band and black steel columns
	var n := (b - a).cross(u).normalized()
	var dir := (b - a).normalized()
	var wl := (b - a).length()
	var dark := W3D.flat(Color(0.035, 0.035, 0.04), 0.55, 0.3)
	var yaw := atan2(dir.x, dir.z) - PI * 0.5
	_rbox(dark, (a + b) * 0.5 + u * BAND + n * 0.04, Vector3(wl, 0.08, 0.08), Basis(Vector3.UP, yaw))
	var cols := int(round(wl / 5.4))
	for i in cols + 1:
		var p := a + dir * (wl * i / float(cols))
		_rbox(dark, p + n * 0.12 + u * H * 0.5, Vector3(0.26, H, 0.24), Basis(Vector3.UP, yaw))
	# strip lights on the wall
	var tube := W3D.glow(Color(0.95, 0.97, 1.0), 3.2)
	for i in cols:
		var p := a + dir * (wl * (i + 0.5) / float(cols))
		_rbox(tube, p + n * 0.1 + u * 3.75, Vector3(1.25, 0.05, 0.05), Basis(Vector3.UP, yaw))
		_rbox(dark, p + n * 0.05 + u * 3.8, Vector3(1.35, 0.07, 0.1), Basis(Vector3.UP, yaw))


func _shell() -> void:
	_wall(Vector3(-HX, 0, Z0), Vector3(HX, 0, Z0))          # back
	_wall(Vector3(HX, 0, Z0), Vector3(HX, 0, Z1))           # right
	_wall(Vector3(HX, 0, Z1), Vector3(-HX, 0, Z1))          # behind the camera
	# left wall, split around the roller door
	var d0 := DOOR_Z - DOOR_W * 0.5
	var d1 := DOOR_Z + DOOR_W * 0.5
	_wall(Vector3(-HX, 0, Z1), Vector3(-HX, 0, d1))
	_wall(Vector3(-HX, 0, d0), Vector3(-HX, 0, Z0))
	var steel := W3D.pbr("corrugated_iron", 2.4, Color(1.0, 0.95, 0.82), 0.95)
	_b.quad(steel, Vector3(-HX, DOOR_H, d1), Vector3(-HX, DOOR_H, d0), Vector3(-HX, H, d0), Vector3(-HX, H, d1))
	# drop ceiling: 0.6 m tiles with square LED panels
	var ceil := W3D.facade("officeceiling002", Vector2(3.6, 3.6), 3.4)
	_b.quad(ceil, Vector3(-HX, H, Z0), Vector3(HX, H, Z0), Vector3(HX, H, Z1), Vector3(-HX, H, Z1))


func _door() -> void:
	var dark := W3D.flat(Color(0.035, 0.035, 0.04), 0.55, 0.3)
	var d0 := DOOR_Z - DOOR_W * 0.5
	var d1 := DOOR_Z + DOOR_W * 0.5
	_box(dark, Vector3(-HX + 0.1, DOOR_H * 0.5, d0), Vector3(0.3, DOOR_H, 0.22))
	_box(dark, Vector3(-HX + 0.1, DOOR_H * 0.5, d1), Vector3(0.3, DOOR_H, 0.22))
	_box(dark, Vector3(-HX + 0.1, DOOR_H + 0.18, DOOR_Z), Vector3(0.42, 0.42, DOOR_W + 0.3))
	# the street outside: dark, with a little sodium light
	var out := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(DOOR_W, DOOR_H)
	out.mesh = qm
	out.rotation.y = PI * 0.5
	out.position = Vector3(-HX - 0.6, DOOR_H * 0.5, DOOR_Z)
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.albedo_texture = UI.gradient_tex([Color(0.01, 0.012, 0.03), Color(0.03, 0.03, 0.045), Color(0.13, 0.09, 0.05)], [0.0, 0.7, 1.0])
	out.material_override = om
	add_child(out)
	# roll-up shutter: slides up into the lintel
	shutter = Node3D.new()
	shutter.position = Vector3(-HX + 0.06, 0, DOOR_Z)
	add_child(shutter)
	var sm := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(DOOR_W, DOOR_H)
	sm.mesh = sq
	sm.rotation.y = PI * 0.5
	sm.position.y = DOOR_H * 0.5
	var smat := W3D.pbr("painted_metal_shutter", 1.0, Color(0.8, 0.8, 0.82)).duplicate() as StandardMaterial3D
	smat.uv1_scale = Vector3(DOOR_W / 2.5, DOOR_H / 2.5, 1.0)
	sm.material_override = smat
	shutter.add_child(sm)


## 0 = shut, 1 = fully rolled up.
func set_door(open: float) -> void:
	shutter.position.y = open * DOOR_H
	shutter.scale.y = maxf(1.0 - open, 0.02)
	shutter.position.y = open * DOOR_H


func _banners() -> void:
	var back := Vector3(0, 0, 1)
	var G := "res://w3d/gen/"
	_hang(_picture(G + "banner_flag.jpg"), Vector3(-9.2, 2.9, Z0), Vector2(1.6, 1.6), back)
	_hang(_picture(G + "banner_wheels.jpg"), Vector3(-5.6, 2.85, Z0), Vector2(2.5, 1.56), back)
	_hang(_picture(G + "banner_lsx.jpg"), Vector3(0.0, 2.95, Z0), Vector2(3.6, 2.25), back)
	_hang(_picture(G + "banner_tires.jpg"), Vector3(3.6, 2.8, Z0), Vector2(1.9, 1.2), back)
	_hang(_picture(G + "banner_dyno.jpg"), Vector3(7.6, 2.9, Z0), Vector2(3.0, 1.88), back)
	_hang(_picture(G + "banner_apex.jpg"), Vector3(HX, 2.9, 0.4), Vector2(2.4, 1.5), Vector3(-1, 0, 0))
	_hang(_picture(G + "banner_wheels.jpg"), Vector3(-HX, 2.9, -4.0), Vector2(2.5, 1.56), Vector3(1, 0, 0))
	_hang(_picture(G + "banner_lsx.jpg"), Vector3(-HX, 2.95, 9.0), Vector2(3.2, 2.0), Vector3(1, 0, 0))


func _back_wall_props() -> void:
	var red := W3D.flat(Color(0.62, 0.035, 0.04), 0.35, 0.2)
	var dark := W3D.flat(Color(0.04, 0.04, 0.045), 0.5, 0.3)
	var steel := W3D.flat(Color(0.55, 0.56, 0.58), 0.35, 0.8)
	var white := W3D.flat(Color(0.86, 0.86, 0.84), 0.3)
	var z := Z0 + 0.55
	# oil shelf: black rack, rows of silver cans with red labels
	var sx := -3.4
	for px in [-0.9, 0.9]:
		for pz in [-0.22, 0.22]:
			_box(dark, Vector3(sx + px, 1.05, z + pz), Vector3(0.05, 2.1, 0.05))
	for i in 4:
		var sy := 0.25 + i * 0.58
		_box(dark, Vector3(sx, sy, z), Vector3(1.85, 0.04, 0.5))
		if i == 3:
			continue
		for k in 7:
			var cx := sx - 0.75 + k * 0.25
			if (k + i * 3) % 5 == 4:
				continue
			_box(steel, Vector3(cx, sy + 0.17, z), Vector3(0.19, 0.3, 0.12))
			_box(red, Vector3(cx, sy + 0.14, z + 0.062), Vector3(0.15, 0.14, 0.005))
	_box(W3D.flat(Color(0.85, 0.35, 0.55), 0.4), Vector3(sx + 0.5, 0.2, z + 0.75), Vector3(0.26, 0.36, 0.2))
	# spare hoods leaning on the wall
	_rbox(white, Vector3(-1.45, 1.35, Z0 + 0.42), Vector3(1.45, 1.75, 0.05), Basis(Vector3.RIGHT, -0.22) * Basis(Vector3.FORWARD, 0.06))
	_rbox(W3D.flat(Color(0.05, 0.05, 0.055), 0.25, 0.4), Vector3(5.2, 1.2, Z0 + 0.4), Vector3(1.4, 1.7, 0.05), Basis(Vector3.RIGHT, -0.2) * Basis(Vector3.FORWARD, -0.05))
	# red parts cabinet and a paint bucket
	_box(red, Vector3(-0.1, 0.75, z), Vector3(0.7, 1.5, 0.5))
	_box(white, Vector3(-0.1, 1.1, z + 0.255), Vector3(0.5, 0.12, 0.005))
	_b.box(W3D.flat(Color(0.75, 0.8, 0.9), 0.5), _xf(Vector3(-0.75, 0.2, z + 0.25)), Vector3(0.34, 0.4, 0.34))
	# red roll cab with drawers
	_tool_chest(Vector3(1.9, 0, z + 0.9), 0.15)
	_tool_chest(Vector3(-8.6, 0, 6.2), PI * 0.5)
	# evaporative cooler
	_box(W3D.flat(Color(0.8, 0.8, 0.78), 0.6), Vector3(3.3, 0.75, z + 0.4), Vector3(0.85, 1.5, 0.6))
	_box(dark, Vector3(3.3, 0.9, z + 0.705), Vector3(0.7, 0.9, 0.01))
	# photo-scanned workshop gear
	_prop("tool_cart", Vector3(-9.4, 0, 0.8), PI * 0.5)
	_prop("metal_tool_chest", Vector3(-9.4, 0.97, 0.8), PI * 0.5)
	_prop("old_military_compressor", Vector3(-10.0, 0, -6.6), 0.0, 1.2)
	_prop("portable_welding_cart", Vector3(-8.4, 0, -7.1), 0.3)
	_prop("barrel_03", Vector3(-10.2, 0, -4.9))
	_prop("barrel_03", Vector3(9.9, 0, 2.6))
	_prop("industrial_storage_cart", Vector3(9.9, 0, 5.4), PI * 0.5)
	_prop("ladder_sectioned_01", Vector3(-10.75, 0, 7.4), PI * 0.5, 2.6)
	_prop("cardboard_box_01", Vector3(9.9, 0.0, 7.2), 0.4, 0.5)
	_prop("cardboard_box_01", Vector3(10.2, 0.0, 7.9), -0.3, 0.5)
	_prop("plastic_crate_01", Vector3(-10.2, 0, 10.0), 0.2, 0.4)
	_prop("metal_toolbox", Vector3(-1.2, 0, z + 1.2), 0.5)
	_prop("metal_trash_can", Vector3(4.3, 0, z + 0.2))
	# tyre stacks
	var lay := Basis(Vector3.RIGHT, PI * 0.5)
	for st in [[Vector3(-7.4, 0, Z0 + 0.6), 5], [Vector3(-6.6, 0, Z0 + 0.65), 3], [Vector3(10.2, 0, -0.8), 4], [Vector3(-10.2, 0, 11.6), 4]]:
		for i in int(st[1]):
			var p := W3D.prop("old_tyre")
			var bb: AABB = p.aabb
			var s := 0.68 / bb.size.x
			var c := bb.position + bb.size * 0.5
			var pos: Vector3 = st[0]
			var xf := Transform3D(Basis(Vector3.UP, i * 0.7) * lay * Basis.from_scale(Vector3.ONE * s), pos + Vector3(0, 0.1 + i * 0.2, 0)) * Transform3D(Basis.IDENTITY, -c)
			_b.add_prop(p, xf)


func _tool_chest(pos: Vector3, yaw: float) -> void:
	var red := W3D.flat(Color(0.62, 0.035, 0.04), 0.35, 0.2)
	var dark := W3D.flat(Color(0.04, 0.04, 0.045), 0.5, 0.3)
	var bs := Basis(Vector3.UP, yaw)
	_rbox(red, pos + Vector3(0, 0.62, 0), Vector3(1.0, 0.9, 0.5), bs)
	_rbox(dark, pos + Vector3(0, 1.09, 0), Vector3(1.04, 0.04, 0.54), bs)
	for i in 6:
		_rbox(dark, pos + Vector3(0, 0.27 + i * 0.14, 0) + bs * Vector3(0, 0, 0.252), Vector3(0.9, 0.02, 0.01), bs)
	for sx in [-0.42, 0.42]:
		for sz in [-0.18, 0.18]:
			_rbox(dark, pos + bs * Vector3(sx, 0.08, sz), Vector3(0.08, 0.16, 0.08), bs)


func _lift() -> void:
	## red scissor lift, raised, like the one in the photo
	var red := W3D.flat(Color(0.6, 0.04, 0.045), 0.4, 0.3)
	var dark := W3D.flat(Color(0.05, 0.05, 0.055), 0.5, 0.4)
	var o := Vector3(-6.8, 0, -3.9)
	var top := 1.55
	for sx in [-0.78, 0.78]:
		_box(dark, o + Vector3(sx, 0.05, 0), Vector3(0.62, 0.1, 4.2))
		_box(red, o + Vector3(sx, top, 0), Vector3(0.62, 0.1, 4.4))
		for side in [-0.24, 0.24]:
			for dirn in [-1.0, 1.0]:
				var ang: float = atan2(top - 0.1, 3.4) * dirn
				var arm_len := sqrt(3.4 * 3.4 + (top - 0.1) * (top - 0.1))
				_rbox(red, o + Vector3(sx + side, top * 0.5 + 0.02, 0), Vector3(0.07, 0.11, arm_len), Basis(Vector3.RIGHT, ang))
		_box(dark, o + Vector3(sx, top * 0.5, 0), Vector3(0.56, 0.07, 0.07))


func _dyno_bay() -> void:
	var plate := W3D.pbr("metal_plate", 1.6, Color(0.5, 0.5, 0.52), 0.8)
	var yellow := W3D.flat(Color(0.86, 0.66, 0.06), 0.6)
	var a := DYNO + Vector3(-1.45, 0.008, -3.0)
	var c := DYNO + Vector3(1.45, 0.008, 3.0)
	_b.quad(plate, Vector3(a.x, a.y, c.z), Vector3(c.x, a.y, c.z), Vector3(c.x, a.y, a.z), a)
	_line(yellow, Vector3(a.x, 0.004, a.z), Vector3(a.x, 0.004, c.z), 0.1)
	_line(yellow, Vector3(c.x, 0.004, a.z), Vector3(c.x, 0.004, c.z), 0.1)
	# roller sets (positioned under the car's axles by set_axles)
	roll_f = _roller_set()
	roll_r = _roller_set()
	set_axles(-1.3, 1.3, 4.4)
	# cooling fan in front of the car
	var orange := W3D.flat(Color(0.9, 0.36, 0.04), 0.45, 0.2)
	var fz := DYNO.z - 4.3
	var fan := Node3D.new()
	fan.position = Vector3(DYNO.x, 0.78, fz)
	add_child(fan)
	var drum := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.56
	tm.outer_radius = 0.7
	tm.rings = 28
	tm.ring_segments = 6
	drum.mesh = tm
	drum.rotation.x = PI * 0.5
	drum.scale = Vector3(1, 3.2, 1)
	drum.material_override = orange
	fan.add_child(drum)
	fan_blades = Node3D.new()
	fan.add_child(fan_blades)
	for i in 5:
		var bl := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 0.52, 0.02)
		bl.mesh = bm
		bl.material_override = W3D.flat(Color(0.12, 0.12, 0.13), 0.4, 0.6)
		var hub := Node3D.new()
		hub.rotation.z = i * TAU / 5.0
		bl.position.y = 0.3
		bl.rotation.y = 0.5
		hub.add_child(bl)
		fan_blades.add_child(hub)
	_box(W3D.flat(Color(0.12, 0.12, 0.13), 0.5, 0.5), Vector3(DYNO.x - 0.55, 0.06, fz), Vector3(0.08, 0.12, 0.7))
	_box(W3D.flat(Color(0.12, 0.12, 0.13), 0.5, 0.5), Vector3(DYNO.x + 0.55, 0.06, fz), Vector3(0.08, 0.12, 0.7))
	# blue dyno control cabinet with extraction hose
	var blue := W3D.flat(Color(0.05, 0.16, 0.5), 0.4, 0.2)
	_box(blue, Vector3(HX - 0.75, 0.8, Z0 + 0.7), Vector3(0.9, 1.6, 0.7))
	_box(W3D.glow(Color(0.2, 0.9, 0.5), 1.2), Vector3(HX - 0.75, 1.25, Z0 + 1.056), Vector3(0.5, 0.3, 0.01))
	var hose := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.13
	hm.bottom_radius = 0.13
	hm.height = 3.2
	hose.mesh = hm
	hose.position = Vector3(HX - 1.5, H - 1.5, Z0 + 0.6)
	hose.rotation.z = 0.25
	hose.material_override = W3D.flat(Color(0.7, 0.7, 0.68), 0.6)
	add_child(hose)
	# wheel chocks and strap anchors
	straps = Node3D.new()
	straps.visible = false
	add_child(straps)


func _roller_set() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var pit := MeshInstance3D.new()
	var pq := PlaneMesh.new()
	pq.size = Vector2(2.7, 1.05)
	pit.mesh = pq
	pit.position.y = 0.012
	pit.material_override = W3D.flat(Color(0.012, 0.012, 0.014), 0.9)
	n.add_child(pit)
	var knurl: StandardMaterial3D = W3D.pbr("metal_plate", 0.35, Color(0.62, 0.62, 0.64), 0.7)
	for dz in [-0.25, 0.25]:
		var r := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.2
		cm.height = 2.5
		cm.radial_segments = 20
		r.mesh = cm
		r.rotation.z = PI * 0.5
		r.position = Vector3(0, -0.105, dz)
		r.material_override = knurl
		r.set_meta("roller", true)
		n.add_child(r)
	return n


## Put the roller sets under the car's axles (car local z, car faces -z) and
## tie the rear down with ratchet straps.
func set_axles(front_z: float, rear_z: float, car_len: float) -> void:
	roll_f.position = DYNO + Vector3(0, 0, front_z)
	roll_r.position = DYNO + Vector3(0, 0, rear_z)
	if straps == null:
		return
	for c in straps.get_children():
		c.queue_free()
	var web := W3D.flat(Color(0.85, 0.7, 0.05), 0.7)
	var tail := DYNO.z + car_len * 0.5 - 0.15
	for sx in [-1.0, 1.0]:
		var a := Vector3(DYNO.x + sx * 0.45, 0.34, tail)
		var b := Vector3(DYNO.x + sx * 1.25, 0.02, tail + 1.5)
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.012, a.distance_to(b))
		m.mesh = bm
		m.material_override = web
		straps.add_child(m)
		m.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
		var hook := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.16, 0.05, 0.16)
		hook.mesh = hb
		hook.position = b
		hook.material_override = W3D.flat(Color(0.1, 0.1, 0.11), 0.5, 0.6)
		straps.add_child(hook)


## Spin the rollers (radians of wheel rotation this frame) and the fan.
func spin_rollers(front: float, rear: float, fan: float) -> void:
	for pair in [[roll_f, front], [roll_r, rear]]:
		for r in (pair[0] as Node3D).get_children():
			if r.has_meta("roller"):
				(r as Node3D).rotate_object_local(Vector3.UP, pair[1])
	fan_blades.rotate_z(fan)


# ------------------------------------------------------------------ dyno TV
func _tv() -> void:
	tv_view = SubViewport.new()
	tv_view.size = Vector2i(1024, 576)
	tv_view.disable_3d = true
	tv_view.transparent_bg = false
	tv_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(tv_view)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.08, TV_SIZE.y + 0.1, TV_SIZE.x + 0.1)
	frame.mesh = fm
	frame.position = TV_POS + Vector3(0.05, 0, 0)
	frame.material_override = W3D.flat(Color(0.02, 0.02, 0.022), 0.3, 0.4)
	add_child(frame)
	var scr := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = TV_SIZE
	scr.mesh = qm
	scr.rotation.y = -PI * 0.5
	scr.position = TV_POS
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tv_view.get_texture()
	m.albedo_color = Color(1.25, 1.25, 1.25)
	scr.material_override = m
	add_child(scr)
	# wall arm
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.12, 0.3, 0.3)
	arm.mesh = am
	arm.position = TV_POS + Vector3(0.1, 0, 0)
	arm.material_override = frame.material_override
	add_child(arm)


## Screen rectangle of the TV for the given camera (for tap tests).
func tv_screen_rect(cam: Camera3D) -> Rect2:
	var r := Rect2()
	var first := true
	for sy in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var p := TV_POS + Vector3(0, sy * TV_SIZE.y, sz * TV_SIZE.x)
			if cam.is_position_behind(p):
				return Rect2()
			var s := cam.unproject_position(p)
			if first:
				r = Rect2(s, Vector2.ZERO)
				first = false
			else:
				r = r.expand(s)
	return r


# ------------------------------------------------------------------ light
func _lights() -> void:
	key_light = SpotLight3D.new()
	key_light.position = Vector3(0.6, H - 0.15, 1.6)
	key_light.look_at_from_position(key_light.position, Vector3(0, 0.3, 0))
	key_light.spot_range = 11.0
	key_light.spot_angle = 50.0
	key_light.spot_attenuation = 0.6
	key_light.light_energy = 4.2
	key_light.light_color = Color(0.97, 0.98, 1.0)
	key_light.shadow_enabled = GFX.p.shadows
	key_light.shadow_blur = 2.0
	add_child(key_light)
	var dy := SpotLight3D.new()
	dy.position = DYNO + Vector3(-0.8, H - 0.15, 1.2)
	dy.look_at_from_position(dy.position, DYNO + Vector3(0, 0.3, 0))
	dy.spot_range = 11.0
	dy.spot_angle = 52.0
	dy.spot_attenuation = 0.6
	dy.light_energy = 3.6
	dy.light_color = Color(0.95, 0.97, 1.0)
	dy.shadow_enabled = GFX.p.shadows
	add_child(dy)
	for p in [Vector3(-6.5, 3.9, -3.0), Vector3(0, 3.9, -4.5), Vector3(-6.0, 3.9, 6.0), Vector3(5.5, 3.9, 6.5), Vector3(7.5, 3.9, -4.5), Vector3(-0.5, 3.9, 4.0)]:
		var o := OmniLight3D.new()
		o.position = p
		o.light_color = Color(0.93, 0.96, 1.0)
		o.light_energy = 2.2
		o.omni_range = 13.0
		o.omni_attenuation = 0.8
		add_child(o)
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0, H * 0.5, (Z0 + Z1) * 0.5)
	probe.size = Vector3(HX * 2.0, H, Z1 - Z0)
	probe.origin_offset = Vector3(0, -H * 0.5 + 1.2, -(Z0 + Z1) * 0.5 + 1.0)
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.78, 0.8, 0.86)
	probe.ambient_color_energy = 0.85
	probe.intensity = 0.9
	add_child(probe)
