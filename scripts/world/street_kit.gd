class_name StreetKit
## Builds real 3D street architecture into a MeshBatch: apartment houses from
## the modular facade kit, modern mid-rises with glass shopfronts, towers,
## warehouses, sidewalks and street furniture.
##
## Facade frame F: origin = bottom-left-front corner seen from the street,
## x = right along the facade, y = up, z = out toward the street.

const FLOOR := 3.0
const SHOP_H := 4.5

const PLASTER_TINTS := [Color(1, 1, 1), Color(0.93, 0.84, 0.7), Color(0.78, 0.8, 0.84), Color(0.92, 0.7, 0.58), Color(0.72, 0.78, 0.7), Color(0.6, 0.62, 0.66)]
const AWNING := [Color(0.55, 0.06, 0.06), Color(0.05, 0.22, 0.42), Color(0.08, 0.3, 0.16), Color(0.75, 0.6, 0.2), Color(0.1, 0.1, 0.11), Color(0.7, 0.35, 0.08)]
# ambientCG facade skins: [name, metres per repeat x, y, glow]
const MID_SKINS := [["facade019a", 15.0, 15.0, 2.0], ["facade020a", 15.0, 15.0, 2.0], ["facade017", 18.0, 18.0, 2.4]]
const TOWER_SKINS := [["facade005", 24.0, 24.0, 0.0], ["facade007", 40.0, 40.0, 2.6], ["facade009", 44.0, 44.0, 2.6], ["facade010", 60.0, 60.0, 2.2],
	["facade012", 48.0, 48.0, 2.0], ["facade014", 52.0, 52.0, 2.0], ["facade015", 48.0, 48.0, 2.0], ["facade017", 30.0, 30.0, 2.4]]

static var _tinted := {}


static func frame(origin: Vector3, out: Vector3) -> Transform3D:
	var right := Vector3.UP.cross(out).normalized()
	return Transform3D(Basis(right, Vector3.UP, out), origin)


static func _loc(F: Transform3D, x: float, y: float, z: float) -> Transform3D:
	return F * Transform3D(Basis.IDENTITY, Vector3(x, y, z))


static func _plaster(tint: int) -> Material:
	var base := W3D.kit_material("plaster")
	if tint == 0 or base == null:
		return base
	if not _tinted.has(tint):
		var m: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
		m.albedo_color = PLASTER_TINTS[tint]
		_tinted[tint] = m
	return _tinted[tint]


static func _side_plaster(tint: int) -> Material:
	## The kit's wall texture on generated quads (UVs in metres -> one repeat per 3 m bay).
	var key := 100 + tint
	if not _tinted.has(key):
		var m: StandardMaterial3D = (W3D.kit_material("plaster") as StandardMaterial3D).duplicate()
		m.albedo_color = PLASTER_TINTS[tint]
		m.uv1_scale = Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0)
		_tinted[key] = m
	return _tinted[key]


# ------------------------------------------------------------------ helpers
## Plain wall quad on the facade plane (local rectangle x0..x1, y0..y1 at depth z).
static func wall(b: MeshBatch, F: Transform3D, mat: Material, x0: float, x1: float, y0: float, y1: float, z := 0.0, uv_world := true) -> void:
	var uo := Vector2(x0, -y1) if uv_world else Vector2.ZERO
	b.quad(mat, F * Vector3(x0, y0, z), F * Vector3(x1, y0, z), F * Vector3(x1, y1, z), F * Vector3(x0, y1, z), uo)


## Box in facade coordinates, given by its min corner and size.
static func lbox(b: MeshBatch, F: Transform3D, mat: Material, mn: Vector3, size: Vector3, faces := 31) -> void:
	b.box(mat, _loc(F, mn.x + size.x * 0.5, mn.y + size.y * 0.5, mn.z + size.z * 0.5), size, faces)


## Window pane with interior-mapping UVs (metres along the facade / up).
static func pane(b: MeshBatch, F: Transform3D, mat: Material, x0: float, x1: float, y0: float, y1: float, z: float, cell_org := Vector2.ZERO) -> void:
	b.quad_uv(mat, F * Vector3(x0, y0, z), F * Vector3(x1, y0, z), F * Vector3(x1, y1, z), F * Vector3(x0, y1, z),
		Vector2(x0, y0) - cell_org, Vector2(x1, y0) - cell_org, Vector2(x1, y1) - cell_org, Vector2(x0, y1) - cell_org)


## Body of a building behind its facade: two side walls, back wall and a flat
## roof with parapet. The front is left open for the caller's facade.
static func shell(b: MeshBatch, F: Transform3D, w: float, h: float, d: float, side_mat: Material, roof_mat: Material, y0 := 0.0) -> void:
	# sides (seen from outside)
	b.quad(side_mat, F * Vector3(w, y0, 0), F * Vector3(w, y0, -d), F * Vector3(w, h, -d), F * Vector3(w, h, 0))
	b.quad(side_mat, F * Vector3(0, y0, -d), F * Vector3(0, y0, 0), F * Vector3(0, h, 0), F * Vector3(0, h, -d))
	b.quad(side_mat, F * Vector3(w, y0, -d), F * Vector3(0, y0, -d), F * Vector3(0, h, -d), F * Vector3(w, h, -d))
	b.quad(roof_mat, F * Vector3(0, h, 0), F * Vector3(w, h, 0), F * Vector3(w, h, -d), F * Vector3(0, h, -d))
	# parapet
	var pm := side_mat
	lbox(b, F, pm, Vector3(0, h, -0.3), Vector3(w, 0.9, 0.3), 31)
	lbox(b, F, pm, Vector3(0, h, -d), Vector3(w, 0.9, 0.3), 31)
	lbox(b, F, pm, Vector3(0, h, -d + 0.3), Vector3(0.3, 0.9, d - 0.6), 31)
	lbox(b, F, pm, Vector3(w - 0.3, h, -d + 0.3), Vector3(0.3, 0.9, d - 0.6), 31)


static func roof_clutter(b: MeshBatch, F: Transform3D, w: float, h: float, d: float, r: RandomNumberGenerator) -> void:
	var metal := W3D.pbr("metal_plate", 2.0, Color(0.75, 0.77, 0.8))
	var conc := W3D.pbr("concrete_wall_008", 3.0, Color(0.7, 0.7, 0.7))
	var n := 1 + int(w * d / 90.0)
	for k in mini(n, 5):
		var sx := r.randf_range(1.2, 2.6)
		var sz := r.randf_range(1.2, 2.2)
		var px := r.randf_range(1.0, maxf(w - sx - 1.0, 1.1))
		var pz := -r.randf_range(1.5, maxf(d - sz - 1.0, 1.6)) - sz
		if r.randf() < 0.6:
			lbox(b, F, metal, Vector3(px, h, pz), Vector3(sx, r.randf_range(0.9, 1.6), sz))      # AC / plant unit
		else:
			lbox(b, F, conc, Vector3(px, h, pz), Vector3(sx + 1.0, 2.6, sz + 1.0))                # stair / lift head
	if r.randf() < 0.35:
		var px2 := r.randf_range(1.0, w - 1.5)
		lbox(b, F, metal, Vector3(px2, h, -d * 0.5), Vector3(0.08, r.randf_range(3.0, 7.0), 0.08), 15)   # mast


# ------------------------------------------------------------------ apartment house (facade kit)
## European-style plastered apartment house from the real modular kit.
## w must be a multiple of 3 m. Returns its height.
static func apartment(b: MeshBatch, F: Transform3D, w: float, floors: int, d: float, r: RandomNumberGenerator, shop_ground := false, signs: Array = []) -> float:
	var bays := int(round(w / 3.0))
	var tint := r.randi() % PLASTER_TINTS.size()
	var plaster := _plaster(tint)
	var remap := {W3D.kit_material("plaster"): plaster, W3D.kit_material("glass"): W3D.window_glass(0.45)}
	var glass_gen := W3D.window_glass(0.45, Vector2(3, 3), 3.5, 2.2, false, true)
	var trim := W3D.kit_material("trim_02")
	# one window type per column, mirrored for a composed facade
	var kinds := ["large", "double", "small"]
	var cols := []
	for i in bays:
		cols.append(kinds[r.randi() % 3])
	for i in bays / 2:
		cols[bays - 1 - i] = cols[i]
	var door_bay := r.randi_range(0, bays - 1)
	var y0 := 0.0
	var first := 0
	if shop_ground:
		shopfront(b, F, w, r, signs)
		y0 = SHOP_H
		first = 1
	for f in range(first, floors):
		var y := y0 + (f - first) * FLOOR
		for i in bays:
			var M := _loc(F, (i + 1) * 3.0, y, 0)
			var kind: String = cols[i]
			if f == 0 and i == door_bay:
				b.add_mesh(W3D.kit("wall_door_centered_large_01"), M, remap)
				b.add_mesh(W3D.kit("door_centered_large_01"), M, remap)
				b.add_mesh(W3D.kit("dado_door_centered_large_01"), M, remap)
				continue
			var v := 1 if f == 0 else (2 if f < floors - 1 else 3)
			var wn := "wall_window_centered_%s_%02d" % [kind, v]
			var gn := "window_centered_%s_%02d" % [kind, v]
			b.add_mesh(W3D.kit(wn), M, remap)
			if f == 0:
				b.add_mesh(W3D.kit(gn), M, remap)
			else:
				# upper floors: cheap window that fills the same opening
				var a := W3D.kit_aabb(gn)
				var x0 := (i + 1) * 3.0 + a.position.x
				var x1 := x0 + a.size.x
				var ya := y + a.position.y
				var yb := ya + a.size.y
				pane(b, F, glass_gen, x0, x1, ya, yb, -0.2, Vector2(0.0, y0))
				lbox(b, F, trim, Vector3(x0, ya, -0.2), Vector3(a.size.x, 0.07, 0.2), 16 | 1)           # sill
				lbox(b, F, trim, Vector3((x0 + x1) * 0.5 - 0.03, ya, -0.19), Vector3(0.06, a.size.y, 0.05), 1 | 4 | 8)   # mullion
				# reveals
				b.quad(plaster, F * Vector3(x0, ya, 0), F * Vector3(x0, ya, -0.2), F * Vector3(x0, yb, -0.2), F * Vector3(x0, yb, 0))
				b.quad(plaster, F * Vector3(x1, ya, -0.2), F * Vector3(x1, ya, 0), F * Vector3(x1, yb, 0), F * Vector3(x1, yb, -0.2))
				b.quad(plaster, F * Vector3(x0, yb, -0.2), F * Vector3(x1, yb, -0.2), F * Vector3(x1, yb, 0), F * Vector3(x0, yb, 0))
			if f == 0:
				b.add_mesh(W3D.kit("dado_standard_standard_01"), M, remap)
			elif f > first:
				b.add_mesh(W3D.kit("cornice_standard_standard_01"), M, remap)
	var h := y0 + (floors - first) * FLOOR
	# crown moulding (real kit piece on small houses, a plain projecting cornice on long ones)
	lbox(b, F, trim, Vector3(-0.12, h, -0.1), Vector3(w + 0.24, 0.22, 0.4))
	lbox(b, F, trim, Vector3(-0.2, h + 0.22, -0.1), Vector3(w + 0.4, 0.2, 0.55))
	h += 0.42
	var side := _side_plaster(tint)
	shell(b, F, w, h, d, side, W3D.pbr("concrete_wall_008", 4.0, Color(0.5, 0.5, 0.5)), 0.0)
	roof_clutter(b, F, w, h, d, r)
	return h


# ------------------------------------------------------------------ shopfront
## Glass shopfronts along a ground floor: stone piers, plinth, recessed lit
## glass with a real room behind it, sign band, some awnings.
## `signs` collects [local centre (world pos), width] for the caller's lettering.
static func shopfront(b: MeshBatch, F: Transform3D, w: float, r: RandomNumberGenerator, signs: Array = []) -> void:
	var n := maxi(int(round(w / 6.0)), 1)
	var sw := w / n
	var pier := W3D.pbr("granite_tile", 1.5, Color(0.42, 0.42, 0.45)) if r.randf() < 0.5 else W3D.pbr("concrete_panels", 2.5, Color(0.55, 0.55, 0.58))
	var metal := W3D.flat(Color(0.03, 0.03, 0.035), 0.35, 0.8)
	var glass := W3D.window_glass(1.0, Vector2(6.0, SHOP_H), 5.0, 3.8, true, true)
	var band_h := 1.0
	var glass_top := SHOP_H - band_h - 0.15
	for k in n:
		var x0 := k * sw
		var x1 := x0 + sw
		# piers
		lbox(b, F, pier, Vector3(x0 - 0.25 if k > 0 else x0, 0, -0.1), Vector3(0.5 if k > 0 else 0.3, SHOP_H, 0.4), 1 | 4 | 8)
		if k == n - 1:
			lbox(b, F, pier, Vector3(x1 - 0.3, 0, -0.1), Vector3(0.3, SHOP_H, 0.4), 1 | 4 | 8)
		var gx0 := x0 + 0.3
		var gx1 := x1 - 0.3
		# plinth under the glass
		lbox(b, F, pier, Vector3(gx0, 0, -0.3), Vector3(gx1 - gx0, 0.45, 0.3), 1 | 16)
		# glass, recessed; the interior-mapping cell is this shop
		var cell_scale := Vector2(6.0 / (gx1 - gx0), 1.0)
		b.quad_uv(glass, F * Vector3(gx0, 0.45, -0.3), F * Vector3(gx1, 0.45, -0.3), F * Vector3(gx1, glass_top, -0.3), F * Vector3(gx0, glass_top, -0.3),
			Vector2(k * 6.0, 0.45), Vector2(k * 6.0 + 6.0, 0.45), Vector2(k * 6.0 + 6.0, glass_top), Vector2(k * 6.0, glass_top))
		# frame: head, mullions, door stiles
		lbox(b, F, metal, Vector3(gx0, glass_top, -0.34), Vector3(gx1 - gx0, 0.12, 0.1), 1 | 32)
		var door_x := gx0 + (gx1 - gx0) * (0.3 if r.randf() < 0.5 else 0.62)
		for mx in [gx0, door_x, door_x + 1.1, gx1 - 0.06]:
			lbox(b, F, metal, Vector3(mx, 0.45 if mx != door_x and mx != door_x + 1.1 else 0.0, -0.34), Vector3(0.06, glass_top - 0.45, 0.1), 1 | 4 | 8)
		lbox(b, F, metal, Vector3(door_x, 2.25, -0.34), Vector3(1.1, 0.06, 0.1), 1 | 32)
		# sign band (dark fascia) + warm down-light strip under it
		lbox(b, F, metal, Vector3(x0 + 0.3, SHOP_H - band_h, 0.0), Vector3(sw - 0.6, band_h, 0.3), 1 | 4 | 8 | 16 | 32)
		lbox(b, F, W3D.glow(Color(1.0, 0.85, 0.62), 3.0), Vector3(gx0 + 0.3, SHOP_H - band_h - 0.05, 0.05), Vector3(gx1 - gx0 - 0.6, 0.05, 0.18), 32 | 1)
		signs.append([F * Vector3((x0 + x1) * 0.5, SHOP_H - band_h * 0.5, 0.32), sw - 1.4, F.basis.z])
		# neon tube along the top of the fascia, a different colour per shop
		var neon_c: Color = City.NEON[r.randi() % City.NEON.size()]
		if r.randf() < 0.7:
			lbox(b, F, W3D.glow(neon_c, 4.5), Vector3(x0 + 0.5, SHOP_H - 0.02, 0.22), Vector3(sw - 1.0, 0.07, 0.07), 1 | 16 | 32)
		# vertical blade sign on some shops, lit both sides
		if r.randf() < 0.22:
			var bc: Color = City.NEON[r.randi() % City.NEON.size()]
			lbox(b, F, W3D.flat(Color(0.02, 0.02, 0.025), 0.4, 0.6), Vector3(x1 - 0.5, SHOP_H + 0.4, 0.3), Vector3(0.18, 4.2, 1.1), 1 | 2 | 4 | 8 | 16 | 32)
			lbox(b, F, W3D.glow(bc, 4.0), Vector3(x1 - 0.53, SHOP_H + 0.6, 0.42), Vector3(0.24, 3.8, 0.08), 4 | 8 | 1)
			lbox(b, F, W3D.glow(bc, 4.0), Vector3(x1 - 0.53, SHOP_H + 0.6, 1.2), Vector3(0.24, 3.8, 0.08), 4 | 8 | 1)
		# awning on some shops
		if r.randf() < 0.4:
			var canvas := W3D.flat(AWNING[r.randi() % AWNING.size()], 0.8)
			var ay := SHOP_H - band_h - 0.1
			b.quad(canvas, F * Vector3(gx0, ay - 0.55, 1.5), F * Vector3(gx1, ay - 0.55, 1.5), F * Vector3(gx1, ay, 0.05), F * Vector3(gx0, ay, 0.05))
			b.quad(canvas, F * Vector3(gx0, ay - 0.85, 1.5), F * Vector3(gx1, ay - 0.85, 1.5), F * Vector3(gx1, ay - 0.55, 1.5), F * Vector3(gx0, ay - 0.55, 1.5))
			b.quad(canvas, F * Vector3(gx1, ay - 0.55, 1.5), F * Vector3(gx0, ay - 0.55, 1.5), F * Vector3(gx0, ay, 0.05), F * Vector3(gx1, ay, 0.05))
	# wall above the door heads between glass and fascia is the fascia itself; cap the floor
	lbox(b, F, pier, Vector3(0, SHOP_H - 0.15, -0.1), Vector3(w, 0.3, 0.55), 1 | 16 | 32)


# ------------------------------------------------------------------ modern mid-rise
## Shops on the ground floor, photo-scanned facade skin above, with projecting
## piers and floor ledges so the wall has real relief. Returns its height.
static func midrise(b: MeshBatch, F: Transform3D, w: float, floors: int, d: float, r: RandomNumberGenerator, signs: Array = []) -> float:
	shopfront(b, F, w, r, signs)
	var skin: Array = MID_SKINS[r.randi() % MID_SKINS.size()]
	var tints := [Color(1, 1, 1), Color(0.86, 0.84, 0.82)]
	var mat := W3D.facade(skin[0], Vector2(skin[1], skin[2]), skin[3], tints[r.randi() % tints.size()])
	var h := SHOP_H + (floors - 1) * FLOOR
	# snap the skin so whole windows fit the wall
	var uo := Vector2(0.0, -h)
	b.quad(mat, F * Vector3(0, SHOP_H, 0), F * Vector3(w, SHOP_H, 0), F * Vector3(w, h, 0), F * Vector3(0, h, 0), uo)
	var trim := W3D.pbr("concrete_panels", 2.5, Color(0.55, 0.55, 0.58))
	# corner piers and a cornice
	for x in [0.0, w - 0.4]:
		lbox(b, F, trim, Vector3(x, SHOP_H, 0.0), Vector3(0.4, h - SHOP_H, 0.25), 1 | 4 | 8)
	if r.randf() < 0.6:
		var step := w / maxf(round(w / 6.0), 1.0)
		var x := step
		while x < w - 1.0:
			lbox(b, F, trim, Vector3(x - 0.15, SHOP_H, 0.0), Vector3(0.3, h - SHOP_H, 0.18), 1 | 4 | 8)
			x += step
	lbox(b, F, trim, Vector3(-0.1, h - 0.4, 0.0), Vector3(w + 0.2, 0.4, 0.4), 1 | 4 | 8 | 16 | 32)
	shell(b, F, w, h, d, W3D.pbr("concrete_wall_008", 4.0, Color(0.55, 0.55, 0.57)), W3D.pbr("concrete_wall_008", 4.0, Color(0.4, 0.4, 0.4)))
	# the photo skin also wraps the upper side walls, so corners are never blank
	b.quad(mat, F * Vector3(w + 0.02, SHOP_H, 0), F * Vector3(w + 0.02, SHOP_H, -d), F * Vector3(w + 0.02, h, -d), F * Vector3(w + 0.02, h, 0), Vector2(3.0, -h))
	b.quad(mat, F * Vector3(-0.02, SHOP_H, -d), F * Vector3(-0.02, SHOP_H, 0), F * Vector3(-0.02, h, 0), F * Vector3(-0.02, h, -d), Vector2(7.0, -h))
	roof_clutter(b, F, w, h, d, r)
	return h


# ------------------------------------------------------------------ tower
## High-rise: stepped shaft with a real facade skin on all four sides, a dark
## mechanical band, crown and roof plant. Centre given in world space.
static func tower(b: MeshBatch, c: Vector3, fw: float, fd: float, h: float, r: RandomNumberGenerator, y0 := 0.0) -> void:
	var skin: Array = TOWER_SKINS[r.randi() % TOWER_SKINS.size()]
	var mat := W3D.facade(skin[0], Vector2(skin[1], skin[2]), skin[3])
	var dark := W3D.flat(Color(0.03, 0.035, 0.04), 0.5, 0.6)
	var steps := 1 + (r.randi() % 3 if h > 70.0 else 0)
	var y := y0
	var cw := fw
	var cd := fd
	var tops := [y0 + h]
	if steps == 2:
		tops = [y0 + h * r.randf_range(0.55, 0.75), y0 + h]
	elif steps == 3:
		tops = [y0 + h * r.randf_range(0.5, 0.6), y0 + h * r.randf_range(0.75, 0.85), y0 + h]
	for s in steps:
		var top: float = tops[s]
		for face in 4:
			var out := Vector3(sin(face * PI * 0.5), 0, cos(face * PI * 0.5))
			var half_out := cd * 0.5 if face % 2 == 0 else cw * 0.5
			var half_w := cw * 0.5 if face % 2 == 0 else cd * 0.5
			var right := Vector3.UP.cross(out)
			var o := c + out * half_out - right * half_w
			var F := Transform3D(Basis(right, Vector3.UP, out), o)
			b.quad(mat, F * Vector3(0, y, 0), F * Vector3(half_w * 2.0, y, 0), F * Vector3(half_w * 2.0, top, 0), F * Vector3(0, top, 0), Vector2(face * 7.0, -top))
			# corner mullion
			lbox(b, F, dark, Vector3(-0.2, y, -0.2), Vector3(0.4, top - y, 0.4), 1 | 8)
		# setback roof + band
		b.box(dark, Transform3D(Basis.IDENTITY, c + Vector3(0, top + 0.6, 0)), Vector3(cw + 0.6, 1.2, cd + 0.6), 31)
		y = top + 1.2
		cw *= 0.78
		cd *= 0.78
	# crown: plant screen, mast, aviation light
	b.box(dark, Transform3D(Basis.IDENTITY, c + Vector3(0, y + 2.0, 0)), Vector3(cw * 1.0, 4.0, cd * 1.0), 31)
	if h > 90.0:
		b.box(dark, Transform3D(Basis.IDENTITY, c + Vector3(0, y + 4.0 + h * 0.06, 0)), Vector3(0.5, h * 0.12, 0.5), 15)
		b.box(W3D.glow(Color(1.0, 0.1, 0.05), 6.0), Transform3D(Basis.IDENTITY, c + Vector3(0, y + 4.0 + h * 0.12, 0)), Vector3(0.9, 0.9, 0.9), 31)


# ------------------------------------------------------------------ warehouse
static func warehouse(b: MeshBatch, F: Transform3D, w: float, h: float, d: float, r: RandomNumberGenerator) -> void:
	var tint: Color = [Color(0.7, 0.72, 0.75), Color(0.55, 0.6, 0.68), Color(0.75, 0.68, 0.58), Color(0.5, 0.52, 0.5)][r.randi() % 4]
	var iron := W3D.pbr("corrugated_iron", 2.0, tint)
	var conc := W3D.pbr("concrete_wall_008", 3.0, Color(0.55, 0.55, 0.55))
	var shutter := W3D.pbr("painted_metal_shutter", 3.0, [Color(0.5, 0.52, 0.55), Color(0.2, 0.3, 0.5), Color(0.55, 0.15, 0.1)][r.randi() % 3])
	# concrete plinth, corrugated wall above
	wall(b, F, conc, 0, w, 0, 1.2)
	wall(b, F, iron, 0, w, 1.2, h)
	var n := maxi(int(w / 9.0), 1)
	for k in n:
		var cx := (k + 0.5) * w / n
		var dw := minf(5.0, w / n - 2.0)
		lbox(b, F, shutter, Vector3(cx - dw * 0.5, 0, 0.02), Vector3(dw, 4.2, 0.08), 1)
		lbox(b, F, W3D.flat(Color(0.85, 0.65, 0.05), 0.6), Vector3(cx - dw * 0.5 - 0.15, 0, 0.02), Vector3(0.15, 4.4, 0.14), 1 | 4 | 8)
		lbox(b, F, W3D.flat(Color(0.85, 0.65, 0.05), 0.6), Vector3(cx + dw * 0.5, 0, 0.02), Vector3(0.15, 4.4, 0.14), 1 | 4 | 8)
		# bulkhead light over each door
		lbox(b, F, W3D.glow(Color(1.0, 0.9, 0.7), 5.0), Vector3(cx - 0.3, 4.8, 0.05), Vector3(0.6, 0.15, 0.25), 1 | 32)
	shell(b, F, w, h, d, iron, W3D.pbr("corrugated_iron", 2.0, tint * Color(0.6, 0.6, 0.6)))


# ------------------------------------------------------------------ sidewalk
## Raised paved slab for one block with a granite kerb all round.
static func sidewalk(b: MeshBatch, c: Vector3, size: float, curb: float, inner := 0.0) -> void:
	var paving := W3D.pbr("concrete_pavement", 3.0, Color(0.62, 0.62, 0.64), 0.75)
	var kerb := W3D.pbr("granite_tile", 1.0, Color(0.5, 0.5, 0.52))
	var h := size * 0.5
	var k := 0.3
	var T := Transform3D(Basis.IDENTITY, c)
	b.quad(paving, T * Vector3(-h + k, curb, h - k), T * Vector3(h - k, curb, h - k), T * Vector3(h - k, curb, -h + k), T * Vector3(-h + k, curb, -h + k), Vector2(c.x, c.z))
	for face in 4:
		var out := Vector3(sin(face * PI * 0.5), 0, cos(face * PI * 0.5))
		var F := frame(c + out * h - Vector3.UP.cross(out) * h, out)
		lbox(b, F, kerb, Vector3(0, 0, -k), Vector3(size, curb + 0.01, k), 1 | 16)


# ------------------------------------------------------------------ date palm (real 3D)
static var _palm: ArrayMesh


## Date palm: bark trunk with a swollen crown shaft and ~20 arching fronds made
## of folded alpha-cut leaf strips. About 600 triangles; instanced per block.
static func palm() -> ArrayMesh:
	if _palm:
		return _palm
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var hgt := 8.2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 8
	var rings := [[0.0, 0.42], [0.5, 0.34], [3.0, 0.27], [6.0, 0.25], [7.4, 0.3], [hgt, 0.36], [hgt + 0.5, 0.12]]
	for i in rings.size() - 1:
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var lean0: float = 0.25 * pow(rings[i][0] / hgt, 2.0)
			var lean1: float = 0.25 * pow(rings[i + 1][0] / hgt, 2.0)
			var p := [Vector3(cos(a0) * rings[i][1] + lean0, rings[i][0], sin(a0) * rings[i][1]), Vector3(cos(a1) * rings[i][1] + lean0, rings[i][0], sin(a1) * rings[i][1]),
				Vector3(cos(a1) * rings[i + 1][1] + lean1, rings[i + 1][0], sin(a1) * rings[i + 1][1]), Vector3(cos(a0) * rings[i + 1][1] + lean1, rings[i + 1][0], sin(a0) * rings[i + 1][1])]
			var uv := [Vector2(float(k) / seg * 2.0, rings[i][0] * 0.5), Vector2(float(k + 1) / seg * 2.0, rings[i][0] * 0.5), Vector2(float(k + 1) / seg * 2.0, rings[i + 1][0] * 0.5), Vector2(float(k) / seg * 2.0, rings[i + 1][0] * 0.5)]
			var nn := [Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(nn[idx])
				st.set_uv(uv[idx])
				st.add_vertex(p[idx])
	var mesh := st.commit()
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load("res://w3d/gen/bark.jpg")
	bark.roughness = 0.9
	mesh.surface_set_material(0, bark)
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crown := Vector3(0.25, hgt + 0.3, 0)
	var nf := 22
	for f in nf:
		var az := TAU * f / nf + r.randf_range(-0.12, 0.12)
		var tier := float(f % 3)                       # upright young fronds, level ones, drooping old ones
		var rise: float = [1.05, 0.55, 0.12][int(tier)] + r.randf_range(-0.08, 0.08)
		var ln: float = r.randf_range(3.6, 4.6) * [0.85, 1.0, 0.95][int(tier)]
		var dir := Vector3(cos(az), 0, sin(az))
		var side := Vector3(-sin(az), 0, cos(az))
		var steps := 6
		var prev_c := crown
		var prev_w := 0.25
		for sgi in steps:
			var t1 := float(sgi + 1) / steps
			var c1: Vector3 = crown + dir * (ln * t1) + Vector3.UP * (ln * (rise * t1 - (0.75 + 0.25 * tier) * t1 * t1))
			var w1: float = 0.75 * sin(PI * minf(t1 * 1.1 + 0.1, 1.0)) + 0.12
			var t0 := float(sgi) / steps
			for hs: float in [-1.0, 1.0]:
				# each half folds down a little from the midrib (a shallow V)
				var a := prev_c
				var b2 := c1
				var c: Vector3 = c1 + side * hs * w1 - Vector3.UP * w1 * 0.28
				var d: Vector3 = prev_c + side * hs * prev_w - Vector3.UP * prev_w * 0.28
				var v0 := 0.5
				var v1 := 0.5 + hs * 0.5
				var pts := [a, b2, c, d]
				var uvs := [Vector2(t0, v0), Vector2(t1, v0), Vector2(t1, v1), Vector2(t0, v1)]
				for idx in [0, 1, 2, 0, 2, 3]:
					sf.set_normal((Vector3.UP * 0.8 + dir * 0.5 + side * hs * 0.35).normalized())
					sf.set_uv(uvs[idx])
					sf.add_vertex(pts[idx])
			prev_c = c1
			prev_w = w1
	sf.commit(mesh)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_texture = load("res://w3d/gen/frond.png")
	leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf.alpha_scissor_threshold = 0.35
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf.roughness = 0.75
	leaf.albedo_color = Color(1.0, 1.1, 0.9)
	leaf.backlight_enabled = true
	leaf.backlight = Color(0.12, 0.16, 0.06)
	mesh.surface_set_material(1, leaf)
	_palm = mesh
	return _palm
