#!/usr/bin/env python3
"""Prepares the generated car bodies for the Unity version (unity/).
For each cars/<id>.glb: cuts out the wheels baked into the body (using the fit in
cars/<id>.json), turns the car so its FRONT faces +Z, puts the bounding-box centre
at x=z=0 with the tyres on y=0 and scales it to length 1. Writes
unity_cars/<id>.glb plus unity_cars/<id>_cfg.json with the wheel spots in that
frame (front/rear: z along, y centre height, r radius, x tyre face), all in body
lengths. The low-poly traffic versions (w3d/cars_lod) are turned the same way."""
import json, os, sys
import numpy as np, trimesh

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "unity_cars")
CUT_DEPTH_M = 0.34      # same as CarVisual.CUT_DEPTH in the Godot game
CAR_LEN_M = 4.5

def frame(mesh):
    v = mesh.vertices
    mn, mx = v.min(0), v.max(0)
    ax = 0 if (mx[0] - mn[0]) > (mx[2] - mn[2]) else 2
    return mn, mx, ax, mx[ax] - mn[ax], (mn + mx) / 2

def to_unity_frame(mesh, ax, L, c, mn, front_sign):
    """Matrix: centre, ground at 0, scale 1/L, rotate so the front (model axis ax, sign front_sign) is +Z."""
    T = np.eye(4); T[:3, 3] = [-c[0], -mn[1], -c[2]]
    S = np.eye(4); S[:3, :3] *= 1.0 / L
    R = np.eye(4)
    if ax == 0:
        # +X*front_sign -> +Z : rotate about Y. (x,z) -> (z', ...)
        # rotation by angle a about Y maps x-axis to (cos a, 0, -sin a); want (0,0,1)*... => a = -90deg for +X->+Z
        a = -np.pi / 2 if front_sign > 0 else np.pi / 2
    else:
        a = 0.0 if front_sign > 0 else np.pi
    R[:3, :3] = trimesh.transformations.rotation_matrix(a, [0, 1, 0])[:3, :3]
    return R @ S @ T

def prep(cid):
    src = os.path.join(ROOT, "cars", cid + ".glb")
    cfg = json.load(open(os.path.join(ROOT, "cars", cid + ".json")))
    scene = trimesh.load(src)
    mesh = scene.to_geometry() if hasattr(scene, "to_geometry") else scene
    mn, mx, ax, L, c = frame(mesh)
    lt = 2 - ax
    fit = cfg["fit"]
    # front: Godot holder yaw rotates the model; front is where the rotated z < 0 (Godot -Z forward)
    yaw = np.radians(cfg.get("yaw", 0))
    wheels = []
    for w in fit["wheels"]:
        along = np.array([w["z"], 0, 0]) if fit.get("axis", "x") == "x" else np.array([0, 0, w["z"]])
        zr = -along[0] * np.sin(yaw) + along[2] * np.cos(yaw)
        wheels.append(dict(w, front=bool(zr < 0)))
    fw = [w for w in wheels if w["front"]]
    rw = [w for w in wheels if not w["front"]]
    assert len(fw) == 1 and len(rw) == 1, (cid, wheels)
    front_sign = 1 if fw[0]["z"] > 0 else -1

    # cut baked wheels (face centroids inside the tyre cylinder, out near the tyre face)
    cen = mesh.triangles_center
    a = (cen[:, ax] - c[ax]) / L
    y = (cen[:, 1] - mn[1]) / L
    lat = np.abs(cen[:, lt] - c[lt]) / L
    cut_depth = CUT_DEPTH_M / CAR_LEN_M
    kill = np.zeros(len(cen), bool)
    for w in wheels:
        kill |= (np.hypot(a - w["z"], y - w["y"]) < w["r"] * 1.03) & (lat > w["x"] - cut_depth)
    print(cid, "faces", len(cen), "cut", int(kill.sum()))
    mesh.update_faces(~kill)
    mesh.remove_unreferenced_vertices()
    M = to_unity_frame(mesh, ax, L, c, mn, front_sign)
    mesh.apply_transform(M)
    os.makedirs(OUT, exist_ok=True)
    _ = mesh.vertex_normals  # glTFast rejects meshes without normals
    mesh.export(os.path.join(OUT, cid + ".glb"), include_normals=True)
    out = {"front": None, "rear": None, "src_yaw": cfg.get("yaw", 0), "key": cfg.get("key", "")}
    for w, k in ((fw[0], "front"), (rw[0], "rear")):
        out[k] = {"z": round(abs(w["z"]) * (1 if k == "front" else -1), 4), "y": w["y"], "r": w["r"], "x": w["x"]}
    vmin, vmax = mesh.vertices.min(0), mesh.vertices.max(0)
    out["size"] = [round(float(s), 4) for s in (vmax - vmin)]
    json.dump(out, open(os.path.join(OUT, cid + "_cfg.json"), "w"), indent=1)

    # traffic LOD: same turn, keep its baked wheels
    lp = os.path.join(ROOT, "w3d", "cars_lod", cid + ".glb")
    if os.path.exists(lp):
        ls = trimesh.load(lp)
        lm = ls.to_geometry() if hasattr(ls, "to_geometry") else ls
        lmn, lmx, lax, lL, lc = frame(lm)
        lm.apply_transform(to_unity_frame(lm, lax, lL, lc, lmn, front_sign))
        _ = lm.vertex_normals
        lm.export(os.path.join(OUT, cid + "_lod.glb"), include_normals=True)

if __name__ == "__main__":
    ids = sys.argv[1:] or ["tuner", "classic", "muscle", "sedan", "rotary", "euro", "suv", "exotic"]
    for i in ids:
        prep(i)
