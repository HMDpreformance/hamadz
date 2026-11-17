using System.Collections.Generic;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Finds where a car model's real lamp lenses are: the mesh vertices at the back whose texture colour is lens red
    /// (tail lamps) or at the front whose colour is bright clear glass (head lamps), grouped into one cluster per lamp.
    /// Result in the car's local space: centre and size of each lens. Measured once per model and cached.
    /// </summary>
    public static class LampFinder
    {
        public struct Lens { public Vector3 centre; public Vector2 size; }
        static readonly Dictionary<string, (List<Lens> tail, List<Lens> head)> cache = new Dictionary<string, (List<Lens>, List<Lens>)>();

        public static (List<Lens> tail, List<Lens> head) Find(string id, GameObject model, Transform carRoot, float length)
        {
            if (cache.TryGetValue(id, out var hit)) return hit;
            var tail = new List<Vector3>(); var head = new List<Vector3>();
            float minZ = float.MaxValue, maxZ = float.MinValue, maxY = float.MinValue;
            var meshes = new List<(Mesh m, Transform t, Color32[] px, int w, int h)>();
            foreach (var mf in model.GetComponentsInChildren<MeshFilter>())
            {
                var m = mf.sharedMesh; var r = mf.GetComponent<Renderer>();
                if (m == null || !m.isReadable || r == null) continue;
                var mat = r.sharedMaterial;
                Texture src = null;
                if (mat != null) foreach (var p in new[] { "baseColorTexture", "_BaseMap", "_MainTex" }) if (mat.HasProperty(p) && mat.GetTexture(p) != null) { src = mat.GetTexture(p); break; }
                if (src == null) continue;
                const int S = 512;
                var rt = RenderTexture.GetTemporary(S, S, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
                Graphics.Blit(src, rt);
                var prev = RenderTexture.active; RenderTexture.active = rt;
                var t = new Texture2D(S, S, TextureFormat.RGBA32, false);
                t.ReadPixels(new Rect(0, 0, S, S), 0, 0);
                RenderTexture.active = prev; RenderTexture.ReleaseTemporary(rt);
                meshes.Add((m, mf.transform, t.GetPixels32(), S, S));
                Object.Destroy(t);
                foreach (var v in m.vertices)
                {
                    var lp = carRoot.InverseTransformPoint(mf.transform.TransformPoint(v));
                    minZ = Mathf.Min(minZ, lp.z); maxZ = Mathf.Max(maxZ, lp.z); maxY = Mathf.Max(maxY, lp.y);
                }
            }
            foreach (var (m, tr, px, w, h) in meshes)
            {
                var verts = m.vertices; var uvs = m.uv;
                if (uvs == null || uvs.Length != verts.Length) continue;
                for (int i = 0; i < verts.Length; i++)
                {
                    var lp = carRoot.InverseTransformPoint(tr.TransformPoint(verts[i]));
                    if (lp.y < maxY * 0.25f) continue;
                    Vector2 uv = uvs[i];
                    int x = Mathf.Clamp((int)(Mathf.Repeat(uv.x, 1f) * w), 0, w - 1), y = Mathf.Clamp((int)(Mathf.Repeat(uv.y, 1f) * h), 0, h - 1);
                    Color c = px[y * w + x];
                    Color.RGBToHSV(c, out float hh, out float ss, out float vv);
                    bool red = (hh < 0.04f || hh > 0.95f) && ss > 0.55f && vv > 0.35f;
                    bool clear = ss < 0.2f && vv > 0.7f;
                    if (red && lp.z < minZ + length * 0.07f) tail.Add(lp);
                    if (clear && lp.z > maxZ - length * 0.1f && lp.y < maxY * 0.8f) head.Add(lp);
                }
            }
            var res = (Cluster(tail), Cluster(head));
            Debug.Log($"[HMD] lamps {id}: {res.Item1.Count} tail lenses, {res.Item2.Count} head lenses (from {tail.Count}/{head.Count} vertices)");
            foreach (var l in res.Item1) Debug.Log($"[HMD]   tail {l.centre} size {l.size}");
            foreach (var l in res.Item2) Debug.Log($"[HMD]   head {l.centre} size {l.size}");
            cache[id] = res;
            return res;
        }

        /// <summary>Groups points into lenses: split left/right, then by gaps over 6 cm along x or y.</summary>
        static List<Lens> Cluster(List<Vector3> pts)
        {
            var outL = new List<Lens>();
            if (pts.Count < 6) return outL;
            foreach (int side in new[] { -1, 1 })
            {
                var s = pts.FindAll(p => p.x * side > 0.05f);
                if (s.Count < 3) continue;
                s.Sort((a, b) => Mathf.Abs(a.x).CompareTo(Mathf.Abs(b.x)));
                var groups = new List<List<Vector3>> { new List<Vector3> { s[0] } };
                for (int i = 1; i < s.Count; i++)
                {
                    if (Mathf.Abs(s[i].x) - Mathf.Abs(s[i - 1].x) > 0.06f) groups.Add(new List<Vector3>());
                    groups[groups.Count - 1].Add(s[i]);
                }
                foreach (var g in groups)
                {
                    if (g.Count < 3) continue;
                    Vector3 mn = g[0], mx = g[0], sum = Vector3.zero;
                    foreach (var p in g) { mn = Vector3.Min(mn, p); mx = Vector3.Max(mx, p); sum += p; }
                    var size = new Vector2(mx.x - mn.x, mx.y - mn.y);
                    if (size.x < 0.03f || size.y < 0.03f) continue;
                    outL.Add(new Lens { centre = (mn + mx) * 0.5f, size = size });
                }
            }
            return outL;
        }
    }
}
