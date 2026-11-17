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
        System.Random rng = new System.Random(21);
        float R() => (float)rng.NextDouble();

        // materials (slots in the per-cell builders)
        Material[] mats;
        const int M_TOWER0 = 0;          // 0..5 tower skins (office, resi, black, hotel, fins, stone)
        const int M_FAC0 = 6;            // 6..13 facades (midrise)
        const int M_STUCCO = 14, M_SAND = 15, M_CORR = 16, M_SHUTTER = 17, M_ROOF = 18, M_SHOP = 19, M_ROOMS = 20,
                  M_LED_W = 21, M_LED_B = 22, M_LED_P = 23, M_LED_G = 24, M_RED = 25, M_POLE = 26, M_LAMP = 27,
                  M_BARK = 28, M_LEAF = 29, M_TREE = 30, M_GLASS = 31, M_WALL = 32, M_SIGN0 = 33, M_SHORE = 37, M_LAND = 38, M_SHALLOW = 39, M_ARCH = 40, M_COUNT = 41;
        float[] towerTile = { 34f, 30f, 44f, 26f, 38f, 24f };

        public void Build(NewCity nc)
        {
            var ta = Res.Load<TextAsset>("City/city_part1");
            if (ta == null) return;
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
            foreach (var l in lots)
            {
                float rr = Mathf.Max(l.w, l.d) * 0.5f;
                if (l.p.x + rr > g.x - 19f && l.p.x - rr < g.x + 19f && l.p.z + rr > g.z - 14f && l.p.z - rr < g.z + 30f) { skipped++; continue; }
                if (OnRoad(l)) { onRoad++; continue; }
                Building(Cell(l.p), l);
            }
            Landmarks.Clear(); foreach (var m in marks) Landmarks.Add((m.kind, m.p, m.h));
            foreach (var m in marks) Landmark(Cell(m.p), m);
            // lamps and trees in their own meshes without colliders (thin poles must never stop the car)
            var props = new Dictionary<Vector2Int, MeshBuilder>();
            MeshBuilder Prop(Vector3 p)
            {
                var k = new Vector2Int(Mathf.FloorToInt(p.x / 320f), Mathf.FloorToInt(p.z / 320f));
                if (!props.TryGetValue(k, out var b)) { b = new MeshBuilder(M_COUNT); props[k] = b; }
                return b;
            }
            foreach (var lp in lamps) Lamp(Prop(lp.p), lp.p, lp.yaw, lp.highway);
            foreach (var t in trees) if (t.palm) Palm(Prop(t.p), t.p, t.s); else Tree(Prop(t.p), t.p, t.s);
            PalmShores(nc, Prop);
            foreach (var kv in props) MeshBuilder.Spawn("Props_" + kv.Key.x + "_" + kv.Key.y, kv.Value.Build("props"), mats, transform, false, false).isStatic = true;
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
                float land = trunk ? 22f : 11.5f;             // land beyond the road edge
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
                            lampHeads.Add(p + Vector3.up * 3.4f);
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
            Debug.Log($"[HMD] newcity json dressing: lots={lots.Count} landmarks={marks.Count} lamps={lamps.Count} trees={trees.Count}");
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
            mats[M_POLE] = Res.Mat(new Color(0.22f, 0.23f, 0.25f), 0.6f, 0.7f);
            mats[M_LAMP] = Res.Glow(new Color(1f, 0.85f, 0.62f), 7f);
            var bark = Res.Tex("Gen/bark");
            mats[M_BARK] = Res.Mat(new Color(0.45f, 0.36f, 0.27f), 0.15f);
            if (bark) Res.SetMainTex(mats[M_BARK], bark, new Vector2(1, 4));
            var frond = Res.Tex("Gen/frond");
            var leaf = Res.Mat(new Color(0.55f, 0.65f, 0.4f), 0.3f);
            if (frond) { Res.SetMainTex(leaf, frond, Vector2.one); leaf.SetFloat("_AlphaClip", 1f); leaf.SetFloat("_Cutoff", 0.4f); leaf.EnableKeyword("_ALPHATEST_ON"); }
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

        // ---------------------------------------------------------------- lamps and trees
        void Lamp(MeshBuilder b, Vector3 p, float yaw, bool highway)
        {
            float h = highway ? 12f : 8f;
            RBox(b, M_POLE, p - Vector3.up * 0.5f, new Vector3(0.25f, h + 0.5f, 0.25f), yaw, new Vector2(1, 4));
            var q = Quaternion.Euler(0, yaw, 0);
            int arms = highway ? 2 : 1;
            for (int a = 0; a < arms; a++)
            {
                Vector3 dir = q * (a == 0 ? Vector3.forward : Vector3.back);
                float len = highway ? 2.6f : 2.2f;
                b.Sub(M_POLE).Add(UnitCube(), Matrix4x4.TRS(p + Vector3.up * h + dir * len * 0.5f, Quaternion.LookRotation(dir), new Vector3(0.15f, 0.15f, len)), M_POLE);
                Vector3 head = p + Vector3.up * (h - 0.2f) + dir * len;
                b.Sub(M_LAMP).Add(UnitCube(), Matrix4x4.TRS(head, Quaternion.LookRotation(dir), new Vector3(0.45f, 0.18f, 0.8f)), M_LAMP);
                lampHeads.Add(head);
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
                float w = Mathf.Lerp(0.42f, 0.26f, (t0 + t1) * 0.5f) * scale;
                b.Sub(M_BARK).Box(p, new Vector3(w, h / 3f + 0.05f, w), 1f, true, true);
            }
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
