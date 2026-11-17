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

def clear_front_lamps(mesh, ax, c, L, front_sign):
    """Generated bodies sometimes get red/orange head lamps. Texels used by the nose that are
    red become clear silver (same brightness), so only the tail lamps stay red."""
    import colorsys
    from PIL import Image
    mat = mesh.visual.material
    img = np.array(mat.baseColorTexture.convert("RGB")).astype(np.float32) / 255.0
    H, W = img.shape[:2]
    uv = np.asarray(mesh.visual.uv)
    cen = mesh.triangles_center
    nose = ((cen[:, ax] - c[ax]) / L * front_sign > 0.33) & ((cen[:, 1] - mesh.vertices[:, 1].min()) / L > 0.09)
    mask = np.zeros((H, W), bool)
    for f in mesh.faces[nose]:
        u, v = uv[f, 0], 1.0 - uv[f, 1]
        x0, x1 = int(np.floor(u.min() * W)), int(np.ceil(u.max() * W)) + 1
        y0, y1 = int(np.floor(v.min() * H)), int(np.ceil(v.max() * H)) + 1
        mask[max(y0, 0):y1, max(x0, 0):x1] = True
    mx, mn = img.max(2), img.min(2)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    red = (img[..., 0] >= mx - 1e-4) & (img[..., 0] - img[..., 2] > 0.18) & (img[..., 1] < img[..., 0] * 0.8) & (sat > 0.35)
    sel = mask & red
    grey = np.clip(mx * 1.05, 0, 1)
    img[sel] = np.stack([grey, grey, grey * 1.02], -1)[sel].clip(0, 1)
    mat.baseColorTexture = Image.fromarray((img * 255).astype(np.uint8))
    print("  front lamp texels cleared:", int(sel.sum()))

def neutral_glass(mesh):
    """Generated glass sometimes comes out teal-green, which the in-game repaint (by hue) would
    turn into body colour. Texels that are green with at least as much blue as red (the paint key
    is a yellow-green, red well above blue) become dark neutral glass."""
    from PIL import Image
    mat = mesh.visual.material
    img = np.array(mat.baseColorTexture.convert("RGB")).astype(np.float32) / 255.0
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    sel = (g > r + 0.03) & (b >= r * 0.92) & (g > b)
    v = img.max(2)
    dark = np.clip(v * 0.32, 0, 1)
    img[sel] = np.stack([dark * 0.92, dark * 0.97, dark * 1.05], -1)[sel]
    mat.baseColorTexture = Image.fromarray((img.clip(0, 1) * 255).astype(np.uint8))
    print("  glass texels neutralised:", int(sel.sum()))

def prep(cid, src=None):
    """src: a newer high-detail body just for Unity (the Godot game keeps cars/<id>.glb).
    Its wheel fit is in <src minus .glb>.json (tools/fit_wheels.py <src>), with "front": +1/-1."""
    hd = src is not None
    src = src or os.path.join(ROOT, "cars", cid + ".glb")
    cfg = json.load(open(src[:-4] + ".json"))
    scene = trimesh.load(src, force="mesh") if hd else trimesh.load(src)
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
        if "front" in cfg: zr = -w["z"] * cfg["front"]
        wheels.append(dict(w, front=bool(zr < 0)))
    fw = [w for w in wheels if w["front"]]
    rw = [w for w in wheels if not w["front"]]
    assert len(fw) == 1 and len(rw) == 1, (cid, wheels)
    front_sign = 1 if fw[0]["z"] > 0 else -1
    if hd and cfg.get("neutral_glass"):
        neutral_glass(mesh)
    if hd and cfg.get("clear_front_lamps"):
        clear_front_lamps(mesh, ax, c, L, front_sign)

    # cut baked wheels (face centroids inside the tyre cylinder, out near the tyre face)
    cen = mesh.triangles_center
    a = (cen[:, ax] - c[ax]) / L
    y = (cen[:, 1] - mn[1]) / L
    lat = np.abs(cen[:, lt] - c[lt]) / L
    cut_depth = (0.5 if hd else CUT_DEPTH_M) / CAR_LEN_M
    kill = np.zeros(len(cen), bool)
    for w in wheels:
        kill |= (np.hypot(a - w["z"], y - w["y"]) < w["r"] * (1.09 if hd else 1.03)) & (lat > w["x"] - cut_depth)
    print(cid, "faces", len(cen), "cut", int(kill.sum()))
    M = to_unity_frame(mesh, ax, L, c, mn, front_sign)
    if hd and os.environ.get("LOD_FULL"):
        # whole body with its baked wheels, turned the same way: the start for the traffic LOD
        # (then: gltf-transform weld/simplify/resize -> unity_cars/<id>_lod.glb)
        full = mesh.copy(); full.apply_transform(M); _ = full.vertex_normals
        full.export(os.environ["LOD_FULL"], include_normals=True)
    mesh.update_faces(~kill)
    mesh.remove_unreferenced_vertices()
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
    if os.path.exists(lp) and not hd:
        ls = trimesh.load(lp)
        lm = ls.to_geometry() if hasattr(ls, "to_geometry") else ls
        lmn, lmx, lax, lL, lc = frame(lm)
        lm.apply_transform(to_unity_frame(lm, lax, lL, lc, lmn, front_sign))
        _ = lm.vertex_normals
        lm.export(os.path.join(OUT, cid + "_lod.glb"), include_normals=True)

if __name__ == "__main__":
    # unity_prep_cars.py [ids...]            from the Godot bodies in cars/
    # unity_prep_cars.py --src new.glb tuner  from a newer high-detail body
    args = sys.argv[1:]
    if args and args[0] == "--src":
        prep(args[2], args[1])
    else:
        for i in args or ["tuner", "classic", "muscle", "sedan", "rotary", "euro", "suv", "exotic"]:
            prep(i)
