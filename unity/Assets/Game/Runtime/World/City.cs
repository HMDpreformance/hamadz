using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace HMD
{
    /// <summary>
    /// Dubai-style night city on a grid: wide boulevards with lane markings, curbs and sidewalks,
    /// palm-lined medians, shop-front podiums with glowing signs, mid-rise blocks with photo facades
    /// whose windows light up at night, glass towers downtown and a far skyline with a super-tall
    /// spire. Each block is merged into one mesh per material to keep draw calls low on phones.
    /// </summary>
    public class City : MonoBehaviour
    {
        public static City I;

        public const int N = 8;              // blocks per side
        public const float Block = 76f;      // block size (kerb to kerb)
        public const float Road = 24f;       // road width (4 lanes + median)
        public const float Pitch = Block + Road;
        public const float Walk = 5f;        // sidewalk width inside the block
        public const float LaneW = 4.2f;
        public const float Median = 2.4f;

        public static readonly Vector2Int GarageBlock = new Vector2Int(5, 3);

        public readonly List<Vector3> lampHeads = new List<Vector3>();
        public Vector3 GarageDoor { get; private set; }
        public Quaternion GarageFacing { get; private set; }
        public Vector3 PlayerStart { get; private set; }
        public Quaternion PlayerStartRot { get; private set; }

        Material asphalt, walkMat, curbMat, lineWhite, lineYellow, medianMat, palmLeaf, palmBark, lampPole, lampGlow;
        Material[] facades, shopMats, neon, towers;
        float[] towerTile;
        Material glassTower, glassDark, roofMat, podiumMat;
        System.Random rng;

        public static float Extent => N * Pitch;

        /// <summary>Centre of the road line that runs between block k-1 and block k (k = 0..N).</summary>
        public static float RoadLine(int k) => k * Pitch - Road * 0.5f;

        public static Vector3 BlockCenter(int i, int j) => new Vector3(i * Pitch + Block * 0.5f, 0, j * Pitch + Block * 0.5f);

        public void Build(int seed = 7)
        {
            I = this;
            rng = new System.Random(seed);
            MakeMaterials();
            BuildGround();
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++)
                    BuildBlock(i, j);
            BuildRoadMarkings();
            BuildMedians();
            BuildSkyline();
            // garage: door on the south face of its block, opening onto the road
            var gc = BlockCenter(GarageBlock.x, GarageBlock.y);
            GarageDoor = new Vector3(gc.x, 0, gc.z - Block * 0.5f + Walk);
            GarageFacing = Quaternion.Euler(0, 180, 0);    // the door looks to -Z
            float roadZ = GarageBlock.y * Pitch - Road * 0.5f;
            PlayerStart = new Vector3(gc.x - 30f, 0.6f, roadZ - LaneW * 0.5f - Median * 0.5f);
            PlayerStartRot = Quaternion.Euler(0, 90, 0);
        }

        void MakeMaterials()
        {
            asphalt = Res.TexMat("Tex/asphalt_04", new Vector2(1, 1) / 6f, 0.45f, 0f, new Color(0.55f, 0.55f, 0.58f));
            walkMat = Res.TexMat("Tex/concrete_pavement", Vector2.one / 3f, 0.35f, 0f, new Color(0.7f, 0.68f, 0.66f));
            curbMat = Res.TexMat("Tex/granite_tile", Vector2.one / 2f, 0.5f, 0f, new Color(0.75f, 0.74f, 0.72f));
            medianMat = Res.TexMat("Tex/granite_tile", Vector2.one / 2f, 0.45f, 0f, new Color(0.55f, 0.52f, 0.5f));
            lineWhite = Res.Mat(new Color(0.85f, 0.85f, 0.82f), 0.55f);
            lineYellow = Res.Mat(new Color(0.9f, 0.7f, 0.1f), 0.55f);
            // wet look: road, paint and pavement mirror the city (WetRoad shader + planar reflection)
            Res.MakeWet(asphalt); Res.MakeWet(lineWhite); Res.MakeWet(lineYellow); Res.MakeWet(walkMat);
            var frond = Res.Tex("Gen/frond");
            palmLeaf = Res.Mat(new Color(0.55f, 0.65f, 0.4f), 0.3f);
            if (frond != null)
            {
                Res.SetMainTex(palmLeaf, frond, Vector2.one);
                palmLeaf.SetFloat("_AlphaClip", 1f);
                palmLeaf.SetFloat("_Cutoff", 0.4f);
                palmLeaf.EnableKeyword("_ALPHATEST_ON");
                palmLeaf.SetFloat("_Cull", 0f);   // two-sided
                palmLeaf.renderQueue = 2450;
            }
            palmBark = Res.Mat(new Color(0.45f, 0.36f, 0.27f), 0.15f);
            var bark = Res.Tex("Gen/bark");
            if (bark) Res.SetMainTex(palmBark, bark, new Vector2(1, 4));
            lampPole = Res.Mat(new Color(0.18f, 0.19f, 0.2f), 0.6f, 0.8f);
            lampGlow = Res.Glow(new Color(1f, 0.82f, 0.55f), 6f);

            var names = new[] { "facade005", "facade007", "facade009", "facade010", "facade012", "facade014", "facade015", "facade017" };
            var fl = new List<Material>();
            foreach (var n in names)
            {
                var m = Res.TexMat("Facade/" + n, Vector2.one, 0.55f, 0f);
                var e = Res.Tex("Facade/" + n + "_emit");
                if (e != null) Res.SetEmission(m, new Color(1f, 0.78f, 0.5f) * 1.6f, e);
                fl.Add(m);
            }
            facades = fl.ToArray();

            var shops = new List<Material>();
            foreach (var n in new[] { "Gen/shops", "Gen/rooms" })
            {
                var t = Res.Tex(n);
                var m = Res.Mat(Color.white, 0.6f);
                if (t) { Res.SetMainTex(m, t, Vector2.one); Res.SetEmission(m, Color.white * 1.3f, t); }
                shops.Add(m);
            }
            shopMats = shops.ToArray();

            neon = new[]
            {
                Res.Glow(new Color(1f, 0.1f, 0.55f), 5f), Res.Glow(new Color(0.1f, 0.85f, 1f), 5f),
                Res.Glow(new Color(1f, 0.55f, 0.05f), 5f), Res.Glow(new Color(0.55f, 0.2f, 1f), 5f),
                Res.Glow(new Color(0.2f, 1f, 0.45f), 4f), Res.Glow(new Color(1f, 0.95f, 0.85f), 4f),
                Res.Glow(new Color(1f, 0.03f, 0.02f), 7f),   // last: red aircraft warning lights
            };
            // tower skins: photo facades with lit windows (generated for the game), one repeat = ~10 floors
            var tn = new[] { "office", "resi", "black", "hotel", "fins", "stone" };
            var tsz = new[] { 34f, 30f, 44f, 26f, 38f, 24f };
            var tl = new List<Material>(); var tt = new List<float>();
            for (int k = 0; k < tn.Length; k++)
            {
                var d = Res.Tex("Tower/" + tn[k]);
                if (d == null) continue;
                bool glassy = k == 0 || k == 2 || k == 4;
                var m = Res.Mat(Color.white, glassy ? 0.6f : 0.45f, glassy ? 0.15f : 0f);   // less mirror: seen steeply from below they reflected the bright probe as a white block
                Res.SetMainTex(m, d, Vector2.one);
                var e = Res.Tex("Tower/" + tn[k] + "_emit");
                Res.SetEmission(m, Color.white * (tn[k] == "fins" ? 0.7f : 1.05f), e != null ? e : d);   // fins skin has big white panels: dimmer
                tl.Add(m); tt.Add(tsz[k]);
            }
            towers = tl.ToArray(); towerTile = tt.ToArray();

            glassTower = Res.Mat(new Color(0.1f, 0.14f, 0.2f), 0.78f, 0.55f);   // less mirror: a near tower top reflected the bright probe as a white block   // opaque mirror glass: reflects the city via the camera probe
            glassTower.SetFloat("_Metallic", 0.85f);
            Res.SetEmission(glassTower, new Color(0.25f, 0.5f, 0.85f) * 0.05f);
            glassDark = Res.Mat(new Color(0.05f, 0.07f, 0.09f), 0.95f, 0.9f);
            roofMat = Res.TexMat("Tex/concrete_panels", Vector2.one / 4f, 0.3f, 0f, new Color(0.5f, 0.5f, 0.5f));
            podiumMat = Res.TexMat("Tex/exterior_wall_cladding", Vector2.one / 3f, 0.5f, 0f, new Color(0.85f, 0.82f, 0.78f));
        }

        float R() => (float)rng.NextDouble();
        int Ri(int n) => rng.Next(n);

        void BuildGround()
        {
            // one big asphalt slab under everything (the roads), with a collider
            var b = new MeshBuilder();
            float m = 60f;
            float x0 = -Road - m, x1 = N * Pitch + m;
            var a = new Vector3(x0, 0, x0); var bb = new Vector3(x1, 0, x0);
            var c = new Vector3(x1, 0, x1); var d = new Vector3(x0, 0, x1);
            // seen from above: a->b->c->d is counter-clockwise when looking down?  Use explicit UVs.
            b.QuadUV(a, bb, c, d, Vector3.up, new Vector2(x0, x0), new Vector2(x1, x0), new Vector2(x1, x1), new Vector2(x0, x1));
            var go = MeshBuilder.Spawn("Asphalt", b.Build("asphalt"), new[] { asphalt }, transform, false, false);
            go.GetComponent<MeshRenderer>().receiveShadows = true;
            var col = go.AddComponent<BoxCollider>();
            col.center = new Vector3((x0 + x1) / 2, -0.5f, (x0 + x1) / 2);
            col.size = new Vector3(x1 - x0, 1f, x1 - x0);
            // invisible city edge walls
            for (int s = 0; s < 4; s++)
            {
                var w = new GameObject("Edge" + s).AddComponent<BoxCollider>();
                w.transform.SetParent(transform, false);
                float len = x1 - x0, mid = (x0 + x1) / 2;
                w.size = s < 2 ? new Vector3(len, 20, 2) : new Vector3(2, 20, len);
                w.center = s == 0 ? new Vector3(mid, 10, x0 + 30) : s == 1 ? new Vector3(mid, 10, x1 - 30) : s == 2 ? new Vector3(x0 + 30, 10, mid) : new Vector3(x1 - 30, 10, mid);
            }
        }

        // sub-mesh slots per block
        const int S_WALK = 0, S_CURB = 1, S_ROOF = 2, S_PODIUM = 3, S_GLASS = 4, S_GLASSDARK = 5, S_SHOP0 = 6, S_SHOP1 = 7, S_POLE = 8, S_LAMP = 9, S_FAC = 10; // + facades
        int NeonSlot(int k) => S_FAC + facades.Length + k;
        int TowerSlot(int k) => S_FAC + facades.Length + neon.Length + k;

        void BuildBlock(int i, int j)
        {
            int subs = S_FAC + facades.Length + neon.Length + towers.Length;
            var b = new MeshBuilder(subs);
            var c = BlockCenter(i, j);
            float h = Block * 0.5f;
            bool garage = new Vector2Int(i, j) == GarageBlock;

            // sidewalk slab + kerb
            b.Sub(S_WALK).Box(c + new Vector3(0, 0.09f, 0), new Vector3(Block - 0.6f, 0.18f, Block - 0.6f), 3f);
            b.Sub(S_CURB).Box(c + new Vector3(0, 0.08f, -h + 0.15f), new Vector3(Block, 0.16f, 0.3f), 1f);
            b.Sub(S_CURB).Box(c + new Vector3(0, 0.08f, h - 0.15f), new Vector3(Block, 0.16f, 0.3f), 1f);
            b.Sub(S_CURB).Box(c + new Vector3(-h + 0.15f, 0.08f, 0), new Vector3(0.3f, 0.16f, Block), 1f);
            b.Sub(S_CURB).Box(c + new Vector3(h - 0.15f, 0.08f, 0), new Vector3(0.3f, 0.16f, Block), 1f);

            // street lamps along the kerb, every ~25 m, arms over the road
            for (int side = 0; side < 4; side++)
                for (float t = -h + 10; t <= h - 10; t += 25f)
                {
                    Vector3 outDir = side == 0 ? Vector3.back : side == 1 ? Vector3.forward : side == 2 ? Vector3.left : Vector3.right;
                    Vector3 along = side < 2 ? Vector3.right : Vector3.forward;
                    Vector3 p = c + along * t + outDir * (h - 0.8f);
                    b.Sub(S_POLE).Box(p + Vector3.up * 4.5f, new Vector3(0.22f, 9f, 0.22f), 1f);
                    b.Sub(S_POLE).Box(p + Vector3.up * 8.9f + outDir * 1.3f, outDir.x != 0 ? new Vector3(2.6f, 0.14f, 0.14f) : new Vector3(0.14f, 0.14f, 2.6f), 1f);
                    Vector3 head = p + Vector3.up * 8.75f + outDir * 2.4f;
                    b.Sub(S_POLE).Box(head + Vector3.up * 0.08f, new Vector3(0.7f, 0.16f, 0.7f), 1f);
                    b.Sub(S_LAMP).Box(head - Vector3.up * 0.04f, new Vector3(0.56f, 0.06f, 0.56f), 1f, false, true);
                    lampHeads.Add(head - Vector3.up * 0.3f);
                }

            // buildings: lots around the edge, the middle is a courtyard / parking
            float inner = h - Walk;
            if (garage)
            {
                // the LSX garage and its yard take the south part; only the north row is built
                BuildRow(b, c, inner, 1, i, j);
            }
            else
            {
                for (int side = 0; side < 4; side++) BuildRow(b, c, inner, side, i, j);
            }

            var mats = new List<Material> { walkMat, curbMat, roofMat, podiumMat, glassTower, glassDark, shopMats[0], shopMats[shopMats.Length > 1 ? 1 : 0], lampPole, lampGlow };
            mats.AddRange(facades);
            mats.AddRange(neon);
            mats.AddRange(towers);
            var go = MeshBuilder.Spawn("Block_" + i + "_" + j, b.Build("block"), mats.ToArray(), transform, true, true);
            go.isStatic = true;
        }

        /// <summary>A row of buildings along one side of a block (0 = south, 1 = north, 2 = west, 3 = east).</summary>
        void BuildRow(MeshBuilder b, Vector3 c, float inner, int side, int bi, int bj)
        {
            // downtown = centre of the grid gets towers
            float dist = Vector2.Distance(new Vector2(bi, bj), new Vector2(N * 0.5f - 0.5f, N * 0.5f - 0.5f));
            float downtown = Mathf.Clamp01(1f - dist / (N * 0.55f));
            Vector3 along = side < 2 ? Vector3.right : Vector3.forward;
            Vector3 outDir = side == 0 ? Vector3.back : side == 1 ? Vector3.forward : side == 2 ? Vector3.left : Vector3.right;
            float depth = 16f + R() * 6f;
            float start = -inner + (side >= 2 ? depth : 0);
            float end = inner - (side >= 2 ? depth : 0);
            float t = start;
            while (t < end - 6f)
            {
                float w = Mathf.Min(end - t, 14f + R() * 16f);
                if (end - (t + w) < 8f) w = end - t;
                Vector3 front = c + outDir * inner + along * (t + w * 0.5f);
                Vector3 ctr = front - outDir * depth * 0.5f;
                Vector3 size = side < 2 ? new Vector3(w - 0.4f, 0, depth) : new Vector3(depth, 0, w - 0.4f);
                bool tower = R() < downtown * 0.75f;
                float height = tower ? 45f + R() * 110f * downtown : 10f + R() * 22f;
                Building(b, ctr, size, height, outDir, along, w, tower);
                t += w;
            }
        }

        void Building(MeshBuilder b, Vector3 ctr, Vector3 size, float height, Vector3 outDir, Vector3 along, float frontW, bool tower)
        {
            float podiumH = 5.2f;
            // podium with shop fronts facing the street
            b.Sub(S_PODIUM).Box(ctr + Vector3.up * podiumH * 0.5f, new Vector3(size.x, podiumH, size.z), 3f, true, false);
            // shop window band (glowing photo shop interiors), on the street face, slightly proud
            Vector3 fc = ctr + outDir * (Vector3.Scale(size, Abs(outDir)).magnitude * 0.5f + 0.05f);
            Vector3 a0 = fc - along * (frontW * 0.5f - 0.8f) + Vector3.up * 0.4f;
            Vector3 a1 = fc + along * (frontW * 0.5f - 0.8f) + Vector3.up * 0.4f;
            WallFacing(b.Sub(R() < 0.5f ? S_SHOP0 : S_SHOP1), a0, a1, 3.6f, outDir, new Vector2(Mathf.Max(6f, frontW - 1.6f), 3.6f), new Vector2(R(), 0));
            // neon sign over the shop
            var ns = NeonSlot(Ri(neon.Length));
            Vector3 sc = fc + outDir * 0.25f + Vector3.up * 4.4f;
            float sw = Mathf.Min(frontW * 0.6f, 9f);
            b.Sub(ns).Box(sc, Abs(along) * sw + Abs(outDir) * 0.12f + Vector3.up * 0.55f, 1f, false, false);
            if (R() < 0.5f)
            {
                // vertical blade sign
                var ns2 = NeonSlot(Ri(neon.Length));
                Vector3 vc = fc + outDir * 0.9f + along * (frontW * 0.5f - 1.5f) + Vector3.up * (podiumH + 4f);
                b.Sub(ns2).Box(vc, Abs(outDir) * 1.4f + Abs(along) * 0.25f + Vector3.up * 5f, 1f, false, false);
            }

            float rest = height - podiumH;
            if (rest < 2) return;
            Vector3 upper = new Vector3(size.x - 1.2f, rest, size.z - 1.2f);
            Vector3 uc = ctr + Vector3.up * (podiumH + rest * 0.5f);
            if (tower)
            {
                // glass tower: shrinks with setbacks, glowing crown
                float tiers = 1 + Ri(3);
                float th = rest / tiers;
                Vector3 s = upper;
                // about a third are mirror-glass towers (they reflect the city through the camera probe), the rest photo skins
                int skin = towers.Length > 0 && R() > 0.32f ? Ri(towers.Length) : -1;
                bool fins = skin >= 0 && R() < 0.45f;
                Vector3 topS = upper;
                for (int k = 0; k < tiers; k++)
                {
                    Vector3 tc = ctr + Vector3.up * (podiumH + th * k + th * 0.5f);
                    if (skin >= 0) b.Sub(TowerSlot(skin)).Box(tc, new Vector3(s.x, th, s.z), towerTile[skin], true, true);
                    else
                    {
                        b.Sub(S_GLASS).Box(tc, new Vector3(s.x, th, s.z), 4f, true, false);
                        // dark mullions every 1.5 m and a thin lit edge every floor, so the mirror reads as a facade
                        var edge = NeonSlot(5);
                        for (float y = 3.5f; y < th - 0.5f; y += 3.5f)
                            b.Sub(S_GLASSDARK).Box(tc + Vector3.up * (y - th * 0.5f), new Vector3(s.x + 0.12f, 0.18f, s.z + 0.12f), 1f, true, true);
                        if (R() < 0.6f)
                            for (float y = 7f; y < th - 0.5f; y += 7f)
                                b.Sub(edge).Box(tc + Vector3.up * (y - th * 0.5f + 0.12f), new Vector3(s.x + 0.16f, 0.05f, s.z + 0.16f), 1f, true, true);
                    }
                    // vertical fins on the lower tier of some towers: deep shadow lines that break the flat box
                    if (fins && k == 0)
                    {
                        for (float fx = -s.x * 0.5f + 1.5f; fx < s.x * 0.5f - 1f; fx += 2.4f)
                            for (int sz = -1; sz <= 1; sz += 2)
                                b.Sub(S_GLASSDARK).Box(tc + new Vector3(fx, 0, sz * (s.z * 0.5f + 0.3f)), new Vector3(0.28f, th, 0.6f), 4f, true, true);
                        for (float fz = -s.z * 0.5f + 1.5f; fz < s.z * 0.5f - 1f; fz += 2.4f)
                            for (int sx = -1; sx <= 1; sx += 2)
                                b.Sub(S_GLASSDARK).Box(tc + new Vector3(sx * (s.x * 0.5f + 0.3f), 0, fz), new Vector3(0.6f, th, 0.28f), 4f, true, true);
                    }
                    topS = s;
                    // roof slab + parapet on every setback, so the steps read as real terraces
                    b.Sub(S_ROOF).Box(tc + Vector3.up * (th * 0.5f + 0.25f), new Vector3(s.x + 0.6f, 0.5f, s.z + 0.6f), 4f, true, false);
                    // corner piers give the tower some depth
                    if (k == 0 && s.x > 8 && s.z > 8)
                        for (int cx = -1; cx <= 1; cx += 2)
                            for (int cz = -1; cz <= 1; cz += 2)
                                b.Sub(S_GLASSDARK).Box(tc + new Vector3(cx * s.x * 0.5f, 0, cz * s.z * 0.5f), new Vector3(0.9f, th, 0.9f), 4f, true, true);
                    // horizontal light bands every few floors (like Dubai towers at night)
                    var band = NeonSlot(R() < 0.6f ? 5 : Ri(neon.Length));
                    for (float y = 3.5f * 4; y < th; y += 3.5f * (4 + Ri(5)))
                        b.Sub(band).Box(tc + Vector3.up * (y - th * 0.5f), new Vector3(s.x + 0.1f, 0.12f, s.z + 0.1f), 1f, true, true);
                    s = new Vector3(s.x * (0.72f + R() * 0.15f), 0, s.z * (0.72f + R() * 0.15f));
                }
                // roof plant, a lit crown and a mast with a red aircraft light
                Vector3 top = ctr + Vector3.up * height;
                Vector3 last = s / (0.72f + 0.075f);
                b.Sub(S_ROOF).Box(top + Vector3.up * 1.6f, new Vector3(last.x * 0.45f, 3.2f, last.z * 0.45f), 4f, true, false);
                b.Sub(NeonSlot(Ri(neon.Length))).Box(top + Vector3.up * 3.4f, new Vector3(last.x * 0.47f, 0.35f, last.z * 0.47f), 1f, true, false);
                int red = NeonSlot(neon.Length - 1);
                if (height > 80f)
                {
                    b.Sub(S_POLE).Box(top + Vector3.up * 9f, new Vector3(0.35f, 12f, 0.35f), 1f, true, false);
                    b.Sub(red).Box(top + Vector3.up * 15.2f, new Vector3(0.7f, 0.7f, 0.7f), 1f, false, false);
                }
                // red aircraft warning lights on the roof corners of tall towers
                if (height > 55f)
                    for (int cx = -1; cx <= 1; cx += 2)
                        for (int cz = -1; cz <= 1; cz += 2)
                            b.Sub(red).Box(top + new Vector3(cx * (topS.x * 0.5f - 0.3f), 0.85f, cz * (topS.z * 0.5f - 0.3f)), Vector3.one * 0.5f, 1f, false, false);
                // a lit brand sign on one face of the top tier, high up (seen from far down the street)
                if (R() < 0.55f && topS.x > 10f)
                {
                    int signMat = NeonSlot(Ri(neon.Length - 1));
                    float sy = height - Mathf.Min(th * 0.5f, 9f);
                    int face = Ri(4);
                    Vector3 fdir = face == 0 ? Vector3.forward : face == 1 ? Vector3.back : face == 2 ? Vector3.right : Vector3.left;
                    float half = (face < 2 ? topS.z : topS.x) * 0.5f + 0.35f;
                    Vector3 signC = ctr + Vector3.up * sy + fdir * half;
                    Vector3 sz3 = face < 2 ? new Vector3(topS.x * 0.55f, 3.2f, 0.25f) : new Vector3(0.25f, 3.2f, topS.z * 0.55f);
                    b.Sub(S_GLASSDARK).Box(signC - fdir * 0.05f, sz3 + Vector3.up * 0.8f + (face < 2 ? Vector3.right : Vector3.forward) * 0.8f, 1f, true, false);
                    b.Sub(signMat).Box(signC + fdir * 0.12f, new Vector3(sz3.x * (face < 2 ? 0.92f : 1f), 2.4f, sz3.z * (face < 2 ? 1f : 0.92f)), 1f, true, false);
                }
            }
            else
            {
                // mid-rise: one photo facade per building, windows glow from the emission map
                int f = S_FAC + Ri(facades.Length);
                Vector3 hs = upper * 0.5f;
                Vector2 uvm = new Vector2(8f, 8f);   // one texture repeat = 8 x 8 m (about 2-3 floors)
                Vector3 bc = uc - Vector3.up * rest * 0.5f;
                Vector3 p00 = bc + new Vector3(-hs.x, 0, -hs.z), p10 = bc + new Vector3(hs.x, 0, -hs.z);
                Vector3 p11 = bc + new Vector3(hs.x, 0, hs.z), p01 = bc + new Vector3(-hs.x, 0, hs.z);
                var off = new Vector2(R(), 0);
                b.Sub(f);
                b.Wall(p00, p10, rest, uvm, off);   // south face (faces -Z)
                b.Wall(p10, p11, rest, uvm, off);   // east
                b.Wall(p11, p01, rest, uvm, off);   // north
                b.Wall(p01, p00, rest, uvm, off);   // west
                b.Sub(S_ROOF).Box(uc + Vector3.up * (rest * 0.5f + 0.25f), new Vector3(upper.x + 0.3f, 0.5f, upper.z + 0.3f), 4f, true, false);
                // rooftop kit: AC boxes, water tank
                for (int k = 0; k < 2 + Ri(3); k++)
                    b.Sub(S_ROOF).Box(uc + new Vector3((R() - 0.5f) * upper.x * 0.7f, rest * 0.5f + 1f, (R() - 0.5f) * upper.z * 0.7f), new Vector3(1.6f, 1.4f, 2.2f), 2f);
            }
        }

        static Vector3 Abs(Vector3 v) => new Vector3(Mathf.Abs(v.x), Mathf.Abs(v.y), Mathf.Abs(v.z));

        /// <summary>A vertical quad whose front looks along outDir.</summary>
        static void WallFacing(MeshBuilder b, Vector3 a0, Vector3 a1, float h, Vector3 outDir, Vector2 uvMetres, Vector2 off)
        {
            // MeshBuilder.Wall faces to the right of a->b; pick the order so that is outDir
            Vector3 right = Vector3.Cross(Vector3.up, (a1 - a0).normalized);
            if (Vector3.Dot(right, outDir) < 0) { var t = a0; a0 = a1; a1 = t; }
            b.Wall(a0, a1, h, uvMetres, off);
        }

        void BuildRoadMarkings()
        {
            var b = new MeshBuilder(2);
            float y = 0.012f;
            for (int k = 0; k <= N; k++)
            {
                float line = RoadLine(k);
                for (int seg = 0; seg < N; seg++)
                {
                    float s0 = seg * Pitch + 1.5f, s1 = seg * Pitch + Block - 1.5f;
                    // lane dashes (between the two lanes on each side of the median)
                    for (int side = -1; side <= 1; side += 2)
                    {
                        float off = side * (Median * 0.5f + LaneW);
                        for (float s = s0; s < s1 - 3; s += 9f)
                        {
                            Strip(b, 0, new Vector3(line + off, y, s), new Vector3(line + off, y, s + 3f), 0.15f);   // along Z
                            Strip(b, 0, new Vector3(s, y, line + off), new Vector3(s + 3f, y, line + off), 0.15f);   // along X
                        }
                        // edge line
                        float e = side * (Road * 0.5f - 0.6f);
                        Strip(b, 0, new Vector3(line + e, y, s0), new Vector3(line + e, y, s1), 0.14f);
                        Strip(b, 0, new Vector3(s0, y, line + e), new Vector3(s1, y, line + e), 0.14f);
                        // stop line before each crossing
                        float sl = side < 0 ? s0 + 0.3f : s1 - 0.3f;
                        Strip(b, 0, new Vector3(line + (side < 0 ? Median * 0.5f : -Road * 0.5f + 0.6f), y, sl), new Vector3(line + (side < 0 ? Road * 0.5f - 0.6f : -Median * 0.5f), y, sl), 0.45f);
                        Strip(b, 0, new Vector3(sl, y, line + (side < 0 ? -Road * 0.5f + 0.6f : Median * 0.5f)), new Vector3(sl, y, line + (side < 0 ? -Median * 0.5f : Road * 0.5f - 0.6f)), 0.45f);
                    }
                }
                // zebra crossings at every intersection side
                for (int m = 0; m <= N; m++)
                {
                    float other = RoadLine(m);
                    for (int side = -1; side <= 1; side += 2)
                    {
                        float zc = other + side * (Road * 0.5f + 2.2f);
                        for (float x = -Road * 0.5f + 1f; x < Road * 0.5f - 1f; x += 1.2f)
                        {
                            Strip(b, 0, new Vector3(line + x, y, zc - 1.6f), new Vector3(line + x, y, zc + 1.6f), 0.55f);
                            Strip(b, 0, new Vector3(zc - 1.6f, y, line + x), new Vector3(zc + 1.6f, y, line + x), 0.55f);
                        }
                    }
                }
            }
            var go = MeshBuilder.Spawn("RoadMarkings", b.Build("markings"), new[] { lineWhite, lineYellow }, transform, false, false);
            go.isStatic = true;
        }

        static void Strip(MeshBuilder b, int sub, Vector3 p0, Vector3 p1, float width)
        {
            Vector3 dir = (p1 - p0).normalized;
            Vector3 side = Vector3.Cross(Vector3.up, dir) * width * 0.5f;
            // top-facing quad
            b.Sub(sub).QuadUV(p0 - side, p0 + side, p1 + side, p1 - side, Vector3.up, Vector2.zero, Vector2.right, Vector2.one, Vector2.up);
        }

        void BuildMedians()
        {
            // raised median with palms down the middle of every road
            var b = new MeshBuilder(3);
            for (int k = 0; k <= N; k++)
            {
                float line = RoadLine(k);
                for (int seg = 0; seg < N; seg++)
                {
                    float s0 = seg * Pitch + 6f, s1 = seg * Pitch + Block - 6f;
                    float mid = (s0 + s1) * 0.5f, len = s1 - s0;
                    b.Sub(0).Box(new Vector3(line, 0.12f, mid), new Vector3(Median, 0.24f, len), 2f);
                    b.Sub(0).Box(new Vector3(mid, 0.12f, line), new Vector3(len, 0.24f, Median), 2f);
                    for (float s = s0 + 6; s < s1 - 3; s += 16f)
                    {
                        Palm(b, new Vector3(line, 0.24f, s));
                        Palm(b, new Vector3(s, 0.24f, line));
                    }
                }
            }
            var go = MeshBuilder.Spawn("Medians", b.Build("medians"), new[] { medianMat, palmBark, palmLeaf }, transform, true, true);
            go.isStatic = true;
        }

        void Palm(MeshBuilder b, Vector3 basePos)
        {
            float h = 7f + R() * 3f;
            // slightly leaning trunk from 3 stacked tapered boxes
            Vector3 lean = new Vector3((R() - 0.5f) * 0.6f, 0, (R() - 0.5f) * 0.6f);
            for (int k = 0; k < 3; k++)
            {
                float t0 = k / 3f, t1 = (k + 1) / 3f;
                Vector3 p = basePos + Vector3.up * h * (t0 + t1) * 0.5f + lean * (t0 + t1) * 0.5f;
                float w = Mathf.Lerp(0.42f, 0.26f, (t0 + t1) * 0.5f);
                b.Sub(1).Box(p, new Vector3(w, h / 3f + 0.05f, w), 1f, true, true);
            }
            Vector3 top = basePos + Vector3.up * h + lean;
            // fronds: 3-segment arching leaves, folded into a V along the spine so they keep a full silhouette
            // seen from street level (flat cards turned edge-on and vanished). A few young fronds point up.
            int n = 13;
            Vector3[] sp = new Vector3[4];
            float[] wid = { 0.12f, 0.7f, 0.55f, 0.1f };
            for (int f = 0; f < n; f++)
            {
                float a = f * Mathf.PI * 2 / n + R() * 0.35f;
                Vector3 dir = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a));
                Vector3 side = Vector3.Cross(Vector3.up, dir).normalized;
                bool young = f % 5 == 0;
                float len = young ? 2.6f : 3.6f + R() * 0.8f;
                float droop = young ? -0.6f : 0.9f + R() * 0.9f;   // how far the tip falls
                sp[0] = top;
                sp[1] = top + dir * len * 0.36f + Vector3.up * (young ? 0.9f : 0.5f);
                sp[2] = top + dir * len * 0.7f + Vector3.up * (young ? 1.3f : 0.25f - droop * 0.35f);
                sp[3] = top + dir * len + Vector3.down * droop + Vector3.up * (young ? 1.2f : 0f);
                for (int k = 0; k < 3; k++)
                {
                    float v0 = k / 3f, v1 = (k + 1) / 3f;
                    Vector3 fold0 = Vector3.down * wid[k] * 0.4f, fold1 = Vector3.down * wid[k + 1] * 0.4f;
                    Vector3 l0 = sp[k] - side * wid[k] + fold0, l1 = sp[k + 1] - side * wid[k + 1] + fold1;
                    Vector3 r0 = sp[k] + side * wid[k] + fold0, r1 = sp[k + 1] + side * wid[k + 1] + fold1;
                    b.Sub(2).QuadUV(l0, sp[k], sp[k + 1], l1, Vector3.up, new Vector2(0, v0), new Vector2(0.5f, v0), new Vector2(0.5f, v1), new Vector2(0, v1));
                    b.Sub(2).QuadUV(sp[k], r0, r1, sp[k + 1], Vector3.up, new Vector2(0.5f, v0), new Vector2(1, v0), new Vector2(1, v1), new Vector2(0.5f, v1));
                }
            }
        }

        void BuildSkyline()
        {
            // far towers in a ring outside the playable grid, plus one super-tall spire
            var b = new MeshBuilder(3 + neon.Length + towers.Length);
            Vector3 center = new Vector3(N * Pitch * 0.5f, 0, N * Pitch * 0.5f);
            for (int k = 0; k < 90; k++)
            {
                float a = R() * Mathf.PI * 2;
                float r = N * Pitch * 0.5f + 180f + R() * 450f;
                Vector3 p = center + new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * r;
                float h = 60f + R() * 220f;
                float w = 18f + R() * 30f;
                if (towers.Length > 0) { int sk = Ri(towers.Length); b.Sub(3 + neon.Length + sk).Box(p + Vector3.up * h * 0.5f, new Vector3(w, h, w * (0.7f + R() * 0.6f)), towerTile[sk] * 1.3f, true, false); }
                else b.Sub(R() < 0.7f ? 0 : 1).Box(p + Vector3.up * h * 0.5f, new Vector3(w, h, w * (0.7f + R() * 0.6f)), 6f, true, false);
                var band = 3 + (R() < 0.6f ? 5 : Ri(neon.Length));
                for (float y = 20; y < h; y += 18f + R() * 30f)
                    b.Sub(band).Box(p + Vector3.up * y, new Vector3(w + 0.3f, 0.6f, w * 0.8f + 0.3f), 2f, true, true);
            }
            // the spire (Dubai's skyline signature), north-east, stepped and glowing
            Vector3 sp = center + new Vector3(520, 0, 640);
            float hh = 0, ww = 70;
            for (int k = 0; k < 9; k++)
            {
                float th = 70f - k * 3f;
                if (towers.Length > 0) b.Sub(3 + neon.Length).Box(sp + Vector3.up * (hh + th * 0.5f), new Vector3(ww, th, ww * 0.8f), 40f, true, false);
                else b.Sub(1).Box(sp + Vector3.up * (hh + th * 0.5f), new Vector3(ww, th, ww * 0.8f), 6f, true, false);
                b.Sub(3 + 5).Box(sp + Vector3.up * (hh + th), new Vector3(ww + 0.5f, 0.8f, ww * 0.8f + 0.5f), 2f, true, true);
                hh += th; ww *= 0.8f;
            }
            b.Sub(2).Box(sp + Vector3.up * (hh + 60), new Vector3(3, 120, 3), 4f, true, false);
            var mats = new List<Material> { glassTower, glassDark, Res.Glow(new Color(0.9f, 0.85f, 1f), 3f) };
            mats.AddRange(neon);
            mats.AddRange(towers);
            var go = MeshBuilder.Spawn("Skyline", b.Build("skyline"), mats.ToArray(), transform, false, false);
            go.isStatic = true;
        }

        /// <summary>Lane centre position: the road at index k along axis (0 = runs along Z, 1 = runs along X).</summary>
        public static float LaneOffset(int lane) => (lane < 2 ? -1 : 1) * (Median * 0.5f + LaneW * (lane % 2 + 0.5f));

        public static bool OnRoad(Vector3 p)
        {
            float mx = Mathf.Repeat(p.x + Road * 0.5f, Pitch), mz = Mathf.Repeat(p.z + Road * 0.5f, Pitch);
            return mx < Road || mz < Road;
        }
    }
}
