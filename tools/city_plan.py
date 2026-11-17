#!/usr/bin/env python3
"""The plan of the new city: a Dubai-shaped road network instead of the square grid.
World: 3200 m (west-east, x) by 2300 m (south-north, y); the sea is in the north.
Writes unity_assets/city/plan.json (roads as polylines in metres, with class and width,
water shapes, districts) and a dark game-style preview picture of the map.
Road classes: highway (yellow, 6 lanes), main (wide grey, 4 lanes), street (2 lanes)."""
import json, math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
W, H = 3200, 2300
random.seed(7)

def spline(pts, step=12.0):
    """Catmull-Rom through the points, resampled about every `step` metres."""
    p = np.array(pts, float)
    p = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        n = max(2, int(np.linalg.norm(p2 - p1) / step))
        for t in np.linspace(0, 1, n, endpoint=False):
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(p[-2])
    return [[round(float(x), 1), round(float(y), 1)] for x, y in out]

def ring(cx, cy, rx, ry, rot=0, n=48, a0=0, a1=360):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    pts = []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        x, y = rx * math.cos(a), ry * math.sin(a)
        pts.append([round(cx + x * c - y * s, 1), round(cy + x * s + y * c, 1)])
    return pts

roads = []
def road(name, cls, pts, smooth=True):
    roads.append({"name": name, "cls": cls, "width": {"highway": 30, "main": 22, "street": 13}[cls], "pts": spline(pts) if smooth else pts})

# The layout is traced from the Higgsfield map picture (docs/HAMAD_NOTES.md): plan x = picture u * 3200, y = (1 - v) * 2300.
# coast: the sea is north of this line
COAST = spline([(0, 1385), (130, 1450), (300, 1505), (480, 1525), (600, 1530), (760, 1540), (950, 1590), (1150, 1640), (1400, 1700), (1600, 1760), (1800, 1795),
                (2000, 1810), (2150, 1850), (2380, 1860), (2520, 1840), (2650, 1800), (2800, 1765), (3000, 1790), (3200, 1880)], 20)
def coast_y(x): return float(np.interp(x, [p[0] for p in COAST], [p[1] for p in COAST]))
PORT = [(0, 800), (150, 790), (200, 700), (205, 560), (150, 440), (60, 360), (0, 340)]      # Jebel Ali port: sea on the west side
def in_poly(x, y, poly):
    ins = False
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1): ins = not ins
    return ins

# highways (yellow on the map)
road("E11", "highway", [(0, 880), (200, 1000), (450, 1090), (750, 1120), (1000, 1110), (1250, 1060), (1500, 1010), (1800, 960), (2050, 975), (2200, 1050), (2350, 1110), (2600, 1145), (2900, 1130), (3200, 1060)])
road("E44", "highway", [(225, 520), (400, 500), (600, 480), (800, 520), (1000, 580), (1300, 600), (1600, 590), (1900, 570), (2200, 590), (2500, 570), (2700, 550), (2900, 570), (3200, 640)])
road("E311", "highway", [(2760, 1880), (2700, 1650), (2635, 1400), (2620, 1200), (2680, 1000), (2705, 800), (2690, 560), (2630, 280), (2580, 0)])
road("Jebel Ali Hwy", "highway", [(400, 0), (430, 70), (500, 220), (560, 380), (600, 480)])     # from the south-west up to the E44
# main roads
road("Marina Ring", "main", ring(290, 1290, 210, 115, 0, 40), smooth=False)
road("Beach Road", "main", [(451, 1364), (520, 1430), (600, 1470), (800, 1480), (1000, 1530), (1250, 1590), (1500, 1650), (1750, 1715), (2000, 1745), (2250, 1790), (2430, 1790), (2600, 1745), (2800, 1700), (3000, 1725), (3200, 1815)])
road("Palm Road", "main", [(600, 1470), (640, 1400), (700, 1290), (735, 1232)])          # from the Palm trunk inland, on into Al Wasl
road("Al Wasl", "main", [(735, 1232), (1000, 1340), (1220, 1400), (1400, 1385), (1470, 1352)])
road("JBR Road", "main", [(505, 957), (520, 1010), (560, 1085), (640, 1150), (735, 1232)])          # Al Khail up under the E11 to the Palm Road
road("Jebel Ali Road", "main", [(118, 1224), (150, 1100), (175, 1010), (300, 860), (440, 680), (545, 500), (520, 300), (545, 185)])
road("Al Khail", "main", [(262, 905), (505, 957), (790, 992), (1050, 960), (1250, 900), (1500, 780), (1750, 715), (1988, 790)])
road("Al Quoz Road", "main", [(985, 1526), (990, 1400), (985, 1200), (930, 1065), (900, 900), (830, 720), (790, 520), (760, 400), (770, 205)])
road("Port Road", "main", [(215, 790), (228, 560), (175, 420), (150, 250), (330, 150), (545, 185), (770, 205), (1022, 330)])
road("Downtown Ring", "main", ring(1870, 1350, 400, 275, 0, 64), smooth=False)       # the big outer ring of the picture
road("Downtown Inner Ring", "main", ring(1870, 1350, 285, 190, 0, 48), smooth=False)
road("Downtown Blvd", "main", [(1700, 1700), (1690, 1560), (1700, 1350), (1710, 1150), (1700, 960), (1650, 800), (1640, 610), (1690, 428)])   # Beach Road, through Downtown, under the E11, to Dubai Hills
road("Hills Ring", "main", ring(1380, 330, 360, 210, 0, 56), smooth=False)
road("Ras Al Khor Road", "main", [(1990, 1088), (2020, 970), (1985, 860), (2020, 720), (2140, 650), (2300, 660), (2420, 740), (2540, 810), (2700, 860)])   # around the lagoon
road("Nad Al Sheba Road", "main", [(2140, 650), (2100, 560), (2010, 380), (1960, 250)])
road("South Road", "main", [(1740, 330), (1960, 250), (2200, 200), (2450, 230), (2640, 340)])
road("Deira Bridge", "main", [(2198, 1508), (2300, 1575), (2440, 1597), (2560, 1600), (2700, 1640)])
road("Creek Bridge", "main", [(2268, 1374), (2340, 1385), (2460, 1390), (2560, 1370), (2640, 1330)])
road("Airport Road", "main", [(3100, 1780), (3020, 1300), (2950, 900), (2900, 600), (2880, 300), (2900, 0)])
# the Palm: trunk from the Beach Road out to sea, fronds, and the crescent (as big as in the picture)
PX, PY = 600, 1530
road("Palm Trunk", "main", [(PX, PY - 60), (PX + 4, PY + 120), (PX, PY + 300), (PX, PY + 622)])
# the inside of the Palm follows the Higgsfield map picture: fronds fan out from the upper trunk like a palm tree,
# the low ones droop down and out, the middle ones go straight out, the top ones sweep up. (dx, y) in picture pixels.
_K = 1.0
for o_, m_, t_ in (((0, 345), (-120, 385), (-195, 465)), ((0, 325), (-150, 350), (-260, 425)), ((0, 300), (-180, 305), (-310, 360)),
                   ((0, 255), (-190, 250), (-335, 270)), ((0, 205), (-180, 180), (-305, 178)), ((0, 160), (-120, 110), (-200, 92)),
                   ((0, 110), (-50, 75), (-82, 58))):
    for sg in (1, -1):
        road("Frond", "street", [(PX - sg * q[0] * _K, PY + 460 + (270 - q[1]) * _K) for q in (o_, m_, t_)])
road("Crescent", "street", ring(PX, PY + 440, 470, 290, 0, 56, -38, 218), smooth=False)

# districts: local street grids, turned and clipped to an ellipse
districts = [
    ("Jebel Ali", 340, 330, 170, 220, 0, 80), ("Dubai Marina", 290, 1290, 205, 110, 0, 62), ("JBR", 640, 1300, 220, 50, 0, 60),
    ("Al Quoz", 1330, 850, 230, 150, 5, 100), ("Jumeirah", 1250, 1545, 420, 85, 7, 75), ("Downtown Dubai", 1870, 1350, 392, 268, 0, 70),
    ("Business Bay", 1840, 1118, 210, 130, 0, 80), ("Dubai Hills", 1380, 330, 350, 200, 0, 85), ("Deira", 2200, 1690, 190, 170, 25, 65),
    ("Ras Al Khor", 2390, 925, 180, 160, 10, 105), ("Nad Al Sheba", 2260, 400, 220, 120, -10, 100), ("Al Wasl", 1220, 1290, 330, 70, 5, 85),
    ("Al Barsha", 690, 850, 190, 130, 12, 85), ("DXB Airport", 2930, 1450, 110, 210, 12, 140),
]
def clipped_grid(cx, cy, rx, ry, rot, pitch):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    def w(x, y): return [round(cx + x * c - y * s, 1), round(cy + x * s + y * c, 1)]
    n = int(max(rx, ry) / pitch) + 1
    for k in range(-n, n + 1):
        u = k * pitch
        if abs(u) < rx * 0.97:                      # line along local y at local x = u
            hh = ry * math.sqrt(1 - (u / rx) ** 2)
            if hh > pitch * 0.6: yield [w(u, -hh), w(u, hh)]
        if abs(u) < ry * 0.97:
            hw = rx * math.sqrt(1 - (u / ry) ** 2)
            if hw > pitch * 0.6: yield [w(-hw, u), w(hw, u)]
MARINA = (290, 1290, 150, 72, 0)                   # the water basin inside the Marina ring
def in_marina(x, y, k=1.0):
    cx, cy, rx, ry, rot = MARINA; c, s_ = math.cos(math.radians(-rot)), math.sin(math.radians(-rot))
    u, v = (x - cx) * c - (y - cy) * s_, (x - cx) * s_ + (y - cy) * c
    return (u / (rx * k)) ** 2 + (v / (ry * k)) ** 2 < 1
water = {
    "creek": spline([(2545, 1900), (2535, 1800), (2490, 1680), (2440, 1540), (2360, 1340), (2300, 1160), (2240, 1010), (2160, 890), (2110, 810)], 20),   # from the sea down to the lagoon
    "canal": spline([(1560, 1205), (1660, 1240), (1780, 1215), (1900, 1170), (2020, 1175), (2130, 1225), (2215, 1250)], 20),                           # Business Bay canal inside the Downtown ring
    "lake": ring(2225, 775, 135, 72, 8, 32),                                                                                                           # Ras Al Khor lagoon
    "marina": ring(MARINA[0], MARINA[1], MARINA[2], MARINA[3], MARINA[4], 40),
    "port": PORT,
}
CREEK_W, CANAL_W = 66.0, 34.0
def _pl_dist(P, x, y):
    return min(math.hypot(x - (x1 + max(0.0, min(1.0, ((x - x1) * (x2 - x1) + (y - y1) * (y2 - y1)) / ((x2 - x1) ** 2 + (y2 - y1) ** 2 or 1e-9))) * (x2 - x1)),
                          y - (y1 + max(0.0, min(1.0, ((x - x1) * (x2 - x1) + (y - y1) * (y2 - y1)) / ((x2 - x1) ** 2 + (y2 - y1) ** 2 or 1e-9))) * (y2 - y1))) for (x1, y1), (x2, y2) in zip(P, P[1:]))
KEEPOUT = [(1820, 1480, 75), (470, 1290, 34), (680, 820, 135), (2430, 808, 55)]   # no streets under the landmarks: needle tower, twisted tower, ski mall, LSX garage in Ras Al Khor (same spots as tools/build_city.py)
def _seg_clear(a, b):
    for kx, ky, kr in KEEPOUT:
        dx, dy = b[0] - a[0], b[1] - a[1]; t = max(0.0, min(1.0, ((kx - a[0]) * dx + (ky - a[1]) * dy) / (dx * dx + dy * dy or 1e-9)))
        if math.hypot(kx - a[0] - t * dx, ky - a[1] - t * dy) < kr: return False
    return True
RINGED = {"Dubai Marina": (290, 1290, 210, 115, 0), "Downtown Dubai": (1870, 1350, 400, 275, 0), "Dubai Hills": (1380, 330, 360, 210, 0)}
for name, cx, cy, rx, ry, rot, pitch in districts:
    if name not in RINGED: continue                 # the other areas are covered by the city-wide street net below
    for seg in clipped_grid(cx, cy, rx, ry, rot, pitch):
        if not all(p[1] < coast_y(p[0]) - 25 and 0 <= p[0] <= W and 0 <= p[1] <= H for p in seg): continue
        if not _seg_clear(seg[0], seg[1]): continue
        # streets stop at the water: the Marina basin, the Business Bay canal
        wet = (lambda q: in_marina(q[0], q[1], 1.22)) if name == "Dubai Marina" else (lambda q: _pl_dist(water["canal"], q[0], q[1]) < CANAL_W / 2 + 22) if name == "Downtown Dubai" else None
        if wet is None:
            roads.append({"name": name, "cls": "street", "width": 13, "pts": seg}); continue
        n_ = max(2, int(math.dist(seg[0], seg[1]) / 10)); run = []
        for i_ in range(n_ + 1):
            q = [seg[0][0] + (seg[1][0] - seg[0][0]) * i_ / n_, seg[0][1] + (seg[1][1] - seg[0][1]) * i_ / n_]
            if wet(q):
                if len(run) >= 6: roads.append({"name": name, "cls": "street", "width": 13, "pts": [run[0], run[-1]]})
                run = []
            else: run.append([round(q[0], 1), round(q[1], 1)])
        if len(run) >= 6: roads.append({"name": name, "cls": "street", "width": 13, "pts": [run[0], run[-1]]})

# ---- the city-wide street net: streets everywhere on land, like a real city map. Long streets run with the
# coast and the highways, cross streets run inland. They stop at highways (cross those on the main roads),
# keep out of the ringed districts (those have their own streets) and out of the water.
def _poly_dist(P, q):
    """Distance from point q to polyline P (n x 2 array), and the direction of the nearest segment."""
    a, b = P[:-1], P[1:]; ab = b - a
    t = np.clip(((q - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-9), 0, 1)
    d = np.linalg.norm(a + ab * t[:, None] - q, axis=1); k = int(d.argmin())
    return float(d[k]), ab[k] / max(np.linalg.norm(ab[k]), 1e-9)
_hw = [np.array(r["pts"], float) for r in roads if r["cls"] == "highway"]
_mn = [np.array(r["pts"], float) for r in roads if r["cls"] == "main"]
_creek = np.array(water["creek"], float); _lake = np.array(water["lake"], float)
def _f_in(x): return 520 + 0.02 * x                      # the inland base line (about the E44)
def _street_ok(q, dirn):
    x, y = q
    if not (8 <= x <= W - 8 and 8 <= y <= H - 8) or y > coast_y(x) - 45: return False
    if any(math.hypot(x - kx, y - ky) < kr for kx, ky, kr in KEEPOUT): return False
    for cx, cy, rx, ry, rot in RINGED.values():
        c, s_ = math.cos(math.radians(-rot)), math.sin(math.radians(-rot))
        u, v = (x - cx) * c - (y - cy) * s_, (x - cx) * s_ + (y - cy) * c
        if (u / rx) ** 2 + (v / ry) ** 2 < 1.0: return False
    if any(_poly_dist(Pm, np.array(q))[0] < 52 for Pm in _hw): return False
    if _poly_dist(_creek, np.array(q))[0] < 62: return False
    if math.hypot((x - 2225) / 172, (y - 775) / 108) < 1: return False          # the lagoon
    if in_poly(x, y, [(0, 830), (180, 820), (232, 700), (236, 550), (180, 420), (80, 330), (0, 310)]): return False   # the port
    if x > 2740 and 1230 < y < 1720: return False                             # the airport
    for Pm in _mn:                                         # no street right beside a main road going the same way
        dd, tdir = _poly_dist(Pm, np.array(q))
        if dd < 62 and abs(float(np.dot(tdir, dirn))) > 0.8: return False
    return True
def _add_street_line(pts):
    P_ = np.array(pts, float); run = []
    for i in range(len(P_)):
        dirn = P_[min(i + 1, len(P_) - 1)] - P_[max(i - 1, 0)]; dirn = dirn / max(np.linalg.norm(dirn), 1e-9)
        if _street_ok(P_[i], dirn): run.append([round(float(P_[i][0]), 1), round(float(P_[i][1]), 1)])
        else:
            if len(run) >= 7: roads.append({"name": "Street", "cls": "street", "width": 13, "pts": run})
            run = []
    if len(run) >= 7: roads.append({"name": "Street", "cls": "street", "width": 13, "pts": run})
PITCH = 64.0
xs = np.arange(0, W + 1, 16.0)
N_U = 24
for k in range(1, N_U):                                    # long streets between the E44 line and the coast
    if random.random() < 0.08: continue
    u = k / N_U
    ph = random.uniform(0, 6.28)                           # long gentle bends, like streets on a real map
    _add_street_line([(x, _f_in(x) + u * (coast_y(x) - 50 - _f_in(x)) + 9 * math.sin(x / 210.0 + ph)) for x in xs])
for k in range(1, 5):                                      # and south of the E44
    _add_street_line([(x, _f_in(x) - k * PITCH) for x in xs])
ys = np.arange(0, H + 1, 16.0)
for k in range(1, int(W / PITCH)):                         # cross streets, leaning a little, broken in places
    x0_ = k * PITCH + random.uniform(-12, 12); lean = random.uniform(-0.05, 0.05)
    ph = random.uniform(0, 6.28)
    line = [(x0_ + lean * (y - 1000) + 8 * math.sin(y / 190.0 + ph), y) for y in ys]
    cut = random.random()
    if cut < 0.3:                                          # some cross streets do not run the whole way
        a_ = random.randint(10, len(line) - 40); line = line[:a_] if random.random() < 0.5 else line[a_:]
    _add_street_line(line)

# ---- heights: the city is not flat
HILLS = ((1380, 330, 450, 8), (900, 40, 380, 4), (1950, 60, 420, 5), (2260, 380, 330, 4), (1870, 1350, 300, 2), (3000, 300, 420, 6))   # Dubai Hills, the southern mountains, Nad Al Sheba, Downtown rise
def terrain(x, y):
    """Ground height in metres: sea level at the coast, rising gently inland, real hills in Dubai Hills
    and Nad Al Sheba, a low rise under Downtown."""
    inland = max(0.0, coast_y(x) - y)
    h = 1.5 + 9.0 * min(1.0, inland / 1500.0) ** 1.3
    for cx, cy, r, amp in HILLS:
        h += amp * math.exp(-((x - cx) ** 2 + (y - cy) ** 2) / (2 * (r * 0.55) ** 2))
    return h

def crossings(A, B):
    """Distances along polyline A (metres) where it crosses polyline B."""
    out = []; dist = 0.0
    for (x1, y1), (x2, y2) in zip(A, A[1:]):
        seg = math.dist((x1, y1), (x2, y2))
        for (x3, y3), (x4, y4) in zip(B, B[1:]):
            den = (x2 - x1) * (y4 - y3) - (y2 - y1) * (x4 - x3)
            if abs(den) < 1e-9: continue
            t = ((x3 - x1) * (y4 - y3) - (y3 - y1) * (x4 - x3)) / den
            u = ((x3 - x1) * (y2 - y1) - (y3 - y1) * (x2 - x1)) / den
            if 0 <= t < 1 and 0 <= u < 1: out.append(dist + t * seg)
        dist += seg
    return out

SCALE = 1.5           # plan units to game metres: the game city is 4.8 km x 3.45 km (Hamad 2026-11-17: distances felt too small at 0.75)
K = 0.75 / SCALE      # ramp lengths below were tuned at 0.75; K keeps them the same in metres

def bump(dists, at, height, flat, ramp):
    """A bridge or underpass profile: full height for `flat` metres around `at`, smooth ramps of `ramp` metres."""
    out = []
    for dd in dists:
        k = abs(dd - at)
        f = 1.0 if k <= flat / 2 else max(0.0, 1 - (k - flat / 2) / ramp)
        out.append(height * (f * f * (3 - 2 * f)))
    return out

hw = [r for r in roads if r["cls"] == "highway"]
levels = []           # where a road leaves the ground, for the game and the map
for r in roads:
    pts = r["pts"]; dists = [0.0]
    for a_, b_ in zip(pts, pts[1:]): dists.append(dists[-1] + math.dist(a_, b_))
    extra = [0.0] * len(pts)
    def add(at, height, flat, ramp, kind):
        b = bump(dists, at, height, flat, ramp)
        for i in range(len(extra)):
            if abs(b[i]) > abs(extra[i]): extra[i] = b[i]
        levels.append({"road": r["name"], "kind": kind, "at": round(at, 1), "height": height})
    if r["cls"] == "highway":
        # flyovers: the highway goes over every main road, and over a highway listed after it
        for o in roads:
            if o is r or o["cls"] == "street": continue
            if o["name"] == "Downtown Blvd" and r is hw[0]: continue      # that road dips under the E11 instead (underpass)
            if o["cls"] == "highway" and hw.index(o) < hw.index(r): continue
            for at in crossings(pts, o["pts"]): add(at, 6.2, 60 * K, 240 * K, "flyover")
    if r["cls"] != "street" or r["name"] == "Palm Trunk":
        for at in crossings(pts, water["creek"]): add(at, 6.5 if r["cls"] == "highway" else 5.0, 90, (185 if r["cls"] == "highway" else 205) * K, "bridge")
        for at in crossings(pts, water["canal"]): add(at, 3.4, 46, 115 * K, "bridge")
    if r["name"] == "Palm Trunk": add(140, 4.0, 50, 100, "bridge")
    if r["name"] == "Downtown Blvd":
        for at in crossings(pts, hw[0]["pts"]): add(at, -5.6, 50 * K, 290 * K, "underpass")
    r["h"] = [round(terrain(x, y) + e, 2) for (x, y), e in zip(pts, extra)]
    r["deck"] = [round(e, 2) for e in extra]      # height above the ground (bridge deck) or below (underpass)

PHASE1_X = 2560       # built first: everything west of this line; roads are blocked there until phase 2
plan = {"size": [W, H], "scale": SCALE, "phase1_x": PHASE1_X, "coast": COAST, "roads": roads, "water": water, "levels": levels, "terrain": [[round(terrain(x, y), 1) for x in range(0, W + 1, 50)] for y in range(0, H + 1, 50)],
        "districts": [{"name": d[0], "x": d[1], "y": d[2]} for d in districts] + [{"name": "Palm Jumeirah", "x": PX, "y": PY + 425}],
        "garage": {"name": "LSXmotorsport", "x": 2430, "y": 790}, "landmark": {"name": "Sky Tower", "x": 1820, "y": 1480},
        "hills": HILLS, "widths": {"creek": CREEK_W, "canal": CANAL_W}}
os.makedirs(os.path.join(ROOT, "unity_assets", "city"), exist_ok=True)
json.dump(plan, open(os.path.join(ROOT, "unity_assets", "city", "plan.json"), "w"), separators=(",", ":"))

# ---- preview in the dark game-map style
S = 1.0                                             # pixels per metre (then halved)
def P(p): return (p[0] * S, (H - p[1]) * S)
SEA = (7, 22, 44)
im = Image.new("RGB", (int(W * S), int(H * S)), SEA)
land = [P(p) for p in COAST] + [(W * S, H * S), (0, H * S)]
def fat(dr, pts, col, wd):
    q = [P(p) for p in pts]; dr.line(q, fill=col, width=wd, joint="curve")
    r = wd / 2
    for x, y in (q[0], q[-1]): dr.ellipse([x - r, y - r, x + r, y + r], fill=col)
PALM = [r for r in roads if r["name"] in ("Palm Trunk", "Frond", "Crescent")]
def shore(dr, col, grow):
    dr.polygon(land, fill=col)
    if grow: dr.line(land[:len(COAST)], fill=col, width=grow)
    for r in PALM: fat(dr, r["pts"], col, (34 if r["name"] == "Frond" else 60) + grow)
glow = Image.new("RGB", im.size, SEA); shore(ImageDraw.Draw(glow), (70, 190, 255), 44)
im = glow.filter(ImageFilter.GaussianBlur(16))          # light-blue glow along every shore
d = ImageDraw.Draw(im)
shore(d, (196, 178, 140), 14)                           # a thin sand beach along every shore
shore(d, (30, 32, 37), 0)
for gx in range(0, W, 100): d.line([(gx, 0), (gx, H)], fill=(40, 41, 45), width=1)
for gy in range(0, H, 100): d.line([(0, gy), (W, gy)], fill=(40, 41, 45), width=1)
sea = Image.new("L", im.size, 0); shore(ImageDraw.Draw(sea), 255, 14)
im = Image.composite(im, glow.filter(ImageFilter.GaussianBlur(16)), sea); d = ImageDraw.Draw(im)
# mountains in the south and east (thin contour strokes), like the picture
random.seed(11)
for mx, my, mr in ((900, 40, 300), (1950, 60, 330), (3000, 300, 330), (3050, 760, 200), (1380, 330, 150)):
    for k_ in range(9):
        rr_ = mr * (1 - k_ / 9.5); pts_ = []
        for a_ in range(0, 361, 12):
            w_ = 1 + 0.16 * math.sin(a_ / 23.0 + k_) + 0.1 * math.sin(a_ / 9.0 + mx)
            pts_.append(P((mx + rr_ * w_ * math.cos(math.radians(a_)), my + 0.55 * rr_ * w_ * math.sin(math.radians(a_)))))
        d.line(pts_, fill=(52 + k_ * 3, 54 + k_ * 3, 60 + k_ * 3), width=2)
BLUE_E, BLUE_F = (70, 170, 235), (10, 42, 82)
d.polygon([P(p) for p in water["port"]], fill=SEA)                                    # the port basin, open to the west sea
d.line([P(p) for p in water["port"]], fill=BLUE_E, width=7)
for k_ in range(7):                                                                    # container piers
    py_ = 400 + k_ * 55; d.line([P((205 - (0 if k_ > 1 else 60), py_)), P((70, py_))], fill=(150, 165, 185), width=12); d.line([P((205, py_)), P((70, py_))], fill=(60, 64, 72), width=5)
fat(d, water["creek"], BLUE_E, int(CREEK_W) + 12); fat(d, water["creek"], BLUE_F, int(CREEK_W))
fat(d, water["canal"], BLUE_E, int(CANAL_W) + 10); fat(d, water["canal"], (12, 60, 104), int(CANAL_W))
d.polygon([P(p) for p in water["lake"]], fill=BLUE_F, outline=BLUE_E, width=6)
d.polygon([P(p) for p in water["marina"]], fill=(10, 44, 84), outline=(80, 180, 240), width=7)
for a_ in range(0, 360, 20):                            # the piers of the Marina, like spokes
    c_, s_ = math.cos(math.radians(a_)), math.sin(math.radians(a_))
    d.line([P((MARINA[0] + MARINA[2] * 0.97 * c_, MARINA[1] + MARINA[3] * 0.97 * s_)), P((MARINA[0] + MARINA[2] * 0.6 * c_, MARINA[1] + MARINA[3] * 0.6 * s_))], fill=(125, 155, 185), width=5)
# the airport: runways and a terminal
for (x1, y1), (x2, y2), wd_ in (((2790, 1620), (3150, 1680), 12), ((2790, 1500), (3150, 1560), 12), ((2800, 1300), (3140, 1340), 8)):
    d.line([P((x1, y1)), P((x2, y2))], fill=(96, 100, 108), width=wd_)
d.line([P((2850, 1380)), P((3080, 1420))], fill=(120, 124, 132), width=22)
try:                                                    # the slip roads of the interchanges (made by build_city.py)
    _built = json.load(open(os.path.join(ROOT, "unity_assets", "city", "city_part1.json")))
    _ramps = [[(p[0] / SCALE, p[2] / SCALE) for p in r_["pts"]] for r_ in _built["roads"] if r_["cls"] == "ramp"]
except Exception: _ramps = []
for rp in _ramps: fat(d, rp, (16, 14, 8), 16)
for rp in _ramps: fat(d, rp, (240, 180, 40), 9)
for cls, edge, col, wd in (("street", (14, 15, 18), (132, 135, 140), 7), ("main", (12, 12, 14), (205, 207, 212), 15), ("highway", (16, 14, 8), (246, 186, 40), 24)):
    for r in roads:
        if r["cls"] == cls: fat(d, r["pts"], edge, wd + 8)
    for r in roads:
        if r["cls"] == cls: fat(d, r["pts"], col, wd)
for r in roads:        # bridges and flyovers: white side rails; underpasses: darker
    run = []
    for pt, e in zip(r["pts"], r["deck"] + [0]):
        if abs(e) > 2.5: run.append((pt, e))
        elif run:
            if len(run) > 1:
                wd = {"highway": 22, "main": 17, "street": 9}[r["cls"]]
                up = run[0][1] > 0
                fat(d, [q[0] for q in run], (255, 255, 255) if up else (0, 0, 0), wd + (12 if up else 10))
                fat(d, [q[0] for q in run], ((255, 200, 70) if r["cls"] == "highway" else (215, 217, 220)) if up else (90, 92, 96), wd)
            run = []
im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS); d = ImageDraw.Draw(im)
MODE = os.environ.get("MAP", "")      # "" = plan preview; "full" = the game's map screen; "base" = the minimap (no text)
if MODE:                             # in the game: part 2 is only dimmed (not open yet)
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0)); ImageDraw.Draw(ov).rectangle([PHASE1_X * S / 2, 0, im.width, im.height], fill=(0, 0, 0, 110))
    im = Image.alpha_composite(im.convert("RGBA"), ov).convert("RGB"); d = ImageDraw.Draw(im)
elif not os.environ.get("PLAIN"):      # phase 2 (east): dimmed, with road blocks on the line
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
    px = PHASE1_X * S / 2
    od.rectangle([px, 0, im.width, im.height], fill=(0, 0, 0, 120))
    for yy in range(0, im.height, 28): od.line([(px, yy), (px, yy + 14)], fill=(255, 70, 50, 255), width=4)
    for r in roads:
        if r["cls"] == "street": continue
        for (x1, y1), (x2, y2) in zip(r["pts"], r["pts"][1:]):
            if (x1 - PHASE1_X) * (x2 - PHASE1_X) < 0:
                yy = (H - (y1 + (y2 - y1) * (PHASE1_X - x1) / (x2 - x1))) * S / 2
                od.rectangle([px - 7, yy - 16, px + 7, yy + 16], fill=(255, 70, 50, 255), outline=(255, 255, 255, 255), width=2)
    im = Image.alpha_composite(im.convert("RGBA"), ov).convert("RGB"); d = ImageDraw.Draw(im)
F = ImageFont.truetype(os.path.join(ROOT, "fonts", "russoone_RussoOne-Regular.ttf" if os.environ.get("MAP") else "rajdhani_Rajdhani-Bold.ttf"), 34 if os.environ.get("MAP") else 30)
def label(x, y, t, font=F, fill=(255, 255, 255)):
    global im, d
    if not MODE:
        d.text((x * S / 2, (H - y) * S / 2), t, font=font, fill=fill, anchor="mm", stroke_width=4, stroke_fill=(0, 0, 0)); return
    lines = t.split(" ") if len(t) > 9 and " " in t and font is F else [t]          # two-word names on two lines
    if len(lines) > 2: lines = [" ".join(lines[:-1]), lines[-1]]
    tw = max(int(d.textlength(l, font=font)) for l in lines) + 40; th_ = 40 * len(lines) + 24
    tile = Image.new("RGBA", (tw, th_), (0, 0, 0, 0)); td = ImageDraw.Draw(tile)
    for i_, l in enumerate(lines): td.text((tw / 2, 30 + 40 * i_), l, font=font, fill=fill + (255,), anchor="mm", stroke_width=5, stroke_fill=(0, 0, 0, 255))
    tile = tile.transform(tile.size, Image.AFFINE, (1, 0.22, -0.11 * th_, 0, 1, 0), Image.BICUBIC)   # slant
    im.paste(tile, (int(x * S / 2 - tw / 2), int((H - y) * S / 2 - th_ / 2)), tile); d = ImageDraw.Draw(im)
if MODE == "base":
    im.save(sys.argv[1], quality=92); sys.exit(0)
for dd in plan["districts"]: label(dd["x"], dd["y"] - ({"Downtown Dubai": 30}.get(dd["name"], 0) if MODE else 0), dd["name"].upper() if MODE else dd["name"])
FS = ImageFont.truetype(os.path.join(ROOT, "fonts", "rajdhani_Rajdhani-Bold.ttf"), 22)
for t, x, y in (("E11", 1130, 1090), ("E44", 1430, 598), ("E311", 2705, 880)):
    cx, cy = x / 2, (H - y) / 2
    d.rounded_rectangle([cx - 32, cy - 17, cx + 32, cy + 17], 6, fill=(24, 70, 170), outline=(255, 255, 255), width=3)
    d.text((cx, cy), t, font=FS, fill=(255, 255, 255), anchor="mm")
g = plan["garage"]; cx, cy = g["x"] / 2, (H - g["y"]) / 2
if not os.environ.get("PLAIN") and not MODE:
    d.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=(215, 30, 30), outline=(255, 255, 255), width=3)
    label(g["x"], g["y"] - 60, "LSX GARAGE", FS, (255, 120, 110))
cx, cy = 1820 / 2, (H - 1480) / 2
d.polygon([(cx, cy - 120), (cx + 5, cy - 60), (cx + 11, cy - 30), (cx + 17, cy), (cx - 17, cy), (cx - 11, cy - 30), (cx - 5, cy - 60)], fill=(225, 230, 238), outline=(0, 0, 0))   # the needle tower
T = ImageFont.truetype(os.path.join(ROOT, "fonts", "russoone_RussoOne-Regular.ttf"), 54)
if MODE:                                                # title: red skyline over slanted steel letters
    random.seed(3); bx = im.width - 300
    for i_ in range(26):
        hh_ = random.randint(8, 30) + (46 if i_ == 13 else 0); d.rectangle([bx + i_ * 10, 62 - hh_, bx + i_ * 10 + 8, 62], fill=(200, 28, 28))
    tile = Image.new("RGBA", (330, 80), (0, 0, 0, 0)); ImageDraw.Draw(tile).text((165, 40), "DUBAI", font=T, fill=(232, 236, 242, 255), anchor="mm", stroke_width=4, stroke_fill=(0, 0, 0, 255))
    tile = tile.transform(tile.size, Image.AFFINE, (1, 0.25, -10, 0, 1, 0), Image.BICUBIC); im.paste(tile, (im.width - 335, 56), tile); d = ImageDraw.Draw(im)
    d.line([(im.width - 310, 132), (im.width - 30, 132)], fill=(200, 28, 28), width=4)
else: d.text((im.width - 40, 36), "DUBAI", font=T, fill=(230, 232, 236), anchor="ra", stroke_width=3, stroke_fill=(0, 0, 0))
d.polygon([(50, 30), (66, 74), (50, 64), (34, 74)], fill=(240, 240, 240)); d.text((50, 96), "N", font=FS, fill=(240, 240, 240), anchor="mm")
if MODE: label((PHASE1_X + W) / 2, 120, "COMING SOON", FS, (255, 150, 130))
if not os.environ.get("PLAIN") and not MODE:
    d.text((PHASE1_X * S / 2 - 16, im.height - 30), "PART 1: BUILT FIRST", font=FS, fill=(120, 255, 140), anchor="rm", stroke_width=3, stroke_fill=(0, 0, 0))
    d.text((PHASE1_X * S / 2 + 16, im.height - 30), "PART 2: LATER (ROADS BLOCKED)", font=FS, fill=(255, 120, 100), anchor="lm", stroke_width=3, stroke_fill=(0, 0, 0))
    d.text((40, im.height - 30), "%.1f km x %.1f km" % (W * SCALE / 1000, H * SCALE / 1000), font=FS, fill=(230, 230, 230), anchor="lm", stroke_width=3, stroke_fill=(0, 0, 0))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "unity_assets", "city", "plan_preview.jpg")
im.save(out, quality=90)
km = sum(sum(math.dist(a, b) for a, b in zip(r["pts"], r["pts"][1:])) for r in roads) / 1000
print(len(levels), "bridges/flyovers/underpasses;", len(roads), "roads, %.1f km, written" % km, out)
