class_name RacePath
extends RefCounted
## A race route as a polyline with arc-length lookups. Used by the AI (racing
## line, corner speeds), by ranking (who is ahead) and by the minimap.

var pts: PackedVector3Array = []
var cum: PackedFloat32Array = []
var vlim: PackedFloat32Array = []    # cornering speed limit at each vertex (m/s) for a_lat = 1
var total := 0.0
var closed := false


static func make(points: PackedVector3Array, is_closed: bool) -> RacePath:
	var p := RacePath.new()
	p.closed = is_closed
	p.pts = _round_corners(points, is_closed)
	p._measure()
	return p


## Sharp street corners become short three-point arcs that cut the apex.
static func _round_corners(src: PackedVector3Array, is_closed: bool) -> PackedVector3Array:
	var out: PackedVector3Array = []
	var n := src.size()
	for i in n:
		var cur := src[i]
		var has_prev := i > 0 or is_closed
		var has_next := i < n - 1 or is_closed
		if not (has_prev and has_next):
			out.append(cur)
			continue
		var prev := src[(i + n - 1) % n]
		var next := src[(i + 1) % n]
		var a := Vector3(cur.x - prev.x, 0, cur.z - prev.z)
		var b := Vector3(next.x - cur.x, 0, next.z - cur.z)
		var la := a.length()
		var lb := b.length()
		if la < 0.01 or lb < 0.01:
			continue
		var ang := a.angle_to(b)
		if ang < 0.6:
			out.append(cur)
			continue
		var cut := minf(13.0, minf(la, lb) * 0.45)
		var p0 := cur - a / la * cut
		var p2 := cur + b / lb * cut
		out.append(p0)
		out.append(p0.lerp(p2, 0.5).lerp(cur, 0.55))
		out.append(p2)
	return out


func _measure() -> void:
	var n := pts.size()
	cum.resize(n)
	vlim.resize(n)
	var acc := 0.0
	for i in n:
		cum[i] = acc
		if i < n - 1:
			acc += Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
	total = acc
	if closed:
		total += Vector2(pts[0].x - pts[n - 1].x, pts[0].z - pts[n - 1].z).length()
	for i in n:
		vlim[i] = 999.0
		if not closed and (i == 0 or i == n - 1):
			continue
		var prev := pts[(i + n - 1) % n]
		var next := pts[(i + 1) % n]
		var a := Vector3(pts[i].x - prev.x, 0, pts[i].z - prev.z)
		var b := Vector3(next.x - pts[i].x, 0, next.z - pts[i].z)
		var ang := a.angle_to(b)
		if ang > 0.03:
			var chord := minf(minf(a.length(), b.length()), 16.0)
			vlim[i] = sqrt(chord / (2.0 * sin(ang * 0.5)))


func _wrap(s: float) -> float:
	return fposmod(s, total) if closed else clampf(s, 0.0, total)


func _seg(s: float) -> int:
	var n := pts.size()
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


func pos_at(s: float) -> Vector3:
	s = _wrap(s)
	var i := _seg(s)
	var n := pts.size()
	var j := (i + 1) % n if closed else mini(i + 1, n - 1)
	var seg_len := (cum[j] - cum[i]) if j > i else (total - cum[i])
	if seg_len < 0.001:
		return pts[i]
	return pts[i].lerp(pts[j], clampf((s - cum[i]) / seg_len, 0.0, 1.0))


func dir_at(s: float) -> Vector3:
	var a := pos_at(s)
	var b := pos_at(s + 2.0) if (closed or s + 2.0 < total) else pos_at(total)
	if not closed and s + 2.0 >= total:
		a = pos_at(total - 2.0)
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


## Arc length of the point on the route closest to `p`, searching near `hint`.
func project(p: Vector3, hint: float, window := 70.0) -> float:
	var best_s := hint
	var best_d := INF
	var n := pts.size()
	var s0 := _wrap(hint - window * 0.4)
	var i0 := _seg(s0)
	var steps := 0
	var i := i0
	var travelled := cum[i0] - s0
	while travelled < window * 1.4 and steps < n:
		var j := (i + 1) % n
		if j == 0 and not closed:
			break
		var a := pts[i]
		var b := pts[j]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := ab.length_squared()
		var t := 0.0
		if l2 > 0.0001:
			t = clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / l2, 0.0, 1.0)
		var q := Vector2(a.x, a.z) + ab * t
		var d := Vector2(p.x, p.z).distance_squared_to(q)
		var ln := sqrt(l2)
		if d < best_d:
			best_d = d
			best_s = cum[i] + ln * t
		travelled += ln
		i = j
		steps += 1
	return best_s


## Highest speed allowed now so that every corner in the next `ahead` metres
## can still be made, given lateral grip `a_lat` and braking `a_brake`.
func speed_limit(s: float, ahead: float, a_lat: float, a_brake: float) -> float:
	var n := pts.size()
	var i := _seg(_wrap(s))
	var lim := 999.0
	var dist := -(_wrap(s) - cum[i])
	var steps := 0
	while dist < ahead and steps < n:
		var j := (i + 1) % n
		if j == 0 and not closed:
			break
		var ln := (cum[j] - cum[i]) if j > i else (total - cum[i])
		dist += ln
		if vlim[j] < 900.0:
			var vc := vlim[j] * sqrt(a_lat)
			lim = minf(lim, sqrt(vc * vc + 2.0 * a_brake * maxf(dist - 4.0, 0.0)))
		i = j
		steps += 1
	return lim
