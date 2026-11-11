#!/usr/bin/env python3
"""Draws the launcher icons (icon.png + Android adaptive layers) with Pillow."""
import math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
S = 4  # supersample


def gauge(size, with_bg):
    W = size * S
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if with_bg:
        for y in range(W):
            t = y / W
            d.line([(0, y), (W, y)], fill=(int(10 + 30 * t), int(8 + 6 * t), int(22 + 30 * t), 255))
    c = W / 2
    r = W * 0.27
    a0, a1 = 135, 405
    bbox = [c - r, c - r * 1.05, c + r, c + r * 0.95]
    d.arc(bbox, a0, a1, fill=(255, 176, 0, 255), width=int(W * 0.035))
    d.arc(bbox, a0 + (a1 - a0) * 0.78, a1, fill=(255, 50, 30, 255), width=int(W * 0.035))
    cy = c - r * 0.05
    for i in range(9):
        a = math.radians(a0 + (a1 - a0) * i / 8)
        col = (255, 60, 40, 255) if i >= 7 else (255, 255, 255, 255)
        d.line([(c + math.cos(a) * r * 0.68, cy + math.sin(a) * r * 0.68), (c + math.cos(a) * r * 0.84, cy + math.sin(a) * r * 0.84)], fill=col, width=int(W * 0.014))
    a = math.radians(a0 + (a1 - a0) * 0.86)
    d.line([(c - math.cos(a) * r * 0.12, cy - math.sin(a) * r * 0.12), (c + math.cos(a) * r * 0.8, cy + math.sin(a) * r * 0.8)], fill=(255, 50, 30, 255), width=int(W * 0.022))
    d.ellipse([c - W * 0.03, cy - W * 0.03, c + W * 0.03, cy + W * 0.03], fill=(255, 255, 255, 255))
    font = ImageFont.truetype(os.path.join(ROOT, "fonts", "russoone_RussoOne-Regular.ttf"), int(W * 0.13))
    txt = "AH"
    tw = d.textlength(txt, font=font)
    d.text((c - tw / 2 + W * 0.004, cy + r * 0.42 + W * 0.004), txt, font=font, fill=(0, 0, 0, 200))
    d.text((c - tw / 2, cy + r * 0.42), txt, font=font, fill=(25, 227, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


gauge(192, True).save(os.path.join(ROOT, "icon.png"))
gauge(432, False).save(os.path.join(ROOT, "icon_fg.png"))
bg = Image.new("RGBA", (432, 432))
d = ImageDraw.Draw(bg)
for y in range(432):
    t = y / 432
    d.line([(0, y), (432, y)], fill=(int(10 + 30 * t), int(8 + 6 * t), int(22 + 30 * t), 255))
bg.save(os.path.join(ROOT, "icon_bg.png"))
print("icons written")
