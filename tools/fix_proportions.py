#!/usr/bin/env python3
"""Corrects the proportions of a generated car body so it matches the real car's
length : width : height. Generated bodies come out too short and too wide (toy look).
The length is stretched only between and beyond the wheels: the zones around the wheel
arches stay rigid, so the arches stay round.

  fix_proportions.py <src.glb> <out.glb> <length_scale> <width_scale> [height_scale]

Needs <src minus .glb>.json with the wheel fit (tools/fit_wheels.py)."""
import sys, json
import numpy as np, trimesh

def main(src, out, sl, sw, sh=1.0):
    cfg = json.load(open(src[:-4] + ".json"))["fit"]
    m = trimesh.load(src, force="mesh")
    v = np.array(m.vertices)
    mn, mx = v.min(0), v.max(0)
    ax = 0 if cfg["axis"] == "x" else 2
    lt = 2 - ax
    L = mx[ax] - mn[ax]; c = (mn + mx) / 2
    a = (v[:, ax] - c[ax]) / L                      # -0.5 .. 0.5
    ws = sorted(cfg["wheels"], key=lambda w: w["z"])
    k = 1.3                                          # rigid zone: 1.3 wheel radii each side of the axle
    bp = [-0.5, ws[0]["z"] - k * ws[0]["r"], ws[0]["z"] + k * ws[0]["r"], ws[1]["z"] - k * ws[1]["r"], ws[1]["z"] + k * ws[1]["r"], 0.5]
    rigid = (bp[2] - bp[1]) + (bp[4] - bp[3])
    s = (sl - rigid) / (1 - rigid)                   # stretch of the flexible parts
    scale = [s, 1, s, 1, s]
    nb = [bp[0]]
    for i in range(5): nb.append(nb[-1] + (bp[i + 1] - bp[i]) * scale[i])
    a2 = np.interp(a, bp, nb)
    a2 -= (nb[0] + nb[-1]) / 2
    v[:, ax] = c[ax] + a2 * L
    v[:, lt] = c[lt] + (v[:, lt] - c[lt]) * sw
    v[:, 1] = mn[1] + (v[:, 1] - mn[1]) * sh
    m.vertices = v
    m.export(out, include_normals=True)
    e = v.max(0) - v.min(0)
    print("flexible stretch %.3f, new size w/l %.3f h/l %.3f" % (s, e[lt] / e[ax], e[1] / e[ax]))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], *[float(x) for x in sys.argv[3:]])
