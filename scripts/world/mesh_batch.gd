class_name MeshBatch
## Collects geometry per material and commits it as ONE mesh (one draw call per
## material). Used to build a whole city block: kit modules and props are
## appended with their transforms, generated boxes/quads get metre-scaled UVs.

var _gen := {}      # Material -> SurfaceTool (generated quads)
var _imp := {}      # Material -> SurfaceTool (appended imported meshes)
var cast_shadows := false


func _tool(d: Dictionary, mat: Material) -> SurfaceTool:
	if not d.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		d[mat] = st
	return d[mat]


## Append an imported mesh. `remap` swaps materials (original -> replacement).
func add_mesh(mesh: Mesh, xf: Transform3D, remap := {}) -> void:
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if remap.has(mat):
			mat = remap[mat]
		_tool(_imp, mat).append_from(mesh, s, xf)


func add_prop(p: Dictionary, xf: Transform3D, remap := {}) -> void:
	for part in p.parts:
		add_mesh(part.mesh, xf * part.xf, remap)


## Quad a-b-c-d (counter-clockwise seen from the front), UVs in metres.
func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_origin := Vector2.ZERO, uv_size := Vector2(-1, -1)) -> void:
	var st := _tool(_gen, mat)
	var n := (b - a).cross(d - a).normalized()
	var w := (b - a).length()
	var h := (d - a).length()
	var u0 := uv_origin
	var us := Vector2(w, h) if uv_size.x < 0.0 else uv_size
	var tangent := (b - a).normalized()
	var pl := Plane(tangent.x, tangent.y, tangent.z, 1.0)
	var uvs := [u0 + Vector2(0, us.y), u0 + Vector2(us.x, us.y), u0 + Vector2(us.x, 0), u0]
	var vs := [a, b, c, d]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_tangent(pl)
		st.set_uv(uvs[i])
		st.add_vertex(vs[i])


## Quad with explicit UVs (a-b-c-d counter-clockwise seen from the front).
func quad_uv(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var st := _tool(_gen, mat)
	var n := (b - a).cross(d - a).normalized()
	var tangent := (b - a).normalized()
	var pl := Plane(tangent.x, tangent.y, tangent.z, 1.0)
	var uvs := [ua, ub, uc, ud]
	var vs := [a, b, c, d]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_tangent(pl)
		st.set_uv(uvs[i])
		st.add_vertex(vs[i])


## Axis box in a local frame: `xf` maps local (x right, y up, z toward viewer).
## `faces` bit mask: 1 +z front, 2 -z back, 4 +x, 8 -x, 16 top, 32 bottom.
func box(mat: Material, xf: Transform3D, size: Vector3, faces := 31, uv_off := Vector2.ZERO) -> void:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
	var o := xf.origin
	var uo := uv_off + Vector2(o.x + o.z, 0.0)
	if faces & 1:
		quad(mat, p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), uo)
	if faces & 2:
		quad(mat, p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), uo)
	if faces & 4:
		quad(mat, p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), uo)
	if faces & 8:
		quad(mat, p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), uo)
	if faces & 16:
		quad(mat, p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1), uo)
	if faces & 32:
		quad(mat, p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1), uo)


func is_empty() -> bool:
	return _gen.is_empty() and _imp.is_empty()


func commit(parent: Node, shadows := false) -> MeshInstance3D:
	if is_empty():
		return null
	var mesh := ArrayMesh.new()
	for d in [_gen, _imp]:
		for mat in d:
			var st: SurfaceTool = d[mat]
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	if OS.get_environment("AH_BENCH") != "":
		var tris := 0
		for si in mesh.get_surface_count():
			tris += mesh.surface_get_array_index_len(si) / 3 if mesh.surface_get_array_index_len(si) > 0 else mesh.surface_get_array_len(si) / 3
		print("  batch surfaces=%d tris=%d" % [mesh.get_surface_count(), tris])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_gen.clear()
	_imp.clear()
	return mi
