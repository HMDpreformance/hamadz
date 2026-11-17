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

# coast: the sea is north of this line
COAST = spline([(0, 1560), (300, 1640), (620, 1700), (900, 1760), (1250, 1800), (1600, 1850), (1950, 1880), (2250, 1960), (2600, 2040), (2900, 2120), (3200, 2180)], 20)
def coast_y(x): return float(np.interp(x, [p[0] for p in COAST], [p[1] for p in COAST]))

# highways
road("E11", "highway", [(0, 980), (450, 1080), (950, 1230), (1500, 1330), (2050, 1330), (2500, 1420), (2900, 1560), (3200, 1640)])
road("E44", "highway", [(0, 420), (600, 470), (1200, 560), (1800, 640), (2400, 620), (2850, 520), (3200, 470)])
road("E311", "highway", [(2480, 0), (2440, 330), (2470, 640), (2580, 1000), (2640, 1420), (2760, 1800), (2880, 2110)])
road("Hills Link", "highway", [(1020, 0), (1000, 300), (1040, 560), (1010, 900), (1140, 1272)])   # joins E11 on its flat ground stretch, clear of the flyover ramps
# main roads
road("Beach Road", "main", [(60, 1480), (400, 1560), (760, 1640), (1150, 1700), (1550, 1750), (1950, 1780), (2300, 1850), (2650, 1930), (3000, 2040)])
road("Al Wasl", "main", [(250, 1300), (700, 1420), (1150, 1500), (1600, 1540), (2000, 1560), (2350, 1640)])
road("Marina Loop", "main", ring(430, 1330, 250, 150, 14, 40), smooth=False)
road("Downtown Ring", "main", ring(1620, 1130, 250, 190, 0, 48), smooth=False)
road("Business Bay", "main", [(1870, 1130), (2050, 1000), (2250, 960), (2420, 1050), (2500, 1240), (2380, 1420)])
road("Al Quoz Road", "main", [(560, 470), (620, 760), (760, 1000), (800, 1240), (760, 1420), (700, 1640)])
road("Al Khail", "main", [(0, 720), (500, 800), (1010, 900), (1500, 880), (2000, 860), (2580, 1000), (3200, 1060)])
road("Hills Ring", "main", ring(1500, 310, 300, 180, 0, 48), smooth=False)
road("Deira Road", "main", [(2640, 1420), (2800, 1500), (2980, 1700), (3050, 1900), (3000, 2040)])
road("Airport Road", "main", [(2850, 520), (2950, 800), (3050, 1060), (3100, 1350), (3200, 1640)])
road("Downtown Blvd", "main", [(1500, 1330), (1560, 1230), (1620, 1130), (1640, 980), (1600, 880)])
road("Jebel Ali Road", "main", [(120, 0), (160, 250), (140, 470), (200, 720), (180, 980), (250, 1300)])
road("Nad Al Sheba", "main", [(1800, 640), (1900, 420), (2100, 250), (2440, 330)])
road("Ras Al Khor", "main", [(2000, 860), (2150, 760), (2400, 620)])
# the Palm: trunk from the Beach Road out to sea, fronds, and the crescent
PX, PY = 620, 1700
road("Palm Trunk", "main", [(PX, PY - 60), (PX + 10, PY + 120), (PX, PY + 330)])
for k in range(-4, 5):
    if k == 0: continue
    y0 = PY + 150 + 22 * (4 - abs(k)); a = math.radians(90 - 17 * k)
    road("Frond", "street", [(PX, y0), (PX + 90 * math.cos(a) + 25 * k, y0 + 60 + 10 * abs(k)), (PX + 46 * k + 150 * math.cos(a), y0 + 110 + 26 * abs(k))])
road("Crescent", "street", ring(PX, PY + 290, 330, 230, 0, 40, -25, 205), smooth=False)

# districts: local street grids, turned and clipped to an ellipse
districts = [
    ("Jebel Ali", 180, 250, 170, 220, 8, 80), ("Dubai Marina", 430, 1330, 230, 135, 14, 70), ("JBR", 330, 1500, 220, 50, 14, 60),
    ("Al Quoz", 760, 640, 230, 150, 5, 100), ("Jumeirah", 1150, 1610, 420, 85, 7, 75), ("Downtown Dubai", 1620, 1130, 230, 175, 20, 70),
    ("Business Bay", 2180, 1180, 210, 130, -15, 80), ("Dubai Hills", 1500, 310, 280, 165, 0, 85), ("Deira", 2900, 1850, 190, 170, 25, 65),
    ("Ras Al Khor", 2850, 820, 180, 160, 10, 105), ("Nad Al Sheba", 2060, 420, 220, 120, -10, 100), ("Al Wasl", 1150, 1410, 330, 70, 5, 85),
    ("Al Barsha", 500, 1020, 190, 130, 12, 85), ("DXB Airport", 3060, 1300, 110, 210, 12, 140),
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
for name, cx, cy, rx, ry, rot, pitch in districts:
    for seg in clipped_grid(cx, cy, rx, ry, rot, pitch):
        if all(p[1] < coast_y(p[0]) - 25 and 0 <= p[0] <= W and 0 <= p[1] <= H for p in seg):
            roads.append({"name": name, "cls": "street", "width": 13, "pts": seg})

water = {
    "creek": spline([(2380, 2010), (2330, 1800), (2380, 1600), (2330, 1420), (2180, 1330), (2020, 1250), (1930, 1130)], 20),
    "lake": ring(2240, 870, 110, 60, 10, 32),
}
# ---- heights: the city is not flat
def terrain(x, y):
    """Ground height in metres: sea level at the coast, rising gently inland, real hills in Dubai Hills
    and Nad Al Sheba, a low rise under Downtown."""
    inland = max(0.0, coast_y(x) - y)
    h = 1.5 + 9.0 * min(1.0, inland / 1500.0) ** 1.3
    for cx, cy, r, amp in ((1500, 310, 330, 11), (1250, 120, 260, 8), (2060, 420, 260, 6), (1620, 1130, 300, 3), (300, 250, 300, 4)):
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
            if o["cls"] == "highway" and hw.index(o) < hw.index(r): continue
            for at in crossings(pts, o["pts"]): add(at, 6.2, 60, 240, "flyover")
    if r["cls"] != "street" or r["name"] == "Palm Trunk":
        for at in crossings(pts, water["creek"]): add(at, 6.5, 90, 170, "bridge")
    if r["name"] == "Palm Trunk": add(150, 5.0, 80, 140, "bridge")
    if r["name"] == "Downtown Blvd":
        for at in crossings(pts, hw[0]["pts"]): add(at, -6.0, 50, 110, "underpass")
    r["h"] = [round(terrain(x, y) + e, 2) for (x, y), e in zip(pts, extra)]
    r["deck"] = [round(e, 2) for e in extra]      # height above the ground (bridge deck) or below (underpass)

SCALE = 0.75          # plan units to game metres: the game city is 2.4 km x 1.7 km (medium size)
PHASE1_X = 1900       # built first: everything west of this line; roads are blocked there until phase 2
plan = {"size": [W, H], "scale": SCALE, "phase1_x": PHASE1_X, "coast": COAST, "roads": roads, "water": water, "levels": levels, "terrain": [[round(terrain(x, y), 1) for x in range(0, W + 1, 50)] for y in range(0, H + 1, 50)],
        "districts": [{"name": d[0], "x": d[1], "y": d[2]} for d in districts] + [{"name": "Palm Jumeirah", "x": PX, "y": PY + 300}],
        "garage": {"name": "LSXmotorsport", "x": 760, "y": 700}, "landmark": {"name": "Sky Tower", "x": 1620, "y": 1130}}
os.makedirs(os.path.join(ROOT, "unity_assets", "city"), exist_ok=True)
json.dump(plan, open(os.path.join(ROOT, "unity_assets", "city", "plan.json"), "w"), separators=(",", ":"))

# ---- preview in the dark game-map style
S = 1.0                                             # pixels per metre (then halved)
def P(p): return (p[0] * S, (H - p[1]) * S)
im = Image.new("RGB", (int(W * S), int(H * S)), (9, 12, 18))
land = [P(p) for p in COAST] + [(W * S, H * S), (0, H * S)]
def fat(dr, pts, col, wd):
    q = [P(p) for p in pts]; dr.line(q, fill=col, width=wd, joint="curve")
    r = wd / 2
    for x, y in (q[0], q[-1]): dr.ellipse([x - r, y - r, x + r, y + r], fill=col)
PALM = [r for r in roads if r["name"] in ("Palm Trunk", "Frond", "Crescent")]
def shore(dr, col, grow):
    dr.polygon(land, fill=col)
    if grow: dr.line(land[:len(COAST)], fill=col, width=grow)
    for r in PALM: fat(dr, r["pts"], col, (30 if r["name"] == "Frond" else 46) + grow)
glow = Image.new("RGB", im.size, (9, 12, 18)); shore(ImageDraw.Draw(glow), (60, 150, 230), 26)
im = glow.filter(ImageFilter.GaussianBlur(12))          # light-blue glow along every shore
d = ImageDraw.Draw(im)
shore(d, (36, 37, 41), 0)
for gx in range(0, W, 100): d.line([(gx, 0), (gx, H)], fill=(40, 41, 45), width=1)
for gy in range(0, H, 100): d.line([(0, gy), (W, gy)], fill=(40, 41, 45), width=1)
sea = Image.new("L", im.size, 0); shore(ImageDraw.Draw(sea), 255, 0)
im = Image.composite(im, glow.filter(ImageFilter.GaussianBlur(12)), sea); d = ImageDraw.Draw(im)
fat(d, water["creek"], (14, 30, 52), 60); d.polygon([P(p) for p in water["lake"]], fill=(14, 30, 52))
for cls, edge, col, wd in (("street", (20, 20, 22), (120, 122, 126), 9), ("main", (16, 16, 18), (190, 192, 196), 17), ("highway", (16, 14, 8), (240, 180, 40), 22)):
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
if not os.environ.get("PLAIN"):      # phase 2 (east): dimmed, with road blocks on the line
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
F = ImageFont.truetype(os.path.join(ROOT, "fonts", "rajdhani_Rajdhani-Bold.ttf"), 30)
def label(x, y, t, font=F, fill=(255, 255, 255)):
    d.text((x * S / 2, (H - y) * S / 2), t, font=font, fill=fill, anchor="mm", stroke_width=4, stroke_fill=(0, 0, 0))
for dd in plan["districts"]: label(dd["x"], dd["y"], dd["name"])
FS = ImageFont.truetype(os.path.join(ROOT, "fonts", "rajdhani_Rajdhani-Bold.ttf"), 22)
for t, x, y in (("E11", 300, 1040), ("E44", 1350, 580), ("E311", 2475, 680)):
    cx, cy = x / 2, (H - y) / 2
    d.rounded_rectangle([cx - 30, cy - 15, cx + 30, cy + 15], 5, fill=(24, 70, 170), outline=(255, 255, 255), width=2)
    d.text((cx, cy), t, font=FS, fill=(255, 255, 255), anchor="mm")
g = plan["garage"]; cx, cy = g["x"] / 2, (H - g["y"]) / 2
if not os.environ.get("PLAIN"):
    d.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=(215, 30, 30), outline=(255, 255, 255), width=3)
    label(g["x"], g["y"] - 60, "LSX GARAGE", FS, (255, 120, 110))
cx, cy = 1620 / 2, (H - 1150) / 2
d.polygon([(cx, cy - 46), (cx + 7, cy), (cx - 7, cy)], fill=(255, 255, 255), outline=(0, 0, 0))
T = ImageFont.truetype(os.path.join(ROOT, "fonts", "russoone_RussoOne-Regular.ttf"), 54)
d.text((im.width - 40, 36), "DUBAI", font=T, fill=(230, 232, 236), anchor="ra", stroke_width=3, stroke_fill=(0, 0, 0))
d.polygon([(50, 30), (66, 74), (50, 64), (34, 74)], fill=(240, 240, 240)); d.text((50, 96), "N", font=FS, fill=(240, 240, 240), anchor="mm")
if not os.environ.get("PLAIN"):
    d.text((PHASE1_X * S / 2 - 16, im.height - 30), "PART 1: BUILT FIRST", font=FS, fill=(120, 255, 140), anchor="rm", stroke_width=3, stroke_fill=(0, 0, 0))
    d.text((PHASE1_X * S / 2 + 16, im.height - 30), "PART 2: LATER (ROADS BLOCKED)", font=FS, fill=(255, 120, 100), anchor="lm", stroke_width=3, stroke_fill=(0, 0, 0))
    d.text((40, im.height - 30), "%.1f km x %.1f km" % (W * SCALE / 1000, H * SCALE / 1000), font=FS, fill=(230, 230, 230), anchor="lm", stroke_width=3, stroke_fill=(0, 0, 0))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "unity_assets", "city", "plan_preview.jpg")
im.save(out, quality=90)
km = sum(sum(math.dist(a, b) for a, b in zip(r["pts"], r["pts"][1:])) for r in roads) / 1000
print(len(levels), "bridges/flyovers/underpasses;", len(roads), "roads, %.1f km, written" % km, out)
