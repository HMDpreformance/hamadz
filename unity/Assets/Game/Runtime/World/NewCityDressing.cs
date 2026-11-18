using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// What stands beside the roads of the new city, from city_part1.json: building lots by Dubai district style
    /// (glass towers, Marina residential towers, JBR beige towers, Al Barsha midrise, villas, Al Quoz warehouses),
    /// the landmarks (needle tower, sail hotel, arch hotel, big wheel, twisted tower, ski mall), street and highway
    /// lamps and palms/trees. Everything is merged into a few meshes per 320 m cell and material, so it stays fast.
    /// </summary>
    public class NewCityDressing : MonoBehaviour
    {
        struct Lot { public Vector3 p; public float w, d, h, yaw; public string style; public bool shops; }
        struct Mark { public string kind; public Vector3 p; public float w, d, h; }
        readonly List<Lot> lots = new List<Lot>();
        readonly List<Mark> marks = new List<Mark>();
        readonly List<(Vector3 p, float yaw, bool highway)> lamps = new List<(Vector3, float, bool)>();
        readonly List<(Vector3 p, bool palm, float s)> trees = new List<(Vector3, bool, float)>();
        public readonly List<Vector3> lampHeads = new List<Vector3>();
        public readonly List<bool> lampCool = new List<bool>();   // per lamp head: true = highway LED (cool white)
        System.Random rng = new System.Random(21);
        float R() => (float)rng.NextDouble();

        // materials (slots in the per-cell builders)
        Material[] mats;
        const int M_TOWER0 = 0;          // 0..5 tower skins (office, resi, black, hotel, fins, stone)
        const int M_FAC0 = 6;            // 6..13 facades (midrise)
        const int M_STUCCO = 14, M_SAND = 15, M_CORR = 16, M_SHUTTER = 17, M_ROOF = 18, M_SHOP = 19, M_ROOMS = 20,
                  M_LED_W = 21, M_LED_B = 22, M_LED_P = 23, M_LED_G = 24, M_RED = 25, M_POLE = 26, M_LAMP = 27,
                  M_BARK = 28, M_LEAF = 29, M_TREE = 30, M_GLASS = 31, M_WALL = 32, M_SIGN0 = 33, M_SHORE = 37, M_LAND = 38, M_SHALLOW = 39, M_ARCH = 40, M_LAMP_LED = 41, M_SIGN_GREEN = 42, M_SIGN_WHITE = 43, M_STEEL = 44,
                  M_PLOT_SAND = 45, M_PLOT_CONC = 46, M_PLOT_TILE = 47, M_POOL = 48, M_POOL_COOL = 49, M_METRO = 50, M_COUNT = 51;
        float[] towerTile = { 34f, 30f, 44f, 26f, 38f, 24f };

        public void Build(NewCity nc)
        {
            var ta = Res.Load<TextAsset>("City/city_part1");
            if (ta == null) return;
            DistanceCuller.Ensure(transform);   // phones: far small things are not drawn
            Parse(ta.text);
            MakeMaterials();
            var cells = new Dictionary<Vector2Int, MeshBuilder>();
            MeshBuilder Cell(Vector3 p)
            {
                var k = new Vector2Int(Mathf.FloorToInt(p.x / 320f), Mathf.FloorToInt(p.z / 320f));
                if (!cells.TryGetValue(k, out var b)) { b = new MeshBuilder(M_COUNT); cells[k] = b; }
                return b;
            }
            // keep the LSX building (door at json.garage, building +Z of the door, 34 x 26 m) clear of lots
            Vector3 g = nc.Garage;
            int skipped = 0, onRoad = 0;
            Physics.SyncTransforms();
            // around LSX: an industrial car district (sheds with roller doors, tyre and parts signs)
            for (int i = 0; i < lots.Count; i++)
            {
                var l0 = lots[i];
                if ((new Vector2(l0.p.x - g.x, l0.p.z - g.z)).magnitude < 200f * (nc.Scale / 0.75f) && l0.style != "warehouse" && !l0.style.StartsWith("tower"))
                { l0.style = "warehouse"; l0.h = Mathf.Clamp(l0.h, 7f, 12f); l0.shops = true; lots[i] = l0; }
                else if ((new Vector2(l0.p.x - g.x, l0.p.z - g.z)).magnitude < 200f * (nc.Scale / 0.75f) && l0.style == "warehouse") { l0.shops = true; lots[i] = l0; }
            }
            LoadModels();
            int modelled = 0;
            foreach (var l in lots)
            {
                float rr = Mathf.Max(l.w, l.d) * 0.5f;
                if (l.p.x + rr > g.x - 19f && l.p.x - rr < g.x + 19f && l.p.z + rr > g.z - 14f && l.p.z - rr < g.z + 30f) { skipped++; continue; }
                if (OnRoad(l)) { onRoad++; continue; }
                Plot(l);
                if (PlaceModel(l)) { modelled++; continue; }
                Building(Cell(l.p), l);
            }
            foreach (var kv in plots)
            {
                var pg = MeshBuilder.Spawn("Plots_" + kv.Key.x + "_" + kv.Key.y, kv.Value.Build("plots"), mats, transform, false, false); pg.isStatic = true;
                DistanceCuller.Add(pg, CellCentre(kv.Key), DistanceCuller.Street + 230f);   // a 320 m cell: centre + half diagonal
            }
            if (models.Count > 0) Debug.Log($"[HMD] building models: {models.Count} loaded, {modelled} lots use a model, the rest keep the box");
            Landmarks.Clear(); foreach (var m in marks) Landmarks.Add((m.kind, m.p, m.h));
            LoadLandmarkModels();
            int lmModels = 0;
            foreach (var m in marks) { if (PlaceLandmark(nc, m)) lmModels++; else Landmark(Cell(m.p), m); }
            if (landmarkModels.Count > 0) Debug.Log($"[HMD] landmark models: {lmModels} of {marks.Count} landmarks use a model");
            // lamps and trees in their own meshes without colliders (thin poles must never stop the car)
            var props = new Dictionary<Vector2Int, MeshBuilder>();
            MeshBuilder Prop(Vector3 p)
            {
                var k = new Vector2Int(Mathf.FloorToInt(p.x / 320f), Mathf.FloorToInt(p.z / 320f));
                if (!props.TryGetValue(k, out var b)) { b = new MeshBuilder(M_COUNT); props[k] = b; }
                return b;
            }
            foreach (var lp in lamps) Lamp(Prop(lp.p), lp.p, lp.yaw, lp.highway);
            LoadTreeModels();
            int treeModels = 0;
            foreach (var t in trees)
            {
                if (t.palm && PlaceTree(t.p, t.s)) { treeModels++; continue; }
                if (t.palm) Palm(Prop(t.p), t.p, t.s); else Tree(Prop(t.p), t.p, t.s);
            }
            if (palmModels.Count > 0) Debug.Log($"[HMD] palm models: {palmModels.Count} loaded, {treeModels} palms placed as models");
            PalmShores(nc, Prop);
            // green overhead sign gantries across the highways, and the elevated metro beside the E11
            foreach (var gt in gantries) Gantry(Prop(gt.p), gt.p, gt.yaw, gt.width);
            foreach (var mt in metros) Metro(mt, Cell, Prop);
            if (gantries.Count > 0 || metros.Count > 0) Debug.Log($"[HMD] gantries {gantries.Count}, metro lines {metros.Count}");
            foreach (var kv in props)
            {
                var pg = MeshBuilder.Spawn("Props_" + kv.Key.x + "_" + kv.Key.y, kv.Value.Build("props"), mats, transform, false, false); pg.isStatic = true;
                DistanceCuller.Add(pg, CellCentre(kv.Key), DistanceCuller.Street + 230f);   // lamps, light pools, gantries, metro deck
            }
            int n = 0;
            foreach (var kv in cells)
            {
                var go = MeshBuilder.Spawn("Dress_" + kv.Key.x + "_" + kv.Key.y, kv.Value.Build("dress"), mats, transform, true, true);
                go.isStatic = true; n++;
            }
            Debug.Log($"[HMD] newcity dressing: {lots.Count - skipped - onRoad} buildings ({skipped} cleared for LSX, {onRoad} skipped: footprint on a road or pavement), {marks.Count} landmarks, {lamps.Count} lamps, {trees.Count} trees, {n} cells");
        }

        /// <summary>True when the footprint (corners, edge middles and centre, 1 m in) lies over asphalt or pavement.</summary>
        static bool OnRoad(Lot l)
        {
            var q = Quaternion.Euler(0, l.yaw, 0);
            float hx = Mathf.Max(0.5f, l.w * 0.5f - 1f), hz = Mathf.Max(0.5f, l.d * 0.5f - 1f);
            if (l.style == "villa") { hx = l.w * 0.3f; hz = l.d * 0.28f; }   // villas use the middle of the lot
            for (int ix = -1; ix <= 1; ix++)
                for (int iz = -1; iz <= 1; iz++)
                {
                    Vector3 p = l.p + q * new Vector3(ix * hx, 0, iz * hz);
                    if (Physics.Raycast(p + Vector3.up * 30f, Vector3.down, out var hit, 60f))
                    {
                        string n = hit.collider.name.ToLowerInvariant();
                        if (n.Contains("asphalt") || n.Contains("sidewalk")) return true;
                    }
                }
            return false;
        }

        public static readonly List<(string kind, Vector3 p, float h)> Landmarks = new List<(string, Vector3, float)>();

        /// <summary>Makes the Palm readable at night like a night photo of the real island: warm sand land along the
        /// trunk, fronds and crescent, a wide bright shore with a turquoise shallow-water edge, promenade lamps, two
        /// rows of small lit villas on every frond and lit apartment blocks along the trunk.</summary>
        void PalmShores(NewCity nc, System.Func<Vector3, MeshBuilder> prop)
        {
            int lampsAdded = 0, villas = 0, blocks = 0;
            foreach (var rd in nc.roads)
            {
                bool frond = rd.name == "Frond", cres = rd.name == "Crescent", trunk = rd.name == "Palm Trunk";
                if (!frond && !cres && !trunk) continue;
                float edge = rd.width * 0.5f;                 // road edge
                float land = (trunk ? 22f : 11.5f) * (nc.Scale / 0.75f);   // land beyond the road edge (scales with the plan)
                float acc = 0, accV = 0, accB = 0;
                for (int i = 1; i < rd.pts.Count; i++)
                {
                    Vector3 a = rd.pts[i - 1], c = rd.pts[i];
                    Vector3 d = c - a; d.y = 0; float len = d.magnitude; if (len < 0.1f) continue; d /= len;
                    Vector3 side = Vector3.Cross(Vector3.up, d);
                    for (int s = -1; s <= 1; s += 2)
                    {
                        var b = prop(a);
                        // bands from the road edge outwards: sand land (flat), bright shore (6 m, sloping), turquoise shallows (6 m, at sea level)
                        Band(b, M_LAND, a, c, side * s, edge + 0.3f, edge + land, 0.08f, 0.08f, len);
                        Band(b, M_SHORE, a, c, side * s, edge + land, edge + land + 6f, 0.08f, -1.0f, len);
                        Band(b, M_SHALLOW, a, c, side * s, edge + land + 6f, edge + land + 12f, -1.0f, -1.3f, len);
                    }
                    acc += len; accV += len; accB += len;
                    if (acc >= 26f)
                    {
                        acc = 0;
                        for (int s = -1; s <= 1; s += 2)
                        {
                            Vector3 p = c + side * s * (edge + land - 0.8f);
                            var b = prop(p);
                            RBox(b, M_POLE, p, new Vector3(0.14f, 3.2f, 0.14f), 0, Vector2.one);
                            RBox(b, M_LAMP, p + Vector3.up * 3.2f, new Vector3(0.35f, 0.35f, 0.35f), 0, Vector2.one);
                            lampHeads.Add(p + Vector3.up * 3.4f); lampCool.Add(false);
                            lampsAdded++;
                        }
                    }
                    // villas: two rows (both sides) every ~20 m on fronds and the crescent, 9 x 8 m, set back from the road
                    if ((frond || cres) && accV >= 20f)
                    {
                        accV = 0;
                        for (int s = -1; s <= 1; s += 2)
                        {
                            Vector3 p = c + side * s * (edge + 1.5f + 4.2f);
                            if (Physics.Raycast(p + Vector3.up * 20f, Vector3.down, out var hit, 40f) && hit.collider.name.ToLowerInvariant().Contains("asphalt")) continue;
                            float yaw = Quaternion.LookRotation(-side * s).eulerAngles.y;   // front faces the road
                            SmallVilla(prop(p), new Vector3(p.x, a.y + 0.08f, p.z), yaw);
                            villas++;
                        }
                    }
                    // apartment blocks along the trunk every ~55 m
                    if (trunk && accB >= 55f)
                    {
                        accB = 0;
                        for (int s = -1; s <= 1; s += 2)
                        {
                            Vector3 p = c + side * s * (edge + 10f);
                            var b = prop(p);
                            float yaw = Quaternion.LookRotation(-side * s).eulerAngles.y;
                            RBox(b, M_SAND, new Vector3(p.x, a.y - 1f, p.z), new Vector3(16f, 23f, 13f), yaw, new Vector2(4, 4));
                            for (int f = 0; f < 6; f++)
                                Face(b, M_ROOMS, new Vector3(p.x, a.y + 1.5f + f * 3.4f, p.z), yaw, 6.5f, -7f, 7f, 0f, 1.6f, new Vector2(14f, 2.2f));
                            RBox(b, M_LED_G, new Vector3(p.x, a.y + 21.6f, p.z), new Vector3(16.3f, 0.35f, 13.3f), yaw, Vector2.one, false);
                            blocks++;
                        }
                    }
                }
            }
            Debug.Log($"[HMD] palm: {lampsAdded} promenade lamps, {villas} villas, {blocks} trunk blocks");
        }

        /// <summary>A flat band parallel to a road segment, from distance d0 to d1 along 'side', heights y0 (inner) to y1 (outer).</summary>
        static void Band(MeshBuilder b, int sub, Vector3 a, Vector3 c, Vector3 side, float d0, float d1, float y0, float y1, float len)
        {
            Vector3 a0 = a + side * d0 + Vector3.up * y0, c0 = c + side * d0 + Vector3.up * y0;
            Vector3 a1 = a + side * d1 + Vector3.up * y1, c1 = c + side * d1 + Vector3.up * y1;
            a0.y = a.y + y0; c0.y = c.y + y0; a1.y = Mathf.Min(a.y + y1, a.y + y0); c1.y = Mathf.Min(c.y + y1, c.y + y0);
            Vector2 u0 = new Vector2(0, 0), u1 = new Vector2(len / 4f, 0), u2 = new Vector2(len / 4f, 1), u3 = new Vector2(0, 1);
            // keep the quad facing up whichever side it is on
            if (Vector3.Dot(Vector3.Cross(c0 - a0, a1 - a0), Vector3.up) < 0) b.Sub(sub).QuadUV(a0, c0, c1, a1, Vector3.up, u0, u1, u2, u3);
            else b.Sub(sub).QuadUV(c0, a0, a1, c1, Vector3.up, u1, u0, u3, u2);
        }

        void SmallVilla(MeshBuilder b, Vector3 p, float yaw)
        {
            int m = R() < 0.6f ? M_STUCCO : M_SAND;
            RBox(b, m, p - Vector3.up * 1f, new Vector3(9f, 6.5f, 8f), yaw, new Vector2(4, 4));
            RBox(b, m, p + Vector3.up * 5.5f, new Vector3(5.5f, 2.8f, 5f), yaw, new Vector2(4, 4));
            Face(b, M_ROOMS, p + Vector3.up * 0.8f, yaw, 4f, -3.5f, 3.5f, 0f, 1.9f, new Vector2(7f, 2.2f));
            Face(b, M_ROOMS, p + Vector3.up * 6f, yaw, 2.5f, -2f, 2f, 0f, 1.4f, new Vector2(4f, 2.2f));
            Face(b, M_LED_G, p + Vector3.up * 5.4f, yaw, 4.02f, -4.4f, 4.4f, 0f, 0.12f, Vector2.one, 0.06f);
        }

        // ---------------------------------------------------------------- parsing
        static float F(string s) => float.Parse(s, CultureInfo.InvariantCulture);

        void Parse(string j)
        {
            foreach (Match m in Regex.Matches(j, @"\{""x"":([-\d.]+),""z"":([-\d.]+),""y"":([-\d.]+),""w"":([-\d.]+),""d"":([-\d.]+),""h"":([-\d.]+),""yaw"":([-\d.]+),""style"":""([a-z_]+)"",""shops"":(true|false)\}"))
                lots.Add(new Lot { p = new Vector3(F(m.Groups[1].Value), F(m.Groups[3].Value), F(m.Groups[2].Value)), w = F(m.Groups[4].Value), d = F(m.Groups[5].Value), h = F(m.Groups[6].Value), yaw = F(m.Groups[7].Value), style = m.Groups[8].Value, shops = m.Groups[9].Value == "true" });
            foreach (Match m in Regex.Matches(j, @"\{""kind"":""([a-z_]+)"",""x"":([-\d.]+),""z"":([-\d.]+),""y"":([-\d.]+),""w"":([-\d.]+),""d"":([-\d.]+),""h"":([-\d.]+)\}"))
                marks.Add(new Mark { kind = m.Groups[1].Value, p = new Vector3(F(m.Groups[2].Value), F(m.Groups[4].Value), F(m.Groups[3].Value)), w = F(m.Groups[5].Value), d = F(m.Groups[6].Value), h = F(m.Groups[7].Value) });
            var lm = Regex.Match(j, @"""lamps"":\[(.*?)\]\]");
            if (lm.Success)
                foreach (Match m in Regex.Matches(lm.Groups[1].Value + "]", @"\[([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+),""([a-z]+)""\]"))
                    lamps.Add((new Vector3(F(m.Groups[1].Value), F(m.Groups[2].Value), F(m.Groups[3].Value)), F(m.Groups[4].Value), m.Groups[5].Value == "highway"));
            var tm = Regex.Match(j, @"""trees"":\[(.*?)\]\]");
            if (tm.Success)
                foreach (Match m in Regex.Matches(tm.Groups[1].Value + "]", @"\[([-\d.]+),([-\d.]+),([-\d.]+),""([a-z]+)"",([-\d.]+)\]"))
                    trees.Add((new Vector3(F(m.Groups[1].Value), F(m.Groups[2].Value), F(m.Groups[3].Value)), m.Groups[4].Value == "palm", F(m.Groups[5].Value)));
            // "gantries": [[x, y, z, yawDeg, roadWidth], ...]
            var gm = Regex.Match(j, @"""gantries"":\[(.*?)\]\]");
            if (gm.Success)
                foreach (Match m in Regex.Matches(gm.Groups[1].Value + "]", @"\[([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\]"))
                    gantries.Add((new Vector3(F(m.Groups[1].Value), F(m.Groups[2].Value), F(m.Groups[3].Value)), F(m.Groups[4].Value), F(m.Groups[5].Value)));
            // "metro": [{"pts": [[x,y,z],...], "pillars": [[x,y,z],...], "width": 8}, ...]
            var mm = Regex.Match(j, @"""metro"":\[(\{.*?\})\]");
            if (mm.Success)
                foreach (Match line in Regex.Matches(mm.Groups[1].Value, @"\{""pts"":\[(.*?)\]\],""pillars"":\[(.*?)\]\],""width"":([-\d.]+)\}"))
                {
                    var ml = new MetroLine { width = F(line.Groups[3].Value) };
                    foreach (Match p in Regex.Matches(line.Groups[1].Value + "]", @"\[([-\d.]+),([-\d.]+),([-\d.]+)\]")) ml.pts.Add(new Vector3(F(p.Groups[1].Value), F(p.Groups[2].Value), F(p.Groups[3].Value)));
                    foreach (Match p in Regex.Matches(line.Groups[2].Value + "]", @"\[([-\d.]+),([-\d.]+),([-\d.]+)\]")) ml.pillars.Add(new Vector3(F(p.Groups[1].Value), F(p.Groups[2].Value), F(p.Groups[3].Value)));
                    metros.Add(ml);
                }
            Debug.Log($"[HMD] newcity json dressing: lots={lots.Count} landmarks={marks.Count} lamps={lamps.Count} trees={trees.Count} gantries={gantries.Count} metro={metros.Count}");
        }

        // ---------------------------------------------------------------- building models (unity_assets/buildings)
        // buildings.json: {"models":[{"id":"marina_tower","w":32,"d":30,"h":170,"styles":["tower_res"],"yaw":0}, ...]}
        //   id = the GLB name (Buildings/<id>.glb), w/d/h = its real size in metres (x, z, y), styles = the lot styles it
        //   may stand on, yaw = extra turn in degrees so the model's front faces local +Z (the road side of a lot).
        [System.Serializable] class BModelJson { public string id; public float w, d, h, yaw; public float weight = 1f; public string[] styles; }
        [System.Serializable] class BModelsJson { public BModelJson[] models; }
        class BModel { public BModelJson j; public Mesh mesh; public Material[][] variants; public Material far; public Vector3 size; }
        readonly Dictionary<string, BModel> lastModel = new Dictionary<string, BModel>();
        // colour variants per model: as made, a warmer sand tone, a cooler grey tone (multiplied onto the albedo)
        static readonly Color[] Tints = { Color.white, new Color(1.06f, 0.97f, 0.86f), new Color(0.88f, 0.93f, 1.02f) };
        readonly List<BModel> models = new List<BModel>();
        readonly Dictionary<string, List<BModel>> byStyle = new Dictionary<string, List<BModel>>();
        static Mesh unitBox;
        Transform modelRoot;
        readonly Dictionary<Vector2Int, Transform> modelCells = new Dictionary<Vector2Int, Transform>();

        void LoadModels()
        {
            var ta = Res.Load<TextAsset>("Buildings/buildings");
            if (ta == null) return;
            BModelsJson list = null;
            try { list = JsonUtility.FromJson<BModelsJson>(ta.text); } catch (System.Exception e) { Debug.LogWarning("[HMD] buildings.json: " + e.Message); }
            if (list?.models == null) return;
            foreach (var j in list.models)
            {
                var prefab = Res.Load<GameObject>("Buildings/" + j.id);
                if (prefab == null) { Debug.LogWarning($"[HMD] building model {j.id}: no GLB"); continue; }
                var m = Bake(prefab, j, "Buildings");
                if (m == null) continue;
                models.Add(m);
                if (j.styles != null)
                    foreach (var s in j.styles) { if (!byStyle.TryGetValue(s, out var l)) byStyle[s] = l = new List<BModel>(); l.Add(m); }
            }
        }

        /// <summary>Merges a model's meshes into one, bottom-centred at the origin, front along +Z; its materials get the
        /// albedo as emission too (the windows are painted into the texture, so they glow at night).</summary>
        /// <summary>The merged mesh of a model (all its parts and sub-meshes, bottom centre at the origin, front along +Z)
        /// and its materials in sub-mesh order. 'mats' is always filled; the mesh is the Editor-baked copy with Mesh LODs
        /// (MeshLodStore) when there is an up-to-date one, else merged here. The Editor bake calls this with useBaked false.</summary>
        public static Mesh MergeModel(GameObject prefab, string folder, string id, float yaw, List<Material> mats, bool useBaked = true)
        {
            var mfs = prefab.GetComponentsInChildren<MeshFilter>(true);
            if (mfs.Length == 0) return null;
            var root = prefab.transform.worldToLocalMatrix;
            var combines = new List<CombineInstance>();
            long indices = 0;
            foreach (var mf in mfs)
            {
                var mr = mf.GetComponent<MeshRenderer>(); if (mf.sharedMesh == null || mr == null) continue;
                for (int s = 0; s < mf.sharedMesh.subMeshCount; s++)
                {
                    combines.Add(new CombineInstance { mesh = mf.sharedMesh, subMeshIndex = s, transform = root * mf.transform.localToWorldMatrix });
                    mats.Add(mr.sharedMaterials[Mathf.Min(s, mr.sharedMaterials.Length - 1)]);
                    indices += mf.sharedMesh.GetIndexCount(s);
                }
            }
            if (combines.Count == 0) return null;
            if (useBaked)
            {
                var baked = MeshLodStore.Load(MeshLodStore.ModelKey(folder, id, yaw), indices);
                if (baked != null && baked.subMeshCount == combines.Count) return baked;
            }
            var mesh = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32, name = "bld_" + id };
            mesh.CombineMeshes(combines.ToArray(), false, true);
            // bottom centre to the origin, turned so the front is +Z
            var b = mesh.bounds; var rot = Quaternion.Euler(0, yaw, 0);
            var v = mesh.vertices; var nrm = mesh.normals;
            for (int i = 0; i < v.Length; i++) v[i] = rot * (v[i] - new Vector3(b.center.x, b.min.y, b.center.z));
            if (nrm != null && nrm.Length == v.Length) for (int i = 0; i < nrm.Length; i++) nrm[i] = rot * nrm[i];
            mesh.vertices = v; if (nrm != null && nrm.Length == v.Length) mesh.normals = nrm; else mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            mesh.name = "bld_" + id + "#" + indices;
            return mesh;
        }

        BModel Bake(GameObject prefab, BModelJson j, string folder)
        {
            var mats = new List<Material>();
            var mesh = MergeModel(prefab, folder, j.id, j.yaw, mats);
            if (mesh == null) return null;
            if (mesh.lodCount <= 1) mesh.UploadMeshData(false);
            var variants = new Material[Tints.Length][]; Color avg = new Color(0.5f, 0.5f, 0.52f);
            for (int t = 0; t < Tints.Length; t++)
            {
                variants[t] = new Material[mats.Count];
                for (int i = 0; i < mats.Count; i++)
                {
                    var src = mats[i];
                    Texture tex = src != null ? (src.HasProperty("_BaseMap") ? src.GetTexture("_BaseMap") : src.HasProperty("baseColorTexture") ? src.GetTexture("baseColorTexture") : src.mainTexture) : null;
                    var m = Res.Mat(Tints[t], 0.35f, 0f);
                    // painted-in windows glow: brighter so near buildings light the street level
                    if (tex) { Res.SetMainTex(m, tex, Vector2.one); Res.SetEmission(m, Color.white * 1.25f, tex); if (i == 0 && t == 0) avg = AverageColour(tex); }
                    else if (src != null && src.HasProperty("_BaseColor")) Res.SetColor(m, src.GetColor("_BaseColor") * Tints[t]);
                    // glTF alpha "mask" (frond cards, railings): keep the cut-out, both sides
                    bool cut = src != null && (src.IsKeywordEnabled("_ALPHATEST_ON") || (src.HasProperty("_AlphaClip") && src.GetFloat("_AlphaClip") > 0.5f) || (src.HasProperty("alphaCutoff") && src.renderQueue >= 2450 && src.renderQueue < 3000));
                    if (cut)
                    {
                        m.SetFloat("_AlphaClip", 1f); m.EnableKeyword("_ALPHATEST_ON");
                        m.SetFloat("_Cutoff", src.HasProperty("alphaCutoff") ? src.GetFloat("alphaCutoff") : 0.5f);
                        m.SetFloat("_Cull", 0f); m.renderQueue = 2450;
                    }
                    m.enableInstancing = true;
                    variants[t][i] = m;
                }
            }
            // the average includes the bright painted windows: darken it so far boxes sit in the night haze
            var far = Res.Mat(avg * 0.55f, 0.3f, 0f); Res.SetEmission(far, avg * 0.18f); far.enableInstancing = true;
            return new BModel { j = j, mesh = mesh, variants = variants, far = far, size = mesh.bounds.size };
        }

        static Color AverageColour(Texture t)
        {
            var rt = RenderTexture.GetTemporary(8, 8, 0, RenderTextureFormat.ARGB32);
            Graphics.Blit(t, rt);
            var prev = RenderTexture.active; RenderTexture.active = rt;
            var tx = new Texture2D(8, 8, TextureFormat.RGBA32, false); tx.ReadPixels(new Rect(0, 0, 8, 8), 0, 0); tx.Apply();
            RenderTexture.active = prev; RenderTexture.ReleaseTemporary(rt);
            Color s = Color.black; foreach (var c in tx.GetPixels()) s += c; Object.Destroy(tx);
            return s / 64f;
        }

        /// <summary>A model on a lot instead of the box, when one exists for the lot's style. Scaled to the lot within
        /// limits (footprint fits the lot, height within 0.75-1.35 of the footprint scale), front to the road (lot yaw).
        /// LOD: the model near, a coloured box far, culled beyond. A box collider keeps cars out.</summary>
        bool PlaceModel(Lot l)
        {
            if (!byStyle.TryGetValue(l.style, out var cands) || cands.Count == 0) return false;
            // variety: never the same model as the last one placed for this style (neighbouring lots come in order)
            lastModel.TryGetValue(l.style, out var prevM);
            // weighted pick (json "weight": rare models like the mosque or petrol station stay rare), never the previous one
            BModel Pick(BModel skip)
            {
                float tot = 0; foreach (var c in cands) if (c != skip) tot += Mathf.Max(0f, c.j.weight);
                if (tot <= 0f) return cands[rng.Next(cands.Count)];
                float r = R() * tot;
                foreach (var c in cands) { if (c == skip) continue; r -= Mathf.Max(0f, c.j.weight); if (r <= 0f) return c; }
                return cands[cands.Count - 1];
            }
            var m = Pick(cands.Count > 1 ? prevM : null);
            lastModel[l.style] = m;
            float sxz = Mathf.Min(l.w / Mathf.Max(1f, m.size.x), l.d / Mathf.Max(1f, m.size.z));
            float sy = Mathf.Clamp(l.h / Mathf.Max(1f, m.size.y), sxz * 0.75f, sxz * 1.35f);
            var scale = new Vector3(sxz, sy, sxz);
            if (modelRoot == null) { modelRoot = new GameObject("BuildingModels").transform; modelRoot.SetParent(transform, false); }
            var key = new Vector2Int(Mathf.FloorToInt(l.p.x / 320f), Mathf.FloorToInt(l.p.z / 320f));
            if (!modelCells.TryGetValue(key, out var cell)) { cell = new GameObject("Bld_" + key.x + "_" + key.y).transform; cell.SetParent(modelRoot, false); modelCells[key] = cell; }
            var go = new GameObject("bld_" + m.j.id); go.transform.SetParent(cell, false);
            go.transform.SetPositionAndRotation(l.p - Vector3.up * 0.3f, Quaternion.Euler(0, l.yaw, 0)); go.transform.localScale = scale;
            var near = new GameObject("lod0"); near.transform.SetParent(go.transform, false);
            near.AddComponent<MeshFilter>().sharedMesh = m.mesh;
            var nr = near.AddComponent<MeshRenderer>(); nr.sharedMaterials = m.variants[rng.Next(m.variants.Length)];
            // square-ish lots: sometimes turned round (the back of a model faces the road), more variety street-side
            if (Mathf.Abs(l.w - l.d) < 0.15f * Mathf.Max(l.w, l.d) && R() < 0.3f) near.transform.localRotation = Quaternion.Euler(0, 180f, 0);
            if (unitBox == null)
            {
                var tmp = GameObject.CreatePrimitive(PrimitiveType.Cube); unitBox = Object.Instantiate(tmp.GetComponent<MeshFilter>().sharedMesh);
                Object.DestroyImmediate(tmp);
                var vv = unitBox.vertices; for (int i = 0; i < vv.Length; i++) vv[i] += Vector3.up * 0.5f; unitBox.vertices = vv; unitBox.RecalculateBounds();
            }
            var farGo = new GameObject("lod1"); farGo.transform.SetParent(go.transform, false); farGo.transform.localScale = m.size;
            farGo.AddComponent<MeshFilter>().sharedMesh = unitBox;
            var fr = farGo.AddComponent<MeshRenderer>(); fr.sharedMaterial = m.far; fr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            var lg = go.AddComponent<LODGroup>();
            float tall = Mathf.Max(m.size.y * sy, 20f);
            // the real model until the building is small on screen (stand-in boxes switching in at 6-12 % of the screen
            // height read as pale blocks over the whole middle distance); the box only for the far haze
            lg.SetLODs(new[] { new LOD(tall > 80f ? 0.008f : 0.018f, new Renderer[] { nr }), new LOD(tall > 80f ? 0.002f : 0.005f, new Renderer[] { fr }) });
            var bc = go.AddComponent<BoxCollider>(); bc.center = new Vector3(0, m.size.y * 0.5f, 0); bc.size = m.size;
            go.isStatic = true; near.isStatic = true; farGo.isStatic = true;
            DistanceCuller.Add(go, l.p, DistanceCuller.ForBuilding(m.size.y * sy));   // towers (80 m+) stay for the skyline
            return true;
        }

        // ---------------------------------------------------------------- palm models (unity_assets/trees)
        [System.Serializable] class TModelJson { public string id, kind; public float h, weight = 1f; public bool emissive; }
        [System.Serializable] class TModelsJson { public TModelJson[] models; }
        readonly List<(TModelJson j, BModel m)> palmModels = new List<(TModelJson, BModel)>();
        Transform treeRoot;

        void LoadTreeModels()
        {
            var ta = Res.Load<TextAsset>("Trees/trees");
            if (ta == null) return;
            TModelsJson list = null;
            try { list = JsonUtility.FromJson<TModelsJson>(ta.text); } catch (System.Exception e) { Debug.LogWarning("[HMD] trees.json: " + e.Message); }
            if (list?.models == null) return;
            foreach (var j in list.models)
            {
                if (j.kind != "palm") continue;
                var prefab = Res.Load<GameObject>("Trees/" + j.id);
                if (prefab == null) { Debug.LogWarning($"[HMD] tree model {j.id}: no GLB"); continue; }
                var m = Bake(prefab, new BModelJson { id = j.id, h = j.h }, "Trees");
                if (m == null) continue;
                // fronds read green under the lamps; the light-wrapped palm glows
                foreach (var mt in m.variants[0])
                {
                    var tex = mt.HasProperty("_BaseMap") ? mt.GetTexture("_BaseMap") : null;
                    Res.SetEmission(mt, Color.white * (j.emissive ? 0.9f : 0.3f), tex);
                }
                palmModels.Add((j, m));
            }
        }

        /// <summary>A palm model at a json tree spot: height h x the spot's scale, random yaw, picked by weight; culled
        /// when small on screen (about 300 m for a 9 m palm). No collider (trees never stop the car).</summary>
        bool PlaceTree(Vector3 p, float s)
        {
            if (palmModels.Count == 0) return false;
            float tot = 0; foreach (var pm in palmModels) tot += Mathf.Max(0f, pm.j.weight);
            float r = R() * tot; var pick = palmModels[0];
            foreach (var pm in palmModels) { r -= Mathf.Max(0f, pm.j.weight); if (r <= 0f) { pick = pm; break; } }
            var m = pick.m;
            float sc = pick.j.h * Mathf.Max(0.3f, s) / Mathf.Max(0.01f, m.size.y);
            if (treeRoot == null) { treeRoot = new GameObject("PalmModels").transform; treeRoot.SetParent(transform, false); }
            var go = new GameObject("palm_" + pick.j.id); go.transform.SetParent(treeRoot, false);
            go.transform.SetPositionAndRotation(p, Quaternion.Euler(0, R() * 360f, 0)); go.transform.localScale = Vector3.one * sc;
            go.AddComponent<MeshFilter>().sharedMesh = m.mesh;
            var mr = go.AddComponent<MeshRenderer>(); mr.sharedMaterials = m.variants[0];
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            var lg = go.AddComponent<LODGroup>(); lg.SetLODs(new[] { new LOD(0.025f, new Renderer[] { mr }) });
            DistanceCuller.Add(go, p, DistanceCuller.Palm);
            go.isStatic = true;
            return true;
        }

        static Vector3 CellCentre(Vector2Int k) => new Vector3((k.x + 0.5f) * 320f, 0f, (k.y + 0.5f) * 320f);

        // ---------------------------------------------------------------- lot ground and light pools
        readonly Dictionary<Vector2Int, MeshBuilder> plots = new Dictionary<Vector2Int, MeshBuilder>();
        int plotLogs;

        /// <summary>The ground of a lot (the flat navy between buildings read as empty): pavers, a concrete yard or granite
        /// paving by style, 1.5 m past the footprint; and a soft warm pool of light on the ground at the road-side front
        /// (shop fronts, villa gates). No colliders.</summary>
        void Plot(Lot l)
        {
            var k = new Vector2Int(Mathf.FloorToInt(l.p.x / 320f), Mathf.FloorToInt(l.p.z / 320f));
            if (!plots.TryGetValue(k, out var b)) { b = new MeshBuilder(M_COUNT); plots[k] = b; }
            int mat = l.style == "villa" ? M_PLOT_SAND : l.style == "warehouse" ? M_PLOT_CONC : M_PLOT_TILE;
            var q = Quaternion.Euler(0, l.yaw, 0);
            float hx = l.w * 0.5f + 1.5f, hz = l.d * 0.5f + 1.5f, y = 0.12f;
            // sit on the real terrain: the json lot height can be a little under it, which hid the plot entirely
            // average of the terrain under the lot (the highest point left the plot floating up to 1 m on slopes: its
            // edge cast a black line across the sand)
            float sum = 0; int hits = 0;
            for (int ix = -1; ix <= 1; ix++)
                for (int iz = -1; iz <= 1; iz++)
                {
                    var pr = l.p + q * new Vector3(ix * hx * 0.9f, 0, iz * hz * 0.9f);
                    if (Physics.Raycast(pr + Vector3.up * 15f, Vector3.down, out var hit, 30f) && hit.collider.name.ToLowerInvariant().Contains("terrain") && Mathf.Abs(hit.point.y - l.p.y) < 3f)
                    { sum += hit.point.y; hits++; }
                }
            float gy = hits > 0 ? Mathf.Max(l.p.y, sum / hits) : l.p.y;
            Vector3 c = new Vector3(l.p.x, gy + y, l.p.z);
            if (plotLogs++ < 3) Debug.Log($"[HMD] plot {l.style} at ({l.p.x:F0},{l.p.y:F2},{l.p.z:F0}): terrain top {gy:F2}");
            Vector3 p0 = c + q * new Vector3(-hx, 0, -hz), p1 = c + q * new Vector3(-hx, 0, hz), p2 = c + q * new Vector3(hx, 0, hz), p3 = c + q * new Vector3(hx, 0, -hz);
            float u = hx * 2f / 4f, v = hz * 2f / 4f;   // 4 m texture repeat
            UpQuad(b, mat, p0, p1, p2, p3, Vector2.zero, new Vector2(0, v), new Vector2(u, v), new Vector2(u, 0));
            // light pool in front: shops and villas get one; towers get two (lobby entrances)
            int pools = l.style.StartsWith("tower") ? 2 : (l.shops || l.style == "villa" || l.style == "midrise") ? 1 : 0;
            for (int i = 0; i < pools; i++)
            {
                float ox = pools == 1 ? 0f : (i == 0 ? -l.w * 0.25f : l.w * 0.25f);
                float pw = Mathf.Min(l.w * (pools == 1 ? 0.7f : 0.4f), 16f), pd = 7f;
                Vector3 pc = new Vector3(l.p.x, gy, l.p.z) + q * new Vector3(ox, 0, l.d * 0.5f + pd * 0.35f) + Vector3.up * (y + 0.05f);
                Vector3 a0 = pc + q * new Vector3(-pw * 0.5f, 0, -pd * 0.5f), a1 = pc + q * new Vector3(-pw * 0.5f, 0, pd * 0.5f);
                Vector3 a2 = pc + q * new Vector3(pw * 0.5f, 0, pd * 0.5f), a3 = pc + q * new Vector3(pw * 0.5f, 0, -pd * 0.5f);
                UpQuad(b, M_POOL, a0, a1, a2, a3, Vector2.zero, new Vector2(0, 1), Vector2.one, new Vector2(1, 0));
            }
        }

        /// <summary>A flat quad that faces up whichever order its corners come in (same test as Band).</summary>
        static void UpQuad(MeshBuilder b, int sub, Vector3 a, Vector3 c, Vector3 d, Vector3 e, Vector2 ua, Vector2 uc, Vector2 ud, Vector2 ue)
        {
            if (Vector3.Dot(Vector3.Cross(c - a, e - a), Vector3.up) < 0) b.Sub(sub).QuadUV(a, c, d, e, Vector3.up, ua, uc, ud, ue);
            else b.Sub(sub).QuadUV(a, e, d, c, Vector3.up, ua, ue, ud, uc);
        }

        // ---------------------------------------------------------------- landmark models (unity_assets/buildings/landmarks)
        // landmarks.json: {"models":[{"kind":"needle_tower","id":"needle_tower","h":420,"yaw":90}, ...]}
        [System.Serializable] class LModelJson { public string kind, id; public float h, yaw; }
        [System.Serializable] class LModelsJson { public LModelJson[] models; }
        readonly Dictionary<string, (LModelJson j, BModel m)> landmarkModels = new Dictionary<string, (LModelJson, BModel)>();
        NewCity cityRef;

        void LoadLandmarkModels()
        {
            var ta = Res.Load<TextAsset>("Buildings/Landmarks/landmarks");
            if (ta == null) return;
            LModelsJson list = null;
            try { list = JsonUtility.FromJson<LModelsJson>(ta.text); } catch (System.Exception e) { Debug.LogWarning("[HMD] landmarks.json: " + e.Message); }
            if (list?.models == null) return;
            foreach (var j in list.models)
            {
                var prefab = Res.Load<GameObject>("Buildings/Landmarks/" + j.id);
                if (prefab == null) { Debug.LogWarning($"[HMD] landmark model {j.id}: no GLB"); continue; }
                var m = Bake(prefab, new BModelJson { id = j.id, yaw = j.yaw, h = j.h }, "Landmarks");
                if (m != null) landmarkModels[j.kind] = (j, m);
            }
        }

        /// <summary>The landmark's model at its json spot, scaled to the json height (proportions kept), never culled:
        /// the skyline. Which way it faces: the gold frame lines up with the nearest main road (drivers look through it),
        /// the arch hotel looks down the Palm trunk, everything else turns its front to the nearest road.</summary>
        bool PlaceLandmark(NewCity nc, Mark mk)
        {
            if (!landmarkModels.TryGetValue(mk.kind, out var lm)) return false;
            var m = lm.m;
            float s = lm.j.h / Mathf.Max(0.01f, m.size.y);
            Vector3 face = Vector3.forward;
            NewCity.Road best = null; int bi = 0; float bd = float.MaxValue;
            foreach (var rd in nc.roads)
            {
                if (rd.cls == "ramp" || rd.cls == "street") continue;
                for (int i = 0; i < rd.pts.Count; i++) { float d = new Vector2(rd.pts[i].x - mk.p.x, rd.pts[i].z - mk.p.z).sqrMagnitude; if (d < bd) { bd = d; best = rd; bi = i; } }
            }
            if (mk.kind == "arch_hotel")
            {
                foreach (var rd in nc.roads)
                    if (rd.name == "Palm Trunk" && rd.pts.Count > 1)
                    {
                        // towards the far (mainland) end of the trunk
                        var a = rd.pts[0]; var b = rd.pts[rd.pts.Count - 1];
                        var far = (new Vector2(a.x - mk.p.x, a.z - mk.p.z)).sqrMagnitude > (new Vector2(b.x - mk.p.x, b.z - mk.p.z)).sqrMagnitude ? a : b;
                        face = far - mk.p; break;
                    }
            }
            else if (best != null)
            {
                if (mk.kind == "gold_frame") face = best.pts[Mathf.Min(best.pts.Count - 1, bi + 1)] - best.pts[Mathf.Max(0, bi - 1)];   // the opening along the road
                else face = best.pts[bi] - mk.p;                                // the front to the road
            }
            face.y = 0; if (face.sqrMagnitude < 0.01f) face = Vector3.forward;
            var go = new GameObject("landmark_" + mk.kind);
            go.transform.SetParent(transform, false);
            go.transform.SetPositionAndRotation(mk.p, Quaternion.LookRotation(face.normalized)); go.transform.localScale = Vector3.one * s;
            go.AddComponent<MeshFilter>().sharedMesh = m.mesh;
            var r = go.AddComponent<MeshRenderer>();
            var mats = m.variants[0];
            foreach (var mt in mats) Res.SetEmission(mt, Color.white * 1.15f, mt.GetTexture("_BaseMap"));   // brighter than the city blocks: the skyline
            r.sharedMaterials = mats;
            // solid landmarks keep cars out; open ones (the frame, the wheel) get no box
            if (mk.kind != "gold_frame" && mk.kind != "big_wheel") { var bc = go.AddComponent<BoxCollider>(); bc.center = new Vector3(0, m.size.y * 0.5f, 0); bc.size = m.size; }
            go.isStatic = true;
            Landmarks.RemoveAll(x => x.kind == mk.kind && x.p == mk.p); Landmarks.Add((mk.kind, mk.p, lm.j.h));
            return true;
        }

        // ---------------------------------------------------------------- gantries and metro
        readonly List<(Vector3 p, float yaw, float width)> gantries = new List<(Vector3, float, float)>();
        class MetroLine { public List<Vector3> pts = new List<Vector3>(), pillars = new List<Vector3>(); public float width = 8f; }
        readonly List<MetroLine> metros = new List<MetroLine>();

        /// <summary>A steel portal across the highway (7 m clear): two posts beyond the edges, a box truss beam, green
        /// sign boards with white arrows and a blank white panel, on both faces (two-way highway), lit from below.</summary>
        void Gantry(MeshBuilder b, Vector3 p, float yaw, float width)
        {
            var q = Quaternion.Euler(0, yaw, 0);
            Vector3 fwd = q * Vector3.forward, side = q * Vector3.right;
            float half = width * 0.5f + 1.6f, clear = 7f;
            for (int s = -1; s <= 1; s += 2)
            {
                Vector3 post = p + side * s * half;
                RBox(b, M_STEEL, post - Vector3.up * 0.5f, new Vector3(0.6f, clear + 2.3f, 0.6f), yaw, new Vector2(1, 4));
                RBox(b, M_ROOF, post - Vector3.up * 0.3f, new Vector3(1.2f, 0.5f, 1.2f), yaw, Vector2.one);   // footing
            }
            // truss beam: two chords and a few verticals
            for (int c = 0; c < 2; c++)
                RBox(b, M_STEEL, p + Vector3.up * (clear + c * 1.5f), new Vector3(half * 2f + 0.6f, 0.3f, 0.5f), yaw, new Vector2(4, 1));
            for (float x = -half; x <= half; x += 3f) RBox(b, M_STEEL, p + side * x + Vector3.up * clear, new Vector3(0.12f, 1.5f, 0.12f), yaw, Vector2.one);
            // boards: across the lanes, three boards (two green with arrows, one blank white panel) per face
            float[] cx = { -width * 0.28f, 0.06f * width, width * 0.33f };
            float[] bw = { width * 0.3f, width * 0.3f, width * 0.18f };
            for (int f = -1; f <= 1; f += 2)
            {
                for (int k = 0; k < 3; k++)
                {
                    Vector3 c = p + side * cx[k] * f + fwd * f * 0.4f + Vector3.up * (clear - 0.2f);
                    bool white = k == 2;
                    RBox(b, white ? M_SIGN_WHITE : M_SIGN_GREEN, c, new Vector3(bw[k], 2.6f, 0.15f), yaw, Vector2.one);
                    if (white) continue;
                    // a white arrow pointing up (straight on) or up-right (exit), and a white rim line under it
                    Vector3 front = c + fwd * f * 0.09f;
                    float ax = k == 0 ? 0f : 12f;
                    b.Sub(M_SIGN_WHITE).Add(UnitCube(), Matrix4x4.TRS(front + Vector3.up * 1.0f, q * Quaternion.Euler(0, 0, -ax * f), new Vector3(0.22f, 1.3f, 0.04f)), M_SIGN_WHITE);
                    b.Sub(M_SIGN_WHITE).Add(UnitCube(), Matrix4x4.TRS(front + Vector3.up * 1.75f, q * Quaternion.Euler(0, 0, 45f - ax * f), new Vector3(0.6f, 0.2f, 0.04f)), M_SIGN_WHITE);
                    b.Sub(M_SIGN_WHITE).Add(UnitCube(), Matrix4x4.TRS(front + Vector3.up * 1.75f, q * Quaternion.Euler(0, 0, -45f - ax * f), new Vector3(0.6f, 0.2f, 0.04f)), M_SIGN_WHITE);
                    b.Sub(M_SIGN_WHITE).Add(UnitCube(), Matrix4x4.TRS(front + Vector3.up * 0.25f, q, new Vector3(bw[k] * 0.8f, 0.07f, 0.04f)), M_SIGN_WHITE);
                }
                // small lamps under the boards light them softly
                for (int k = 0; k < 3; k++)
                    RBox(b, M_LED_W, p + side * cx[k] * f + fwd * f * 0.9f + Vector3.up * (clear - 0.35f), new Vector3(bw[k] * 0.7f, 0.08f, 0.12f), yaw, Vector2.one);
            }
        }

        /// <summary>The elevated metro: a concrete U deck (parapets both sides, a thin blue light line on the outer
        /// edge) along the json centre line, and round pillars with flared heads (pillars collide, the deck does not).</summary>
        void Metro(MetroLine ml, System.Func<Vector3, MeshBuilder> solid, System.Func<Vector3, MeshBuilder> prop)
        {
            float w = ml.width;
            for (int i = 0; i + 1 < ml.pts.Count; i++)
            {
                Vector3 a = ml.pts[i], c = ml.pts[i + 1];
                Vector3 d = c - a; d.y = 0; float len = d.magnitude; if (len < 0.1f) continue;
                float yaw = Quaternion.LookRotation(d / len).eulerAngles.y;
                Vector3 mid = (a + c) * 0.5f, side = Vector3.Cross(Vector3.up, d / len);
                var b = prop(mid);
                RBox(b, M_METRO, mid - Vector3.up * 1.8f, new Vector3(w, 1.8f, len + 0.4f), yaw, new Vector2(6, 6));            // deck slab
                for (int s = -1; s <= 1; s += 2)
                {
                    RBox(b, M_METRO, mid + side * s * (w * 0.5f - 0.2f), new Vector3(0.4f, 1.3f, len + 0.4f), yaw, new Vector2(6, 2));   // parapet
                    RBox(b, M_LED_B, mid + side * s * (w * 0.5f + 0.03f) - Vector3.up * 0.9f, new Vector3(0.06f, 0.12f, len + 0.4f), yaw, Vector2.one, false);
                }
            }
            foreach (var pl in ml.pillars)
            {
                // deck height above this pillar: nearest centre-line point
                float top = pl.y + 10f; float bd = float.MaxValue; int ni = 0;
                for (int i = 0; i < ml.pts.Count; i++) { var p = ml.pts[i]; float dd = new Vector2(p.x - pl.x, p.z - pl.z).sqrMagnitude; if (dd < bd) { bd = dd; top = p.y; ni = i; } }
                var dl = ml.pts[Mathf.Min(ml.pts.Count - 1, ni + 1)] - ml.pts[Mathf.Max(0, ni - 1)]; dl.y = 0;
                float pyaw = dl.sqrMagnitude > 0.01f ? Quaternion.LookRotation(dl).eulerAngles.y : 0f;
                float h = top - 1.8f - pl.y; if (h < 1f) continue;
                var b = solid(pl);
                // round slim pillar (1.3 m, like the Dubai metro) and a flared head under the deck
                float ph = h - 1.2f + 0.5f;
                b.Sub(M_METRO).Add(UnitCylinder(), Matrix4x4.TRS(pl + Vector3.up * (ph * 0.5f - 0.5f), Quaternion.identity, new Vector3(1.3f, ph * 0.5f, 1.3f)), M_METRO);
                RBox(b, M_METRO, pl + Vector3.up * (h - 1.2f), new Vector3(w * 0.7f, 1.2f, 2.2f), pyaw, new Vector2(4, 4));
            }
        }

        // ---------------------------------------------------------------- materials
        void MakeMaterials()
        {
            mats = new Material[M_COUNT];
            var tn = new[] { "office", "resi", "black", "hotel", "fins", "stone" };
            for (int k = 0; k < 6; k++)
            {
                var d = Res.Tex("Tower/" + tn[k]);
                bool glassy = k == 0 || k == 2 || k == 4;
                var m = Res.Mat(Color.white, glassy ? 0.6f : 0.45f, glassy ? 0.15f : 0f);
                if (d) Res.SetMainTex(m, d, Vector2.one);
                var e = Res.Tex("Tower/" + tn[k] + "_emit");
                if (d) Res.SetEmission(m, Color.white * (tn[k] == "fins" ? 0.7f : 1.05f), e != null ? e : d);
                mats[M_TOWER0 + k] = m;
            }
            var fn = new[] { "facade005", "facade007", "facade009", "facade010", "facade012", "facade014", "facade015", "facade017" };
            for (int k = 0; k < 8; k++)
            {
                var m = Res.TexMat("Facade/" + fn[k], Vector2.one, 0.55f, 0f);
                var e = Res.Tex("Facade/" + fn[k] + "_emit");
                if (e != null) Res.SetEmission(m, new Color(1f, 0.78f, 0.5f) * 1.6f, e);
                mats[M_FAC0 + k] = m;
            }
            mats[M_STUCCO] = Res.TexMat("Tex/white_stucco", Vector2.one, 0.3f, 0f, new Color(0.92f, 0.9f, 0.86f));
            mats[M_SAND] = Res.TexMat("Tex/white_stucco", Vector2.one, 0.3f, 0f, new Color(0.86f, 0.74f, 0.56f));
            mats[M_CORR] = Res.TexMat("Tex/corrugated_iron", Vector2.one, 0.4f, 0.1f, new Color(0.7f, 0.72f, 0.74f), 1f, false);
            mats[M_SHUTTER] = Res.TexMat("Tex/painted_metal_shutter", Vector2.one, 0.45f, 0.2f, new Color(0.75f, 0.76f, 0.78f), 1f, false);
            mats[M_ROOF] = Res.TexMat("Tex/concrete_panels", Vector2.one, 0.25f, 0f, new Color(0.35f, 0.35f, 0.37f));
            foreach (var (slot, n) in new[] { (M_SHOP, "Gen/shops"), (M_ROOMS, "Gen/rooms") })
            {
                var t = Res.Tex(n); var m = Res.Mat(Color.white, 0.6f);
                if (t) { Res.SetMainTex(m, t, Vector2.one); Res.SetEmission(m, Color.white * 1.3f, t); }
                mats[slot] = m;
            }
            mats[M_LED_W] = Res.Glow(new Color(0.85f, 0.92f, 1f), 4f);
            mats[M_LED_B] = Res.Glow(new Color(0.15f, 0.55f, 1f), 5f);
            mats[M_LED_P] = Res.Glow(new Color(0.75f, 0.2f, 1f), 5f);
            mats[M_LED_G] = Res.Glow(new Color(1f, 0.75f, 0.35f), 4f);
            mats[M_RED] = Res.Glow(new Color(1f, 0.03f, 0.02f), 7f);
            mats[M_POLE] = Res.Mat(new Color(0.42f, 0.43f, 0.45f), 0.55f, 0.75f);   // dark grey metal, not black
            // metro viaduct: light grey concrete with a little spill light from the road lamps
            mats[M_METRO] = Res.TexMat("Tex/concrete_panels", Vector2.one, 0.3f, 0f, new Color(0.82f, 0.82f, 0.84f));
            Res.SetEmission(mats[M_METRO], new Color(0.2f, 0.2f, 0.21f) * 1.4f, mats[M_METRO].GetTexture("_BaseMap"));
            mats[M_LAMP] = Res.Glow(new Color(1f, 0.66f, 0.3f), 8f);       // sodium
            mats[M_LAMP_LED] = Res.Glow(new Color(0.85f, 0.93f, 1f), 9f);  // highway LED
            // highway sign boards: Dubai green, softly lit from below; white arrows and panels glow a little
            mats[M_SIGN_GREEN] = Res.Mat(new Color(0.02f, 0.3f, 0.14f), 0.55f, 0f);
            // softly lit at night (at 0.9 / 1.6 the boards glowed like screens)
            Res.SetEmission(mats[M_SIGN_GREEN], new Color(0.02f, 0.3f, 0.12f) * 0.16f);
            mats[M_SIGN_WHITE] = Res.Glow(new Color(0.95f, 0.97f, 1f), 0.55f);
            mats[M_STEEL] = Res.Mat(new Color(0.55f, 0.57f, 0.6f), 0.55f, 0.8f);
            // ground under the lots: sand-coloured pavers round villas, concrete yards in industry, granite round towers
            mats[M_PLOT_SAND] = Res.TexMat("Tex/patterned_paving", Vector2.one, 0.3f, 0f, new Color(0.86f, 0.76f, 0.6f));
            mats[M_PLOT_CONC] = Res.TexMat("Tex/hangar_concrete_floor", Vector2.one, 0.35f, 0f, new Color(0.62f, 0.62f, 0.64f));
            mats[M_PLOT_TILE] = Res.TexMat("Tex/granite_tile", Vector2.one, 0.55f, 0f, new Color(0.7f, 0.7f, 0.72f));
            // the Higgsfield ground set when present (plot UVs run 1 per 4 m): villa tiles 8 m, concrete yard 12 m, granite 8 m
            // towers: the granite bands aliased into strong black and white stripes at a distance, so tower plazas use
            // the villa tiles at a larger size in a cool grey tint
            foreach (var (slot, name, metres) in new[] { (M_PLOT_SAND, "Ground/villa_tiles", 8f), (M_PLOT_CONC, "Ground/yard_concrete", 12f), (M_PLOT_TILE, "Ground/villa_tiles", 10f) })
            {
                var gt = Res.Tex(name);
                if (gt == null) continue;
                var gm = Res.Mat(slot == M_PLOT_TILE ? new Color(0.7f, 0.72f, 0.76f) : new Color(0.85f, 0.83f, 0.8f), slot == M_PLOT_TILE ? 0.45f : 0.3f, 0f);
                Res.SetMainTex(gm, gt, Vector2.one * (4f / metres));
                mats[slot] = gm;
            }
            // city spill light on the lot ground: at 0.04 it vanished into the night; the texture shows through now
            foreach (int s in new[] { M_PLOT_SAND, M_PLOT_CONC, M_PLOT_TILE })
            {
                var t = mats[s].HasProperty("_BaseMap") ? mats[s].GetTexture("_BaseMap") : null;
                Res.SetEmission(mats[s], (s == M_PLOT_CONC ? new Color(0.2f, 0.2f, 0.21f) : new Color(0.26f, 0.21f, 0.15f)) * 0.55f, t);
            }
            // warm light spilling on the ground at shop fronts and villa gates (soft, additive, no real light)
            mats[M_POOL] = Res.Particle(new Color(1f, 0.7f, 0.4f, 0.7f), Res.SoftDot);
            mats[M_POOL_COOL] = Res.Particle(new Color(0.78f, 0.88f, 1f, 0.85f), Res.SoftDot);   // highway pools read on the road from the chase cam
            var bark = Res.Tex("Gen/bark");
            mats[M_BARK] = Res.Mat(new Color(0.58f, 0.44f, 0.31f), 0.15f);
            if (bark) Res.SetMainTex(mats[M_BARK], bark, new Vector2(1, 4));
            // Dubai boulevards uplight their palms: warm trunks and green-lit fronds instead of black cut-outs
            Res.SetEmission(mats[M_BARK], new Color(0.55f, 0.38f, 0.22f) * 0.75f, bark);
            var frond = Res.Tex("Gen/frond");
            var leaf = Res.Mat(new Color(0.42f, 0.55f, 0.32f), 0.3f);
            if (frond) { Res.SetMainTex(leaf, frond, Vector2.one); leaf.SetFloat("_AlphaClip", 1f); leaf.SetFloat("_Cutoff", 0.4f); leaf.EnableKeyword("_ALPHATEST_ON"); }
            Res.SetEmission(leaf, new Color(0.16f, 0.28f, 0.1f) * 0.5f);   // uniform: the frond texture is dark, only its alpha shapes the leaves
            leaf.SetFloat("_Cull", 0f); leaf.renderQueue = 2450;
            mats[M_LEAF] = leaf;
            mats[M_TREE] = Res.Mat(new Color(0.12f, 0.22f, 0.1f), 0.2f);
            mats[M_GLASS] = Res.Mat(new Color(0.08f, 0.12f, 0.18f), 0.8f, 0.5f);
            mats[M_WALL] = Res.Mat(new Color(0.78f, 0.74f, 0.66f), 0.25f);
            var sc = new[] { new Color(1f, 0.15f, 0.2f), new Color(0.1f, 0.85f, 1f), new Color(1f, 0.6f, 0.1f), new Color(0.3f, 1f, 0.45f) };
            for (int k = 0; k < 4; k++) mats[M_SIGN0 + k] = Res.Glow(sc[k], 4.5f);
            // pale wet sand shore with a faint warm glow, so the Palm's outline shows from above at night
            mats[M_SHORE] = Res.Mat(new Color(0.9f, 0.82f, 0.66f), 0.5f, 0f);
            Res.SetEmission(mats[M_SHORE], new Color(0.7f, 0.56f, 0.36f) * 1.6f);
            mats[M_LAND] = Res.Mat(new Color(0.62f, 0.52f, 0.38f), 0.3f, 0f);
            Res.SetEmission(mats[M_LAND], new Color(0.42f, 0.32f, 0.2f) * 0.55f);   // warm sand lit by the street lights
            mats[M_SHALLOW] = Res.Mat(new Color(0.1f, 0.45f, 0.48f), 0.9f, 0f);
            Res.SetEmission(mats[M_SHALLOW], new Color(0.05f, 0.35f, 0.4f) * 0.9f);   // turquoise shallow water
            var archT = Res.Tex("Tower/hotel");
            mats[M_ARCH] = Res.Mat(new Color(0.95f, 0.72f, 0.62f), 0.45f, 0f);   // pink-sand hotel facade
            if (archT) { Res.SetMainTex(mats[M_ARCH], archT, Vector2.one); Res.SetEmission(mats[M_ARCH], new Color(1f, 0.75f, 0.55f) * 1.3f, archT); }
        }

        // ---------------------------------------------------------------- geometry helpers
        /// <summary>Oriented box: centre (bottom centre if bottom = true), size along local x (w), y (h), z (d), turned by yaw.</summary>
        static void RBox(MeshBuilder b, int sub, Vector3 c, Vector3 size, float yaw, Vector2 uvM, bool top = true, bool bottomCentred = true)
        {
            var q = Quaternion.Euler(0, yaw, 0);
            Vector3 baseC = bottomCentred ? c : c - Vector3.up * size.y * 0.5f;
            float hx = size.x * 0.5f, hz = size.z * 0.5f;
            Vector3 p0 = baseC + q * new Vector3(-hx, 0, -hz), p1 = baseC + q * new Vector3(hx, 0, -hz);
            Vector3 p2 = baseC + q * new Vector3(hx, 0, hz), p3 = baseC + q * new Vector3(-hx, 0, hz);
            b.Sub(sub);
            b.Wall(p0, p1, size.y, uvM); b.Wall(p1, p2, size.y, uvM); b.Wall(p2, p3, size.y, uvM); b.Wall(p3, p0, size.y, uvM);
            if (top)
            {
                Vector3 u = Vector3.up * size.y;
                b.QuadUV(p0 + u, p1 + u, p2 + u, p3 + u, Vector3.up, Vector2.zero, new Vector2(size.x / uvM.x, 0), new Vector2(size.x / uvM.x, size.z / uvM.x), new Vector2(0, size.z / uvM.x));
            }
        }

        /// <summary>A flat quad on one face of an oriented box (local face +Z = front), raised slightly so it shows.</summary>
        static void Face(MeshBuilder b, int sub, Vector3 baseC, float yaw, float halfDepth, float x0, float x1, float y0, float y1, Vector2 uvM, float outset = 0.05f)
        {
            var q = Quaternion.Euler(0, yaw, 0);
            Vector3 a = baseC + q * new Vector3(x1, y0, halfDepth + outset), c = baseC + q * new Vector3(x0, y0, halfDepth + outset);
            b.Sub(sub);
            b.Wall(a, c, y1 - y0, uvM, default);
            // Wall builds from the bottom edge: lift it to y0 by building from points already at y0
        }

        // ---------------------------------------------------------------- buildings
        void Building(MeshBuilder b, Lot l)
        {
            const float sink = 3f;
            Vector3 c = l.p - Vector3.up * sink;
            float h = l.h + sink, hd = l.d * 0.5f;
            switch (l.style)
            {
                case "tower":
                case "tower_res":
                case "tower_beige":
                {
                    int skin = l.style == "tower_res" ? 1 : l.style == "tower_beige" ? (R() < 0.5f ? 3 : 5) : (new[] { 0, 2, 4 })[rng.Next(3)];
                    float podium = l.shops ? 9f : 4f;
                    // podium + tower body with one setback for tall ones
                    RBox(b, M_ROOF, c, new Vector3(l.w, podium + sink, l.d), l.yaw, new Vector2(8, 8));
                    float t1 = l.h > 120 ? h * 0.62f : h;
                    Vector3 s = new Vector3(l.w * 0.86f, t1 - podium - sink, l.d * 0.86f);
                    Vector3 bc = c + Vector3.up * (podium + sink);
                    RBox(b, M_TOWER0 + skin, bc, s, l.yaw, new Vector2(towerTile[skin], towerTile[skin]));
                    if (l.h > 120)
                    {
                        Vector3 s2 = new Vector3(s.x * 0.76f, h - t1, s.z * 0.76f);
                        RBox(b, M_TOWER0 + skin, bc + Vector3.up * s.y, s2, l.yaw, new Vector2(towerTile[skin], towerTile[skin]));
                        s = new Vector3(s2.x, s.y + s2.y, s2.z);
                    }
                    // LED edges at the corners and a crown line, red aircraft lights on tall towers
                    int led = l.style == "tower" ? (R() < 0.5f ? M_LED_W : M_LED_B) : l.style == "tower_res" ? M_LED_P : M_LED_G;
                    var q = Quaternion.Euler(0, l.yaw, 0);
                    float topY = c.y + h;
                    for (int cx = -1; cx <= 1; cx += 2)
                        for (int cz = -1; cz <= 1; cz += 2)
                        {
                            Vector3 corner = bc + q * new Vector3(cx * l.w * 0.43f, 0, cz * l.d * 0.43f);
                            RBox(b, led, corner, new Vector3(0.35f, (l.h > 120 ? t1 - podium - sink : s.y), 0.35f), l.yaw, Vector2.one);
                            if (l.h > 55) RBox(b, M_RED, new Vector3(corner.x, topY + 0.4f, corner.z) + q * new Vector3(-cx * l.w * 0.1f, 0, -cz * l.d * 0.1f), Vector3.one * 0.6f, 0, Vector2.one);
                        }
                    RBox(b, led, new Vector3(c.x, topY - 0.4f, c.z), new Vector3(s.x + 0.3f, 0.4f, s.z + 0.3f), l.yaw, Vector2.one, false);
                    if (l.shops) Face(b, M_SHOP, c + Vector3.up * (sink + 0.3f), l.yaw, hd, -l.w * 0.45f, l.w * 0.45f, 0f, 4.5f, new Vector2(Mathf.Max(6f, l.w * 0.9f), 4.5f));
                    break;
                }
                case "midrise":
                {
                    int f = M_FAC0 + rng.Next(8);
                    RBox(b, f, c, new Vector3(l.w, h, l.d), l.yaw, new Vector2(12f, 14f));
                    RBox(b, M_ROOF, c + Vector3.up * h, new Vector3(l.w + 0.4f, 0.6f, l.d + 0.4f), l.yaw, new Vector2(6, 6));
                    if (l.shops)
                    {
                        Face(b, M_SHOP, c + Vector3.up * (sink + 0.3f), l.yaw, hd, -l.w * 0.45f, l.w * 0.45f, 0f, 4.2f, new Vector2(Mathf.Max(6f, l.w * 0.9f), 4.2f));
                        Face(b, M_SIGN0 + rng.Next(4), c + Vector3.up * (sink + 4.8f), l.yaw, hd, -l.w * 0.3f, l.w * 0.3f, 0f, 0.7f, Vector2.one, 0.2f);
                    }
                    break;
                }
                case "villa":
                {
                    int m = R() < 0.55f ? M_STUCCO : M_SAND;
                    float vw = l.w * 0.6f, vd = l.d * 0.55f, vh = Mathf.Min(l.h, 8f);
                    RBox(b, m, c, new Vector3(vw, vh + sink, vd), l.yaw, new Vector2(4, 4));
                    RBox(b, m, c + Vector3.up * (vh + sink), new Vector3(vw * 0.6f, 3f, vd * 0.6f), l.yaw, new Vector2(4, 4));   // upper floor
                    // lit windows on the front, low garden wall all round
                    Face(b, M_ROOMS, c + Vector3.up * (sink + 1f), l.yaw, vd * 0.5f, -vw * 0.35f, vw * 0.35f, 0f, 1.8f, new Vector2(vw * 0.7f, 2.2f));
                    var q = Quaternion.Euler(0, l.yaw, 0);
                    float wx = l.w * 0.48f, wz = l.d * 0.48f;
                    RBox(b, M_WALL, c + q * new Vector3(0, 0, wz), new Vector3(l.w * 0.96f, sink + 1.6f, 0.3f), l.yaw, new Vector2(4, 4));
                    RBox(b, M_WALL, c + q * new Vector3(0, 0, -wz), new Vector3(l.w * 0.96f, sink + 1.6f, 0.3f), l.yaw, new Vector2(4, 4));
                    RBox(b, M_WALL, c + q * new Vector3(wx, 0, 0), new Vector3(0.3f, sink + 1.6f, l.d * 0.96f), l.yaw, new Vector2(4, 4));
                    RBox(b, M_WALL, c + q * new Vector3(-wx, 0, 0), new Vector3(0.3f, sink + 1.6f, l.d * 0.96f), l.yaw, new Vector2(4, 4));
                    break;
                }
                case "warehouse":
                default:
                {
                    RBox(b, M_CORR, c, new Vector3(l.w, h, l.d), l.yaw, new Vector2(3f, 3f));
                    RBox(b, M_ROOF, c + Vector3.up * h, new Vector3(l.w + 0.3f, 0.4f, l.d + 0.3f), l.yaw, new Vector2(6, 6));
                    // roller doors on the front, a lit shop sign over some (tyres, parts: made-up names in the textures)
                    int doors = Mathf.Clamp((int)(l.w / 9f), 1, 4);
                    for (int k = 0; k < doors; k++)
                    {
                        float x0 = -l.w * 0.45f + k * (l.w * 0.9f / doors) + 1f, x1 = x0 + l.w * 0.9f / doors - 2f;
                        Face(b, M_SHUTTER, c + Vector3.up * sink, l.yaw, hd, x0, x1, 0f, Mathf.Min(5f, l.h * 0.7f), new Vector2(3f, 3f));
                    }
                    if (l.shops || R() < 0.4f) Face(b, M_SIGN0 + rng.Next(4), c + Vector3.up * (sink + Mathf.Min(6f, l.h * 0.8f)), l.yaw, hd, -l.w * 0.3f, l.w * 0.3f, 0f, 0.9f, Vector2.one, 0.15f);
                    break;
                }
            }
        }

        // ---------------------------------------------------------------- landmarks
        void Landmark(MeshBuilder b, Mark m)
        {
            Vector3 c = m.p - Vector3.up * 3f;
            switch (m.kind)
            {
                case "needle_tower":
                {
                    // stepped tapering tiers round a core, then a long spire: visible from everywhere, lit silver-white
                    float y = 0; float w = m.w;
                    for (int k = 0; k < 9 && y < m.h * 0.78f; k++)
                    {
                        float th = m.h * 0.78f / 9f;
                        RBox(b, M_TOWER0 + 4, c + Vector3.up * y, new Vector3(w, th + 3f, w * 0.8f), k * 8f, new Vector2(38, 38));
                        RBox(b, M_LED_W, c + Vector3.up * (y + th), new Vector3(w + 0.4f, 0.4f, w * 0.8f + 0.4f), k * 8f, Vector2.one, false);
                        y += th; w *= 0.84f;
                    }
                    RBox(b, M_POLE, c + Vector3.up * y, new Vector3(w * 0.5f, m.h - y + 3f, w * 0.5f), 0, new Vector2(4, 4));
                    RBox(b, M_LED_W, c + Vector3.up * y, new Vector3(w * 0.2f, m.h - y + 3f, w * 0.55f), 45, Vector2.one);
                    RBox(b, M_RED, c + Vector3.up * (m.h + 3f), Vector3.one * 1.2f, 0, Vector2.one);
                    break;
                }
                case "sail_hotel":
                {
                    // a sail: slices that lean forward and get narrower going up, a white glowing edge
                    int n = 16;
                    for (int k = 0; k < n; k++)
                    {
                        float t = k / (float)n, th = m.h / n;
                        float lean = Mathf.Sin(t * Mathf.PI * 0.5f) * m.d * 0.6f;
                        float ww = Mathf.Lerp(m.w, m.w * 0.15f, t);
                        RBox(b, M_TOWER0 + 3, c + new Vector3(0, t * m.h, -lean * 0.5f), new Vector3(ww, th + 0.2f, m.d * (1 - t * 0.5f)), 0, new Vector2(26, 26));
                    }
                    RBox(b, M_LED_W, c + new Vector3(0, 0, m.d * 0.5f), new Vector3(1f, m.h, 1f), 0, Vector2.one);
                    RBox(b, M_LED_B, c, new Vector3(m.w * 1.2f, 1f, m.d * 1.2f), 0, Vector2.one, false);
                    break;
                }
                case "arch_hotel":
                {
                    // pink-sand towers on both sides stepping in near the top, a bridge block over a tall arch, lit arch and crown
                    float tw = m.w * 0.3f, gap = m.w - 2f * tw;
                    for (int s = -1; s <= 1; s += 2)
                    {
                        Vector3 tc = c + new Vector3(s * (m.w * 0.5f - tw * 0.5f), 0, 0);
                        RBox(b, M_ARCH, tc, new Vector3(tw, m.h * 0.62f + 3f, m.d), 0, new Vector2(26, 26));
                        RBox(b, M_ARCH, tc + new Vector3(-s * tw * 0.08f, m.h * 0.62f + 3f, 0), new Vector3(tw * 0.84f, m.h * 0.38f, m.d * 0.86f), 0, new Vector2(26, 26));
                        RBox(b, M_LED_G, tc + new Vector3(-s * tw * 0.08f, m.h + 3f, 0), new Vector3(tw * 0.86f, 0.6f, m.d * 0.88f), 0, Vector2.one, false);
                        RBox(b, M_LED_G, tc + new Vector3(s * tw * 0.5f, 0, 0), new Vector3(0.6f, m.h + 3f, 0.6f), 0, Vector2.one);
                    }
                    float archTop = m.h * 0.72f;
                    RBox(b, M_ARCH, c + new Vector3(0, archTop + 3f, 0), new Vector3(gap + 2f, m.h * 0.2f, m.d * 0.7f), 0, new Vector2(26, 26));
                    // the arch outline: a lit band under the bridge and up both inner walls
                    RBox(b, M_LED_G, c + new Vector3(0, archTop + 2.4f, m.d * 0.36f), new Vector3(gap, 0.8f, 0.4f), 0, Vector2.one);
                    RBox(b, M_LED_G, c + new Vector3(0, archTop + 2.4f, -m.d * 0.36f), new Vector3(gap, 0.8f, 0.4f), 0, Vector2.one);
                    for (int s = -1; s <= 1; s += 2) RBox(b, M_LED_G, c + new Vector3(s * gap * 0.5f, 0, m.d * 0.5f + 0.2f), new Vector3(0.6f, archTop + 3f, 0.4f), 0, Vector2.one);
                    break;
                }
                case "big_wheel":
                {
                    // ring of lit segments in the X/Y plane on a stand
                    float rad = m.h * 0.45f; Vector3 hub = c + Vector3.up * (m.h * 0.52f + 3f);
                    int seg = 40;
                    for (int k = 0; k < seg; k++)
                    {
                        float a = k * Mathf.PI * 2 / seg;
                        Vector3 p = hub + new Vector3(0, Mathf.Sin(a) * rad, Mathf.Cos(a) * rad);
                        b.Sub(M_LED_P).Add(UnitCube(), Matrix4x4.TRS(p, Quaternion.Euler(-a * Mathf.Rad2Deg, 0, 0), new Vector3(1.2f, 1f, rad * 2 * Mathf.PI / seg)), M_LED_P);
                        if (k % 4 == 0) b.Sub(M_POLE).Add(UnitCube(), Matrix4x4.TRS((p + hub) * 0.5f, Quaternion.Euler(-a * Mathf.Rad2Deg + 90, 0, 0), new Vector3(0.4f, 0.4f, rad)), M_POLE);
                    }
                    for (int s = -1; s <= 1; s += 2)
                        b.Sub(M_POLE).Add(UnitCube(), Matrix4x4.TRS(c + new Vector3(0, (m.h * 0.52f + 3f) * 0.5f, s * rad * 0.3f), Quaternion.Euler(-s * 15f, 0, 0), new Vector3(1.5f, m.h * 0.55f, 1.5f)), M_POLE);
                    break;
                }
                case "twisted_tower":
                {
                    int n = 30; float th = (m.h + 3f) / n;
                    for (int k = 0; k < n; k++)
                    {
                        RBox(b, M_TOWER0 + 1, c + Vector3.up * (k * th), new Vector3(m.w, th + 0.05f, m.d), k * 3f, new Vector2(30, 30), k == n - 1);
                        if (k % 3 == 0) RBox(b, M_LED_P, c + Vector3.up * (k * th + th * 0.5f), new Vector3(m.w + 0.3f, 0.25f, m.d + 0.3f), k * 3f, Vector2.one, false);
                    }
                    break;
                }
                case "ski_mall":
                default:
                {
                    // long box with a sloped roof (the indoor ski slope), glowing entrance strip
                    RBox(b, M_ROOF, c, new Vector3(m.w, m.h * 0.35f + 3f, m.d), 0, new Vector2(8, 8));
                    int n = 10;
                    for (int k = 0; k < n; k++)
                    {
                        float t = k / (float)n;
                        RBox(b, M_STUCCO, c + new Vector3(-m.w * 0.5f + (t + 0.05f) * m.w, m.h * 0.35f + 3f, 0), new Vector3(m.w / n, m.h * 0.65f * (1 - t), m.d * 0.5f), 0, new Vector2(6, 6));
                    }
                    RBox(b, M_LED_B, c + new Vector3(0, 6f, m.d * 0.5f + 0.2f), new Vector3(m.w * 0.8f, 1f, 0.3f), 0, Vector2.one);
                    break;
                }
            }
        }

        static Mesh unitCube;
        static Mesh UnitCube()
        {
            if (unitCube != null) return unitCube;
            var b = new MeshBuilder(); b.Box(Vector3.zero, Vector3.one, 1f, false, false);
            return unitCube = b.Build("cube");
        }

        static Mesh unitCyl;
        /// <summary>Unity's cylinder: radius 0.5, height 2, centred.</summary>
        static Mesh UnitCylinder()
        {
            if (unitCyl != null) return unitCyl;
            var tmp = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            unitCyl = Object.Instantiate(tmp.GetComponent<MeshFilter>().sharedMesh);
            Object.DestroyImmediate(tmp);
            return unitCyl;
        }

        // ---------------------------------------------------------------- lamps and trees
        void Lamp(MeshBuilder b, Vector3 p, float yaw, bool highway)
        {
            float h = highway ? 12f : 8f;
            RBox(b, M_POLE, p - Vector3.up * 0.5f, new Vector3(0.15f, h + 0.5f, 0.15f), yaw, new Vector2(1, 4));   // slim pole
            var q = Quaternion.Euler(0, yaw, 0);
            int arms = highway ? 2 : 1;
            for (int a = 0; a < arms; a++)
            {
                Vector3 dir = q * (a == 0 ? Vector3.forward : Vector3.back);
                float len = highway ? 2.6f : 2.2f;
                b.Sub(M_POLE).Add(UnitCube(), Matrix4x4.TRS(p + Vector3.up * h + dir * len * 0.5f, Quaternion.LookRotation(dir), new Vector3(0.09f, 0.09f, len)), M_POLE);
                Vector3 head = p + Vector3.up * (h - 0.2f) + dir * len;
                // highways: cool white LED heads; streets: warm sodium
                int hm = highway ? M_LAMP_LED : M_LAMP;
                b.Sub(hm).Add(UnitCube(), Matrix4x4.TRS(head, Quaternion.LookRotation(dir), new Vector3(0.45f, 0.18f, 0.8f)), hm);
                lampHeads.Add(head); lampCool.Add(highway);
                // a glow pool on the road under every lamp (only the nearest 40 are real lights): the street reads lit
                if (Physics.Raycast(head + Vector3.down * 0.5f, Vector3.down, out var hit, 20f))
                {
                    float r = highway ? 10f : 6f; Vector3 g = hit.point + Vector3.up * 0.06f;
                    UpQuad(b, highway ? M_POOL_COOL : M_POOL, g + new Vector3(-r, 0, -r), g + new Vector3(-r, 0, r), g + new Vector3(r, 0, r), g + new Vector3(r, 0, -r),
                        Vector2.zero, new Vector2(0, 1), Vector2.one, new Vector2(1, 0));
                }
            }
        }

        void Palm(MeshBuilder b, Vector3 basePos, float scale)
        {
            float h = (7f + R() * 3f) * scale;
            Vector3 lean = new Vector3((R() - 0.5f) * 0.6f, 0, (R() - 0.5f) * 0.6f);
            for (int k = 0; k < 3; k++)
            {
                float t0 = k / 3f, t1 = (k + 1) / 3f;
                Vector3 p = basePos + Vector3.up * h * (t0 + t1) * 0.5f + lean * (t0 + t1) * 0.5f;
                float w = Mathf.Lerp(0.3f, 0.18f, (t0 + t1) * 0.5f) * scale;   // slimmer trunk
                b.Sub(M_BARK).Box(p, new Vector3(w, h / 3f + 0.05f, w), 1f, true, true);
            }
            // Dubai at night: many palms wrapped in warm fairy lights up the trunk, the rest have a small uplight
            if (R() < 0.45f)
            {
                for (float y = 0.5f; y < h * 0.72f; y += 0.5f * scale)
                {
                    float t = y / h; float w = Mathf.Lerp(0.3f, 0.18f, t) * scale * 1.12f;
                    b.Sub(M_LED_G).Box(basePos + Vector3.up * y + lean * t, new Vector3(w, 0.05f, w), 1f, false, false);
                }
            }
            else b.Sub(M_LED_W).Box(basePos + new Vector3(0.45f * scale, 0.06f, 0), new Vector3(0.28f, 0.1f, 0.28f), 1f, true, false);
            Vector3 top = basePos + Vector3.up * h + lean;
            Vector3[] sp = new Vector3[4];
            float[] wid = { 0.12f, 0.7f, 0.55f, 0.1f };
            for (int f = 0; f < 11; f++)
            {
                float a = f * Mathf.PI * 2 / 11 + R() * 0.35f;
                Vector3 dir = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)), side = Vector3.Cross(Vector3.up, dir);
                float len = (3.6f + R() * 0.8f) * scale, droop = (0.9f + R() * 0.9f) * scale;
                sp[0] = top; sp[1] = top + dir * len * 0.36f + Vector3.up * 0.5f * scale;
                sp[2] = top + dir * len * 0.7f + Vector3.up * (0.25f * scale - droop * 0.35f); sp[3] = top + dir * len + Vector3.down * droop;
                for (int k = 0; k < 3; k++)
                {
                    float v0 = k / 3f, v1 = (k + 1) / 3f;
                    Vector3 f0 = Vector3.down * wid[k] * 0.4f * scale, f1 = Vector3.down * wid[k + 1] * 0.4f * scale;
                    Vector3 l0 = sp[k] - side * wid[k] * scale + f0, l1 = sp[k + 1] - side * wid[k + 1] * scale + f1;
                    Vector3 r0 = sp[k] + side * wid[k] * scale + f0, r1 = sp[k + 1] + side * wid[k + 1] * scale + f1;
                    b.Sub(M_LEAF).QuadUV(l0, sp[k], sp[k + 1], l1, Vector3.up, new Vector2(0, v0), new Vector2(0.5f, v0), new Vector2(0.5f, v1), new Vector2(0, v1));
                    b.Sub(M_LEAF).QuadUV(sp[k], r0, r1, sp[k + 1], Vector3.up, new Vector2(0.5f, v0), new Vector2(1, v0), new Vector2(1, v1), new Vector2(0.5f, v1));
                }
            }
        }

        void Tree(MeshBuilder b, Vector3 p, float s)
        {
            b.Sub(M_BARK).Box(p + Vector3.up * 1.4f * s, new Vector3(0.3f, 2.8f, 0.3f) * s, 1f, true, true);
            for (int k = 0; k < 3; k++)
            {
                float y = (2.6f + k * 1.1f) * s, w = (3.2f - k * 0.8f) * s;
                RBox(b, M_TREE, p + Vector3.up * y, new Vector3(w, 1.4f * s, w), k * 30f + R() * 20f, new Vector2(2, 2));
            }
        }
    }
}
