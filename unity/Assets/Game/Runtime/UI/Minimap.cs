using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace HMD
{
    /// <summary>
    /// Round minimap that turns with the car. The LSX garage shows as a red wrench marker; when it is
    /// off the map, an arrow on the rim points to it. Tap the minimap for the full-screen map, which
    /// has a GO TO GARAGE button.
    /// </summary>
    public class Minimap : MonoBehaviour, IPointerClickHandler
    {
        public System.Action OnGoGarage;
        Transform player;
        RawImage bigImg;
        MinimapDisc disc;
        RectTransform garageIcon, edgeArrow, bigPlayer, bigGarage;
        GameObject big;
        Texture2D tex;
        const float Size = 300f;          // on-screen diameter
        const float ViewMetres = 360f;    // world metres across the minimap
        const int TexSize = 1024;
        float worldMin, worldSize;
        float worldMinZ = float.NaN, worldSizeZ;   // set when the map is not square (new city pictures)
        Texture bigTex;
        bool pictureMap;

        public void Build(Transform root, Transform playerT)
        {
            player = playerT;
            worldMin = -City.Road - 20f;
            worldSize = City.Extent + City.Road + 40f;
            var ncity = NewCity.I;
            if (ncity != null && ncity.roads.Count > 0)
            {
                // the new city: ready map pictures drawn from the same plan (x 0..2400, z 0..1725, north up)
                var baseT = Res.Tex("City/map_base"); var fullT = Res.Tex("City/map_full");
                if (baseT != null && fullT != null)
                {
                    worldMin = 0f; worldSize = 2400f; worldMinZ = 0f; worldSizeZ = 1725f;
                    baseT.wrapMode = TextureWrapMode.Clamp; fullT.wrapMode = TextureWrapMode.Clamp;
                    tex = baseT; bigTex = fullT; pictureMap = true;
                }
                else { worldMin = -100f; worldSize = 1960f; tex = DrawNewCityMap(ncity); }
            }
            else tex = DrawMap();

            // no frame, no bezel: the map is a soft disc that is solid in the middle and fades to nothing at the
            // edge (Hamad 2026-11-17: "remove the sides, use transparency from the edge to the middle")
            var frame = UIKit.Img("Minimap", root, Vector2.zero, Vector2.zero, new Vector2(48, 268), new Vector2(Size + 14, Size + 14), new Color(0, 0, 0, 0f), UIKit.CircleSprite);
            var dgo = new GameObject("Disc", typeof(RectTransform));
            dgo.transform.SetParent(frame.transform, false);
            disc = dgo.AddComponent<MinimapDisc>();
            disc.rectTransform.anchorMin = disc.rectTransform.anchorMax = new Vector2(0.5f, 0.5f);
            disc.rectTransform.sizeDelta = new Vector2(Size, Size);
            disc.tex = tex; disc.radius = Size * 0.5f; disc.raycastTarget = false;
            garageIcon = UIKit.Img("Garage", frame.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(46, 46), Color.white, WrenchSprite).rectTransform;
            garageIcon.GetComponent<Image>().raycastTarget = false;
            var me = UIKit.Img("Player", frame.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(30, 34), new Color(0.55f, 0.85f, 1f), UIKit.ArrowSprite);
            me.raycastTarget = false;
            edgeArrow = UIKit.Img("GarageArrow", frame.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(34, 34), new Color(1f, 0.15f, 0.12f), UIKit.ArrowSprite).rectTransform;
            edgeArrow.GetComponent<Image>().raycastTarget = false;
            frame.gameObject.AddComponent<MinimapTap>().map = this;

            // full-screen map
            var bigRt = UIKit.Rect("BigMap", root, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            UIKit.Stretch(bigRt);
            big = bigRt.gameObject;
            var dim = big.AddComponent<Image>(); dim.color = new Color(0, 0, 0, 0.82f);
            var bi = new GameObject("Map", typeof(RectTransform)).AddComponent<RawImage>();
            bi.transform.SetParent(bigRt, false);
            bi.rectTransform.anchorMin = bi.rectTransform.anchorMax = new Vector2(0.5f, 0.5f);
            bi.rectTransform.sizeDelta = pictureMap ? new Vector2(1320, 1320f * 1150f / 1600f) : new Vector2(940, 940);
            bi.texture = bigTex != null ? bigTex : tex;
            bigImg = bi;
            bigGarage = UIKit.Img("Garage", bi.transform, new Vector2(0, 0), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(60, 60), Color.white, WrenchSprite).rectTransform;
            bigPlayer = UIKit.Img("Player", bi.transform, new Vector2(0, 0), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(40, 46), new Color(0.55f, 0.85f, 1f), UIKit.ArrowSprite).rectTransform;
            // district labels (white with a soft shadow) and a north arrow, like a real city map
            string[] names = { "MARINA", "JUMEIRAH", "AL BARSHA", "BUSINESS BAY", "DOWNTOWN", "DEIRA", "AL QUOZ", "KARAMA", "LSX MOTORSPORT" };
            Vector2[] spots = { new Vector2(0.16f, 0.16f), new Vector2(0.16f, 0.5f), new Vector2(0.5f, 0.16f), new Vector2(0.84f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0.84f, 0.84f), new Vector2(0.16f, 0.84f), new Vector2(0.5f, 0.84f), Vector2.zero };
            if (pictureMap) { names = new[] { "" }; spots = new[] { Vector2.zero }; }   // the picture has its own names
            else if (ncity != null && ncity.districts.Count > 0)
            {
                // real district names at their places in the new city
                names = new string[ncity.districts.Count + 1]; spots = new Vector2[ncity.districts.Count + 1];
                for (int n = 0; n < ncity.districts.Count; n++)
                {
                    names[n] = ncity.districts[n].name.ToUpperInvariant();
                    var dp = ncity.districts[n].pos;
                    spots[n] = new Vector2((dp.x - worldMin) / worldSize, (dp.z - worldMin) / worldSize);
                }
            }
            for (int n = 0; n < names.Length - 1; n++)
            {
                var lb = UIKit.Label("District", bi.transform, spots[n], new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(260, 40), names[n], 26, new Color(1f, 1f, 1f, 0.92f), TextAnchor.MiddleCenter, Res.TitleFont);
                var sh = lb.GetComponent<Shadow>() ?? lb.gameObject.AddComponent<Shadow>();
                sh.effectColor = new Color(0, 0, 0, 0.85f); sh.effectDistance = new Vector2(2, -2);
            }
            if (!pictureMap) { var na = UIKit.Img("North", bi.transform, new Vector2(1, 1), new Vector2(0.5f, 0.5f), new Vector2(-50, -60), new Vector2(34, 40), Color.white, UIKit.ArrowSprite);
            UIKit.Label("NorthN", bi.transform, new Vector2(1, 1), new Vector2(0.5f, 0.5f), new Vector2(-50, -22), new Vector2(40, 30), "N", 26, Color.white, TextAnchor.MiddleCenter, Res.TitleFont); }
            UIKit.Label("Title", bigRt, new Vector2(0.5f, 1), new Vector2(0.5f, 1), new Vector2(0, -20), new Vector2(800, 60), "DUBAI  ·  NIGHT CITY", 44, Color.white, TextAnchor.MiddleCenter, Res.TitleFont);
            UIKit.Btn("GoGarage", bigRt, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-40, 40), new Vector2(380, 96), "GO TO GARAGE", () => { Close(); OnGoGarage?.Invoke(); }, new Color(0.95f, 0.1f, 0.1f), 38);
            UIKit.Btn("Close", bigRt, new Vector2(1, 1), new Vector2(1, 1), new Vector2(-40, -30), new Vector2(200, 86), "CLOSE", Close, Color.white, 36);
            big.SetActive(false);
        }

        public void OnPointerClick(PointerEventData e) => Open();
        public void Open() { big.SetActive(true); }
        public void Close() { big.SetActive(false); }
        public bool IsOpen => big != null && big.activeSelf;

        float MinZ => float.IsNaN(worldMinZ) ? worldMin : worldMinZ;
        float SizeZ => float.IsNaN(worldMinZ) ? worldSize : worldSizeZ;
        Vector2 ToUV(Vector3 w) => new Vector2((w.x - worldMin) / worldSize, (w.z - MinZ) / SizeZ);

        void LateUpdate()
        {
            if (player == null || (City.I == null && NewCity.I == null)) return;
            // minimap: map texture slides under the player and turns with the car (heading up)
            float metresPerPx = ViewMetres / Size;
            Vector2 uv = ToUV(player.position);
            disc.Set(uv, new Vector2(metresPerPx / worldSize, metresPerPx / SizeZ), player.eulerAngles.y);

            Vector3 g = City.I != null ? City.I.GarageDoor : NewCity.I.Garage;   // new city: the LSX spot from the json
            Vector3 d = g - player.position;
            Vector2 local = new Vector2(d.x, d.z) / metresPerPx;
            float r = Size * 0.5f - 34f;   // inside the solid part of the disc
            Vector2 screen = Rotate(local, player.eulerAngles.y);
            garageIcon.anchoredPosition = screen;
            bool inside = screen.magnitude < r;
            garageIcon.gameObject.SetActive(inside);
            edgeArrow.gameObject.SetActive(!inside);
            if (!inside)
            {
                Vector2 dir = screen.normalized;
                edgeArrow.anchoredPosition = dir * (Size * 0.5f - 22f);
                edgeArrow.localRotation = Quaternion.Euler(0, 0, Mathf.Atan2(dir.y, dir.x) * Mathf.Rad2Deg - 90f);
            }

            if (big.activeSelf)
            {
                Vector2 s = bigImg.rectTransform.sizeDelta;
                bigPlayer.anchoredPosition = Vector2.Scale(ToUV(player.position), s);
                bigPlayer.localRotation = Quaternion.Euler(0, 0, -player.eulerAngles.y);
                bigGarage.anchoredPosition = Vector2.Scale(ToUV(g), s);
            }
        }

        static Vector2 Rotate(Vector2 v, float deg)
        {
            float a = deg * Mathf.Deg2Rad, c = Mathf.Cos(a), s = Mathf.Sin(a);
            return new Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
        }

        /// <summary>The new city as a dark game map (Hamad's Dubai reference): dark ground, faint grid, grey streets with
        /// a darker edge and round joins, yellow highways and main roads drawn on top, sea in dark blue past the coast.</summary>
        Texture2D DrawNewCityMap(NewCity nc)
        {
            Physics.SyncTransforms();
            int S = TexSize;
            var col = new Color[S * S];
            Color ground = new Color(0.075f, 0.08f, 0.09f), sea = new Color(0.03f, 0.08f, 0.15f), grid = new Color(0.12f, 0.13f, 0.15f);
            float ppm = S / worldSize;
            var b = nc.MeshBounds;
            for (int y = 0; y < S; y++)
                for (int x = 0; x < S; x++)
                {
                    float wx = worldMin + (x + 0.5f) / ppm, wz = worldMin + (y + 0.5f) / ppm;
                    // land where the terrain is above the sea (raycast once per 4 px block, cheap enough at load)
                    Color c = ground;
                    if ((x & 3) == 0 && (y & 3) == 0)
                    {
                        bool land = Physics.Raycast(new Vector3(wx, 200f, wz), Vector3.down, out var hit, 400f) && hit.point.y > 0.3f;
                        c = land ? ground : sea;
                        for (int dy = 0; dy < 4 && y + dy < S; dy++) for (int dx = 0; dx < 4 && x + dx < S; dx++) col[(y + dy) * S + x + dx] = c;
                    }
                }
            for (int y = 0; y < S; y++)
                for (int x = 0; x < S; x++)
                {
                    float wx = worldMin + (x + 0.5f) / ppm, wz = worldMin + (y + 0.5f) / ppm;
                    if (col[y * S + x] != sea && (Mathf.Repeat(wx, 100f) < 1f / ppm || Mathf.Repeat(wz, 100f) < 1f / ppm)) col[y * S + x] = Color.Lerp(col[y * S + x], grid, 0.6f);
                }
            void Stamp(Vector3 p, float radiusM, Color c)
            {
                float cx = (p.x - worldMin) * ppm, cy = (p.z - worldMin) * ppm, r = Mathf.Max(1.2f, radiusM * ppm);
                int x0 = Mathf.Max(0, (int)(cx - r - 1)), x1 = Mathf.Min(S - 1, (int)(cx + r + 1)), y0 = Mathf.Max(0, (int)(cy - r - 1)), y1 = Mathf.Min(S - 1, (int)(cy + r + 1));
                for (int yy = y0; yy <= y1; yy++)
                    for (int xx = x0; xx <= x1; xx++)
                    {
                        float d = Mathf.Sqrt((xx + 0.5f - cx) * (xx + 0.5f - cx) + (yy + 0.5f - cy) * (yy + 0.5f - cy));
                        float a = Mathf.Clamp01(r - d + 0.5f);
                        if (a > 0) col[yy * S + xx] = Color.Lerp(col[yy * S + xx], c, a);
                    }
            }
            void Road(NewCity.Road rd, float extra, Color c)
            {
                for (int i = 1; i < rd.pts.Count; i++)
                {
                    var a = rd.pts[i - 1]; var bb = rd.pts[i];
                    int steps = Mathf.Max(1, (int)(Vector3.Distance(a, bb) * ppm / 1.5f));
                    for (int s = 0; s <= steps; s++) Stamp(Vector3.Lerp(a, bb, s / (float)steps), rd.width * 0.5f + extra, c);
                }
            }
            Color edge = new Color(0.02f, 0.02f, 0.025f), street = new Color(0.6f, 0.62f, 0.66f), main = new Color(0.98f, 0.76f, 0.25f);
            bool Big(NewCity.Road r) => r.cls == "highway" || r.cls == "main";
            foreach (var rd in nc.roads) if (!Big(rd)) Road(rd, 2.5f, edge);
            foreach (var rd in nc.roads) if (!Big(rd)) Road(rd, 0f, street);
            foreach (var rd in nc.roads) if (Big(rd)) Road(rd, 3f, edge);
            foreach (var rd in nc.roads) if (Big(rd)) Road(rd, 0.5f, main);
            var t = new Texture2D(S, S, TextureFormat.RGBA32, true);
            t.SetPixels(col);
            t.Apply(true);
            t.wrapMode = TextureWrapMode.Clamp;
            t.filterMode = FilterMode.Trilinear;
            t.anisoLevel = 4;
            return t;
        }

        Texture2D DrawMap()
        {
            // a street map, not blocks: dark ground, faint building footprints, roads as smooth light bands with a
            // darker kerb edge, rounded corners at the crossings, main roads a little wider and brighter
            var t = new Texture2D(TexSize, TexSize, TextureFormat.RGBA32, true);
            var px = new Color32[TexSize * TexSize];
            // dark game-map style (Hamad's Dubai reference): near-black with a faint grid, dark-grey blocks, light grey
            // streets, warm yellow main roads, dark blue water/edge with a soft light-blue glow line
            Color bg = new Color(0.03f, 0.07f, 0.13f), ground = new Color(0.07f, 0.075f, 0.085f), bld = new Color(0.12f, 0.125f, 0.14f);
            Color edge = new Color(0.04f, 0.04f, 0.045f), road = new Color(0.62f, 0.64f, 0.67f), main = new Color(0.98f, 0.76f, 0.25f);
            Color glow = new Color(0.35f, 0.65f, 1f);
            float pix = worldSize / TexSize;
            float hw = City.Road * 0.5f, cr = 9f;   // road half width, corner radius
            for (int y = 0; y < TexSize; y++)
                for (int x = 0; x < TexSize; x++)
                {
                    float wx = worldMin + (x + 0.5f) / TexSize * worldSize, wz = worldMin + (y + 0.5f) / TexSize * worldSize;
                    Color c = bg;
                    // edge of the city: dark blue water with a light-blue glow line at the shore
                    float outside = Mathf.Max(Mathf.Max(-City.Road - 6 - wx, wx - City.Extent - 6), Mathf.Max(-City.Road - 6 - wz, wz - City.Extent - 6));
                    if (outside > 0) c = Color.Lerp(bg, glow, Mathf.Clamp01(1f - outside / 14f) * 0.55f);
                    if (wx > -City.Road - 6 && wz > -City.Road - 6 && wx < City.Extent + 6 && wz < City.Extent + 6)
                    {
                        int kx = Mathf.RoundToInt((wx + hw) / City.Pitch), kz = Mathf.RoundToInt((wz + hw) / City.Pitch);
                        float ax = Mathf.Abs(wx - City.RoadLine(kx)), az = Mathf.Abs(wz - City.RoadLine(kz));
                        bool mainX = kx % 4 == 0, mainZ = kz % 4 == 0;
                        float hx = mainX ? hw * 1.15f : hw, hz = mainZ ? hw * 1.15f : hw;
                        // distance inside the road (positive) / inside the block (negative), with rounded block corners
                        float dRoad = Mathf.Max(hx - ax, hz - az);
                        if (ax > hx && az > hz && ax < hx + cr && az < hz + cr)
                        {
                            float cdx = ax - hx - cr, cdz = az - hz - cr;
                            dRoad = Mathf.Max(dRoad, Mathf.Sqrt(cdx * cdx + cdz * cdz) - cr);
                        }
                        // block interior: ground with building footprints (2 x 2 lots, a walkway between)
                        float lx = Mathf.Repeat(wx, City.Pitch), lz = Mathf.Repeat(wz, City.Pitch);
                        float half = City.Block * 0.5f;
                        float fx = Mathf.Abs(Mathf.Abs(lx - half) - half * 0.5f), fz = Mathf.Abs(Mathf.Abs(lz - half) - half * 0.5f);
                        float inLot = Mathf.Min(half * 0.5f - 4f - fx, half * 0.5f - 4f - fz);
                        c = Color.Lerp(ground, bld, Mathf.Clamp01(inLot / pix + 0.5f) * 0.9f);
                        // faint map grid every 50 m
                        if (Mathf.Repeat(wx, 50f) < pix || Mathf.Repeat(wz, 50f) < pix) c = Color.Lerp(c, new Color(0.2f, 0.22f, 0.26f), 0.25f);
                        // road band with a soft darker edge
                        Color rc = (ax < hx && mainX) || (az < hz && mainZ) ? main : road;
                        float e = Mathf.Clamp01(dRoad / pix + 0.5f);
                        float inner = Mathf.Clamp01((dRoad - 1.6f) / pix + 0.5f);
                        c = Color.Lerp(c, edge, e);
                        c = Color.Lerp(c, rc, inner);
                    }
                    px[y * TexSize + x] = c;
                }
            t.SetPixels32(px);
            t.Apply(true);
            t.wrapMode = TextureWrapMode.Clamp;
            t.filterMode = FilterMode.Trilinear;
            t.anisoLevel = 4;
            return t;
        }

        static Sprite wrench;
        /// <summary>Red round badge with a white wrench (the garage marker).</summary>
        public static Sprite WrenchSprite
        {
            get
            {
                if (wrench) return wrench;
                const int n = 96;
                var t = new Texture2D(n, n, TextureFormat.RGBA32, false);
                Vector2 c = new Vector2(n / 2f, n / 2f);
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        Vector2 p = new Vector2(x + 0.5f, y + 0.5f);
                        float d = Vector2.Distance(p, c);
                        Color col = new Color(0, 0, 0, 0);
                        if (d < n / 2f - 1) col = new Color(0.85f, 0.08f, 0.06f, 1);
                        if (d < n / 2f - 1 && d > n / 2f - 6) col = Color.white;
                        // wrench in local coords rotated 45 degrees
                        Vector2 q = p - c;
                        float a = -45f * Mathf.Deg2Rad;
                        Vector2 r = new Vector2(q.x * Mathf.Cos(a) - q.y * Mathf.Sin(a), q.x * Mathf.Sin(a) + q.y * Mathf.Cos(a));
                        bool handle = Mathf.Abs(r.x) < 5.5f && r.y > -26 && r.y < 14;
                        Vector2 head = r - new Vector2(0, 20);
                        bool ring = head.magnitude < 13 && !(Mathf.Abs(head.x) < 5 && head.y > -2);
                        if (handle || ring) col = Color.white;
                        t.SetPixel(x, y, col);
                    }
                t.Apply();
                wrench = Sprite.Create(t, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f));
                return wrench;
            }
        }
    }

    /// <summary>The minimap picture as a round fan mesh. Its texture coordinates follow the car (heading up) and its
    /// vertex alpha goes from solid in the middle to clear at the rim, so the map has no hard border.</summary>
    public class MinimapDisc : MaskableGraphic
    {
        public Texture tex;
        public float radius = 150f;
        Vector2 uvCentre, uvPerPx; float yaw;
        public override Texture mainTexture => tex != null ? tex : s_WhiteTexture;
        // ring radius (0..1) and alpha: solid to 55 %, then a smooth fall to zero
        static readonly float[] RingR = { 0.30f, 0.55f, 0.68f, 0.80f, 0.90f, 1.00f };
        static readonly float[] RingA = { 1.00f, 1.00f, 0.86f, 0.55f, 0.22f, 0.00f };
        const int Seg = 48;

        public void Set(Vector2 centreUv, Vector2 perPx, float yawDeg)
        {
            uvCentre = centreUv; uvPerPx = perPx; yaw = yawDeg;
            SetVerticesDirty();
        }

        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear();
            float a = -yaw * Mathf.Deg2Rad, ca = Mathf.Cos(a), sa = Mathf.Sin(a);
            void Add(Vector2 p, float alpha)
            {
                // screen offset -> world offset (turn back by the heading) -> map uv
                Vector2 w = new Vector2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
                Color32 c = new Color(color.r, color.g, color.b, color.a * alpha);
                vh.AddVert(new Vector3(p.x, p.y, 0), c, new Vector2(uvCentre.x + w.x * uvPerPx.x, uvCentre.y + w.y * uvPerPx.y));
            }
            Add(Vector2.zero, 1f);
            for (int r = 0; r < RingR.Length; r++)
                for (int i = 0; i < Seg; i++)
                {
                    float t = i * Mathf.PI * 2f / Seg;
                    Add(new Vector2(Mathf.Cos(t), Mathf.Sin(t)) * (radius * RingR[r]), RingA[r]);
                }
            for (int i = 0; i < Seg; i++) vh.AddTriangle(0, 1 + i, 1 + (i + 1) % Seg);
            for (int r = 0; r + 1 < RingR.Length; r++)
                for (int i = 0; i < Seg; i++)
                {
                    int i0 = 1 + r * Seg + i, i1 = 1 + r * Seg + (i + 1) % Seg, o0 = i0 + Seg, o1 = i1 + Seg;
                    vh.AddTriangle(i0, o0, o1); vh.AddTriangle(i0, o1, i1);
                }
        }
    }

    public class MinimapTap : MonoBehaviour, IPointerClickHandler
    {
        public Minimap map;
        public void OnPointerClick(PointerEventData e) => map.Open();
    }
}
