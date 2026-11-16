class_name ParkedCars
## Real car bodies for the cars parked at the kerb: 5,000-triangle versions of
## the game's own car models (w3d/cars_lod), drawn with one MultiMesh per model
## and painted per car through the instance colour.

const IDS := ["sedan", "suv", "euro", "classic", "muscle"]
const LEN := {"sedan": 4.7, "suv": 4.8, "euro": 4.4, "classic": 4.6, "muscle": 4.8}
const PAINTS := [Color(0.42, 0.03, 0.03), Color(0.03, 0.07, 0.28), Color(0.5, 0.5, 0.52), Color(0.02, 0.02, 0.025),
	Color(0.7, 0.7, 0.68), Color(0.06, 0.18, 0.09), Color(0.5, 0.3, 0.04), Color(0.25, 0.26, 0.28)]

static var _cache := {}
static var _shader: Shader


static func _find(n: Node, xf: Transform3D) -> Array:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return [(n as MeshInstance3D).mesh, t]
	for c in n.get_children():
		var r := _find(c, t)
		if not r.is_empty():
			return r
	return []


static func _yaw(id: String) -> float:
	var jp := "res://cars/%s.json" % id
	if FileAccess.file_exists(jp):
		var j = JSON.parse_string(FileAccess.get_file_as_string(jp))
		if j is Dictionary:
			return float(j.get("yaw", 90.0))
	return 90.0


## {mesh, fix (model -> car frame: nose toward -z, wheels on y = 0), mat}
static func lod(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var ps: PackedScene = load("res://w3d/cars_lod/%s.glb" % id)
	var root := ps.instantiate()
	var found := _find(root, Transform3D.IDENTITY)
	root.free()
	var mesh: Mesh = found[0]
	var xf: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(_yaw(id))), Vector3.ZERO) * (found[1] as Transform3D)
	var box: AABB = xf * mesh.get_aabb()
	var s: float = float(LEN[id]) / maxf(box.size.z, 0.01)
	var c := box.get_center()
	var fix := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(-c.x * s, -box.position.y * s, -c.z * s)) * xf
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CarVisual.MODEL_SHADER.replace("uniform vec3 paint : source_color = vec3(0.6, 0.0, 0.0);", "").replace("void fragment() {", "void fragment() {\n\tvec3 paint = COLOR.rgb;").replace("EMISSION = c * red * tail_e;", "vec3 nw = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;\n\tEMISSION = c * red * tail_e + mix(c, paint * shade, m) * vec3(1.0, 0.76, 0.54) * 0.2 * clamp(nw.y * 0.8 + 0.25, 0.0, 1.0);")
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	var src := mesh.surface_get_material(0)
	if src is BaseMaterial3D:
		mat.set_shader_parameter("tex", (src as BaseMaterial3D).albedo_texture)
	mat.set_shader_parameter("tail_e", 0.25)
	mat.set_shader_parameter("paint_rough", 0.22)
	var d := {"mesh": mesh, "fix": fix, "mat": mat}
	_cache[id] = d
	return d


## Adds the cars (Array of {xf: Transform3D, id: String, paint: Color}) under `n`.
static func add(n: Node3D, cars: Array) -> void:
	if OS.get_environment("AH_BENCH") != "":
		for c in cars:
			print("PARKED ", c.id, " ", n.position + (c.xf as Transform3D).origin)
	var by := {}
	for c in cars:
		if not by.has(c.id):
			by[c.id] = []
		by[c.id].append(c)
	for id in by:
		var d := lod(id)
		var list: Array = by[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = d.mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, (list[i].xf as Transform3D) * (d.fix as Transform3D))
			mm.set_instance_color(i, list[i].paint)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = d.mat
		n.add_child(mi)
