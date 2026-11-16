#!/usr/bin/env python3
"""Measures the wheels baked into each generated car body (cars/<id>.glb) and
writes them to cars/<id>.json as "fit": positions are in body lengths, in the
GLB's own frame, relative to the bounding-box centre (y from the box bottom).
CarVisual uses this to cut the baked wheels out and to put the real spinning
wheels exactly where they were."""
import sys, json, glob, os
import numpy as np, trimesh

def fit(path):
    sc = trimesh.load(path, force='mesh')
    V, _ = trimesh.sample.sample_surface(sc, 600000, seed=1)
    V = np.asarray(V)
    mn, mx = sc.vertices.min(0), sc.vertices.max(0)
    ax = 0 if (mx[0] - mn[0]) > (mx[2] - mn[2]) else 2
    lt = 2 - ax
    L = mx[ax] - mn[ax]
    c = (mn + mx) / 2
    a = (V[:, ax] - c[ax]) / L
    y = (V[:, 1] - mn[1]) / L
    lat = np.abs(V[:, lt] - c[lt]) / L
    hw = float(np.abs(sc.vertices[:, lt] - c[lt]).max() / L)
    out = (lat > 0.6 * hw) & (y < 0.2)
    A, Y, LT = a[out], y[out], lat[out]
    res = []
    for sign in (-1, 1):
        best = (-1, 0, 0, 0)
        for zc in np.arange(0.14, 0.43, 0.003) * sign:
            near = np.abs(A - zc) < 0.11
            if near.sum() < 200:
                continue
            An, Yn = A[near] - zc, Y[near]
            for r in np.arange(0.058, 0.105, 0.002):
                for yc in r + np.arange(-0.012, 0.016, 0.003):
                    d = np.sqrt(An ** 2 + (Yn - yc) ** 2)
                    # tyre tread on the lower part of the circle (the arch above is excluded)
                    scv = np.sum((np.abs(d - r) < 0.002) & (Yn < yc + 0.3 * r)) / r
                    if scv > best[0]:
                        best = (scv, zc, r, yc)
        _, zc, r, yc = best
        inside = (np.hypot(A - zc, Y - yc) < 0.8 * r)
        face = float(np.percentile(LT[inside], 97))
        res.append({"z": round(float(zc), 4), "y": round(float(yc), 4), "r": round(float(r), 4), "x": round(face, 4)})
    return {"axis": "x" if ax == 0 else "z", "wheels": res}

for p in sorted(glob.glob(os.path.join(os.path.dirname(__file__), "..", "cars", "*.glb"))):
    f = fit(p)
    jp = p[:-4] + ".json"
    cfg = json.load(open(jp)) if os.path.exists(jp) else {}
    if f:
        cfg["fit"] = f
        json.dump(cfg, open(jp, "w"))
    print(os.path.basename(p), f)
