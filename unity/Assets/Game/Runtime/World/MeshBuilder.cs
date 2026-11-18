using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace HMD
{
    /// <summary>Small mesh-building helper: boxes with world-scaled UVs, lathes, quads. Several sub-meshes per mesh.</summary>
    public class MeshBuilder
    {
        readonly List<Vector3> v = new List<Vector3>();
        readonly List<Vector3> n = new List<Vector3>();
        readonly List<Vector2> uv = new List<Vector2>();
        readonly List<List<int>> subs = new List<List<int>>();
        int cur;

        public MeshBuilder(int submeshes = 1)
        {
            for (int i = 0; i < submeshes; i++) subs.Add(new List<int>());
        }

        public MeshBuilder Sub(int i) { while (subs.Count <= i) subs.Add(new List<int>()); cur = i; return this; }
        public int VertexCount => v.Count;

        /// <summary>A quad from 4 corners (counter-clockwise seen from the front), UVs in metres / uvScale.</summary>
        public void Quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, float uvScale = 1f, Vector2? uvOffset = null)
        {
            Vector3 normal = Vector3.Cross(d - a, b - a).normalized;
            float w = (b - a).magnitude, h = (d - a).magnitude;
            Vector2 o = uvOffset ?? Vector2.zero;
            QuadUV(a, b, c, d, normal, o, o + new Vector2(w / uvScale, 0), o + new Vector2(w / uvScale, h / uvScale), o + new Vector2(0, h / uvScale));
        }

        public void QuadUV(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 normal, Vector2 ua, Vector2 ub, Vector2 uc, Vector2 ud)
        {
            int i = v.Count;
            v.Add(a); v.Add(b); v.Add(c); v.Add(d);
            n.Add(normal); n.Add(normal); n.Add(normal); n.Add(normal);
            uv.Add(ua); uv.Add(ub); uv.Add(uc); uv.Add(ud);
            var t = subs[cur];
            // Unity is clockwise-front: a,d,c / a,c,b
            t.Add(i); t.Add(i + 3); t.Add(i + 2);
            t.Add(i); t.Add(i + 2); t.Add(i + 1);
        }

        /// <summary>Axis-aligned box. uvScale = metres per texture repeat. skipBottom saves triangles for things on the ground.</summary>
        public void Box(Vector3 center, Vector3 size, float uvScale = 1f, bool skipBottom = true, bool skipTop = false)
        {
            Vector3 h = size * 0.5f;
            Vector3 c = center;
            Vector3 p000 = c + new Vector3(-h.x, -h.y, -h.z), p100 = c + new Vector3(h.x, -h.y, -h.z);
            Vector3 p010 = c + new Vector3(-h.x, h.y, -h.z), p110 = c + new Vector3(h.x, h.y, -h.z);
            Vector3 p001 = c + new Vector3(-h.x, -h.y, h.z), p101 = c + new Vector3(h.x, -h.y, h.z);
            Vector3 p011 = c + new Vector3(-h.x, h.y, h.z), p111 = c + new Vector3(h.x, h.y, h.z);
            Quad(p000, p100, p110, p010, uvScale);  // -Z face (front, facing -Z)
            Quad(p101, p001, p011, p111, uvScale);  // +Z
            Quad(p001, p000, p010, p011, uvScale);  // -X
            Quad(p100, p101, p111, p110, uvScale);  // +X
            if (!skipTop) Quad(p010, p110, p111, p011, uvScale);
            if (!skipBottom) Quad(p001, p101, p100, p000, uvScale);
        }

        /// <summary>A box face only (for facades): a vertical wall from a to b (bottom edge), height h, facing out to the right of a→b.</summary>
        public void Wall(Vector3 a, Vector3 b, float h, Vector2 uvMetres, Vector2 uvOffset = default)
        {
            Vector3 up = Vector3.up * h;
            float w = (b - a).magnitude;
            Vector3 nrm = Vector3.Cross(Vector3.up, (b - a).normalized);
            QuadUV(a, b, b + up, a + up, nrm,
                uvOffset, uvOffset + new Vector2(w / uvMetres.x, 0),
                uvOffset + new Vector2(w / uvMetres.x, h / uvMetres.y), uvOffset + new Vector2(0, h / uvMetres.y));
        }

        /// <summary>Revolve a (radius, x) profile around the X axis. Profile points: (x offset, radius).</summary>
        public void Lathe(Vector2[] profile, int segments, Vector3 center, bool smooth = true)
        {
            for (int s = 0; s < segments; s++)
            {
                float a0 = s * Mathf.PI * 2 / segments, a1 = (s + 1) * Mathf.PI * 2 / segments;
                for (int k = 0; k < profile.Length - 1; k++)
                {
                    Vector2 p0 = profile[k], p1 = profile[k + 1];
                    Vector3 A = center + new Vector3(p0.x, Mathf.Cos(a0) * p0.y, Mathf.Sin(a0) * p0.y);
                    Vector3 B = center + new Vector3(p0.x, Mathf.Cos(a1) * p0.y, Mathf.Sin(a1) * p0.y);
                    Vector3 C = center + new Vector3(p1.x, Mathf.Cos(a1) * p1.y, Mathf.Sin(a1) * p1.y);
                    Vector3 D = center + new Vector3(p1.x, Mathf.Cos(a0) * p1.y, Mathf.Sin(a0) * p1.y);
                    int i = v.Count;
                    v.Add(A); v.Add(B); v.Add(C); v.Add(D);
                    // profile walks around the cross-section with the outside on its left: normal = left of dir
                    Vector2 dir = (p1 - p0).normalized;
                    Vector2 pn = new Vector2(-dir.y, dir.x);
                    Vector3 nA = new Vector3(pn.x, Mathf.Cos(a0) * pn.y, Mathf.Sin(a0) * pn.y).normalized;
                    Vector3 nB = new Vector3(pn.x, Mathf.Cos(a1) * pn.y, Mathf.Sin(a1) * pn.y).normalized;
                    Vector3 fn = Vector3.Cross(B - A, C - A);
                    if (fn.sqrMagnitude < 1e-12f) fn = Vector3.Cross(C - A, D - A);
                    bool flip = Vector3.Dot(fn, nA + nB) < 0;
                    if (!smooth) { Vector3 f = (flip ? -fn : fn).normalized; nA = f; nB = f; }
                    n.Add(nA); n.Add(nB); n.Add(nB); n.Add(nA);
                    float u0 = (float)s / segments, u1 = (float)(s + 1) / segments;
                    uv.Add(new Vector2(u0, k)); uv.Add(new Vector2(u1, k)); uv.Add(new Vector2(u1, k + 1)); uv.Add(new Vector2(u0, k + 1));
                    var t = subs[cur];
                    if (!flip) { t.Add(i); t.Add(i + 1); t.Add(i + 2); t.Add(i); t.Add(i + 2); t.Add(i + 3); }
                    else { t.Add(i); t.Add(i + 2); t.Add(i + 1); t.Add(i); t.Add(i + 3); t.Add(i + 2); }
                }
            }
        }

        /// <summary>Flat disc facing +X or -X (sign), around the X axis.</summary>
        public void Disc(Vector3 center, float r, int segments, float sign)
        {
            int c0 = v.Count;
            v.Add(center); n.Add(new Vector3(sign, 0, 0)); uv.Add(new Vector2(0.5f, 0.5f));
            for (int s = 0; s <= segments; s++)
            {
                float a = s * Mathf.PI * 2 / segments;
                v.Add(center + new Vector3(0, Mathf.Cos(a) * r, Mathf.Sin(a) * r));
                n.Add(new Vector3(sign, 0, 0));
                uv.Add(new Vector2(0.5f + Mathf.Cos(a) * 0.5f, 0.5f + Mathf.Sin(a) * 0.5f));
            }
            var t = subs[cur];
            for (int s = 0; s < segments; s++)
            {
                if (sign > 0) { t.Add(c0); t.Add(c0 + 1 + s); t.Add(c0 + 2 + s); }
                else { t.Add(c0); t.Add(c0 + 2 + s); t.Add(c0 + 1 + s); }
            }
        }

        /// <summary>Add another mesh's triangles transformed (for batching props into one mesh).</summary>
        public void Add(Mesh m, Matrix4x4 xf, int sub = -1)
        {
            var mv = m.vertices; var mn = m.normals; var mu = m.uv;
            int baseI = v.Count;
            for (int i = 0; i < mv.Length; i++)
            {
                v.Add(xf.MultiplyPoint3x4(mv[i]));
                n.Add(mn.Length > i ? xf.MultiplyVector(mn[i]).normalized : Vector3.up);
                uv.Add(mu.Length > i ? mu[i] : Vector2.zero);
            }
            for (int s = 0; s < m.subMeshCount; s++)
            {
                var tris = m.GetTriangles(s);
                var t = subs[sub >= 0 ? sub : Mathf.Min(s, subs.Count - 1)];
                foreach (var i in tris) t.Add(baseI + i);
            }
        }

        public Mesh Build(string name = "mesh")
        {
            var m = new Mesh { name = name };
            if (v.Count > 65000) m.indexFormat = IndexFormat.UInt32;
            m.SetVertices(v);
            m.SetNormals(n);
            m.SetUVs(0, uv);
            m.subMeshCount = subs.Count;
            for (int i = 0; i < subs.Count; i++) m.SetTriangles(subs[i], i);
            m.RecalculateBounds();
            m.RecalculateTangents();
            return m;
        }

        public static GameObject Spawn(string name, Mesh mesh, Material[] mats, Transform parent, bool collider = false, bool shadows = true)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            mats = DropEmptySubmeshes(mesh, mats);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterials = mats;
            mr.shadowCastingMode = shadows ? ShadowCastingMode.On : ShadowCastingMode.Off;
            if (collider) go.AddComponent<MeshCollider>().sharedMesh = mesh;
            return go;
        }

        // which original slots each compacted mesh kept (a mesh can be spawned more than once)
        static readonly System.Collections.Generic.Dictionary<Mesh, int[]> kept = new System.Collections.Generic.Dictionary<Mesh, int[]>();

        /// <summary>
        /// City cells are built with one submesh per material slot (51), but each cell uses only a few. Every empty slot still
        /// cost a draw call: 93% of all submeshes were empty, and Business Bay drew about 1900 times a frame instead of under 600.
        /// Keeps only the submeshes that have triangles, with their materials.
        /// </summary>
        public static Material[] DropEmptySubmeshes(Mesh mesh, Material[] mats)
        {
            if (mesh == null || mats == null) return mats;
            if (!kept.TryGetValue(mesh, out var keep))
            {
                if (mesh.subMeshCount < 2) return mats;
                var k = new System.Collections.Generic.List<int>();
                for (int s = 0; s < mesh.subMeshCount; s++) if (mesh.GetSubMesh(s).indexCount > 0) k.Add(s);
                if (k.Count == mesh.subMeshCount || k.Count == 0) return mats;
                keep = k.ToArray();
                var idx = new int[keep.Length][]; var top = new MeshTopology[keep.Length];
                for (int i = 0; i < keep.Length; i++) { idx[i] = mesh.GetIndices(keep[i]); top[i] = mesh.GetTopology(keep[i]); }
                var b = mesh.bounds;
                mesh.subMeshCount = keep.Length;
                for (int i = 0; i < keep.Length; i++) mesh.SetIndices(idx[i], top[i], i, false);
                mesh.bounds = b;
                kept[mesh] = keep;
            }
            var nm = new Material[keep.Length];
            for (int i = 0; i < keep.Length; i++) nm[i] = keep[i] < mats.Length ? mats[keep[i]] : null;
            return nm;
        }

        public static GameObject Cube(string name, Transform parent, Vector3 pos, Vector3 size, Material mat, bool collider = false)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = name;
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = size;
            go.GetComponent<Renderer>().sharedMaterial = mat;
            if (!collider) Object.Destroy(go.GetComponent<Collider>());
            return go;
        }
    }
}
