class_name MeshKit
## Small procedural-mesh helpers built on SurfaceTool. Winding is fixed
## automatically from the supplied normals, so callers never worry about it.

static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-12:
		return
	if g.dot(na + nb + nc) > 0.0:
		st.set_normal(na); st.set_uv(ua); st.add_vertex(a)
		st.set_normal(nc); st.set_uv(uc); st.add_vertex(c)
		st.set_normal(nb); st.set_uv(ub); st.add_vertex(b)
	else:
		st.set_normal(na); st.set_uv(ua); st.add_vertex(a)
		st.set_normal(nb); st.set_uv(ub); st.add_vertex(b)
		st.set_normal(nc); st.set_uv(uc); st.add_vertex(c)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	tri(st, a, b, c, na, nb, nc, Vector2(a.z, a.x), Vector2(b.z, b.x), Vector2(c.z, c.x))
	tri(st, a, c, d, na, nc, nd, Vector2(a.z, a.x), Vector2(c.z, c.x), Vector2(d.z, d.x))


static func flat_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	tri(st, a, b, c, n, n, n, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	tri(st, a, c, d, n, n, n, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))


## Oriented box. `basis` columns are the box axes.
static func box(st: SurfaceTool, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var ax := basis.x
	var ay := basis.y
	var az := basis.z
	for s in [-1.0, 1.0]:
		# +-X faces
		var c: Vector3 = center + ax * h.x * s
		flat_quad(st, c - ay * h.y - az * h.z, c + ay * h.y - az * h.z, c + ay * h.y + az * h.z, c - ay * h.y + az * h.z, ax * s)
		c = center + ay * h.y * s
		flat_quad(st, c - ax * h.x - az * h.z, c + ax * h.x - az * h.z, c + ax * h.x + az * h.z, c - ax * h.x + az * h.z, ay * s)
		c = center + az * h.z * s
		flat_quad(st, c - ax * h.x - ay * h.y, c + ax * h.x - ay * h.y, c + ax * h.x + ay * h.y, c - ax * h.x + ay * h.y, az * s)


## Convex prism from 8 corners (two quads a0..a3 and b0..b3), flat shaded.
static func hexa(st: SurfaceTool, a: Array, b: Array) -> void:
	var center := Vector3.ZERO
	for p in a:
		center += p
	for p in b:
		center += p
	center /= 8.0
	var faces := [[a[0], a[1], a[2], a[3]], [b[0], b[1], b[2], b[3]]]
	for i in 4:
		var j := (i + 1) % 4
		faces.append([a[i], a[j], b[j], b[i]])
	for f in faces:
		var fc: Vector3 = (f[0] + f[1] + f[2] + f[3]) * 0.25
		var n: Vector3 = (f[1] - f[0]).cross(f[2] - f[0])
		if n.length_squared() < 1e-14:
			n = (f[2] - f[0]).cross(f[3] - f[0])
		n = n.normalized()
		if n.dot(fc - center) < 0.0:
			n = -n
		flat_quad(st, f[0], f[1], f[2], f[3], n)


## Cylinder along `axis` (unit), from center-axis*h/2 to center+axis*h/2.
static func cylinder(st: SurfaceTool, center: Vector3, axis: Vector3, radius: float, height: float, segs := 16, caps := true, radius2 := -1.0) -> void:
	if radius2 < 0.0:
		radius2 = radius
	var u := axis.cross(Vector3.UP)
	if u.length_squared() < 0.01:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := axis.cross(u).normalized()
	var p0 := center - axis * height * 0.5
	var p1 := center + axis * height * 0.5
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		tri(st, p0 + d0 * radius, p0 + d1 * radius, p1 + d1 * radius2, d0, d1, d1)
		tri(st, p0 + d0 * radius, p1 + d1 * radius2, p1 + d0 * radius2, d0, d1, d0)
		if caps:
			tri(st, p0, p0 + d0 * radius, p0 + d1 * radius, -axis, -axis, -axis)
			tri(st, p1, p1 + d0 * radius2, p1 + d1 * radius2, axis, axis, axis)


## Surface of revolution around the X axis. profile = [Vector2(x, r), ...].
## `outward` selects which side the normals face (true: away from the axis side of travel).
static func lathe_x(st: SurfaceTool, profile: Array, segs := 32, flip := false) -> void:
	var n := profile.size()
	var norms := []
	for i in n:
		var a: Vector2 = profile[maxi(i - 1, 0)]
		var b: Vector2 = profile[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		var nn := Vector2(-t.y, t.x)  # (x, r) space normal
		if flip:
			nn = -nn
		norms.append(nn)
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		for i in n - 1:
			var p: Vector2 = profile[i]
			var q: Vector2 = profile[i + 1]
			var np: Vector2 = norms[i]
			var nq: Vector2 = norms[i + 1]
			var v00 := Vector3(p.x, p.y * cos(a0), p.y * sin(a0))
			var v01 := Vector3(p.x, p.y * cos(a1), p.y * sin(a1))
			var v10 := Vector3(q.x, q.y * cos(a0), q.y * sin(a0))
			var v11 := Vector3(q.x, q.y * cos(a1), q.y * sin(a1))
			var n00 := Vector3(np.x, np.y * cos(a0), np.y * sin(a0))
			var n01 := Vector3(np.x, np.y * cos(a1), np.y * sin(a1))
			var n10 := Vector3(nq.x, nq.y * cos(a0), nq.y * sin(a0))
			var n11 := Vector3(nq.x, nq.y * cos(a1), nq.y * sin(a1))
			tri(st, v00, v01, v11, n00, n01, n11)
			tri(st, v00, v11, v10, n00, n11, n10)


static func add_surface(mesh: ArrayMesh, st: SurfaceTool, mat: Material) -> void:
	var arr := st.commit_to_arrays()
	if arr[Mesh.ARRAY_VERTEX] == null or arr[Mesh.ARRAY_VERTEX].size() == 0:
		return
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


static func instance(mesh: Mesh, node_name := "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = node_name
	return mi


## Cubic Hermite through key points [[u, v], ...] (Catmull-Rom tangents).
static func curve(keys: Array, u: float) -> float:
	var n := keys.size()
	if u <= keys[0][0]:
		return keys[0][1]
	if u >= keys[n - 1][0]:
		return keys[n - 1][1]
	var i := 0
	while i < n - 2 and u > keys[i + 1][0]:
		i += 1
	var u0: float = keys[i][0]
	var u1: float = keys[i + 1][0]
	var v0: float = keys[i][1]
	var v1: float = keys[i + 1][1]
	var m0 := 0.0
	var m1 := 0.0
	if i > 0:
		m0 = (v1 - keys[i - 1][1]) / (u1 - keys[i - 1][0])
	else:
		m0 = (v1 - v0) / (u1 - u0)
	if i < n - 2:
		m1 = (keys[i + 2][1] - v0) / (keys[i + 2][0] - u0)
	else:
		m1 = (v1 - v0) / (u1 - u0)
	var h := u1 - u0
	var t := (u - u0) / h
	var t2 := t * t
	var t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * v0 + (t3 - 2 * t2 + t) * h * m0 + (-2 * t3 + 3 * t2) * v1 + (t3 - t2) * h * m1
