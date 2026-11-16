"""Builds the low-poly parked-car bodies in w3d/cars_lod from the full car models.
usage: python3 make_car_lod.py cars/sedan.glb w3d/cars_lod/sedan.glb 6000
Decimates the body, unwraps it again (xatlas) and re-bakes the colour texture from
the original model, so the small mesh has a clean atlas of its own."""
import sys, numpy as np, trimesh, fast_simplification, xatlas
from scipy.spatial import cKDTree
from PIL import Image, ImageFilter
src, dst, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
RES = 1024
m = trimesh.load(src, force='mesh', process=False)
V = np.asarray(m.vertices); F = np.asarray(m.faces); UV = np.asarray(m.visual.uv)
img = np.asarray(m.visual.material.baseColorTexture.convert('RGB'))
key = np.round(V / (np.ptp(V, axis=0).max() * 1e-4)).astype(np.int64)
_, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
inv = inv.reshape(-1)
Vw = V[first]; Fw = inv[F]
Fw = Fw[(Fw[:, 0] != Fw[:, 1]) & (Fw[:, 1] != Fw[:, 2]) & (Fw[:, 0] != Fw[:, 2])]
Vs, Fs = fast_simplification.simplify(Vw.astype(np.float32), Fw.astype(np.int64), target_reduction=1.0 - target / len(Fw), agg=6)
ms = trimesh.Trimesh(Vs, Fs, process=False)
Ns = np.asarray(ms.vertex_normals)
# coloured point cloud of the original surface
rng = np.random.default_rng(1)
area = m.area_faces
fi = rng.choice(len(F), size=1500000, p=area / area.sum())
r1 = np.sqrt(rng.random(len(fi))); r2 = rng.random(len(fi))
bc = np.stack([1 - r1, r1 * (1 - r2), r1 * r2], axis=1)
pts = (V[F[fi]] * bc[:, :, None]).sum(1)
puv = (UV[F[fi]] * bc[:, :, None]).sum(1)
px = np.clip((puv[:, 0] % 1.0) * img.shape[1], 0, img.shape[1] - 1).astype(int)
py = np.clip((1.0 - puv[:, 1] % 1.0) * img.shape[0], 0, img.shape[0] - 1).astype(int)
pcol = img[py, px]
tree = cKDTree(pts)
# new atlas
atlas = xatlas.Atlas()
atlas.add_mesh(Vs, Fs.astype(np.uint32))
po = xatlas.PackOptions(); po.padding = 3; po.resolution = RES
atlas.generate(pack_options=po)
vmap, idx, uvs = atlas[0]
P = Vs[vmap]; N = Ns[vmap]
tex = np.zeros((RES, RES, 3), np.uint8); mask = np.zeros((RES, RES), bool)
for tri in idx:
    t = uvs[tri] * RES
    x0, y0 = np.floor(t.min(0)).astype(int) - 1; x1, y1 = np.ceil(t.max(0)).astype(int) + 1
    x0 = max(x0, 0); y0 = max(y0, 0); x1 = min(x1, RES - 1); y1 = min(y1, RES - 1)
    if x1 < x0 or y1 < y0: continue
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
    q = np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5], 1)
    a, b, c = t
    d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(d) < 1e-9: continue
    w0 = ((b[1] - c[1]) * (q[:, 0] - c[0]) + (c[0] - b[0]) * (q[:, 1] - c[1])) / d
    w1 = ((c[1] - a[1]) * (q[:, 0] - c[0]) + (a[0] - c[0]) * (q[:, 1] - c[1])) / d
    w2 = 1 - w0 - w1
    ok = (w0 > -0.6 / 1) & (w1 > -0.6) & (w2 > -0.6) if False else (np.minimum(np.minimum(w0, w1), w2) > -0.25)
    if not ok.any(): continue
    w = np.stack([w0, w1, w2], 1)[ok]
    pos = w @ P[tri]
    _, ni = tree.query(pos)
    tex[RES - 1 - q[ok][:, 1].astype(int), q[ok][:, 0].astype(int)] = pcol[ni]
    mask[RES - 1 - q[ok][:, 1].astype(int), q[ok][:, 0].astype(int)] = True
# dilate into the gutters
im = Image.fromarray(tex)
for _ in range(4):
    blur = np.asarray(im.filter(ImageFilter.MaxFilter(3)))
    arr = np.asarray(im).copy(); arr[~mask] = blur[~mask]
    mask = mask | (blur.sum(2) > 0)
    im = Image.fromarray(arr)
mat = trimesh.visual.material.PBRMaterial(baseColorTexture=im, metallicFactor=0.2, roughnessFactor=0.5)
out = trimesh.Trimesh(P, idx, vertex_normals=N, visual=trimesh.visual.TextureVisuals(uv=uvs, material=mat), process=False)
out.export(dst)
print(dst, len(Fw), '->', len(idx))
