#!/usr/bin/env python3
"""Draws the old-school analog HUD dials for the Unity game (amber needle gauges like the
street racers of the 2000s): unity_assets/gen/gauge_speed.png (0..280 km/h),
gauge_tach.png (0..9 x1000 rpm), gauge_needle.png (points up), gauge_redarc.png (full red
ring; the HUD shows only the part past the car's redline).
Angles: value 0 sits at 225 degrees (lower left), full scale at -45 (lower right), clockwise."""
import math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "unity_assets", "gen")
FONT = os.path.join(ROOT, "fonts", "russoone_RussoOne-Regular.ttf")
SS = 4                      # supersampling
AMBER = (255, 176, 32)
AMBER_HI = (255, 214, 110)

def ang(f): return math.radians(225 - 270 * f)
def pt(c, r, a): return (c + r * math.cos(a), c - r * math.sin(a))

def face(size, majors, minor_per, label, numsize, unit, red_from=None):
    n = size * SS; c = n / 2; R = n / 2
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # soft drop shadow, chrome bezel, smoked face
    d.ellipse([c - R * 0.985, c - R * 0.985, c + R * 0.985, c + R * 0.985], fill=(0, 0, 0, 150))
    for i in range(60):          # bezel: brushed metal gradient ring
        t = i / 59
        r = R * (0.97 - 0.07 * t)
        g = int(70 + 150 * (0.5 + 0.5 * math.cos(t * math.pi * 2 + 0.6)))
        d.ellipse([c - r, c - r, c + r, c + r], fill=(g, int(g * 0.93), int(g * 0.8), 255))
    r0 = R * 0.895
    d.ellipse([c - r0, c - r0, c + r0, c + r0], fill=(8, 8, 10, 255))
    for i in range(40):          # face: dark glass, a little lighter in the middle
        t = i / 39
        r = r0 * (1 - 0.55 * t)
        v = int(10 + 22 * t)
        d.ellipse([c - r, c - r, c + r, c + r], fill=(v, int(v * 0.95), int(v * 0.9), 250))
    # amber inner ring
    r1 = R * 0.86
    d.ellipse([c - r1, c - r1, c + r1, c + r1], outline=AMBER + (255,), width=int(n * 0.006))
    steps = (len(majors) - 1) * minor_per
    for i in range(steps + 1):
        f = i / steps; a = ang(f); major = i % minor_per == 0
        val = majors[0] + (majors[-1] - majors[0]) * f
        col = (255, 60, 40) if red_from is not None and val >= red_from - 1e-6 else (AMBER_HI if major else AMBER)
        d.line([pt(c, R * (0.84 if True else 0), a), pt(c, R * (0.735 if major else 0.79), a)], fill=col + (255,), width=int(n * (0.013 if major else 0.006)))
    font = ImageFont.truetype(FONT, int(n * numsize))
    for k, m in enumerate(majors):
        f = k / (len(majors) - 1); a = ang(f)
        x, y = pt(c, R * 0.615, a)
        col = (255, 80, 60) if red_from is not None and m >= red_from else AMBER_HI
        d.text((x, y), str(m), font=font, fill=col + (255,), anchor="mm")
    uf = ImageFont.truetype(FONT, int(n * 0.062))
    d.text((c, c - R * 0.30), unit, font=uf, fill=AMBER + (255,), anchor="mm")
    if label:
        d.text((c, c + R * 0.74), label, font=ImageFont.truetype(FONT, int(n * 0.05)), fill=(200, 200, 205, 255), anchor="mm")
    # glass shine across the top
    shine = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    sd.pieslice([c - r0, c - r0, c + r0, c + r0], 200, 340, fill=(255, 255, 255, 26))
    sd.ellipse([c - r0 * 1.3, c - r0 * 0.55, c + r0 * 1.3, c + r0 * 2.2], fill=(0, 0, 0, 0))
    im = Image.alpha_composite(im, shine.filter(ImageFilter.GaussianBlur(n * 0.004)))
    return im.resize((size, size), Image.LANCZOS)

def needle(w, h):
    n = SS; im = Image.new("RGBA", (w * n, h * n), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    cx = w * n / 2
    # pivot at the image centre; the pointer goes up, a short tail goes down
    d.polygon([(cx, h * n * 0.03), (cx + w * n * 0.16, h * n * 0.5), (cx + w * n * 0.2, h * n * 0.62), (cx - w * n * 0.2, h * n * 0.62), (cx - w * n * 0.16, h * n * 0.5)], fill=(255, 70, 30, 255))
    d.polygon([(cx, h * n * 0.03), (cx + w * n * 0.05, h * n * 0.5), (cx - w * n * 0.05, h * n * 0.5)], fill=(255, 190, 150, 255))
    r = w * n * 0.5
    d.ellipse([cx - r, h * n / 2 - r, cx + r, h * n / 2 + r], fill=(30, 30, 34, 255), outline=(170, 170, 175, 255), width=int(n * 2))
    r2 = r * 0.45
    d.ellipse([cx - r2, h * n / 2 - r2, cx + r2, h * n / 2 + r2], fill=(120, 120, 126, 255))
    return im.resize((w, h), Image.LANCZOS)

def redarc(size):
    n = size * SS; c = n / 2; R = n / 2
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([c - R * 0.855, c - R * 0.855, c + R * 0.855, c + R * 0.855], outline=(255, 40, 30, 255), width=int(n * 0.03))
    return im.resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    face(640, list(range(0, 281, 20)), 2, "", 0.058, "KM/H").save(os.path.join(OUT, "gauge_speed.png"))
    face(420, list(range(0, 10)), 5, "", 0.085, "RPM x1000").save(os.path.join(OUT, "gauge_tach.png"))
    needle(64, 512).save(os.path.join(OUT, "gauge_needle.png"))
    redarc(420).save(os.path.join(OUT, "gauge_redarc.png"))
    print("gauges written to", OUT)
