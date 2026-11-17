#!/usr/bin/env python3
"""Draws the old-school analog HUD dials for the Unity game (light vintage needle gauges: ivory faces, chrome bezels, red needles): unity_assets/gen/gauge_speed.png (0..280 km/h),
gauge_tach.png (0..9 x1000 rpm), gauge_needle.png (points up), gauge_redarc.png (full red
ring; the HUD shows only the part past the car's redline).
Angles: value 0 sits at 225 degrees (lower left), full scale at -45 (lower right), clockwise."""
import math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "unity_assets", "gen")
FONT = os.path.join(ROOT, "fonts", "russoone_RussoOne-Regular.ttf")
FONT2 = os.path.join(ROOT, "fonts", "rajdhani_Rajdhani-Bold.ttf")
SS = 4                      # supersampling
AMBER = (255, 176, 32)
AMBER_HI = (255, 214, 110)

def ang(f): return math.radians(225 - 270 * f)
def pt(c, r, a): return (c + r * math.cos(a), c - r * math.sin(a))

def face(size, majors, minor_per, label, numsize, unit, red_from=None):
    """Light vintage dial: thin chrome bezel, ivory face that lets a little of the street through,
    dark numerals and ticks, a fine double ring like a 60s/70s instrument."""
    n = size * SS; c = n / 2; R = n / 2
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([c - R * 0.985, c - R * 0.985, c + R * 0.985, c + R * 0.985], fill=(0, 0, 0, 110))
    for i in range(50):          # slim polished chrome bezel
        t = i / 49
        r = R * (0.965 - 0.045 * t)
        g = int(120 + 125 * (0.5 + 0.5 * math.cos(t * math.pi * 2 + 0.4)))
        d.ellipse([c - r, c - r, c + r, c + r], fill=(g, g, int(g * 0.97), 255))
    r0 = R * 0.915
    for i in range(50):          # ivory face, a touch darker at the rim, slightly see-through
        t = i / 49
        r = r0 * (1 - 0.75 * t)
        d.ellipse([c - r, c - r, c + r, c + r], fill=(int(214 + 30 * t), int(206 + 30 * t), int(184 + 34 * t), 224))
    INK = (38, 34, 30)
    r1 = R * 0.875
    d.ellipse([c - r1, c - r1, c + r1, c + r1], outline=INK + (255,), width=max(1, int(n * 0.004)))
    r2 = R * 0.48
    d.ellipse([c - r2, c - r2, c + r2, c + r2], outline=INK + (90,), width=max(1, int(n * 0.003)))
    steps = (len(majors) - 1) * minor_per
    for i in range(steps + 1):
        f = i / steps; a = ang(f); major = i % minor_per == 0
        val = majors[0] + (majors[-1] - majors[0]) * f
        col = (190, 30, 22) if red_from is not None and val >= red_from - 1e-6 else INK
        d.line([pt(c, R * 0.86, a), pt(c, R * (0.765 if major else 0.81), a)], fill=col + (255,), width=int(n * (0.011 if major else 0.005)))
    font = ImageFont.truetype(FONT2, int(n * numsize))
    for k, m in enumerate(majors):
        f = k / (len(majors) - 1); a = ang(f)
        x, y = pt(c, R * 0.655, a)
        d.text((x, y), str(m), font=font, fill=INK + (255,), anchor="mm")
    d.text((c, c - R * 0.27), unit, font=ImageFont.truetype(FONT2, int(n * 0.058)), fill=(150, 40, 25, 255), anchor="mm")
    # glass shine across the top
    shine = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    sd.pieslice([c - r0, c - r0, c + r0, c + r0], 200, 340, fill=(255, 255, 255, 46))
    sd.ellipse([c - r0 * 1.3, c - r0 * 0.55, c + r0 * 1.3, c + r0 * 2.2], fill=(0, 0, 0, 0))
    im = Image.alpha_composite(im, shine.filter(ImageFilter.GaussianBlur(n * 0.004)))
    return im.resize((size, size), Image.LANCZOS)

def needle(w, h):
    n = SS; im = Image.new("RGBA", (w * n, h * n), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    cx = w * n / 2; H = h * n; W = w * n
    # pivot at the image centre; a slim red pointer goes up, a short counterweight goes down
    d.polygon([(cx, H * 0.04), (cx + W * 0.10, H * 0.5), (cx + W * 0.13, H * 0.60), (cx - W * 0.13, H * 0.60), (cx - W * 0.10, H * 0.5)], fill=(200, 28, 20, 255))
    r = W * 0.42
    for i in range(20):
        t = i / 19; rr = r * (1 - 0.9 * t); g = int(90 + 150 * t)
        d.ellipse([cx - rr, H / 2 - rr, cx + rr, H / 2 + rr], fill=(g, g, g, 255))
    return im.resize((w, h), Image.LANCZOS)

def redarc(size):
    n = size * SS; c = n / 2; R = n / 2
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([c - R * 0.86, c - R * 0.86, c + R * 0.86, c + R * 0.86], outline=(200, 28, 20, 255), width=int(n * 0.028))
    return im.resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    face(640, list(range(0, 281, 20)), 2, "", 0.07, "KM/H").save(os.path.join(OUT, "gauge_speed.png"))
    face(420, list(range(0, 10)), 5, "", 0.105, "RPM x1000").save(os.path.join(OUT, "gauge_tach.png"))
    needle(64, 512).save(os.path.join(OUT, "gauge_needle.png"))
    redarc(420).save(os.path.join(OUT, "gauge_redarc.png"))
    print("gauges written to", OUT)
