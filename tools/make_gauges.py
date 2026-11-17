#!/usr/bin/env python3
"""Draws the old-school analog HUD dials for the Unity game (blue flame needle gauges: dark faces with blue flames, chrome bezels, ice-blue numbers): unity_assets/gen/gauge_speed.png (0..280 km/h),
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

FACE_MID, FACE_SIDE = 0.62, 0.20   # how solid the dial face is in the middle and at the sides
FLAME = os.path.join(ROOT, "unity_assets", "gen_src", "dial_flame.jpg")   # blue flames on black, square

def face(size, majors, minor_per, label, numsize, unit, red_from=None):
    """Blue flame dial: slim chrome bezel, near-black face with blue flames rising from the bottom,
    ice-blue numerals and ticks with a soft glow."""
    n = size * SS; c = n / 2; R = n / 2
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i in range(50):          # slim polished chrome bezel with a cold blue tint
        t = i / 49
        r = R * (0.965 - 0.045 * t)
        g = int(110 + 130 * (0.5 + 0.5 * math.cos(t * math.pi * 2 + 0.4)))
        d.ellipse([c - r, c - r, c + r, c + r], fill=(int(g * 0.9), int(g * 0.96), g, 255))
    r0 = R * 0.915
    # the face: flames picture inside the circle, darkened towards the top so the numbers read
    fl = Image.open(FLAME).convert("RGB").resize((int(2 * r0), int(2 * r0)), Image.LANCZOS)
    base = Image.new("RGB", fl.size, (4, 8, 20))
    fl = Image.blend(base, fl, 0.85)
    # see-through face: about 60% solid in the middle, fading to 20% solid (80% see-through) at the sides,
    # so the street shows through the dial and it sits in the game picture
    import numpy as np
    w = fl.size[0]
    yy, xx = np.mgrid[0:w, 0:w]
    rr = np.hypot(xx - w / 2, yy - w / 2) / (w / 2)
    al = np.where(rr <= 1, 255 * (FACE_MID + (FACE_SIDE - FACE_MID) * np.clip(rr, 0, 1) ** 1.6), 0).astype("uint8")
    mask = Image.fromarray(al, "L")
    hole = Image.new("L", (n, n), 255)
    ImageDraw.Draw(hole).ellipse([c - r0, c - r0, c + r0, c + r0], fill=0)
    im.putalpha(Image.composite(im.getchannel("A"), Image.new("L", (n, n), 0), hole))   # clear the bezel disc inside
    lay = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    fla = fl.convert("RGBA"); fla.putalpha(mask)
    lay.paste(fla, (int(c - r0), int(c - r0)))
    im = Image.alpha_composite(im, lay)
    d = ImageDraw.Draw(im)
    ICE = (190, 235, 255); BLUE = (40, 150, 255)
    glow = Image.new("RGBA", (n, n), (0, 0, 0, 0)); gd = ImageDraw.Draw(glow)
    ink = Image.new("RGBA", (n, n), (0, 0, 0, 0)); kd = ImageDraw.Draw(ink)
    r1 = R * 0.875
    for dd, col in ((gd, BLUE), (kd, ICE)):
        dd.ellipse([c - r1, c - r1, c + r1, c + r1], outline=col + (255,), width=max(1, int(n * 0.005)))
    steps = (len(majors) - 1) * minor_per
    font = ImageFont.truetype(FONT, int(n * numsize))
    for i in range(steps + 1):
        f = i / steps; a = ang(f); major = i % minor_per == 0
        for dd, col in ((gd, BLUE), (kd, ICE if major else (120, 200, 255))):
            dd.line([pt(c, R * 0.86, a), pt(c, R * (0.765 if major else 0.81), a)], fill=col + (255,), width=int(n * (0.012 if major else 0.005)))
    for k, m in enumerate(majors):
        f = k / (len(majors) - 1); a = ang(f)
        x, y = pt(c, R * 0.645, a)
        # dark backing so numbers stay readable over bright flames
        d.text((x, y), str(m), font=font, fill=(0, 6, 20, 255), anchor="mm", stroke_width=int(n * 0.008), stroke_fill=(0, 6, 20, 255))
        gd.text((x, y), str(m), font=font, fill=BLUE + (255,), anchor="mm")
        kd.text((x, y), str(m), font=font, fill=(255, 255, 255, 255), anchor="mm")
    uf = ImageFont.truetype(FONT, int(n * 0.05))
    kd.text((c, c - R * 0.27), unit, font=uf, fill=(120, 200, 255, 255), anchor="mm")
    im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(n * 0.012)))
    im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(n * 0.004)))
    im = Image.alpha_composite(im, ink)
    shine = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    sd.pieslice([c - r0, c - r0, c + r0, c + r0], 200, 340, fill=(200, 230, 255, 30))
    sd.ellipse([c - r0 * 1.3, c - r0 * 0.55, c + r0 * 1.3, c + r0 * 2.2], fill=(0, 0, 0, 0))
    im = Image.alpha_composite(im, shine.filter(ImageFilter.GaussianBlur(n * 0.004)))
    return im.resize((size, size), Image.LANCZOS)

def needle(w, h):
    n = SS; im = Image.new("RGBA", (w * n, h * n), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    cx = w * n / 2; H = h * n; W = w * n
    # pivot at the image centre; a slim red pointer goes up, a short counterweight goes down
    d.polygon([(cx, H * 0.04), (cx + W * 0.10, H * 0.5), (cx + W * 0.13, H * 0.60), (cx - W * 0.13, H * 0.60), (cx - W * 0.10, H * 0.5)], fill=(255, 120, 30, 255))
    d.polygon([(cx, H * 0.04), (cx + W * 0.04, H * 0.5), (cx - W * 0.04, H * 0.5)], fill=(255, 225, 170, 255))
    r = W * 0.42
    for i in range(20):
        t = i / 19; rr = r * (1 - 0.9 * t); g = int(90 + 150 * t)
        d.ellipse([cx - rr, H / 2 - rr, cx + rr, H / 2 + rr], fill=(g, g, g, 255))
    return im.resize((w, h), Image.LANCZOS)

def redarc(size):
    n = size * SS; c = n / 2; R = n / 2
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([c - R * 0.86, c - R * 0.86, c + R * 0.86, c + R * 0.86], outline=(255, 50, 30, 255), width=int(n * 0.03))
    return im.resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    face(640, list(range(0, 281, 20)), 2, "", 0.058, "KM/H").save(os.path.join(OUT, "gauge_speed.png"))
    face(420, list(range(0, 10)), 5, "", 0.09, "RPM x1000").save(os.path.join(OUT, "gauge_tach.png"))
    needle(64, 512).save(os.path.join(OUT, "gauge_needle.png"))
    redarc(420).save(os.path.join(OUT, "gauge_redarc.png"))
    print("gauges written to", OUT)
