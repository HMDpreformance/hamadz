#!/usr/bin/env python3
"""Builds the Dubai-shaped city for the Unity game from unity_assets/city/plan.json
(tools/city_plan.py): part 1 only (west of plan.phase1_x), scaled to game metres.

Out (unity_assets/city/):
  city_part1.glb   meshes by name: asphalt, sidewalk, marking_white, marking_yellow, concrete
                   (bridge slabs, pillars, parapets, skirts), terrain, water, barrier_red, barrier_white
  city_part1.json  road centre lines with heights (traffic, minimap), junctions, road blocks, garage, spawn

Game frame: x = plan x * scale (east), z = plan y * scale (north), y up, sea level y = 0.
Rules (see the research notes): one road class per road, level junction zones, the road keeps
its own height line and the ground is shaped to it, bridges leave the ground alone."""
import json, math, os, sys
import numpy as np, trimesh
from scipy.spatial import cKDTree

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CITY = os.path.join(ROOT, "unity_assets", "city")
plan = json.load(open(os.path.join(CITY, "plan.json")))
S = plan["scale"]; PX = plan["phase1_x"]
WIDTH = {"highway": 26.0, "main": 17.0, "street": 10.0, "ramp": 8.0}
WALK = 3.0; KERB = 0.15; STEP = 5.0
COAST = np.array(plan["coast"])

def coast_y(x): return float(np.interp(x, COAST[:, 0], COAST[:, 1]))

def ground(X, Z):
    """Natural ground height at a game position (the plan's terrain, with the sea bed north of the coast)."""
    x, y = X / S, Z / S
    d = coast_y(x) - y
    if d < 0: return max(-5.0, 1.5 + d * 0.09)
    h = 1.5 + 9.0 * min(1.0, d / 1500.0) ** 1.3
    for cx, cy, r, amp in ((1500, 310, 330, 11), (1250, 120, 260, 8), (2060, 420, 260, 6), (1620, 1130, 300, 3), (300, 250, 300, 4)):
        h += amp * math.exp(-((x - cx) ** 2 + (y - cy) ** 2) / (2 * (r * 0.55) ** 2))
    return h

def resample(P, step=STEP, extra=None):
    """Points every `step` metres along a polyline; `extra` (per point values) is interpolated too."""
    P = np.asarray(P, float)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    keep = np.concatenate([[True], seg > 1e-6]); P = P[keep]
    if extra is not None: extra = np.asarray(extra, float)[keep]
    cum = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    n = max(2, int(round(cum[-1] / step)) + 1)
    s = np.linspace(0, cum[-1], n)
    Q = np.stack([np.interp(s, cum, P[:, 0]), np.interp(s, cum, P[:, 1])], 1)
    return (Q, s, np.interp(s, cum, extra)) if extra is not None else (Q, s)

class Road:
    def __init__(self, name, cls, P, deck, blocked=(False, False)):
        self.name, self.cls, self.w = name, cls, WIDTH[cls]
        self.P, self.s, self.deck = resample(P, STEP, deck)
        self.deck = np.maximum(self.deck, 0.0)
        self.blocked = blocked
        self.junc = []                     # (s, radius, height index) of level junctions on this road
    def frame(self):
        t = np.gradient(self.P, axis=0); t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
        return t, np.stack([-t[:, 1], t[:, 0]], 1)      # tangent, left normal (x,z)
    def at(self, s):
        return np.array([np.interp(s, self.s, self.P[:, 0]), np.interp(s, self.s, self.P[:, 1])])

# ---- 1. roads of part 1, in game metres
roads = []
for r in plan["roads"]:
    P = np.array(r["pts"], float); deck = np.array(r["deck"], float)
    Pf, sf, df = resample(P, 4.0, deck)
    inside = Pf[:, 0] <= PX
    i = 0
    while i < len(Pf):
        if not inside[i]: i += 1; continue
        j = i
        while j + 1 < len(Pf) and inside[j + 1]: j += 1
        if j - i >= 3:
            edge = lambda p: p[0] < 3 or p[1] < 3 or p[1] > plan["size"][1] - 3      # the road leaves the map here
            roads.append(Road(r["name"], r["cls"], Pf[i:j + 1] * S, df[i:j + 1], (i > 0 or edge(Pf[i]), j < len(Pf) - 1 or edge(Pf[j]))))
        i = j + 1

def seg_hits(A, B):
    """Crossings of polylines A and B (arrays n x 2): list of (index a, t a, index b, t b)."""
    out = []
    a1, a2 = A[:-1], A[1:]; b1, b2 = B[:-1], B[1:]
    amin, amax = np.minimum(a1, a2), np.maximum(a1, a2)
    bmin, bmax = np.minimum(b1, b2).min(0), np.maximum(b1, b2).max(0)
    cand = np.where((amax[:, 0] >= bmin[0]) & (amin[:, 0] <= bmax[0]) & (amax[:, 1] >= bmin[1]) & (amin[:, 1] <= bmax[1]))[0]
    for i in cand:
        d1 = a2[i] - a1[i]; d2 = b2 - b1
        den = d1[0] * d2[:, 1] - d1[1] * d2[:, 0]
        ok = np.abs(den) > 1e-9
        w = b1 - a1[i]
        t = np.where(ok, (w[:, 0] * d2[:, 1] - w[:, 1] * d2[:, 0]) / np.where(ok, den, 1), -1)
        u = np.where(ok, (w[:, 0] * d1[1] - w[:, 1] * d1[0]) / np.where(ok, den, 1), -1)
        for j in np.where((t >= 0) & (t < 1) & (u >= 0) & (u < 1))[0]: out.append((i, float(t[j]), int(j), float(u[j])))
    return out

# a street or main road that meets a highway ramp (highway 1 to 4.5 m up: a solid wall) is cut there
def cut_at_ramps(roads):
    out = []
    for R in roads:
        cuts = []
        for H in roads:
            if H is R or H.cls != "highway" or R.cls == "highway": continue
            for i, t, j, u in seg_hits(R.P, H.P):
                dk = np.interp(H.s[j] + u * STEP, H.s, H.deck)
                if 0.8 < dk < 5.2: cuts.append(R.s[i] + t * STEP)
        if not cuts: out.append(R); continue
        keep = np.ones(len(R.P), bool)
        for c in cuts: keep &= np.abs(R.s - c) > 26
        i = 0
        while i < len(keep):
            if not keep[i]: i += 1; continue
            j = i
            while j + 1 < len(keep) and keep[j + 1]: j += 1
            if j - i >= 4: out.append(Road(R.name, R.cls, R.P[i:j + 1], R.deck[i:j + 1], (R.blocked[0] and i == 0, R.blocked[1] and j == len(keep) - 1)))
            i = j + 1
    return out
roads = cut_at_ramps(roads)

# ---- 2. interchanges: where a highway flies over a main road, four ramps join the two
ramps = []
for hwy in [r for r in roads if r.cls == "highway"]:
    for o in [r for r in roads if r.cls == "main"]:
        for i, t, j, u in seg_hits(hwy.P, o.P):
            sh = hwy.s[i] + t * STEP; so = o.s[j] + u * STEP
            if np.interp(sh, hwy.s, hwy.deck) < 3.5: continue
            C = hwy.at(sh); th = hwy.at(min(sh + 5, hwy.s[-1])) - hwy.at(max(sh - 5, 0)); th /= np.linalg.norm(th)
            nh = np.array([-th[1], th[0]])
            for d in (-1, 1):
                sa = sh + d * 212
                if sa < 10 or sa > hwy.s[-1] - 10 or np.interp(sa, hwy.s, hwy.deck) > 0.3: continue
                A = hwy.at(sa)
                for lat in (-1, 1):
                    cands = [so + e * 70 for e in (-1, 1) if 5 < so + e * 70 < o.s[-1] - 5]
                    cands = [c for c in cands if np.dot(o.at(c) - C, nh) * lat > 0]
                    if not cands: continue
                    B = o.at(cands[0])
                    if max(A[0], B[0]) > PX * S - 15: continue
                    M = A + nh * lat * 22 - th * d * 75
                    tt = np.linspace(0, 1, 24)[:, None]
                    curve = (1 - tt) ** 2 * A + 2 * (1 - tt) * tt * M + tt ** 2 * B
                    ramps.append(Road("Ramp", "ramp", curve, np.zeros(len(curve))))
roads += ramps

# ---- 3. height line of every road: smoothed ground + bridge deck
for r in roads:
    g = np.array([max(1.5, ground(x, z)) for x, z in r.P])
    k = 13; pad = np.pad(g, k, mode="edge"); g = np.convolve(pad, np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
    r.base = g; r.h = g + r.deck

# ---- 4. level junctions: crossings and T ends where both roads are on the ground
junctions = []        # dicts: pos, members [(road index, s)], h
def add_junction(pos, members):
    for J in junctions:
        if np.linalg.norm(J["pos"] - pos) < 9:
            for m in members:
                if all(m[0] != q[0] or abs(m[1] - q[1]) > 12 for q in J["members"]): J["members"].append(m)
            return
    junctions.append({"pos": np.array(pos, float), "members": list(members)})

for a in range(len(roads)):
    A = roads[a]
    for b in range(a + 1, len(roads)):
        B = roads[b]
        for i, t, j, u in seg_hits(A.P, B.P):
            sa = A.s[i] + t * (A.s[i + 1] - A.s[i]); sb = B.s[j] + u * (B.s[j + 1] - B.s[j])
            if np.interp(sa, A.s, A.deck) < 1 and np.interp(sb, B.s, B.deck) < 1:
                add_junction(A.at(sa), [(a, sa), (b, sb)])
# T ends: a road that stops on (or just short of) another road joins it
allP = np.concatenate([r.P for r in roads]); owner = np.concatenate([np.full(len(r.P), k) for k, r in enumerate(roads)])
sidx = np.concatenate([np.arange(len(r.P)) for r in roads]); tree = cKDTree(allP)
for a, A in enumerate(roads):
    for end in (0, -1):
        if A.blocked[0 if end == 0 else 1] or A.deck[end] > 1: continue
        p = A.P[end]
        for q in tree.query_ball_point(p, 22):
            b = owner[q]
            if b == a: continue
            B = roads[b]
            if np.linalg.norm(allP[q] - p) <= B.w / 2 + 6 and B.deck[sidx[q]] < 1:
                # extend the ending road onto the other road's centre line so the surfaces overlap
                if np.linalg.norm(allP[q] - p) > 0.5:
                    if end == 0:
                        A.P = np.vstack([allP[q], A.P]); dl = np.linalg.norm(A.P[1] - A.P[0])
                        A.s = np.concatenate([[0], A.s + dl]); A.deck = np.concatenate([[0], A.deck]); A.base = np.concatenate([[A.base[0]], A.base]); A.h = np.concatenate([[A.h[0]], A.h])
                        for J in junctions: J["members"] = [(m[0], m[1] + dl) if m[0] == a else m for m in J["members"]]
                    else:
                        dl = np.linalg.norm(allP[q] - A.P[-1]); A.P = np.vstack([A.P, allP[q]])
                        A.s = np.concatenate([A.s, [A.s[-1] + dl]]); A.deck = np.concatenate([A.deck, [0]]); A.base = np.concatenate([A.base, [A.base[-1]]]); A.h = np.concatenate([A.h, [A.h[-1]]])
                add_junction(allP[q], [(a, A.s[0] if end == 0 else A.s[-1]), (b, B.s[sidx[q]])])
                break

# junction heights by relaxation: each road's height line is smoothed (no bumps, gentle slopes) while
# every junction zone is held level at one height shared by all its roads
for J in junctions: J["r"] = float(max(roads[k].w for k, s in J["members"]) / 2 + 4)
masks = []
for J in junctions: masks.append([(k, np.abs(roads[k].s - sj) < J["r"]) for k, sj in J["members"]])
for R in roads: R.target = R.h.copy()
for it in range(140):
    for R in roads:
        h = R.h; sm = h.copy()
        sm[1:-1] = 0.25 * h[:-2] + 0.5 * h[1:-1] + 0.25 * h[2:]
        R.h = sm + 0.02 * (R.target - sm)              # a weak pull back to the ground line and the bridge height
    for J, mk in zip(junctions, masks):
        vals = np.concatenate([roads[k].h[m] for k, m in mk if m.any()])
        if len(vals) == 0: continue
        J["h"] = float(vals.mean())
        for k, m in mk: roads[k].h[m] = J["h"]
for J in junctions:
    J.setdefault("h", float(np.interp(J["members"][0][1], roads[J["members"][0][0]].s, roads[J["members"][0][0]].h)))
    for k, sj in J["members"]: roads[k].junc.append((sj, J["r"]))
for R in roads: R.deck = np.maximum(R.h - R.base, 0.0) * (R.deck > 0.05)   # the real height above the ground after smoothing
worst = {}
for R in roads:
    ds = np.maximum(np.diff(R.s), 1e-6); gr = np.abs(np.diff(R.h)) / ds * 100
    worst[R.cls] = max(worst.get(R.cls, 0), float(gr.max()))
    if gr.max() > 6.5:
        k = int(gr.argmax()); print("  steep %.1f%% on %s (%s) at x %.0f z %.0f, deck %.1f" % (gr.max(), R.name, R.cls, R.P[k][0], R.P[k][1], R.deck[k]))
print("steepest slope per class (%):", {k: round(v, 1) for k, v in worst.items()})

# ---- 5. meshes
class Mesh:
    def __init__(self): self.v = []; self.f = []; self.uv = []
    def quad(self, a, b, c, d):
        """Corners counter-clockwise seen from the visible side (glTF: counter-clockwise front)."""
        i = len(self.v); self.v += [a, b, c, d]; self.f += [[i, i + 1, i + 2], [i, i + 2, i + 3]]
    def box(self, c, sx, sy, sz, yaw=0.0):
        cs, sn = math.cos(yaw), math.sin(yaw)
        def P(x, y, z): return [c[0] + x * cs - z * sn, c[1] + y, c[2] + x * sn + z * cs]
        x, y, z = sx / 2, sy, sz / 2
        p = [P(-x, 0, -z), P(x, 0, -z), P(x, 0, z), P(-x, 0, z), P(-x, y, -z), P(x, y, -z), P(x, y, z), P(-x, y, z)]
        for q in ((4, 7, 6, 5), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)): self.quad(*[p[k] for k in q])
    def mesh(self, color):
        v = np.array(self.v, float); f = np.array(self.f, int)
        m = trimesh.Trimesh(v, f, process=False)
        m.visual = trimesh.visual.TextureVisuals(uv=np.stack([v[:, 0] / 10.0, v[:, 2] / 10.0], 1),
                                                 material=trimesh.visual.material.PBRMaterial(baseColorFactor=color, roughnessFactor=0.9, metallicFactor=0.0))
        return m

M = {k: Mesh() for k in ("asphalt", "sidewalk", "marking_white", "marking_yellow", "concrete", "terrain", "water", "barrier_red", "barrier_white")}
def V(p, y): return [float(p[0]), float(y), float(p[1])]

def in_junction(R, s, pad=0.0):
    return any(abs(s - sj) < rj + pad for sj, rj in R.junc)

def strip(mesh, R, off_l, off_r, dy_l, dy_r, skip=None):
    """A ribbon along the road between two lateral offsets (left positive), top side up."""
    t, n = R.frame()
    for i in range(len(R.P) - 1):
        if skip and skip(i): continue
        a = R.P[i] + n[i] * off_l; b = R.P[i] + n[i] * off_r; c = R.P[i + 1] + n[i + 1] * off_r; d = R.P[i + 1] + n[i + 1] * off_l
        mesh.quad(V(a, R.h[i] + dy_l), V(d, R.h[i + 1] + dy_l), V(c, R.h[i + 1] + dy_r), V(b, R.h[i] + dy_r))

def wall(mesh, R, off, top, bottom, face):
    """A vertical face along the road at a lateral offset; face = +1 looks left, -1 looks right.
    top/bottom: functions of the sample index giving heights."""
    t, n = R.frame()
    for i in range(len(R.P) - 1):
        y0t, y1t, y0b, y1b = top(i), top(i + 1), bottom(i), bottom(i + 1)
        if y0t - y0b < 0.02 and y1t - y1b < 0.02: continue
        a = R.P[i] + n[i] * off; b = R.P[i + 1] + n[i + 1] * off
        q = [V(a, y0b), V(b, y1b), V(b, y1t), V(a, y0t)]
        mesh.quad(*(q if face < 0 else q[::-1]))

def dashes(mesh, R, off, width, on, gap, y=0.03):
    s = 2.0
    while s + on < R.s[-1] - 2:
        if not in_junction(R, s, 2) and not in_junction(R, s + on, 2):
            p0, p1 = R.at(s), R.at(s + on)
            d = p1 - p0; L = np.linalg.norm(d)
            if L > 1e-6:
                nn = np.array([-d[1], d[0]]) / L
                h0, h1 = np.interp(s, R.s, R.h) + y, np.interp(s + on, R.s, R.h) + y
                a, b, c, e = p0 + nn * (off + width / 2), p0 + nn * (off - width / 2), p1 + nn * (off - width / 2), p1 + nn * (off + width / 2)
                mesh.quad(V(a, h0), V(e, h1), V(c, h1), V(b, h0))
        s += on + gap

stats = {"bridge_m": 0.0}
for R in roads:
    hw = R.w / 2
    strip(M["asphalt"], R, hw, -hw, 0, 0)
    elevated = R.deck > 1.0
    high = R.deck >= 4.5
    edge = hw + (WALK if R.cls in ("main", "street") else 0.0)
    if R.cls in ("main", "street"):
        for side in (1, -1):
            sk = lambda i, R=R: elevated[i] or elevated[i + 1] or in_junction(R, R.s[i], 3.5) or in_junction(R, R.s[i + 1], 3.5)
            o1, o2 = (edge, hw) if side > 0 else (-hw, -edge)
            strip(M["sidewalk"], R, o1, o2, KERB, KERB, sk)
            t, n = R.frame()
            for i in range(len(R.P) - 1):            # kerb face
                if sk(i): continue
                a = R.P[i] + n[i] * hw * side; b = R.P[i + 1] + n[i + 1] * hw * side
                q = [V(a, R.h[i]), V(b, R.h[i + 1]), V(b, R.h[i + 1] + KERB), V(a, R.h[i] + KERB)]
                M["sidewalk"].quad(*(q if side > 0 else q[::-1]))
    # sides: on the ground and on ramps a solid skirt down into the ground; high up a slab with pillars
    for side in (1, -1):
        o = edge * side
        top = lambda i, R=R: R.h[i] + (KERB if R.cls in ("main", "street") and not elevated[i] else 0.0)
        bot = lambda i, R=R: (R.h[i] - 1.1) if high[i] else (R.base[i] - 2.5)
        wall(M["concrete"], R, o, top, bot, side)
        if elevated.any():                            # parapet where the road is off the ground
            par = lambda i, R=R: R.h[i] + (0.95 if elevated[i] else 0.0)
            wall(M["concrete"], R, o, par, lambda i, R=R: R.h[i], side)
            wall(M["concrete"], R, o - 0.35 * side, par, lambda i, R=R: R.h[i], -side)
            t, n = R.frame()
            for i in range(len(R.P) - 1):
                if not (elevated[i] and elevated[i + 1]): continue
                a = R.P[i] + n[i] * o; b = R.P[i] + n[i] * (o - 0.35 * side); c = R.P[i + 1] + n[i + 1] * (o - 0.35 * side); d = R.P[i + 1] + n[i + 1] * o
                q = [V(a, R.h[i] + 0.95), V(d, R.h[i + 1] + 0.95), V(c, R.h[i + 1] + 0.95), V(b, R.h[i] + 0.95)]
                M["concrete"].quad(*(q if side > 0 else q[::-1]))
    if high.any():
        t, n = R.frame()
        for i in range(len(R.P) - 1):                 # underside of the slab
            if not (high[i] and high[i + 1]): continue
            a = R.P[i] + n[i] * edge; b = R.P[i] - n[i] * edge; c = R.P[i + 1] - n[i + 1] * edge; d = R.P[i + 1] + n[i + 1] * edge
            M["concrete"].quad(V(a, R.h[i] - 1.1), V(b, R.h[i] - 1.1), V(c, R.h[i + 1] - 1.1), V(d, R.h[i + 1] - 1.1))
        stats["bridge_m"] += float(high.sum() * STEP)
        last = -99.0
        for i in np.where(high)[0]:                   # pillars, not where another road passes below
            if R.s[i] - last < 28: continue
            p = R.P[i]
            near = [q for q in tree.query_ball_point(p, 20) if roads[owner[q]] is not R and roads[owner[q]].deck[min(sidx[q], len(roads[owner[q]].deck) - 1)] < 2]
            if near: continue
            g = min(ground(p[0], p[1]), 0.0) - 4.0 if ground(p[0], p[1]) < 0.5 else ground(p[0], p[1]) - 1.0
            yaw = math.atan2(t[i][1], t[i][0])
            M["concrete"].box([p[0], g, p[1]], 2.0, R.h[i] - 1.1 - g, R.w * 0.55, yaw)
            last = R.s[i]
    # road paint
    if R.cls == "highway":
        strip(M["marking_yellow"], R, 0.45, 0.15, 0.03, 0.03, lambda i, R=R: in_junction(R, R.s[i], 2))
        strip(M["marking_yellow"], R, -0.15, -0.45, 0.03, 0.03, lambda i, R=R: in_junction(R, R.s[i], 2))
        for o in (4.2, 8.2, -4.2, -8.2): dashes(M["marking_white"], R, o, 0.18, 4, 8)
    elif R.cls == "main":
        strip(M["marking_yellow"], R, 0.35, 0.12, 0.03, 0.03, lambda i, R=R: in_junction(R, R.s[i], 2))
        strip(M["marking_yellow"], R, -0.12, -0.35, 0.03, 0.03, lambda i, R=R: in_junction(R, R.s[i], 2))
        for o in (4.2, -4.2): dashes(M["marking_white"], R, o, 0.16, 3, 6)
    elif R.cls == "street":
        dashes(M["marking_white"], R, 0, 0.15, 3, 6)
    if R.cls != "street":
        for o in (hw - 0.45, -(hw - 0.45)):
            strip(M["marking_white"], R, o + 0.09, o - 0.09, 0.03, 0.03, lambda i, R=R: in_junction(R, R.s[i], 2))

# road blocks where part 2 begins: striped barriers across the road
blocks = []
for R in roads:
    for end, is_blocked in ((0, R.blocked[0]), (-1, R.blocked[1])):
        if not is_blocked: continue
        t, n = R.frame(); k = 2 if end == 0 else -3
        p, yaw = R.P[k], math.atan2(n[k][1], n[k][0])
        cnt = int(R.w / 2.0)
        for q in range(cnt):
            off = (q + 0.5 - cnt / 2) * 2.0
            c = p + n[k] * off
            M["barrier_red" if q % 2 == 0 else "barrier_white"].box([c[0], R.h[k], c[1]], 1.9, 1.1, 0.6, yaw)
        blocks.append({"x": round(float(p[0]), 1), "z": round(float(p[1]), 1), "y": round(float(R.h[k]), 2), "yaw": round(math.degrees(yaw), 1), "width": R.w, "road": R.name})

# terrain: the ground is shaped to the roads (just under them, so no step shows beside the road), natural beyond, sea bed in the north
allP = np.concatenate([r.P for r in roads]); allH = np.concatenate([r.h for r in roads]); allD = np.concatenate([r.deck for r in roads])
allE = np.concatenate([np.full(len(r.P), r.w / 2 + (WALK if r.cls in ("main", "street") else 0)) for r in roads])
tree = cKDTree(allP)
G = 8.0
x0, x1, z0, z1 = -80.0, PX * S + 60.0, -80.0, plan["size"][1] * S + 80.0
nx, nz = int((x1 - x0) / G) + 1, int((z1 - z0) / G) + 1
TH = np.zeros((nz, nx))
for iz in range(nz):
    for ix in range(nx):
        X, Z = x0 + ix * G, z0 + iz * G
        g = ground(X, Z)
        idx = tree.query_ball_point([X, Z], 44.0)
        if idx:
            idx = np.array(idx); d = np.linalg.norm(allP[idx] - [X, Z], axis=1) - allE[idx]
            lowroad = allD[idx] < 0.5
            cap = np.where(lowroad, allH[idx] - 0.15, allH[idx] - 1.6)        # never above a road or a ramp
            near = d < 7.0
            if near.any(): g = min(g, cap[near].min()) if not (near & lowroad).any() else cap[near & lowroad].min()
            else:
                k = int(np.argmin(d)); w = min(1.0, (d[k] - 7.0) / 26.0); w = w * w * (3 - 2 * w)
                target = cap[k] if lowroad[k] else min(g, cap[k])
                g = target * (1 - w) + g * w
        TH[iz, ix] = g
tm = M["terrain"]
for iz in range(nz - 1):
    for ix in range(nx - 1):
        if max(TH[iz, ix], TH[iz + 1, ix], TH[iz, ix + 1], TH[iz + 1, ix + 1]) < -4.9: continue
        X, Z = x0 + ix * G, z0 + iz * G
        tm.quad([X, TH[iz, ix], Z], [X, TH[iz + 1, ix], Z + G], [X + G, TH[iz + 1, ix + 1], Z + G], [X + G, TH[iz, ix + 1], Z])
M["water"].quad([x0 - 400, 0, z0], [x0 - 400, 0, z1 + 500], [x1 + 400, 0, z1 + 500], [x1 + 400, 0, z0])

COL = {"asphalt": [38, 40, 44, 255], "sidewalk": [150, 148, 142, 255], "marking_white": [235, 235, 230, 255], "marking_yellow": [240, 185, 40, 255],
       "concrete": [120, 122, 126, 255], "terrain": [176, 152, 112, 255], "water": [20, 60, 95, 255], "barrier_red": [215, 40, 30, 255], "barrier_white": [240, 240, 240, 255]}
scene = trimesh.Scene()
for k, m in M.items():
    if m.v: scene.add_geometry(m.mesh(COL[k]), geom_name=k, node_name=k)
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(CITY, "city_part1.glb")
scene.export(out)

g = plan["garage"]
info = {
    "bounds": [x0, z0, x1, z1], "scale": S, "grid": {"x0": x0, "z0": z0, "step": G, "nx": nx, "nz": nz},
    "roads": [{"name": r.name, "cls": r.cls, "width": r.w,
               "pts": [[round(float(p[0]), 1), round(float(h), 2), round(float(p[1]), 1)] for p, h in zip(r.P[::2], r.h[::2])],
               "deck": [round(float(d), 1) for d in r.deck[::2]]} for r in roads],
    "junctions": [{"x": round(float(J["pos"][0]), 1), "z": round(float(J["pos"][1]), 1), "y": round(J["h"], 2), "r": float(J["r"]), "roads": sorted({int(k) for k, s in J["members"]})} for J in junctions],
    "blocks": blocks,
    "garage": {"x": g["x"] * S, "z": g["y"] * S, "y": round(ground(g["x"] * S, g["y"] * S), 2)},
    "districts": [{"name": d["name"], "x": d["x"] * S, "z": d["y"] * S} for d in plan["districts"] if d["x"] <= PX],
}
json.dump(info, open(out[:-4] + ".json", "w"), separators=(",", ":"))
km = sum(r.s[-1] for r in roads) / 1000
tris = sum(len(m.f) for m in M.values())
print("%d roads (%d ramps), %.1f km, %d junctions, %d road blocks, %.0f m of bridge deck, %d triangles -> %s" % (len(roads), len(ramps), km, len(junctions), len(blocks), stats["bridge_m"], tris, out))
