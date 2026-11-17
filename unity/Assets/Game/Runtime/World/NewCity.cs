using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Part 1 of the Dubai-shaped city (tools/build_city.py -> unity_assets/city/city_part1.glb + .json), used with
    /// -newcity. Loads the meshes, gives each its material (wet asphalt with reflections, paving, concrete, sand,
    /// water, road paint, barriers) and colliders, and reads the road centre lines from the json for the spawn
    /// point and the test drive. The grid city stays the default.
    /// </summary>
    public class NewCity : MonoBehaviour
    {
        public static NewCity I;
        public static bool Wanted => System.Environment.CommandLine.Contains("-newcity");

        public class Road { public string name, cls; public float width; public List<Vector3> pts = new List<Vector3>(); }
        public readonly List<Road> roads = new List<Road>();
        public Vector3 Garage { get; private set; }
        public Vector3 SpawnPos { get; private set; }
        public Quaternion SpawnRot { get; private set; }
        public readonly List<(string name, Vector3 pos)> districts = new List<(string, Vector3)>();
        public readonly List<Vector3> junctions = new List<Vector3>();
        public readonly List<(string road, Vector3 pos, float yaw)> blocks = new List<(string, Vector3, float)>();
        public Bounds MeshBounds { get; private set; }
        public bool Mirrored { get; private set; }

        public void Build()
        {
            I = this;
            ReadJson();
            var prefab = Res.Load<GameObject>("City/city_part1");
            if (prefab == null) { Debug.LogError("[HMD] newcity: City/city_part1 not imported"); return; }
            var go = Instantiate(prefab, transform);
            go.name = "CityPart1";
            go.transform.localPosition = Vector3.zero; go.transform.localRotation = Quaternion.identity; go.transform.localScale = Vector3.one;

            // glTF is right-handed: check the imported mesh lands on the json coordinates (x east 0..1400), mirror if not
            var rs = go.GetComponentsInChildren<Renderer>();
            Bounds b = rs[0].bounds; foreach (var r in rs) b.Encapsulate(r.bounds);
            if (b.center.x < 0)
            {
                go.transform.localScale = new Vector3(-1, 1, 1);
                Mirrored = true;
                b = rs[0].bounds; foreach (var r in rs) b.Encapsulate(r.bounds);
            }
            if (b.center.z < 0 && b.center.x > 0)
            {
                go.transform.localScale = Vector3.Scale(go.transform.localScale, new Vector3(1, 1, -1));
                Mirrored = true;
                b = rs[0].bounds; foreach (var r in rs) b.Encapsulate(r.bounds);
            }
            MeshBounds = b;
            Debug.Log($"[HMD] newcity: mesh bounds {b.min} .. {b.max}, mirrored={Mirrored}, roads={roads.Count}, garage={Garage}");

            Materials(go);
            FindSpawn();
            Lamps();
        }

        void Materials(GameObject go)
        {
            var asphalt = Res.TexMat("Tex/asphalt_04", Vector2.one * (10f / 6f), 0.45f, 0f, new Color(0.55f, 0.55f, 0.58f));
            Res.MakeWet(asphalt);
            var walk = Res.TexMat("Tex/concrete_pavement", Vector2.one * (10f / 3f), 0.35f, 0f, new Color(0.7f, 0.68f, 0.66f));
            Res.MakeWet(walk);
            var concrete = Res.TexMat("Tex/concrete_panels", Vector2.one * (10f / 4f), 0.3f, 0f, new Color(0.62f, 0.62f, 0.64f));
            var sand = Res.Mat(new Color(0.26f, 0.22f, 0.17f), 0.12f, 0f);   // plain dark sand, no stone pattern
            var water = Res.Mat(new Color(0.01f, 0.03f, 0.06f), 0.96f, 0.4f);
            var white = Res.Mat(new Color(0.85f, 0.85f, 0.82f), 0.55f); Res.MakeWet(white);
            var yellow = Res.Mat(new Color(0.9f, 0.7f, 0.1f), 0.55f); Res.MakeWet(yellow);
            var red = Res.Mat(new Color(0.75f, 0.06f, 0.05f), 0.5f, 0.1f);
            var barrierW = Res.Mat(new Color(0.85f, 0.86f, 0.88f), 0.5f, 0.1f);
            foreach (var mf in go.GetComponentsInChildren<MeshFilter>())
            {
                var r = mf.GetComponent<MeshRenderer>();
                string n = (mf.name + " " + (r && r.sharedMaterial ? r.sharedMaterial.name : "")).ToLowerInvariant();
                Material m = null; bool col = true;
                if (n.Contains("asphalt")) m = asphalt;
                else if (n.Contains("sidewalk")) m = walk;
                else if (n.Contains("marking_white")) { m = white; col = false; }
                else if (n.Contains("marking_yellow")) { m = yellow; col = false; }
                else if (n.Contains("concrete")) m = concrete;
                else if (n.Contains("terrain")) m = sand;
                else if (n.Contains("water")) { m = water; col = false; }
                else if (n.Contains("barrier_red")) m = red;
                else if (n.Contains("barrier_white")) m = barrierW;
                if (m != null && r) r.sharedMaterial = m;
                if (col && mf.sharedMesh != null) mf.gameObject.AddComponent<MeshCollider>().sharedMesh = mf.sharedMesh;
                Debug.Log($"[HMD] newcity mesh {mf.name}: {(m ? m.name : "?")} verts={mf.sharedMesh?.vertexCount} collider={col}");
            }
        }

        public readonly List<Vector3> lampHeads = new List<Vector3>();

        /// <summary>Street lamp heads along the roads (both sides, every ~36 m, 8 m up), lit near the camera by LampLights.</summary>
        void Lamps()
        {
            foreach (var rd in roads)
            {
                if (rd.cls == "ramp") continue;
                float acc = 0;
                for (int i = 1; i < rd.pts.Count; i++)
                {
                    var seg = rd.pts[i] - rd.pts[i - 1];
                    acc += seg.magnitude;
                    if (acc < 36f) continue;
                    acc = 0;
                    var d = new Vector3(seg.x, 0, seg.z).normalized;
                    var side = Vector3.Cross(Vector3.up, d);
                    for (int s = -1; s <= 1; s += 2)
                        lampHeads.Add(rd.pts[i] + side * s * (rd.width * 0.5f + 0.6f) + Vector3.up * 8f);
                }
            }
            Debug.Log($"[HMD] newcity: {lampHeads.Count} street lamps");
        }

        void FindSpawn()
        {
            // nearest road point to the garage, facing along the road, set on the surface
            float best = float.MaxValue; Vector3 p = Garage, dir = Vector3.forward;
            foreach (var rd in roads)
                for (int i = 0; i + 1 < rd.pts.Count; i++)
                {
                    float d = (rd.pts[i] - Garage).sqrMagnitude;
                    if (d < best) { best = d; p = rd.pts[i]; dir = rd.pts[i + 1] - rd.pts[i]; }
                }
            dir.y = 0;
            SpawnPos = Surface(p) + Vector3.up * 0.6f;
            SpawnRot = Quaternion.LookRotation(dir.sqrMagnitude > 0.01f ? dir.normalized : Vector3.forward);
        }

        /// <summary>The top surface under a point (or the point itself if nothing is hit).</summary>
        public static Vector3 Surface(Vector3 p)
        {
            // from just above the point: under a flyover this finds the lower road, not the deck above
            if (Physics.Raycast(new Vector3(p.x, p.y + 2.5f, p.z), Vector3.down, out var hit, 30f)) return hit.point;
            if (Physics.Raycast(new Vector3(p.x, p.y + 40f, p.z), Vector3.down, out hit, 120f)) return hit.point;
            return p;
        }

        // ---------------------------------------------------------------- json (nested arrays: parsed by hand)
        static float F(string s) => float.Parse(s, CultureInfo.InvariantCulture);

        void ReadJson()
        {
            var ta = Res.Load<TextAsset>("City/city_part1");
            if (ta == null) { Debug.LogError("[HMD] newcity: city_part1.json not imported"); return; }
            string j = ta.text;
            var g = Regex.Match(j, "\"garage\":\\{\"x\":([-\\d.]+),\"z\":([-\\d.]+),\"y\":([-\\d.]+)\\}");
            if (g.Success) Garage = new Vector3(F(g.Groups[1].Value), F(g.Groups[3].Value), F(g.Groups[2].Value));
            foreach (Match m in Regex.Matches(j, "\\{\"name\":\"([^\"]+)\",\"cls\":\"([a-z_]+)\",\"width\":([-\\d.]+),\"pts\":\\[(.*?)\\]\\]"))
            {
                var rd = new Road { name = m.Groups[1].Value, cls = m.Groups[2].Value, width = F(m.Groups[3].Value) };
                foreach (Match q in Regex.Matches(m.Groups[4].Value + "]", "\\[([-\\d.]+),([-\\d.]+),([-\\d.]+)\\]"))
                    rd.pts.Add(new Vector3(F(q.Groups[1].Value), F(q.Groups[2].Value), F(q.Groups[3].Value)));
                roads.Add(rd);
            }
            foreach (Match m in Regex.Matches(j, "\\{\"name\":\"([^\"]+)\",\"x\":([-\\d.]+),\"z\":([-\\d.]+)\\}"))
                districts.Add((m.Groups[1].Value, new Vector3(F(m.Groups[2].Value), 0, F(m.Groups[3].Value))));
            foreach (Match m in Regex.Matches(j, "\\{\"x\":([-\\d.]+),\"z\":([-\\d.]+),\"y\":([-\\d.]+),\"yaw\":([-\\d.]+),\"width\":([-\\d.]+),\"road\":\"([^\"]+)\"\\}"))
                blocks.Add((m.Groups[6].Value, new Vector3(F(m.Groups[1].Value), F(m.Groups[3].Value), F(m.Groups[2].Value)), F(m.Groups[4].Value)));
            foreach (Match m in Regex.Matches(j, @"\{""x"":([-\d.]+),""z"":([-\d.]+),""y"":([-\d.]+),""r"":([-\d.]+),""roads"""))
                junctions.Add(new Vector3(F(m.Groups[1].Value), F(m.Groups[3].Value), F(m.Groups[2].Value)));
            Debug.Log($"[HMD] newcity json: {roads.Count} roads, {districts.Count} districts, {blocks.Count} road blocks");
        }

        public Road Find(string name) => roads.Find(r => r.name == name);
    }
}
