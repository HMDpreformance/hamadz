class_name OpenWorld
extends City
## "Halcyon Bay": the open-world map. A 12 x 9 block street grid split into
## districts (downtown, residential, industrial, beachfront), ringed by a
## six-lane highway that dives through a tunnel in the north and crosses the
## bay on a bridge in the south.
##
## Streaming: only the blocks near the focus node are built (buildings, signs,
## props, colliders, pedestrians). Everything further away is a single
## multimesh of low-detail boxes, so memory and draw calls stay flat no matter
## how large the map gets. Blocks are generated deterministically from their
## grid coordinates, one per frame, and freed again when the player leaves.

const NX := 12
const NZ := 9
const HW_OFF := 46.0          # highway centre line distance outside the grid
const HW_SOUTH := 150.0       # the south side swings out over the water
const HW_R := 80.0            # corner radius
const HW_HALF := 12.0         # half width of the carriageway
const HW_RISE := 9.0          # bridge deck height
const LOAD_R := 300.0
const UNLOAD_R := 380.0
const EXIT_N := [2, 6, 10]    # grid roads with highway junctions (north side)
const EXIT_WE := [1, 4]       # ... west and east sides
const TUNNEL := [60.0, 262.0] # x range of the north tunnel
const SPECIAL := {
	Vector2i(6, 4): "plaza", Vector2i(5, 2): "parking", Vector2i(7, 6): "parking",
	Vector2i(3, 5): "gas", Vector2i(9, 2): "gas", Vector2i(2, 3): "park", Vector2i(1, 6): "park",
	Vector2i(7, 3): "needle",
	Vector2i(10, 4): "yard", Vector2i(10, 6): "yard", Vector2i(11, 1): "yard",
}

var x0 := 0.0
var x1 := 0.0
var z0 := 0.0
var z1 := 0.0
var hw_c := Vector2.ZERO      # centre of the highway rounded rectangle
var hw_h := Vector2.ZERO      # its half size
var hw_path: PackedVector3Array = []
var water_z := 0.0

var _loaded := {}             # Vector2i -> Node3D
var _queue: Array[Vector2i] = []
var _stream_t := 0.0
var _lod_mm: MultiMesh
var _lod_xf := {}
var _mats := {}
var _car_mesh: ArrayMesh
var _ped_mesh: ArrayMesh
var _ped_mat: ShaderMaterial
var _lamped := {}


func road_x(i: int) -> float:
	return (i - NX * 0.5) * PITCH


func road_z(j: int) -> float:
	return (j - NZ * 0.5) * PITCH


func block_center(b: Vector2i) -> Vector3:
	return Vector3(road_x(b.x) + PITCH * 0.5, 0, road_z(b.y) + PITCH * 0.5)


func district(b: Vector2i) -> String:
	if SPECIAL.has(b):
		return SPECIAL[b]
	if b.y == NZ - 1:
		return "beach"
	if b.x <= 3:
		return "residential"
	if b.x >= 9:
		return "industrial"
	return "downtown"


func district_name(p: Vector3) -> String:
	if on_highway(p):
		return "SAHRA EXPRESSWAY"
	if p.z > z1 + ROAD * 0.5:
		return "CORNICHE"
	var b := Vector2i(clampi(int(floor((p.x - x0) / PITCH)), 0, NX - 1), clampi(int(floor((p.z - z0) / PITCH)), 0, NZ - 1))
	if b.y == NZ - 1:
		return "MARINA WALK"
	if b.x <= 3:
		return "OASIS VILLAS"
	if b.x >= 9:
		return "SAND YARDS"
	return "SAHRA DOWNTOWN"


func build() -> void:
	_rng.seed = seed_v
	x0 = road_x(0)
	x1 = road_x(NX)
	z0 = road_z(0)
	z1 = road_z(NZ)
	water_z = z1 + 40.0
	var xa := x0 - HW_OFF
	var xb := x1 + HW_OFF
	var za := z0 - HW_OFF
	var zb := z1 + HW_SOUTH
	hw_c = Vector2((xa + xb) * 0.5, (za + zb) * 0.5)
	hw_h = Vector2((xb - xa) * 0.5, (zb - za) * 0.5)
	half = maxf(hw_h.x, hw_h.y)
	_world_ground()
	_water()
	_highway()
	_connectors()
	_lamps_and_signals()
	_lod_blocks()
	_far_shore()
	_promenade()
	_needle()
	_dunes()
	set_process(true)


# ---------------------------------------------------------------- queries
## Signed distance to the highway centre line (rounded rectangle).
func hw_dist(p: Vector3) -> float:
	var q := Vector2(absf(p.x - hw_c.x), absf(p.z - hw_c.y)) - (hw_h - Vector2(HW_R, HW_R))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - HW_R


func on_highway(p: Vector3) -> bool:
	return absf(hw_dist(p)) < HW_HALF + 1.2


func hw_height(z: float) -> float:
	return HW_RISE * smoothstep(z1 - 70.0, z1 + 80.0, z)


func in_tunnel(p: Vector3) -> bool:
	return p.x > TUNNEL[0] and p.x < TUNNEL[1] and absf(p.z - (z0 - HW_OFF)) < HW_HALF + 2.0


func space_at(p: Vector3) -> String:
	if in_tunnel(p):
		return "tunnel"
	if on_highway(p) or p.z > z1 + ROAD:
		return "open"
	return "street"


func ground_height(p: Vector3) -> float:
	if absf(hw_dist(p)) < HW_HALF + 1.5:
		return hw_height(p.z)
	if p.x > x0 and p.x < x1 and p.z > z0 and p.z < z1:
		var fx := fposmod(p.x - x0, PITCH)
		var fz := fposmod(p.z - z0, PITCH)
		var hr := ROAD * 0.5
		if fx > hr and fx < PITCH - hr and fz > hr and fz < PITCH - hr:
			return CURB
	elif p.z > z1 + ROAD * 0.5 and p.z < water_z and p.x > x0 and p.x < x1:
		return CURB
	return 0.0


## True while north-south traffic has a green light.
func ns_green() -> bool:
	return _signal_phase == 0


func ew_green() -> bool:
	return _signal_phase == 2


func _mat(key: String, make: Callable) -> Material:
	if not _mats.has(key):
		_mats[key] = make.call()
	return _mats[key]


# ---------------------------------------------------------------- ground + water
func _world_ground() -> void:
	var m := ShaderMaterial.new()
	m.shader = _ground_shader()
	m.set_shader_parameter("pitch", PITCH)
	m.set_shader_parameter("half_road", ROAD * 0.5)
	m.set_shader_parameter("offset", Vector2(road_x(0), road_z(0)))
	m.set_shader_parameter("extent", Vector2((x1 - x0) * 0.5, (z1 - z0) * 0.5))
	m.set_shader_parameter("outside", Color(0.2, 0.15, 0.1))
	m.set_shader_parameter("outside_rough", 0.95)
	m.set_shader_parameter("shop_rect", Vector4(road_x(4) - ROAD, road_x(9) + ROAD, z0 - ROAD, z1 + ROAD))
	m.set_shader_parameter("noise_tex", EnvKit.noise_tex(3, 0.03))
	m.set_shader_parameter("asphalt_tex", load("res://textures/asphalt.jpg"))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hw_h.x * 2 + 240, (water_z - (z0 - HW_OFF - 120.0)))
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(0, 0, (water_z + (z0 - HW_OFF - 120.0)) * 0.5)
	add_child(mi)


func _water() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	float a = texture(noise_tex, p * 0.012 + vec2(TIME * 0.012, TIME * 0.02)).r;
	float b = texture(noise_tex, p * 0.045 - vec2(TIME * 0.03, TIME * 0.011)).r;
	float w = a * 0.6 + b * 0.4;
	ALBEDO = vec3(0.0, 0.03, 0.04);
	ROUGHNESS = 0.03 + 0.08 * w;
	METALLIC = 0.4;
	SPECULAR = 0.9;
	NORMAL_MAP = vec3(0.5 + (a - 0.5) * 0.5, 0.5 + (b - 0.5) * 0.5, 1.0);
	NORMAL_MAP_DEPTH = 0.55;
	// faint shimmer of the city lights on the swell
	EMISSION = vec3(0.0, 0.05, 0.06) + vec3(0.9, 0.75, 0.5) * smoothstep(0.62, 0.9, w) * 0.06 * smoothstep(900.0, 40.0, p.y - 400.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", EnvKit.noise_tex(21, 0.02))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3600, 1500)
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(0, -0.6, water_z + 750.0)
	add_child(mi)
	# sea wall
	EnvKit.box(self, Vector3(x1 - x0 + 2.0 * HW_OFF + 60.0, 1.2, 1.0), Vector3(0, -0.3, water_z + 0.5), _mat("concrete", func(): return EnvKit.solid(Color(0.16, 0.16, 0.17), 0.8)))


# ---------------------------------------------------------------- highway
func _hw_polyline() -> PackedVector3Array:
	var pts: PackedVector3Array = []
	var cx := hw_c.x
	var cz := hw_c.y
	var ix := hw_h.x - HW_R
	var iz := hw_h.y - HW_R
	# clockwise seen from above (x right, z down): north side west->east first
	var corners := [Vector2(ix, -iz), Vector2(ix, iz), Vector2(-ix, iz), Vector2(-ix, -iz)]
	var starts := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var prev_end := Vector3(cx - ix, 0, cz - hw_h.y)
	for k in 4:
		var c: Vector2 = corners[k]
		var a0: float = starts[k]
		var first := Vector3(cx + c.x + cos(a0) * HW_R, 0, cz + c.y + sin(a0) * HW_R)
		var seg := first - prev_end
		var n := maxi(int(ceil(seg.length() / 14.0)), 1)
		for i in n:
			pts.append(prev_end + seg * (float(i) / n))
		var steps := 12
		for i in steps:
			var a := a0 + (PI * 0.5) * (float(i) / steps)
			pts.append(Vector3(cx + c.x + cos(a) * HW_R, 0, cz + c.y + sin(a) * HW_R))
		var a1 := a0 + PI * 0.5
		prev_end = Vector3(cx + c.x + cos(a1) * HW_R, 0, cz + c.y + sin(a1) * HW_R)
	for i in pts.size():
		pts[i].y = hw_height(pts[i].z)
	return pts


func _exit_gap(p: Vector3) -> bool:
	## Inner barrier opens where a grid road joins the highway.
	if absf(p.z - (z0 - HW_OFF)) < 14.0:
		for i in EXIT_N:
			if absf(p.x - road_x(i)) < 10.5:
				return true
	for j in EXIT_WE:
		if absf(p.z - road_z(j)) < 10.5 and (absf(p.x - (x0 - HW_OFF)) < 14.0 or absf(p.x - (x1 + HW_OFF)) < 14.0):
			return true
	return false


func _highway() -> void:
	hw_path = _hw_polyline()
	var n := hw_path.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skirt := SurfaceTool.new()
	skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var barrier_xf := []
	var pole_xf := []
	var head_xf := []
	var pylon_xf := []
	var body := StaticBody3D.new()
	add_child(body)
	var v := 0.0
	var lamp_acc := 0.0
	for i in n:
		var a := hw_path[i]
		var b := hw_path[(i + 1) % n]
		var d := b - a
		var flat := Vector3(d.x, 0, d.z)
		var ln := flat.length()
		var dir := flat / ln
		var side := Vector3(dir.z, 0, -dir.x)          # points outward (away from the city)
		# next segment's side for smooth joins
		var c := hw_path[(i + 2) % n]
		var d2 := Vector3(c.x - b.x, 0, c.z - b.z).normalized()
		var side2 := Vector3(d2.z, 0, -d2.x)
		var up := Vector3(0, 0.03, 0)
		var p0 := a - side * HW_HALF + up
		var p1 := a + side * HW_HALF + up
		var p2 := b + side2 * HW_HALF + up
		var p3 := b - side2 * HW_HALF + up
		for tri in [[p0, p1, p2, Vector2(0, v), Vector2(1, v), Vector2(1, v + ln)], [p0, p2, p3, Vector2(0, v), Vector2(1, v + ln), Vector2(0, v + ln)]]:
			for k in 3:
				st.set_normal(Vector3.UP)
				st.set_uv(tri[3 + k])
				st.add_vertex(tri[k])
		# embankment / bridge sides where the deck is raised
		if a.y > 0.3 or b.y > 0.3:
			for sg: float in [-1.0, 1.0]:
				var e0 := a + side * HW_HALF * sg
				var e1 := b + side2 * HW_HALF * sg
				var lo0 := Vector3(e0.x, minf(e0.y - 1.4, -0.7) if a.z > water_z else -0.2, e0.z)
				var lo1 := Vector3(e1.x, minf(e1.y - 1.4, -0.7) if b.z > water_z else -0.2, e1.z)
				var quad := [e0, e1, lo1, e0, lo1, lo0] if sg > 0.0 else [e0, lo1, e1, e0, lo0, lo1]
				for q in quad:
					skirt.set_normal(side * sg)
					skirt.add_vertex(q)
		var mid := (a + b) * 0.5
		var basis := Basis.looking_at(d.normalized(), Vector3.UP)
		for sg: float in [-1.0, 1.0]:
			if sg < 0.0 and _exit_gap(mid - side * HW_HALF):
				continue
			var bp := mid + side * (HW_HALF + 0.35) * sg + Vector3(0, 0.45, 0)
			barrier_xf.append(Transform3D(basis * Basis.from_scale(Vector3(1, 1, d.length() / 14.0 + 0.02)), bp))
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(1.0, 6.0, d.length() + 0.6)
			cs.shape = bs
			cs.transform = Transform3D(basis, bp + Vector3(0, 1.0, 0) + side * 0.3 * sg)
			body.add_child(cs)
		lamp_acc += ln
		if lamp_acc > 42.0 and not in_tunnel(mid):
			lamp_acc = 0.0
			var lp := mid + side * (HW_HALF + 0.9)
			pole_xf.append(Transform3D(Basis.IDENTITY, lp + Vector3(0, 5.0, 0)))
			head_xf.append(Transform3D(basis, lp + Vector3(0, 10.0, 0) - side * 2.2))
			lamp_positions.append(lp + Vector3(0, 9.4, 0) - side * 3.0)
		if mid.z > water_z + 30.0 and i % 3 == 0:
			pylon_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, (mid.y + 2.0) / 10.0, 1)), Vector3(mid.x, mid.y * 0.5 - 1.2, mid.z)))
		v += ln
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _hw_material()
	add_child(mi)
	var sk := MeshInstance3D.new()
	sk.mesh = skirt.commit()
	sk.material_override = _mat("concrete", func(): return EnvKit.solid(Color(0.16, 0.16, 0.17), 0.8))
	add_child(sk)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.9, 14.0)
	_mm(bm, _mat("barrier", func(): return EnvKit.solid(Color(0.3, 0.3, 0.31), 0.75)), barrier_xf)
	var pm := CylinderMesh.new()
	pm.top_radius = 0.09
	pm.bottom_radius = 0.16
	pm.height = 10.0
	pm.radial_segments = 6
	pm.rings = 1
	_mm(pm, _mat("pole", func(): return EnvKit.solid(Color(0.08, 0.085, 0.09), 0.5, 0.7)), pole_xf)
	var hm := BoxMesh.new()
	hm.size = Vector3(0.9, 0.12, 0.4)
	_mm(hm, _mat("sodium", func(): return EnvKit.emissive(Color(1.0, 0.62, 0.25), 7.0)), head_xf)
	var ym := BoxMesh.new()
	ym.size = Vector3(3.0, 10.0, 16.0)
	_mm(ym, _mat("concrete", func(): return EnvKit.solid(Color(0.16, 0.16, 0.17), 0.8)), pylon_xf)
	_bridge_towers()
	_tunnel()


func _hw_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float width = 24.0;
uniform sampler2D asphalt_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
void fragment() {
	float x = (UV.x - 0.5) * width;
	float ax = abs(x);
	float along = UV.y;
	float dash = step(fract(along / 12.0), 0.4);
	float white = smoothstep(0.1, 0.06, abs(ax - 4.0)) * dash + smoothstep(0.1, 0.06, abs(ax - 7.7)) * dash;
	white += smoothstep(0.12, 0.08, abs(ax - 11.3));
	float yellow = smoothstep(0.1, 0.06, abs(ax - 0.28));
	float fine = texture(noise_tex, vec2(x, along) * 0.6).r;
	float n = texture(noise_tex, vec2(x, along) * 0.03).r;
	vec3 asphalt = texture(asphalt_tex, vec2(x, along) * 0.22).rgb * 0.3 * (0.8 + 0.4 * n);
	// darker tyre lanes
	asphalt *= 1.0 - 0.18 * smoothstep(1.6, 0.4, abs(fract(ax / 3.85 + 0.02) - 0.5) * 3.85);
	vec3 col = mix(asphalt, vec3(0.62), clamp(white, 0.0, 1.0) * (0.55 + 0.45 * n));
	col = mix(col, vec3(0.7, 0.5, 0.05), yellow * (0.55 + 0.45 * n));
	ALBEDO = col;
	ROUGHNESS = 0.2 + fine * 0.14;
	SPECULAR = 0.65;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", EnvKit.noise_tex(3, 0.03))
	m.set_shader_parameter("width", HW_HALF * 2.0)
	m.set_shader_parameter("asphalt_tex", load("res://textures/asphalt.jpg"))
	return m


func _bridge_towers() -> void:
	## Two cable-stayed towers on the bay crossing, with lit cables.
	var z := z1 + HW_SOUTH
	var conc := _mat("concrete", func(): return EnvKit.solid(Color(0.16, 0.16, 0.17), 0.8))
	var cable := _mat("cable", func(): return EnvKit.emissive(Color(0.5, 0.75, 1.0), 2.2))
	var beacon := _mat("beacon", func(): return EnvKit.emissive(Color(1.0, 0.1, 0.05), 5.0))
	for tx: float in [-170.0, 170.0]:
		for sg: float in [-1.0, 1.0]:
			EnvKit.box(self, Vector3(2.4, 70.0, 3.0), Vector3(tx, 34.0, z + sg * (HW_HALF + 2.4)), conc)
			EnvKit.box(self, Vector3(1.0, 1.0, 1.0), Vector3(tx, 69.8, z + sg * (HW_HALF + 2.4)), beacon)
			for k in 7:
				for dirx: float in [-1.0, 1.0]:
					var top := Vector3(tx, 64.0 - k * 6.5, z + sg * (HW_HALF + 2.0))
					var bot := Vector3(tx + dirx * (22.0 + k * 20.0), HW_RISE + 0.9, z + sg * (HW_HALF + 0.6))
					var c := EnvKit.box(self, Vector3(0.14, 0.14, top.distance_to(bot)), (top + bot) * 0.5, cable)
					c.transform.basis = Basis.looking_at(bot - top, Vector3.UP)
		EnvKit.box(self, Vector3(2.0, 2.4, HW_HALF * 2.0 + 7.0), Vector3(tx, 52.0, z), conc)


func _tunnel() -> void:
	var z := z0 - HW_OFF
	var len_x: float = TUNNEL[1] - TUNNEL[0]
	var cx: float = (TUNNEL[0] + TUNNEL[1]) * 0.5
	var conc := _mat("tunnel", func(): return EnvKit.solid(Color(0.11, 0.11, 0.115), 0.55))
	EnvKit.box(self, Vector3(len_x, 0.6, HW_HALF * 2.0 + 3.0), Vector3(cx, 6.3, z), conc)
	for sg: float in [-1.0, 1.0]:
		EnvKit.box(self, Vector3(len_x, 6.0, 0.8), Vector3(cx, 3.0, z + sg * (HW_HALF + 1.1)), conc)
		# portals
		EnvKit.box(self, Vector3(3.0, 12.0, HW_HALF * 2.0 + 12.0), Vector3(cx + sg * (len_x * 0.5 + 1.5), 6.0 + 6.6, z), conc)
	# hill over the tunnel
	var hill := EnvKit.box(self, Vector3(len_x + 60.0, 9.0, 120.0), Vector3(cx, 11.0, z - 30.0), _mat("hill", func(): return EnvKit.solid(Color(0.03, 0.05, 0.03), 0.95)))
	hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# strip lights: emissive tubes plus a few real lights that the pool picks up
	var tubes := []
	var x: float = TUNNEL[0] + 8.0
	while x < TUNNEL[1] - 4.0:
		for sg: float in [-1.0, 1.0]:
			tubes.append(Transform3D(Basis.IDENTITY, Vector3(x, 5.7, z + sg * 6.0)))
		lamp_positions.append(Vector3(x, 5.2, z))
		x += 16.0
	var tm := BoxMesh.new()
	tm.size = Vector3(7.0, 0.12, 0.3)
	_mm(tm, _mat("tube", func(): return EnvKit.emissive(Color(1.0, 0.78, 0.45), 6.0)), tubes)
	add_sign("TUNNEL", Vector3(TUNNEL[0] - 0.3, 9.5, z), -PI * 0.5, Color(1.0, 0.65, 0.05), 2.2)
	add_sign("TUNNEL", Vector3(TUNNEL[1] + 0.3, 9.5, z), PI * 0.5, Color(1.0, 0.65, 0.05), 2.2)


func _connectors() -> void:
	## Short link roads between the grid edge and the highway.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := []
	var w := 8.5
	for i in EXIT_N:
		quads.append([Vector3(road_x(i) - w, 0, z0 - HW_OFF + HW_HALF - 0.5), Vector3(road_x(i) + w, 0, z0 - ROAD * 0.5 + 0.2), false])
	for j in EXIT_WE:
		quads.append([Vector3(x0 - HW_OFF + HW_HALF - 0.5, 0, road_z(j) - w), Vector3(x0 - ROAD * 0.5 + 0.2, 0, road_z(j) + w), true])
		quads.append([Vector3(x1 + ROAD * 0.5 - 0.2, 0, road_z(j) - w), Vector3(x1 + HW_OFF - HW_HALF + 0.5, 0, road_z(j) + w), true])
	var body := StaticBody3D.new()
	add_child(body)
	for q in quads:
		var a: Vector3 = q[0]
		var b: Vector3 = q[1]
		var along_x: bool = q[2]
		var y := 0.025
		var c := [Vector3(a.x, y, a.z), Vector3(b.x, y, a.z), Vector3(b.x, y, b.z), Vector3(a.x, y, b.z)]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		if along_x:
			uv = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
		var ln := absf(b.x - a.x) if along_x else absf(b.z - a.z)
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(uv[k].x, uv[k].y * ln))
			st.add_vertex(c[k])
		# kerb walls so the link road is a clean channel
		for sg: float in [-1.0, 1.0]:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			var mid := (a + b) * 0.5
			if along_x:
				bs.size = Vector3(absf(b.x - a.x) - 1.0, 4.0, 0.6)
				cs.position = Vector3(mid.x, 2.0, mid.z + sg * (w + 0.5))
			else:
				bs.size = Vector3(0.6, 4.0, absf(b.z - a.z) - 1.0)
				cs.position = Vector3(mid.x + sg * (w + 0.5), 2.0, mid.z)
			cs.shape = bs
			body.add_child(cs)
			var rail := EnvKit.box(self, bs.size * Vector3(1, 0.2, 1), cs.position * Vector3(1, 0.2, 1), _mat("barrier", func(): return EnvKit.solid(Color(0.3, 0.3, 0.31), 0.75)))
			rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _hw_material()
	m.set_shader_parameter("width", w * 2.0 * 1.42)       # two lanes: only the centre + edge lines land on the strip
	mi.material_override = m
	add_child(mi)
	# the grid's outer edges are walled where there is no link road (keeps cars out of the verge)
	var edge := StaticBody3D.new()
	add_child(edge)
	var spans := []
	var hr := ROAD * 0.5 + 0.4
	var xs := [x0 - hr - 8.0]
	for i in EXIT_N:
		xs.append(road_x(i) - w - 0.5)
		xs.append(road_x(i) + w + 0.5)
	xs.append(x1 + hr + 8.0)
	for k in range(0, xs.size(), 2):
		spans.append([Vector3(xs[k], 0, z0 - hr), Vector3(xs[k + 1], 0, z0 - hr)])
	for sgx: float in [-1.0, 1.0]:
		var ex := (x0 - hr) if sgx < 0.0 else (x1 + hr)
		var zs := [z0 - hr]
		for j in EXIT_WE:
			zs.append(road_z(j) - w - 0.5)
			zs.append(road_z(j) + w + 0.5)
		zs.append(water_z)
		for k in range(0, zs.size(), 2):
			spans.append([Vector3(ex, 0, zs[k]), Vector3(ex, 0, zs[k + 1])])
	spans.append([Vector3(x0 - hr, 0, water_z + 0.5), Vector3(x1 + hr, 0, water_z + 0.5)])
	var guard := []
	for sp in spans:
		var a: Vector3 = sp[0]
		var b: Vector3 = sp[1]
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var d := b - a
		bs.size = Vector3(maxf(absf(d.x), 0.6), 4.0, maxf(absf(d.z), 0.6))
		cs.shape = bs
		cs.position = (a + b) * 0.5 + Vector3(0, 2.0, 0)
		edge.add_child(cs)
		guard.append(Transform3D(Basis.IDENTITY.scaled(Vector3(maxf(absf(d.x), 0.3), 1, maxf(absf(d.z), 0.3))), (a + b) * 0.5 + Vector3(0, 0.55, 0)))
	var gm := BoxMesh.new()
	gm.size = Vector3(1, 0.32, 1)
	_mm(gm, _mat("guard", func(): return EnvKit.solid(Color(0.42, 0.43, 0.45), 0.35, 0.8)), guard)


# ---------------------------------------------------------------- lamps + signals (global, cheap)
func _lamps_and_signals() -> void:
	var poles := []
	var arms := []
	var heads := []
	var pools := []
	var hr := ROAD * 0.5 + 0.9
	for axis in 2:
		var lines := NX + 1 if axis == 0 else NZ + 1
		var segs := NZ if axis == 0 else NX
		for i in lines:
			var rc := road_x(i) if axis == 0 else road_z(i)
			for seg in segs:
				var base := (road_z(seg) if axis == 0 else road_x(seg)) + ROAD * 0.5
				for k in 2:
					var t := base + BLOCK * (0.25 + 0.5 * k)
					var sgn := -1.0 if k == 0 else 1.0
					# no lamp posts standing in the verge outside the grid
					if (i == 0 and sgn < 0.0) or (i == lines - 1 and sgn > 0.0 and axis == 0):
						sgn = -sgn
					var p := Vector3(rc + sgn * hr, 0, t) if axis == 0 else Vector3(t, 0, rc + sgn * hr)
					var inward := Vector3(-sgn, 0, 0) if axis == 0 else Vector3(0, 0, -sgn)
					poles.append(Transform3D(Basis.IDENTITY, p + Vector3(0, 3.6 + CURB, 0)))
					var ab := Basis.looking_at(inward, Vector3.UP)
					arms.append(Transform3D(ab, p + Vector3(0, 7.2, 0) + inward * 1.3))
					heads.append(Transform3D(ab, p + Vector3(0, 7.1, 0) + inward * 2.7))
					pools.append(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.03, 0) + inward * 3.4))
					lamp_positions.append(p + Vector3(0, 6.6, 0) + inward * 3.0)
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.12
	pm.height = 7.2
	pm.radial_segments = 6
	pm.rings = 1
	var metal := _mat("pole", func(): return EnvKit.solid(Color(0.08, 0.085, 0.09), 0.5, 0.7))
	_mm(pm, metal, poles)
	var am := BoxMesh.new()
	am.size = Vector3(0.09, 0.09, 2.8)
	_mm(am, metal, arms)
	var hm := BoxMesh.new()
	hm.size = Vector3(0.34, 0.1, 0.7)
	_mm(hm, EnvKit.emissive(Color(1.0, 0.72, 0.38), 6.0), heads)
	var qm := PlaneMesh.new()
	qm.size = Vector2(17, 17)
	_mm(qm, EnvKit.glow_mat(Color(1.0, 0.6, 0.25), 0.16), pools)
	var count: int = maxi(int(GFX.p.lights) - 2, 2)
	for i in count:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 3.0
		l.omni_range = 19.0
		l.omni_attenuation = 1.1
		l.shadow_enabled = false
		add_child(l)
		_light_pool.append(l)
	# traffic signals at every interior crossing
	var posts := []
	var boxes := []
	var hr2 := ROAD * 0.5 + 0.7
	for i in range(1, NX):
		for j in range(1, NZ):
			var c := Vector3(road_x(i), 0, road_z(j))
			var defs := [
				[Vector3(hr2, 0, -hr2), 0.0, true],
				[Vector3(-hr2, 0, hr2), PI, true],
				[Vector3(hr2, 0, hr2), PI * 0.5, false],
				[Vector3(-hr2, 0, -hr2), -PI * 0.5, false],
			]
			for d in defs:
				var p: Vector3 = c + d[0]
				var b := Basis(Vector3.UP, d[1])
				posts.append(Transform3D(Basis.IDENTITY, p + Vector3(0, 2.6 + CURB, 0)))
				boxes.append(Transform3D(b, p + Vector3(0, 4.9, 0)))
				var f: Vector3 = b * Vector3(0, 0, 0.16)
				_signal_data.append({"g": p + Vector3(0, 4.5, 0) + f, "y": p + Vector3(0, 4.9, 0) + f, "r": p + Vector3(0, 5.3, 0) + f, "ns": d[2], "basis": b})
	var spm := CylinderMesh.new()
	spm.top_radius = 0.07
	spm.bottom_radius = 0.09
	spm.height = 5.2
	spm.radial_segments = 6
	spm.rings = 1
	_mm(spm, metal, posts)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 1.3, 0.3)
	_mm(bm, EnvKit.solid(Color(0.02, 0.02, 0.02), 0.6), boxes)
	_signal_mm = MultiMesh.new()
	_signal_mm.transform_format = MultiMesh.TRANSFORM_3D
	_signal_mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	sm.radial_segments = 8
	sm.rings = 4
	_signal_mm.mesh = sm
	_signal_mm.instance_count = _signal_data.size()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _signal_mm
	mi.material_override = mat
	add_child(mi)
	_update_signals(0)


# ---------------------------------------------------------------- distant stand-ins
func _lod_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform float gain = 1.0;
varying vec3 wp;
varying vec3 wn;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float side = step(0.5, abs(wn.x));
	float u = mix(wp.x, wp.z, side);
	vec2 cell = floor(vec2(u / 3.0, wp.y / 3.3));
	vec2 f = fract(vec2(u / 3.0, wp.y / 3.3));
	float win = step(0.15, f.x) * step(f.x, 0.85) * step(0.25, f.y) * step(f.y, 0.8) * step(abs(wn.y), 0.5);
	float h = hash(cell + side * 17.0);
	vec3 wc = mix(vec3(1.0, 0.74, 0.4), vec3(0.55, 0.8, 1.0), step(0.86, hash(cell + 5.0)));
	ALBEDO = vec3(0.05, 0.055, 0.07);
	EMISSION = wc * win * step(0.68, h) * (0.5 + 1.4 * hash(cell + 9.0)) * step(4.0, wp.y) * gain;
	ROUGHNESS = 0.7;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _lod_height(b: Vector2i) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = b.x * 977 + b.y * 131 + seed_v
	match district(b):
		"downtown":
			return _tower_h(b, r)
		"beach":
			return r.randf_range(50.0, 110.0)
		"industrial":
			return r.randf_range(9.0, 14.0)
		"residential":
			return 6.5
	return 0.0


func _lod_blocks() -> void:
	_lod_mm = MultiMesh.new()
	_lod_mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	_lod_mm.mesh = bm
	_lod_mm.instance_count = NX * NZ
	for bi in NX:
		for bj in NZ:
			var b := Vector2i(bi, bj)
			var h := _lod_height(b)
			var c := block_center(b)
			var fw := BLOCK - 12.0 if h < 40.0 else 30.0
			var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(fw, maxf(h, 0.01), fw)), c + Vector3(0, h * 0.5, 0))
			if h <= 0.0:
				xf = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), c - Vector3(0, 50, 0))
			_lod_xf[b] = xf
			_lod_mm.set_instance_transform(bi * NZ + bj, xf)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _lod_mm
	mi.material_override = SkylineKit.facade("office")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# sidewalks for the whole grid are one multimesh too
	var slabs := []
	for bi in NX:
		for bj in NZ:
			slabs.append(Transform3D(Basis.IDENTITY, block_center(Vector2i(bi, bj)) + Vector3(0, CURB * 0.5, 0)))
	var swm := BoxMesh.new()
	swm.size = Vector3(BLOCK, CURB, BLOCK)
	var sidewalk := StandardMaterial3D.new()
	sidewalk.albedo_color = Color(0.55, 0.55, 0.56)
	sidewalk.albedo_texture = load("res://textures/city_paving.jpg")
	sidewalk.uv1_triplanar = true
	sidewalk.uv1_scale = Vector3(0.22, 0.22, 0.22)
	sidewalk.roughness = 0.35
	sidewalk.metallic = 0.15
	_mm(swm, sidewalk, slabs)


func _far_shore() -> void:
	## Skyline across the bay and a few towers beyond the highway: silhouettes only.
	var xf := []
	var r := RandomNumberGenerator.new()
	r.seed = 404
	for k in 46:
		var w := r.randf_range(26.0, 60.0)
		var h := r.randf_range(30.0, 150.0)
		var x := r.randf_range(-1300.0, 1300.0)
		xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w, h, w)), Vector3(x, h * 0.5 - 2.0, z1 + r.randf_range(760.0, 980.0))))
	for k in 40:
		var w := r.randf_range(30.0, 60.0)
		var h := r.randf_range(14.0, 60.0)
		var t := r.randf_range(-1.0, 1.0)
		var sidek := k % 3
		var p := Vector3(t * (hw_h.x + 60.0), h * 0.5, z0 - HW_OFF - r.randf_range(70.0, 160.0))
		if sidek == 1:
			p = Vector3(x0 - HW_OFF - r.randf_range(70.0, 160.0), h * 0.5, t * (z1 - z0) * 0.5)
		elif sidek == 2:
			p = Vector3(x1 + HW_OFF + r.randf_range(70.0, 160.0), h * 0.5, t * (z1 - z0) * 0.5)
		if p.x > TUNNEL[0] - 60.0 and p.x < TUNNEL[1] + 60.0 and p.z < z0:
			continue
		xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w, h, w)), p))
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	var mi := _mm(bm, SkylineKit.facade("glass"), xf)
	mi.extra_cull_margin = 2000.0


func _promenade() -> void:
	## Marina strip between the coast road and the water: palms, piers, boats, lights.
	var deck := StandardMaterial3D.new()
	deck.albedo_color = Color(0.3, 0.26, 0.2)
	deck.albedo_texture = EnvKit.noise_tex(8, 0.05)
	deck.uv1_triplanar = true
	deck.uv1_scale = Vector3(0.15, 0.15, 0.15)
	deck.roughness = 0.8
	var zc := (z1 + ROAD * 0.5 + water_z) * 0.5
	var depth := water_z - (z1 + ROAD * 0.5)
	EnvKit.box(self, Vector3(x1 - x0, CURB, depth), Vector3(0, CURB * 0.5, zc), deck)
	var trunks := []
	var fronds := []
	var bollards := []
	var piers := []
	var boats := []
	var masts := []
	var r := RandomNumberGenerator.new()
	r.seed = 909
	var x := x0 + 14.0
	var k := 0
	while x < x1 - 10.0:
		var lean := Basis(Vector3.FORWARD, r.randf_range(-0.12, 0.12))
		trunks.append(Transform3D(lean, Vector3(x, 4.2, z1 + ROAD * 0.5 + 3.0)))
		for a in 6:
			fronds.append(Transform3D(Basis(Vector3.UP, a * PI / 3.0 + x) * Basis(Vector3.RIGHT, 0.55), Vector3(x, 8.3, z1 + ROAD * 0.5 + 3.0)))
		bollards.append(Transform3D(Basis.IDENTITY, Vector3(x + 9.0, 0.6, water_z - 1.6)))
		if k % 5 == 2:
			piers.append(Transform3D(Basis.IDENTITY, Vector3(x, -0.1, water_z + 22.0)))
			for sgn: float in [-1.0, 1.0]:
				for m in 3:
					var bp := Vector3(x + sgn * 6.5, -0.2, water_z + 8.0 + m * 13.0)
					boats.append(Transform3D(Basis(Vector3.UP, PI * 0.5 + r.randf_range(-0.08, 0.08)), bp))
					masts.append(Transform3D(Basis.IDENTITY, bp + Vector3(0, 4.6, 0)))
		x += 18.0
		k += 1
	var tm := CylinderMesh.new()
	tm.top_radius = 0.16
	tm.bottom_radius = 0.26
	tm.height = 8.4
	tm.radial_segments = 6
	tm.rings = 1
	_mm(tm, _mat("trunk", func(): return EnvKit.solid(Color(0.16, 0.12, 0.08), 0.9)), trunks)
	var fm := PrismMesh.new()
	fm.size = Vector3(0.9, 3.6, 0.06)
	var leaf := EnvKit.solid(Color(0.05, 0.2, 0.07), 0.8)
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mm(fm, leaf, fronds)
	var bom := CylinderMesh.new()
	bom.top_radius = 0.12
	bom.bottom_radius = 0.12
	bom.height = 1.0
	bom.radial_segments = 6
	_mm(bom, EnvKit.emissive(Color(0.3, 0.8, 1.0), 3.0), bollards)
	var pim := BoxMesh.new()
	pim.size = Vector3(3.0, 0.5, 44.0)
	_mm(pim, deck, piers)
	var hull := BoxMesh.new()
	hull.size = Vector3(9.0, 1.6, 2.8)
	_mm(hull, EnvKit.solid(Color(0.85, 0.86, 0.9), 0.3), boats)
	var mm := CylinderMesh.new()
	mm.top_radius = 0.05
	mm.bottom_radius = 0.07
	mm.height = 8.0
	mm.radial_segments = 5
	_mm(mm, EnvKit.solid(Color(0.7, 0.7, 0.72), 0.3, 0.6), masts)
	for i in 4:
		add_sign(["MARINA", "PIER 7", "OCEAN CLUB", "BOARDWALK"][i], Vector3(x0 + (i + 0.5) * (x1 - x0) / 4.0, 6.5, water_z - 4.0), PI, NEON[(i * 2 + 1) % NEON.size()], 2.6)


# ---------------------------------------------------------------- streaming
func preload_around(center: Vector3) -> void:
	## Synchronous first load (behind the loading screen).
	_stream(center)
	while not _queue.is_empty():
		_build_block(_queue.pop_front())
	_assign_lights(center)


func _stream(center: Vector3) -> void:
	var want := {}
	for bi in NX:
		for bj in NZ:
			var b := Vector2i(bi, bj)
			var c := block_center(b)
			var d := Vector2(c.x - center.x, c.z - center.z).length()
			if d < LOAD_R:
				want[b] = d
			elif d > UNLOAD_R and _loaded.has(b):
				_unload_block(b)
	var add: Array[Vector2i] = []
	for b in want:
		if not _loaded.has(b):
			add.append(b)
	add.sort_custom(func(p, q): return want[p] < want[q])
	_queue = add


func _unload_block(b: Vector2i) -> void:
	var n: Node3D = _loaded[b]
	_loaded.erase(b)
	n.queue_free()
	_lod_mm.set_instance_transform(b.x * NZ + b.y, _lod_xf[b])


func loaded_count() -> int:
	return _loaded.size()


func _process(delta: float) -> void:
	super._process(delta)
	_stream_t -= delta
	if _stream_t <= 0.0 and focus != null:
		_stream_t = 0.35
		_stream(focus.global_position)
	if not _queue.is_empty():
		_build_block(_queue.pop_front())


func _build_block(b: Vector2i) -> void:
	if _loaded.has(b):
		return
	var n := Node3D.new()
	n.name = "Block_%d_%d" % [b.x, b.y]
	add_child(n)
	_loaded[b] = n
	_lod_mm.set_instance_transform(b.x * NZ + b.y, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0, -60, 0)))
	_rng.seed = b.x * 977 + b.y * 131 + seed_v
	build_parent = n
	var c := block_center(b)
	var lamps_before := lamp_positions.size()
	match district(b):
		"downtown":
			_fill_downtown(c, b)
		"beach":
			_fill_beach(c, b)
		"residential":
			_fill_residential(n, c, b)
		"industrial":
			_fill_industrial(n, c)
		"plaza":
			_fill_plaza(n, c)
		"parking":
			_fill_parking(n, c)
		"gas":
			_fill_gas(n, c)
		"park":
			_fill_park(n, c)
		"yard":
			_fill_yard(n, c)
		"needle":
			_fill_needle(n, c)
	if not district(b) in ["industrial", "yard", "park"]:
		_street_palms(n, c)
	if district(b) in ["downtown", "beach", "residential"]:
		_pedestrians(n, c, 5 if district(b) == "residential" else 9)
	build_parent = null
	if _lamped.has(b):
		lamp_positions.resize(lamps_before)      # this block's lights were registered on an earlier visit
	_lamped[b] = true


func _block_collider(n: Node3D, c: Vector3, sx: float, sz: float, off := Vector3.ZERO, h := 14.0) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(sx, h, sz)
	cs.shape = bs
	sb.add_child(cs)
	sb.position = c + off + Vector3(0, h * 0.5, 0)
	n.add_child(sb)


func _local_mm(n: Node3D, mesh: Mesh, mat: Material, xforms: Array, colors := []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	n.add_child(mi)
	return mi


func _tower_h(b: Vector2i, r: RandomNumberGenerator) -> float:
	var central := 1.0 - (absf(b.x - 7.0) / 4.0 + absf(b.y - 3.0) / 5.0) * 0.6
	return 45.0 + clampf(central, 0.0, 1.0) * r.randf_range(60.0, 150.0)


func _fill_downtown(c: Vector3, b: Vector2i) -> void:
	## Glass towers on a lit podium: one landmark tower or a cluster of two or three.
	var r := RandomNumberGenerator.new()
	r.seed = b.x * 977 + b.y * 131 + seed_v
	var h := _tower_h(b, r)
	var lot := BLOCK - 10.0
	EnvKit.box(build_parent, Vector3(lot, 6.0, lot), Vector3(c.x, CURB + 3.0, c.z), SkylineKit.facade("stone", (b.x + b.y) % 2))
	var spots := []
	match r.randi() % 3:
		0:
			spots = [[Vector2.ZERO, 32.0, h]]
		1:
			spots = [[Vector2(-12, -10), 22.0, h], [Vector2(13, 12), 20.0, h * r.randf_range(0.5, 0.75)]]
		_:
			spots = [[Vector2(-13, 12), 18.0, h], [Vector2(13, 12), 18.0, h * r.randf_range(0.55, 0.8)], [Vector2(0, -13), 22.0, h * r.randf_range(0.4, 0.65)]]
	for sp in spots:
		var t := SkylineKit.random_tower(r, sp[1], sp[1] * r.randf_range(0.8, 1.1), sp[2])
		t.position = Vector3(c.x + sp[0].x, CURB + 6.0, c.z + sp[0].y)
		t.rotation.y = (PI * 0.5) * (r.randi() % 4) + (r.randf_range(-0.3, 0.3) if r.randf() < 0.3 else 0.0)
		build_parent.add_child(t)
	var txt: String = ["AL NOOR", "SKY MALL", "GOLD SOUK", "CAFE 24", "OASIS", "DATES + CO", "SAHRA BANK", "ZAFRAN"][r.randi() % 8]
	add_sign(txt, Vector3(c.x, 7.0, c.z + lot * 0.5 + 0.3), 0.0, NEON[r.randi() % NEON.size()], 1.8)
	_block_collider(build_parent, c, lot, lot)
	if (b.x + b.y) % 2 == 0:
		_parked(build_parent, c, 2)


func _fill_beach(c: Vector3, b: Vector2i) -> void:
	## Marina towers facing the water: slim, curved residential glass.
	var r := RandomNumberGenerator.new()
	r.seed = b.x * 311 + seed_v
	var lot := BLOCK - 10.0
	EnvKit.box(build_parent, Vector3(lot, 6.0, lot), Vector3(c.x, CURB + 3.0, c.z), SkylineKit.facade("resi", b.x % 2))
	for sx: float in [-1.0, 1.0]:
		var h := r.randf_range(50.0, 110.0)
		var t := SkylineKit.random_tower(r, 20.0, 16.0, h)
		t.position = Vector3(c.x + sx * 13.0, CURB + 6.0, c.z + r.randf_range(-6.0, 6.0))
		build_parent.add_child(t)
	var txt: String = ["MARINA", "BEACH CLUB", "YACHT BAR", "SEAFOOD", "HOTEL", "LOUNGE"][r.randi() % 6]
	add_sign(txt, Vector3(c.x, 7.0, c.z + lot * 0.5 + 0.3), 0.0, NEON[r.randi() % NEON.size()], 2.0)
	_block_collider(build_parent, c, lot, lot)


func _fill_needle(n: Node3D, c: Vector3) -> void:
	## Ground around the supertall: reflecting pool and fountain jets.
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.01, 0.03, 0.05)
	pm.metallic = 0.8
	pm.roughness = 0.03
	for sg: float in [-1.0, 1.0]:
		var pb := EnvKit.box(n, Vector3(BLOCK - 8.0, 0.05, 8.0), c + Vector3(0, CURB + 0.03, sg * 25.0), pm)
		pb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var jets := []
	for k in 12:
		for sg: float in [-1.0, 1.0]:
			jets.append(Transform3D(Basis.IDENTITY, c + Vector3(-25.0 + k * 4.5, 2.2, sg * 25.0)))
	var jm := CylinderMesh.new()
	jm.top_radius = 0.05
	jm.bottom_radius = 0.25
	jm.height = 4.4
	jm.radial_segments = 6
	jm.rings = 1
	_local_mm(n, jm, _mat("jet", func(): return EnvKit.emissive(Color(0.75, 0.9, 1.0), 1.6)), jets)
	_block_collider(n, c, 46.0, 40.0, Vector3.ZERO, 30.0)
	lamp_positions.append(c + Vector3(0, 6.0, 26.0))


func _needle() -> void:
	## The supertall is always built so it shows on the skyline from anywhere.
	var t := SkylineKit.supertall(430.0)
	t.position = block_center(Vector2i(7, 3)) + Vector3(0, CURB, 0)
	t.scale = Vector3(0.62, 1.0, 0.62)
	add_child(t)
	for mi in t.get_children():
		if mi is GeometryInstance3D:
			mi.extra_cull_margin = 600.0


func _dunes() -> void:
	## Desert beyond the highway: long low sand dunes.
	var r := RandomNumberGenerator.new()
	r.seed = 515
	var xf := []
	for k in 70:
		var a := r.randf_range(0.0, TAU)
		var p := Vector3(hw_c.x + cos(a) * (hw_h.x + r.randf_range(120.0, 500.0)), -2.0, hw_c.y + sin(a) * (hw_h.y + r.randf_range(120.0, 500.0)))
		if p.z > water_z - 20.0:
			continue
		var sx := r.randf_range(50.0, 140.0)
		xf.append(Transform3D(Basis(Vector3.UP, r.randf_range(0, PI)).scaled(Vector3(sx, r.randf_range(8.0, 22.0), sx * r.randf_range(0.3, 0.6))), p))
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 6
	sm.is_hemisphere = true
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.36, 0.27, 0.17)
	sand.roughness = 1.0
	var mi := _mm(sm, sand, xf)
	mi.extra_cull_margin = 800.0


func _street_palms(n: Node3D, c: Vector3) -> void:
	## Date palms down every sidewalk.
	var xf := []
	var e := BLOCK * 0.5 - 1.6
	for k in 5:
		var t := -BLOCK * 0.5 + 8.0 + k * 12.0
		for v in [Vector3(t, CURB, e), Vector3(t, CURB, -e), Vector3(e, CURB, t), Vector3(-e, CURB, t)]:
			var sc := 0.85 + fmod(absf(v.x * 13.1 + v.z * 7.7 + c.x), 0.35)
			xf.append(Transform3D(Basis(Vector3.UP, fmod(c.x + v.x * 3.0 + v.z, TAU)).scaled(Vector3.ONE * sc), c + v))
	var mi := _local_mm(n, SkylineKit.palm_mesh(), SkylineKit.palm_material(), xf)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _fill_residential(n: Node3D, c: Vector3, b: Vector2i) -> void:
	## Two rows of houses back to back, lawns, trees, a few porch lights.
	var walls := []
	var wall_cols := []
	var roofs := []
	var roof_cols := []
	var wins := []
	var trunks := []
	var crowns := []
	# sand, cream and white villas with flat roofs and parapets
	var palette := [Color(0.72, 0.62, 0.48), Color(0.8, 0.76, 0.68), Color(0.66, 0.55, 0.42), Color(0.85, 0.83, 0.78), Color(0.7, 0.6, 0.5), Color(0.6, 0.5, 0.38)]
	var roofp := [Color(0.55, 0.48, 0.38), Color(0.62, 0.58, 0.52)]
	# a shop row faces the avenue on some blocks
	var shops := b.x == 3 or b.y == 4
	for row: float in [-1.0, 1.0]:
		for k in 4:
			if shops and row > 0.0:
				continue
			var w := _rng.randf_range(9.0, 11.5)
			var d := _rng.randf_range(9.0, 12.0)
			var h := 3.2 if _rng.randf() < 0.6 else 6.0
			var p := Vector3(c.x - 22.5 + k * 15.0, CURB, c.z + row * 15.5)
			walls.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w, h, d)), p + Vector3(0, h * 0.5, 0)))
			wall_cols.append(palette[_rng.randi() % palette.size()])
			roofs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w + 0.4, 0.7, d + 0.4)), p + Vector3(0, h + 0.35, 0)))
			roof_cols.append(roofp[_rng.randi() % roofp.size()])
			if _rng.randf() < 0.75:
				wins.append(Transform3D(Basis.IDENTITY, p + Vector3(_rng.randf_range(-2.5, 2.5), 1.7, row * (d * 0.5 + 0.03))))
			if _rng.randf() < 0.4 and h > 4.0:
				wins.append(Transform3D(Basis.IDENTITY, p + Vector3(_rng.randf_range(-2.5, 2.5), 4.6, row * (d * 0.5 + 0.03))))
			_block_collider(n, p, w, d, Vector3.ZERO, 8.0)
			if _rng.randf() < 0.8:
				var tp := p + Vector3(_rng.randf_range(-5.0, 5.0), 0, row * (d * 0.5 + 4.5))
				trunks.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.0)), tp))
	if shops:
		var p := Vector3(c.x, CURB, c.z + 16.0)
		add_building(p, Vector3(BLOCK - 12.0, 7.0, 16.0))
		_block_collider(n, p, BLOCK - 12.0, 16.0, Vector3.ZERO, 8.0)
		for k in 3:
			add_sign(SIGNS[_rng.randi() % SIGNS.size()], Vector3(c.x - 18.0 + k * 18.0, 5.6, c.z + 24.3), 0.0, NEON[_rng.randi() % NEON.size()], 1.6)
	var unit := BoxMesh.new()
	unit.size = Vector3(1, 1, 1)
	var wm := _mat("house_wall", func():
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.85
		return m)
	_local_mm(n, unit, SkylineKit.facade("villa"), walls)
	_local_mm(n, unit, wm, roofs, roof_cols)
	var qm := BoxMesh.new()
	qm.size = Vector3(1.6, 1.2, 0.06)
	_local_mm(n, qm, _mat("house_win", func(): return EnvKit.emissive(Color(1.0, 0.75, 0.42), 2.6)), wins)
	if not trunks.is_empty():
		_local_mm(n, SkylineKit.palm_mesh(), SkylineKit.palm_material(), trunks)
	# gravel and paving between the villas
	var lawn := EnvKit.box(n, Vector3(BLOCK - 4.0, 0.04, BLOCK - 4.0), c + Vector3(0, CURB + 0.02, 0), _mat("lawn", func(): return EnvKit.solid(Color(0.26, 0.21, 0.15), 0.95)))
	lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parked(n, c, 4)


func _trees(n: Node3D, trunks: Array, _crowns: Array) -> void:
	## Parks get date palms too (one palm per trunk position).
	if trunks.is_empty():
		return
	var xf := []
	for t in trunks:
		xf.append(Transform3D(Basis(Vector3.UP, fmod(t.origin.x * 1.7, TAU)), Vector3(t.origin.x, CURB, t.origin.z)))
	_local_mm(n, SkylineKit.palm_mesh(), SkylineKit.palm_material(), xf)


func _fill_industrial(n: Node3D, c: Vector3) -> void:
	## Warehouses with loading doors and sodium wall lights.
	var lot := BLOCK - 10.0
	var steel := _mat("steel", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.22, 0.24)
		m.albedo_texture = EnvKit.noise_tex(31, 0.2)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.08, 0.5, 0.08)
		m.roughness = 0.55
		m.metallic = 0.5
		return m)
	var doors := []
	var lights := []
	var split := _rng.randi() % 2 == 0
	var rects := [[Vector3(0, 0, 0), Vector3(lot, 0, lot)]]
	if split:
		rects = [[Vector3(-lot * 0.25 - 1.0, 0, 0), Vector3(lot * 0.5 - 2.0, 0, lot)], [Vector3(lot * 0.25 + 1.0, 0, 0), Vector3(lot * 0.5 - 2.0, 0, lot)]]
	for r in rects:
		var off: Vector3 = r[0]
		var sz: Vector3 = r[1]
		var h := _rng.randf_range(8.0, 13.0)
		EnvKit.box(n, Vector3(sz.x, h, sz.z), c + off + Vector3(0, CURB + h * 0.5, 0), steel)
		# saw-tooth roof monitors
		for k in 3:
			EnvKit.box(n, Vector3(sz.x * 0.9, 1.4, 3.0), c + off + Vector3(0, CURB + h + 0.7, (k - 1) * sz.z * 0.3), steel)
		for sg: float in [-1.0, 1.0]:
			for k in int(sz.x / 9.0):
				var dx := -sz.x * 0.5 + 5.0 + k * 9.0
				doors.append(Transform3D(Basis.IDENTITY, c + off + Vector3(dx, CURB + 2.2, sg * (sz.z * 0.5 + 0.04))))
				lights.append(Transform3D(Basis.IDENTITY, c + off + Vector3(dx, CURB + 5.2, sg * (sz.z * 0.5 + 0.12))))
	var dm := BoxMesh.new()
	dm.size = Vector3(5.0, 4.4, 0.08)
	_local_mm(n, dm, _mat("rolldoor", func(): return EnvKit.solid(Color(0.32, 0.3, 0.26), 0.5, 0.6)), doors)
	var lm := BoxMesh.new()
	lm.size = Vector3(0.6, 0.22, 0.22)
	_local_mm(n, lm, _mat("sodium", func(): return EnvKit.emissive(Color(1.0, 0.62, 0.25), 7.0)), lights)
	_block_collider(n, c, lot, lot)
	if _rng.randf() < 0.5:
		add_sign(["FREIGHT", "IRONWORKS", "COLD STORE", "MACHINE CO", "BAY STEEL", "DEPOT 9"][_rng.randi() % 6], c + Vector3(0, 7.5, lot * 0.5 + 0.3), 0.0, NEON[2], 2.4)


func _fill_yard(n: Node3D, c: Vector3) -> void:
	## Container yard: stacks with drivable lanes between them (a shortcut through the block).
	var xf := []
	var cols := []
	var pal := [Color(0.55, 0.12, 0.08), Color(0.08, 0.25, 0.5), Color(0.6, 0.42, 0.06), Color(0.1, 0.36, 0.2), Color(0.4, 0.4, 0.42), Color(0.5, 0.2, 0.05)]
	for row in 3:
		for k in 3:
			# lanes run along x between rows, and one lane crosses in the middle
			var px := c.x + (k - 1) * 19.0
			var pz := c.z + (row - 1) * 18.0
			if k == 1 and row == 1:
				continue
			var levels := 1 + _rng.randi() % 3
			for lv in levels:
				xf.append(Transform3D(Basis.IDENTITY, Vector3(px + _rng.randf_range(-0.3, 0.3), CURB + 1.3 + lv * 2.6, pz)))
				cols.append(pal[_rng.randi() % pal.size()])
			_block_collider(n, Vector3(px, 0, pz), 12.4, 5.0, Vector3.ZERO, 8.0)
	var cm := BoxMesh.new()
	cm.size = Vector3(12.2, 2.6, 4.9)
	var m := _mat("container", func():
		var mt := StandardMaterial3D.new()
		mt.vertex_color_use_as_albedo = true
		mt.albedo_texture = EnvKit.noise_tex(31, 0.2)
		mt.uv1_triplanar = true
		mt.uv1_scale = Vector3(0.6, 0.05, 0.6)
		mt.roughness = 0.5
		mt.metallic = 0.4
		return mt)
	_local_mm(n, cm, m, xf, cols)
	# flood lights on masts at two corners
	for sg: float in [-1.0, 1.0]:
		var p := c + Vector3(sg * 27.0, 0, sg * 27.0)
		EnvKit.cyl(n, 0.15, 14.0, p + Vector3(0, 7.0, 0), _mat("pole", func(): return EnvKit.solid(Color(0.08, 0.085, 0.09), 0.5, 0.7)), Vector3.ZERO, 6)
		EnvKit.box(n, Vector3(1.6, 0.5, 0.5), p + Vector3(0, 14.0, 0), _mat("flood", func(): return EnvKit.emissive(Color(0.85, 0.92, 1.0), 8.0)))
		lamp_positions.append(p + Vector3(-sg * 4.0, 11.0, -sg * 4.0))


func _fill_plaza(n: Node3D, c: Vector3) -> void:
	## Syndicate Square: the open meet spot in the middle of downtown.
	var paint := EnvKit.box(n, Vector3(BLOCK - 2.0, 0.03, BLOCK - 2.0), c + Vector3(0, CURB + 0.02, 0), _mat("plaza", func(): return EnvKit.solid(Color(0.05, 0.05, 0.06), 0.35)))
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lines := []
	for k in 9:
		for sg: float in [-1.0, 1.0]:
			lines.append(Transform3D(Basis.IDENTITY, c + Vector3(-22.0 + k * 5.5, CURB + 0.05, sg * 22.0)))
	var lm := BoxMesh.new()
	lm.size = Vector3(0.14, 0.01, 6.0)
	_local_mm(n, lm, _mat("paintline", func(): return EnvKit.emissive(Color(0.9, 0.9, 0.85), 0.35)), lines)
	for sg: float in [-1.0, 1.0]:
		for sg2: float in [-1.0, 1.0]:
			var p := c + Vector3(sg * 28.0, 0, sg2 * 28.0)
			EnvKit.cyl(n, 0.14, 9.0, p + Vector3(0, 4.5, 0), _mat("pole", func(): return EnvKit.solid(Color(0.08, 0.085, 0.09), 0.5, 0.7)), Vector3.ZERO, 6)
			EnvKit.box(n, Vector3(1.4, 0.3, 1.4), p + Vector3(0, 9.0, 0), _mat("flood", func(): return EnvKit.emissive(Color(0.85, 0.92, 1.0), 8.0)))
			_block_collider(n, p, 0.6, 0.6, Vector3.ZERO, 6.0)
	lamp_positions.append(c + Vector3(0, 9.0, 0))
	add_sign("SYNDICATE SQUARE", c + Vector3(0, 11.0, -BLOCK * 0.5 + 1.0), 0.0, NEON[0], 3.2)
	EnvKit.box(n, Vector3(30.0, 13.0, 1.2), c + Vector3(0, 6.5, -BLOCK * 0.5 + 0.2), _mat("tunnel", func(): return EnvKit.solid(Color(0.11, 0.11, 0.115), 0.55)))
	_block_collider(n, c, 30.0, 1.6, Vector3(0, 0, -BLOCK * 0.5 + 0.2))


func _fill_parking(n: Node3D, c: Vector3) -> void:
	## Open-sided parking deck you can cut straight through.
	var conc := _mat("tunnel", func(): return EnvKit.solid(Color(0.11, 0.11, 0.115), 0.55))
	var lot := BLOCK - 8.0
	for lv in 3:
		EnvKit.box(n, Vector3(lot, 0.5, lot), c + Vector3(0, CURB + 3.6 + lv * 3.4, 0), conc)
	var pillars := []
	for ix in 5:
		for iz in 5:
			if ix in [1, 2, 3] and iz in [1, 2, 3] and not (ix == 2 and iz == 2):
				continue
			var p := c + Vector3((ix - 2) * lot * 0.24, 0, (iz - 2) * lot * 0.24)
			pillars.append(Transform3D(Basis.IDENTITY, p + Vector3(0, CURB + 5.2, 0)))
			_block_collider(n, p, 1.0, 1.0, Vector3.ZERO, 5.0)
	var pm := BoxMesh.new()
	pm.size = Vector3(0.9, 10.4, 0.9)
	_local_mm(n, pm, conc, pillars)
	var tubes := []
	for k in 4:
		tubes.append(Transform3D(Basis.IDENTITY, c + Vector3((k - 1.5) * 13.0, CURB + 3.25, 0)))
		lamp_positions.append(c + Vector3((k - 1.5) * 13.0, 2.8, 0))
	var tm := BoxMesh.new()
	tm.size = Vector3(0.3, 0.1, lot * 0.8)
	_local_mm(n, tm, _mat("tube", func(): return EnvKit.emissive(Color(1.0, 0.78, 0.45), 6.0)), tubes)
	add_sign("PARK", c + Vector3(lot * 0.5 + 0.3, 9.0, 0), PI * 0.5, NEON[1], 2.6, true)


func _fill_gas(n: Node3D, c: Vector3) -> void:
	var white := _mat("canopy", func(): return EnvKit.solid(Color(0.75, 0.76, 0.78), 0.4))
	EnvKit.box(n, Vector3(30.0, 0.7, 16.0), c + Vector3(0, CURB + 5.6, 4.0), white)
	EnvKit.box(n, Vector3(29.0, 0.1, 15.0), c + Vector3(0, CURB + 5.2, 4.0), _mat("canopy_glow", func(): return EnvKit.emissive(Color(0.9, 0.95, 1.0), 3.5)))
	EnvKit.box(n, Vector3(30.2, 0.5, 16.2), c + Vector3(0, CURB + 5.9, 4.0), _mat("gas_trim", func(): return EnvKit.emissive(Color(1.0, 0.25, 0.05), 3.0)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := c + Vector3(sx * 13.0, 0, 4.0 + sz * 6.0)
			EnvKit.box(n, Vector3(0.5, 5.4, 0.5), p + Vector3(0, CURB + 2.7, 0), white)
			_block_collider(n, p, 0.7, 0.7, Vector3.ZERO, 5.0)
		var pump := c + Vector3(sx * 6.0, 0, 4.0)
		EnvKit.box(n, Vector3(1.2, 1.9, 3.4), pump + Vector3(0, CURB + 0.95, 0), _mat("pump", func(): return EnvKit.solid(Color(0.6, 0.08, 0.05), 0.4)))
		EnvKit.box(n, Vector3(1.24, 0.5, 1.0), pump + Vector3(0, CURB + 1.5, 0), _mat("canopy_glow", func(): return EnvKit.emissive(Color(0.9, 0.95, 1.0), 3.5)))
		_block_collider(n, pump, 1.4, 3.6, Vector3.ZERO, 3.0)
	# shop
	add_building(c + Vector3(0, CURB, -19.0), Vector3(34.0, 5.0, 14.0))
	_block_collider(n, c, 34.0, 14.0, Vector3(0, 0, -19.0), 6.0)
	add_sign("VOLT FUEL", c + Vector3(0, 7.4, 12.2), 0.0, NEON[5], 2.0)
	add_sign("24 HR", c + Vector3(-22.0, 9.0, 24.0), 0.0, NEON[2], 2.2)
	EnvKit.box(n, Vector3(0.5, 9.0, 0.5), c + Vector3(-22.0, 4.5, 23.6), white)
	lamp_positions.append(c + Vector3(0, 4.6, 4.0))


func _fill_park(n: Node3D, c: Vector3) -> void:
	var lawn := EnvKit.box(n, Vector3(BLOCK - 2.0, 0.04, BLOCK - 2.0), c + Vector3(0, CURB + 0.02, 0), _mat("lawn", func(): return EnvKit.solid(Color(0.045, 0.1, 0.04), 0.95)))
	lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trunks := []
	var crowns := []
	for k in 16:
		var p := c + Vector3(_rng.randf_range(-27.0, 27.0), CURB, _rng.randf_range(-27.0, 27.0))
		if absf(p.x - c.x) < 4.0 or absf(p.z - c.z) < 4.0:
			continue        # keep the two paths clear, you can drive through
		trunks.append(Transform3D(Basis.IDENTITY, p + Vector3(0, 1.6, 0)))
		var s := _rng.randf_range(3.0, 5.0)
		crowns.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * 1.1, s)), p + Vector3(0, 4.8, 0)))
		_block_collider(n, p, 0.5, 0.5, Vector3.ZERO, 4.0)
	_trees(n, trunks, crowns)
	var path := _mat("path", func(): return EnvKit.solid(Color(0.24, 0.22, 0.19), 0.9))
	EnvKit.box(n, Vector3(BLOCK - 2.0, 0.05, 6.0), c + Vector3(0, CURB + 0.04, 0), path)
	EnvKit.box(n, Vector3(6.0, 0.05, BLOCK - 2.0), c + Vector3(0, CURB + 0.04, 0), path)
	EnvKit.cyl(n, 2.4, 0.8, c + Vector3(0, CURB + 0.4, 0), _mat("concrete", func(): return EnvKit.solid(Color(0.16, 0.16, 0.17), 0.8)), Vector3.ZERO, 12)
	_block_collider(n, c, 4.0, 4.0, Vector3.ZERO, 3.0)
	lamp_positions.append(c + Vector3(0, 5.0, 0))


# ---------------------------------------------------------------- parked cars + people
func _parked_mesh() -> ArrayMesh:
	if _car_mesh:
		return _car_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshKit.box(st, Vector3(0, 0.55, 0), Vector3(1.78, 0.62, 4.4))
	MeshKit.hexa(st,
		[Vector3(-0.84, 0.86, -1.3), Vector3(0.84, 0.86, -1.3), Vector3(0.84, 0.86, 1.7), Vector3(-0.84, 0.86, 1.7)],
		[Vector3(-0.7, 1.36, -0.5), Vector3(0.7, 1.36, -0.5), Vector3(0.7, 1.36, 1.1), Vector3(-0.7, 1.36, 1.1)])
	st.generate_normals()
	_car_mesh = st.commit()
	return _car_mesh


func _parked(n: Node3D, c: Vector3, count: int) -> void:
	## Cars parked at the kerb. They narrow the street and are solid.
	var xf := []
	var cols := []
	var pal := [Color(0.5, 0.05, 0.05), Color(0.05, 0.1, 0.35), Color(0.6, 0.6, 0.62), Color(0.03, 0.03, 0.035), Color(0.75, 0.75, 0.72), Color(0.1, 0.25, 0.12), Color(0.55, 0.35, 0.05)]
	var edge := BLOCK * 0.5 + 1.05
	for k in count:
		var side := _rng.randi() % 4
		var t := _rng.randf_range(-20.0, 20.0)
		var p := Vector3(c.x + t, 0, c.z - edge)
		var yaw := PI * 0.5
		match side:
			1: p = Vector3(c.x + t, 0, c.z + edge)
			2:
				p = Vector3(c.x - edge, 0, c.z + t)
				yaw = 0.0
			3:
				p = Vector3(c.x + edge, 0, c.z + t)
				yaw = 0.0
		xf.append(Transform3D(Basis(Vector3.UP, yaw), p))
		cols.append(pal[_rng.randi() % pal.size()])
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.8, 1.4, 4.4)
		cs.shape = bs
		sb.add_child(cs)
		sb.transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.7, 0))
		n.add_child(sb)
	var m := _mat("parked", func():
		var mt := StandardMaterial3D.new()
		mt.vertex_color_use_as_albedo = true
		mt.roughness = 0.25
		mt.metallic = 0.6
		return mt)
	_local_mm(n, _parked_mesh(), m, xf, cols)


func _person_mesh() -> ArrayMesh:
	if _ped_mesh:
		return _ped_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.12, 0.12, 0.16))
	MeshKit.box(st, Vector3(-0.1, 0.42, 0), Vector3(0.15, 0.84, 0.18))
	MeshKit.box(st, Vector3(0.1, 0.42, 0), Vector3(0.15, 0.84, 0.18))
	st.set_color(Color(1, 1, 1))
	MeshKit.box(st, Vector3(0, 1.14, 0), Vector3(0.44, 0.62, 0.24))
	st.set_color(Color(0.75, 0.55, 0.42))
	MeshKit.box(st, Vector3(0, 1.6, 0), Vector3(0.2, 0.24, 0.2))
	st.generate_normals()
	_ped_mesh = st.commit()
	return _ped_mesh


func _pedestrians(n: Node3D, c: Vector3, count: int) -> void:
	## People walking laps of the block's sidewalk. Moved entirely in the vertex
	## shader (no nodes, no scripts), so a crowd costs one draw call per block.
	if not GFX.p.get("people", true):
		return
	if _ped_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float radius = 29.5;
void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float speed = INSTANCE_CUSTOM.y;
	float lane = INSTANCE_CUSTOM.z;
	float r = radius + lane;
	float s = fract(phase + TIME * speed / (8.0 * r)) * 4.0;
	if (speed < 0.0) s = 4.0 - fract(phase - TIME * speed / (8.0 * r)) * 4.0;
	float side = floor(s);
	float f = fract(s) * 2.0 - 1.0;
	vec2 pos;
	float ang;
	if (side < 1.0) { pos = vec2(f * r, -r); ang = 1.5708; }
	else if (side < 2.0) { pos = vec2(r, f * r); ang = 0.0; }
	else if (side < 3.0) { pos = vec2(-f * r, r); ang = -1.5708; }
	else { pos = vec2(-r, -f * r); ang = 3.14159; }
	if (speed < 0.0) ang += 3.14159;
	float cs = cos(ang);
	float sn = sin(ang);
	vec3 v = VERTEX;
	// stride: legs swing, body bobs
	float step_t = TIME * abs(speed) * 4.2 + phase * 40.0;
	if (v.y < 0.85) v.z += sin(step_t) * 0.22 * sign(v.x) * (0.85 - v.y);
	v.y += abs(sin(step_t)) * 0.03;
	vec3 w = vec3(v.x * cs + v.z * sn, v.y, -v.x * sn + v.z * cs);
	VERTEX = w + vec3(pos.x, 0.14, pos.y);
	NORMAL = vec3(NORMAL.x * cs + NORMAL.z * sn, NORMAL.y, -NORMAL.x * sn + NORMAL.z * cs);
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
}
"""
		_ped_mat = ShaderMaterial.new()
		_ped_mat.shader = sh
		_ped_mat.set_shader_parameter("radius", BLOCK * 0.5 - 2.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _person_mesh()
	mm.instance_count = count
	var pal := [Color(0.5, 0.1, 0.1), Color(0.1, 0.2, 0.5), Color(0.6, 0.55, 0.2), Color(0.15, 0.15, 0.18), Color(0.7, 0.7, 0.7), Color(0.2, 0.4, 0.25), Color(0.5, 0.2, 0.5)]
	for i in count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_color(i, pal[_rng.randi() % pal.size()])
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf_range(1.0, 1.7) * (1.0 if _rng.randf() < 0.5 else -1.0), _rng.randf_range(-0.9, 0.9), 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _ped_mat
	mi.position = Vector3(c.x, 0, c.z)
	mi.custom_aabb = AABB(Vector3(-34, 0, -34), Vector3(68, 3, 68))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
