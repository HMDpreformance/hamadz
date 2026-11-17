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

        /// <summary>Plan units to metres (from the json). The map pictures cover 3200 x 2300 plan units.</summary>
        public float Scale = 0.75f;
        public class Road { public string name, cls; public float width; public List<Vector3> pts = new List<Vector3>(); }
        public readonly List<Road> roads = new List<Road>();
        /// <summary>Height of the sea surface (top of the water meshes; they have no collider).</summary>
        public static float WaterY = -999f;

        /// <summary>A safe place to put a car back: the right-hand lane of the nearest road (not a ramp), on the deck
        /// at that road's own height, facing along the road in the direction closest to <paramref name="heading"/>.</summary>
        public bool NearestLane(Vector3 p, Vector3 heading, out Vector3 pos, out Quaternion rot)
        {
            float best = float.MaxValue; Road br = null; int bi = 0;
            foreach (var rd in roads)
            {
                if (rd.cls == "ramp" || rd.pts.Count < 2) continue;
                for (int i = 0; i + 1 < rd.pts.Count; i++)
                {
                    var q = rd.pts[i]; float d = (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z);
                    if (d < best) { best = d; br = rd; bi = i; }
                }
            }
            pos = p; rot = Quaternion.identity;
            if (br == null) return false;
            var dir = br.pts[bi + 1] - br.pts[bi]; dir.y = 0; dir = dir.sqrMagnitude > 0.01f ? dir.normalized : Vector3.forward;
            heading.y = 0;
            if (heading.sqrMagnitude > 0.01f && Vector3.Dot(heading, dir) < 0) dir = -dir;
            var c = Vector3.Lerp(br.pts[bi], br.pts[bi + 1], 0.5f) + Vector3.Cross(Vector3.up, dir) * br.width * 0.25f;
            pos = Surface(c); rot = Quaternion.LookRotation(dir);
            return true;
        }
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
            // ground set (unity_assets/ground, Higgsfield, seamless): asphalt every 4 m, red/grey interlock pavers every
            // 6 m on the sidewalks (mesh UV 1 = 10 m). Night only: the ground shows through texture and local light, the
            // tints keep the road dark grey but clearly lighter than before and not navy.
            var gAsphalt = Res.Tex("Ground/asphalt");
            var asphalt = Res.TexMat("Tex/asphalt_04", Vector2.one * (10f / (gAsphalt ? 4f : 6f)), 0.45f, 0f, gAsphalt ? new Color(0.7f, 0.67f, 0.63f) : new Color(0.55f, 0.55f, 0.58f));   // a touch warm against the blue night
            if (gAsphalt) Res.SetMainTex(asphalt, gAsphalt, Vector2.one * (10f / 4f));
            Res.MakeWet(asphalt);
            var gPavers = Res.Tex("Ground/pavers");
            var walk = Res.TexMat("Tex/concrete_pavement", Vector2.one * (10f / (gPavers ? 6f : 3f)), 0.35f, 0f, gPavers ? new Color(0.86f, 0.78f, 0.7f) : new Color(0.7f, 0.68f, 0.66f));
            if (gPavers) Res.SetMainTex(walk, gPavers, Vector2.one * (10f / 6f));
            Res.MakeWet(walk);
            var concrete = Res.TexMat("Tex/concrete_panels", Vector2.one * (10f / 4f), 0.3f, 0f, new Color(0.62f, 0.62f, 0.64f));
            // the ground between the roads: was a plain dark sand colour that read as black at night (Hamad 2026-11-17:
            // "do something about the darkness, change the textures of the ground"). Now a light desert sand texture
            // (Higgsfield, seamless), tiled every 6 m by world position, with a little warm city spill light.
            var sandTex = Res.Tex("Ground/sand") ?? Res.Tex("Gen/ground_sand");
            var sand = Res.Mat(sandTex ? new Color(0.78f, 0.7f, 0.58f) : new Color(0.42f, 0.36f, 0.28f), 0.15f, 0f);
            if (sandTex) { Res.SetMainTex(sand, sandTex, Vector2.one); Res.SetEmission(sand, new Color(0.34f, 0.27f, 0.19f) * 0.55f, sandTex); }
            else Res.SetEmission(sand, new Color(0.3f, 0.24f, 0.16f) * 0.3f);
            var grassTex = Res.Tex("Ground/grass");
            var grass = Res.Mat(new Color(0.62f, 0.72f, 0.5f), 0.25f, 0f);
            if (grassTex) { Res.SetMainTex(grass, grassTex, Vector2.one); Res.SetEmission(grass, new Color(0.12f, 0.2f, 0.09f) * 0.95f, grassTex); }
            // sea: lighter blue and mirror-like (the wet-road shader at full wetness gives it the planar reflection)
            var water = Res.Mat(new Color(0.1f, 0.21f, 0.34f), 0.95f, 0f);
            Res.MakeWet(water);
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
                else if (n.Contains("grass"))
                {
                    // lawn verges behind the sidewalks (green districts): grass every 3 m, a dark night green with a small
                    // floor of light so it never reads black between the lamps; no collider (verges are not driven on)
                    m = grass; col = false;
                    WorldUV(mf, 3f);
                }
                else if (n.Contains("terrain"))
                {
                    m = sand;
                    WorldUV(mf, 6f);   // the generator writes no UVs for the terrain: one texture tile per 6 m
                }
                else if (n.Contains("water")) { m = water; col = false; if (r) WaterY = Mathf.Max(WaterY, r.bounds.max.y); }
                else if (n.Contains("barrier_red")) m = red;
                else if (n.Contains("barrier_white")) m = barrierW;
                if (m != null && r) r.sharedMaterial = m;
                if (col && mf.sharedMesh != null)
                {
                    var mc = mf.gameObject.AddComponent<MeshCollider>(); mc.sharedMesh = mf.sharedMesh;
                    // walls and barriers: the body glances off instead of grabbing and spinning (WheelColliders take their
                    // grip from their own friction curves, so driving on concrete decks is not affected)
                    if (n.Contains("concrete") || n.Contains("barrier")) mc.sharedMaterial = WallSlide;
                }
                Debug.Log($"[HMD] newcity mesh {mf.name}: {(m ? m.name : "?")} verts={mf.sharedMesh?.vertexCount} collider={col}");
            }
        }

        static PhysicsMaterial wallSlide;
        static PhysicsMaterial WallSlide => wallSlide ??= new PhysicsMaterial("WallSlide")
        { dynamicFriction = 0.08f, staticFriction = 0.08f, bounciness = 0.05f, frictionCombine = PhysicsMaterialCombine.Minimum, bounceCombine = PhysicsMaterialCombine.Minimum };

        /// <summary>Planar UVs from world x/z, one texture tile per 'metres' (meshes the generator writes without UVs).</summary>
        static void WorldUV(MeshFilter mf, float metres)
        {
            var tm = mf.sharedMesh;
            if (tm == null || !tm.isReadable) return;
            var v = tm.vertices; var uv = new Vector2[v.Length]; var tr = mf.transform;
            for (int i = 0; i < v.Length; i++) { var w = tr.TransformPoint(v[i]); uv[i] = new Vector2(w.x / metres, w.z / metres); }
            tm.uv = uv;
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
            var sc = Regex.Match(j, "\"scale\":([\\d.]+)");
            if (sc.Success) Scale = F(sc.Groups[1].Value);
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
