using UnityEngine;
using UnityEngine.Rendering;

namespace HMD
{
    /// <summary>
    /// The inside of LSXmotorsport, built to match Hamad's workshop photo: cream corrugated metal walls
    /// with a black lower band, white drop-ceiling tiles with square LED panels, polished grey concrete
    /// with yellow bay lines, red scissor lifts and tool chests, banners, wheels and bonnets on the wall,
    /// oil shelves and a big cooling fan. The dyno bay (from his dyno photo) has rollers set into the
    /// floor, a blue extraction fan with a duct, dyno banners and a darker ceiling, and a TV on the wall
    /// that shows the power graph.
    /// </summary>
    public class Workshop : MonoBehaviour
    {
        public static readonly Vector3 Origin = new Vector3(0, 0, -3000f);
        public const float W = 28f, D = 34f, H = 6.2f;

        public Vector3 DisplaySpot => transform.TransformPoint(new Vector3(-4f, 0, 12f));
        public Quaternion DisplayRot => transform.rotation * Quaternion.Euler(0, 200, 0);
        public Vector3 DynoSpot => transform.TransformPoint(new Vector3(7.5f, 0, 25f));
        // car on the dyno faces the room (nose towards the door), as Hamad asked
        public Quaternion DynoRot => transform.rotation * Quaternion.Euler(0, 180, 0);
        public Vector3 ShutterIn => transform.TransformPoint(new Vector3(-4f, 0, 1f));
        public Transform Tv { get; private set; }
        public Renderer TvScreen { get; private set; }
        public Transform[] Rollers { get; private set; }

        Material corr, band, ceil, led, floor, yellow, red, black, steel, chrome, blueFan;

        public void Build()
        {
            transform.position = Origin;
            corr = Res.TexMat("Tex/corrugated_iron", new Vector2(1f / 2f, 1f / 2f), 0.4f, 0.1f, new Color(0.93f, 0.9f, 0.8f), 1f, false);   // cream painted metal
            band = Res.Mat(new Color(0.03f, 0.03f, 0.03f), 0.5f, 0.1f);
            ceil = Res.Mat(new Color(0.9f, 0.9f, 0.88f), 0.2f);
            led = Res.Glow(new Color(1f, 0.98f, 0.94f), 3.2f);
            floor = Res.TexMat("Tex/garage_floor", Vector2.one / 4f, 0.88f, 0f, new Color(0.62f, 0.63f, 0.65f));   // polished
            var epoxy = Res.Tex("Gen/shop_floor");
            if (epoxy != null)
            {
                // light grey polished epoxy like the real workshop floor
                floor = Res.Mat(new Color(0.78f, 0.79f, 0.8f), 0.86f, 0f);
                Res.SetMainTex(floor, epoxy, Vector2.one / 7f);
            }
            yellow = Res.Mat(new Color(0.98f, 0.78f, 0.02f), 0.6f);
            red = Res.Mat(new Color(0.75f, 0.03f, 0.03f), 0.75f, 0.2f);
            black = Res.Mat(new Color(0.02f, 0.02f, 0.025f), 0.6f, 0.3f);
            steel = Res.Mat(new Color(0.5f, 0.52f, 0.55f), 0.65f, 0.9f);
            chrome = Res.Mat(new Color(0.85f, 0.86f, 0.88f), 0.95f, 1f);
            blueFan = Res.Mat(new Color(0.05f, 0.25f, 0.8f), 0.6f, 0.3f);

            Shell();
            Ceiling();
            Lines();
            Lifts();
            ToolChests();
            WallDisplay();
            DynoBay();
            Lights();
            Banners();
            Props();

            var probe = new GameObject("RoomProbe").AddComponent<ReflectionProbe>();
            probe.transform.SetParent(transform, false);
            probe.transform.localPosition = new Vector3(0, 2.5f, D * 0.5f);
            probe.size = new Vector3(W, H, D);
            probe.boxProjection = true;
            probe.mode = ReflectionProbeMode.Realtime;
            probe.refreshMode = ReflectionProbeRefreshMode.ViaScripting;
            probe.timeSlicingMode = ReflectionProbeTimeSlicingMode.NoTimeSlicing;
            probe.resolution = 256;
            probe.importance = 10;
            Probe = probe;
        }

        public ReflectionProbe Probe { get; private set; }

        Transform Box(string name, Vector3 pos, Vector3 size, Material m, bool col = false) =>
            MeshBuilder.Cube(name, transform, pos, size, m, col).transform;

        void Shell()
        {
            // floor
            var f = new MeshBuilder();
            f.QuadUV(new Vector3(-W / 2, 0, 0), new Vector3(W / 2, 0, 0), new Vector3(W / 2, 0, D), new Vector3(-W / 2, 0, D), Vector3.up,
                     new Vector2(0, 0), new Vector2(W, 0), new Vector2(W, D), new Vector2(0, D));
            var fg = MeshBuilder.Spawn("Floor", f.Build("floor"), new[] { floor }, transform, false, false);
            fg.AddComponent<BoxCollider>().center = new Vector3(0, -0.5f, D / 2);
            fg.GetComponent<BoxCollider>().size = new Vector3(W, 1, D);
            // walls (inside faces), corrugated + black lower band
            var w = new MeshBuilder(2);
            Vector2 uv = new Vector2(2f, 2f);
            Vector3 a = new Vector3(-W / 2, 0, 0), b = new Vector3(W / 2, 0, 0), c = new Vector3(W / 2, 0, D), d = new Vector3(-W / 2, 0, D);
            // inside faces: walk the room clockwise seen from above so each wall faces in
            w.Sub(0); w.Wall(b, a, H, uv); w.Wall(c, b, H, uv); w.Wall(d, c, H, uv); w.Wall(a, d, H, uv);
            Vector3 i = Vector3.up * 0.001f;
            w.Sub(1);
            float bandH = 1.1f;
            Vector3 inset(Vector3 p) => p + (new Vector3(0, 0, D / 2) - new Vector3(p.x, 0, p.z)).normalized * 0.03f;
            w.Wall(inset(b), inset(a), bandH, uv); w.Wall(inset(c), inset(b), bandH, uv); w.Wall(inset(d), inset(c), bandH, uv); w.Wall(inset(a), inset(d), bandH, uv);
            var wg = MeshBuilder.Spawn("Walls", w.Build("walls"), new[] { corr, band }, transform, true, false);
            // the shutter (closed roller door) in the south wall
            Box("Shutter", new Vector3(-4f, 2.2f, 0.05f), new Vector3(5.6f, 4.4f, 0.1f), Res.TexMat("Tex/corrugated_iron", new Vector2(1f / 1.2f, 1f / 3f), 0.5f, 0.3f, new Color(0.65f, 0.67f, 0.7f), 1f, false));
            Box("ShutterFrame", new Vector3(-4f, 4.55f, 0.15f), new Vector3(6f, 0.3f, 0.3f), black);
        }

        void Ceiling()
        {
            // drop ceiling: white tiles on a grid with square LED panels; darker over the dyno bay
            var b = new MeshBuilder(3);
            float tile = 1.2f;
            for (float x = -W / 2; x < W / 2 - 0.01f; x += tile)
                for (float z = 0; z < D - 0.01f; z += tile)
                {
                    bool dyno = x > 2f && z > 19f;
                    int ix = Mathf.RoundToInt((x + W / 2) / tile), iz = Mathf.RoundToInt(z / tile);
                    bool panel = dyno ? (ix % 4 == 1 && iz % 3 == 1) : (ix % 3 == 1 && iz % 3 == 1);
                    Vector3 p0 = new Vector3(x + 0.02f, H, z + 0.02f), p1 = new Vector3(x + tile - 0.02f, H, z + tile - 0.02f);
                    // facing down
                    b.Sub(panel ? 1 : dyno ? 2 : 0).QuadUV(new Vector3(p0.x, H, p0.z), new Vector3(p0.x, H, p1.z), new Vector3(p1.x, H, p1.z), new Vector3(p1.x, H, p0.z), Vector3.down,
                        Vector2.zero, Vector2.right, Vector2.one, Vector2.up);
                }
            var darkCeil = Res.Mat(new Color(0.06f, 0.06f, 0.065f), 0.2f);
            MeshBuilder.Spawn("Ceiling", b.Build("ceiling"), new[] { ceil, led, darkCeil }, transform, false, false);
            // tile grid (the T-bar)
            var g = new MeshBuilder();
            for (float x = -W / 2; x <= W / 2; x += 1.2f) g.Box(new Vector3(x, H - 0.02f, D / 2), new Vector3(0.04f, 0.04f, D), 1f, false, true);
            for (float z = 0; z <= D; z += 1.2f) g.Box(new Vector3(0, H - 0.02f, z), new Vector3(W, 0.04f, 0.04f), 1f, false, true);
            MeshBuilder.Spawn("CeilingGrid", g.Build("grid"), new[] { Res.Mat(new Color(0.82f, 0.82f, 0.8f), 0.3f, 0.5f) }, transform, false, false);
        }

        void Lines()
        {
            // yellow bay lines on the floor
            var b = new MeshBuilder();
            void L(Vector3 c, Vector3 s) => b.Box(c, s, 1f, true, false);
            for (int k = 0; k < 3; k++)
            {
                float x = -11f + k * 6f;
                L(new Vector3(x, 0.006f, 10f), new Vector3(0.12f, 0.012f, 12f));
            }
            L(new Vector3(-5f, 0.006f, 16f), new Vector3(18f, 0.012f, 0.12f));
            // dyno bay box
            L(new Vector3(7.5f, 0.006f, 20f), new Vector3(8f, 0.012f, 0.14f));
            L(new Vector3(7.5f, 0.006f, 31f), new Vector3(8f, 0.012f, 0.14f));
            L(new Vector3(3.5f, 0.006f, 25.5f), new Vector3(0.14f, 0.012f, 11f));
            L(new Vector3(11.5f, 0.006f, 25.5f), new Vector3(0.14f, 0.012f, 11f));
            MeshBuilder.Spawn("BayLines", b.Build("lines"), new[] { yellow }, transform, false, false);
        }

        void Lifts()
        {
            // two red scissor lifts in the work bays
            for (int k = 0; k < 2; k++)
            {
                float x = -8f + k * 6f;
                var root = new GameObject("Lift" + k).transform;
                root.SetParent(transform, false);
                root.localPosition = new Vector3(x, 0, 8f);
                for (int s = -1; s <= 1; s += 2)
                {
                    MeshBuilder.Cube("Pad", root, new Vector3(s * 0.75f, 0.08f, 0), new Vector3(0.55f, 0.12f, 4.4f), red);
                    var arm1 = MeshBuilder.Cube("Arm", root, new Vector3(s * 0.75f, 0.05f, 0), new Vector3(0.12f, 0.06f, 3.6f), red).transform;
                    arm1.localRotation = Quaternion.Euler(2f, 0, 0);
                    MeshBuilder.Cube("Base", root, new Vector3(s * 0.75f, 0.01f, 0), new Vector3(0.7f, 0.02f, 4.6f), black);
                }
                MeshBuilder.Cube("Control", root, new Vector3(-1.9f, 0.55f, -1.9f), new Vector3(0.35f, 1.1f, 0.3f), red);
            }
        }

        void ToolChests()
        {
            // red roll-cab tool chests along the west wall
            for (int k = 0; k < 4; k++)
            {
                float z = 5f + k * 2.1f;
                var root = new GameObject("ToolChest" + k).transform;
                root.SetParent(transform, false);
                root.localPosition = new Vector3(-W / 2 + 0.5f, 0, z);
                MeshBuilder.Cube("Cab", root, new Vector3(0, 0.55f, 0), new Vector3(0.75f, 1.0f, 1.9f), red, true);
                MeshBuilder.Cube("Top", root, new Vector3(0, 1.07f, 0), new Vector3(0.78f, 0.04f, 1.94f), steel);
                MeshBuilder.Cube("Upper", root, new Vector3(-0.05f, 1.45f, 0), new Vector3(0.6f, 0.7f, 1.8f), red);
                for (int dIdx = 0; dIdx < 6; dIdx++)
                    MeshBuilder.Cube("Handle", root, new Vector3(0.39f, 0.18f + dIdx * 0.15f, 0), new Vector3(0.02f, 0.02f, 1.4f), chrome);
                for (int i2 = 0; i2 < 4; i2++)
                    MeshBuilder.Cube("Wheel", root, new Vector3(((i2 & 1) * 2 - 1) * 0.3f, 0.04f, ((i2 >> 1) * 2 - 1) * 0.85f), new Vector3(0.06f, 0.08f, 0.08f), black);
            }
            // oil shelves on the north wall
            var shelf = new GameObject("OilShelves").transform;
            shelf.SetParent(transform, false);
            shelf.localPosition = new Vector3(-8f, 0, D - 0.5f);
            for (int lvl = 0; lvl < 4; lvl++)
            {
                MeshBuilder.Cube("Shelf", shelf, new Vector3(0, 0.4f + lvl * 0.55f, 0), new Vector3(4f, 0.04f, 0.6f), steel);
                for (int b = 0; b < 12; b++)
                {
                    var c = (b + lvl) % 3 == 0 ? new Color(0.05f, 0.2f, 0.75f) : (b + lvl) % 3 == 1 ? new Color(0.85f, 0.1f, 0.05f) : new Color(0.95f, 0.75f, 0.05f);
                    MeshBuilder.Cube("Oil", shelf, new Vector3(-1.8f + b * 0.32f, 0.56f + lvl * 0.55f, 0), new Vector3(0.22f, 0.3f, 0.14f), Res.Mat(c, 0.7f));
                }
            }
            for (int s = -1; s <= 1; s += 2) MeshBuilder.Cube("Post", shelf, new Vector3(s * 2f, 1.1f, 0), new Vector3(0.05f, 2.2f, 0.6f), steel);
            // big cooling fan on a stand
            var fan = new GameObject("CoolerFan").transform;
            fan.SetParent(transform, false);
            fan.localPosition = new Vector3(2.5f, 0, 26f);
            fan.localRotation = Quaternion.Euler(0, 90, 0);
            MeshBuilder.Cube("Housing", fan, new Vector3(0, 1.0f, 0), new Vector3(1.4f, 1.4f, 0.4f), black, true);
            MeshBuilder.Cube("Grille", fan, new Vector3(0, 1.0f, 0.21f), new Vector3(1.25f, 1.25f, 0.02f), steel);
            MeshBuilder.Cube("Feet", fan, new Vector3(0, 0.1f, 0), new Vector3(1.2f, 0.2f, 0.6f), black);
        }

        void WallDisplay()
        {
            // wheels and bonnets hung on the east wall
            var mats = WheelMesh.Materials(new Color(0.75f, 0.76f, 0.8f), new Color(0.75f, 0.04f, 0.04f));
            for (int k = 0; k < 5; k++)
            {
                var wgo = new GameObject("WallWheel" + k);
                wgo.transform.SetParent(transform, false);
                wgo.transform.localPosition = new Vector3(W / 2 - 0.2f, 3.6f, 3f + k * 1.6f);
                wgo.transform.localRotation = Quaternion.Euler(0, 180, 0);
                wgo.AddComponent<MeshFilter>().sharedMesh = WheelMesh.Get(0.33f, 0.24f, (WheelMesh.Style)(k % 4));
                wgo.AddComponent<MeshRenderer>().sharedMaterials = mats;
            }
            var hoodCols = new[] { new Color(0.05f, 0.05f, 0.06f), new Color(0.8f, 0.05f, 0.05f), new Color(0.85f, 0.85f, 0.88f) };
            for (int k = 0; k < 3; k++)
            {
                var hood = Box("Bonnet" + k, new Vector3(W / 2 - 0.1f, 2.0f, 4f + k * 2.6f), new Vector3(0.06f, 1.1f, 1.6f), Res.Mat(hoodCols[k], 0.9f, 0.5f));
                hood.localRotation = Quaternion.Euler(0, 0, -8f);
            }
        }

        void DynoBay()
        {
            var root = new GameObject("Dyno").transform;
            root.SetParent(transform, false);
            root.localPosition = new Vector3(7.5f, 0, 25f);
            // pit with two rollers under the rear axle area (the car is placed so its driven axle sits on them)
            MeshBuilder.Cube("Plate", root, new Vector3(0, 0.005f, 0), new Vector3(3.2f, 0.01f, 2.2f), Res.TexMat("Tex/garage_floor", Vector2.one, 0.8f, 0.8f, new Color(0.35f, 0.36f, 0.38f)));
            MeshBuilder.Cube("Slot", root, new Vector3(0, 0.0105f, 0), new Vector3(2.9f, 0.001f, 1.15f), Res.Mat(new Color(0.01f, 0.01f, 0.012f), 0.1f));   // dark pit the rollers turn in
            Rollers = new Transform[2];
            for (int k = 0; k < 2; k++)
            {
                var r = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                Object.Destroy(r.GetComponent<Collider>());
                r.name = "Roller" + k;
                r.transform.SetParent(root, false);
                r.transform.localPosition = new Vector3(0, -0.14f, (k - 0.5f) * 0.6f);   // set into the floor: only the tops show through the slot
                r.transform.localRotation = Quaternion.Euler(0, 0, 90);
                r.transform.localScale = new Vector3(0.38f, 1.45f, 0.38f);
                r.GetComponent<Renderer>().sharedMaterial = steel;
                Rollers[k] = r.transform;
            }
            // straps
            for (int s = -1; s <= 1; s += 2)
                MeshBuilder.Cube("Strap", root, new Vector3(s * 1.1f, 0.25f, 2.6f), new Vector3(0.05f, 0.5f, 1.2f), Res.Mat(new Color(0.95f, 0.75f, 0.05f), 0.4f)).transform.localRotation = Quaternion.Euler(35, 0, 0);
            // blue extraction fan + duct (from the dyno photo)
            var fan = new GameObject("ExtractFan").transform;
            fan.SetParent(root, false);
            fan.localPosition = new Vector3(0, 0, -5.2f);
            MeshBuilder.Cube("FanBody", fan, new Vector3(0, 0.9f, 0), new Vector3(1.6f, 1.6f, 0.6f), blueFan, true);
            MeshBuilder.Cube("FanGrille", fan, new Vector3(0, 0.9f, 0.31f), new Vector3(1.4f, 1.4f, 0.02f), steel);
            var duct = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            Object.Destroy(duct.GetComponent<Collider>());
            duct.transform.SetParent(root, false);
            duct.transform.localPosition = new Vector3(0, H - 1.0f, 0f);
            duct.transform.localRotation = Quaternion.Euler(90, 0, 0);
            duct.transform.localScale = new Vector3(0.6f, 4f, 0.6f);
            duct.GetComponent<Renderer>().sharedMaterial = chrome;

            // TV on the east wall, angled to the dyno
            Tv = new GameObject("TV").transform;
            Tv.SetParent(transform, false);
            Tv.localPosition = new Vector3(W / 2 - 0.15f, 2.9f, 24.5f);
            Tv.localRotation = Quaternion.Euler(0, -90, 0);
            MeshBuilder.Cube("Bezel", Tv, Vector3.zero, new Vector3(2.4f, 1.42f, 0.08f), black);
            var screen = GameObject.CreatePrimitive(PrimitiveType.Quad);
            screen.name = "Screen";
            screen.transform.SetParent(Tv, false);
            screen.transform.localPosition = new Vector3(0, 0, -0.045f);
            screen.transform.localScale = new Vector3(2.28f, 1.3f, 1);
            screen.transform.localRotation = Quaternion.Euler(0, 0, 0);
            var sc = screen.GetComponent<Collider>();
            if (sc) sc.isTrigger = false;   // kept: tapping the TV raycasts this collider
            TvScreen = screen.GetComponent<Renderer>();
            TvScreen.sharedMaterial = Res.UnlitMat(new Color(0.02f, 0.03f, 0.05f));
            // the TV must face into the room (-X): a quad faces -Z locally, so rotate it to face the room
            Tv.localRotation = Quaternion.Euler(0, 90, 0);
        }

        void Lights()
        {
            // a few real lights for shading + the LED panels glow; dyno bay is darker
            int i = 0;
            // bright, even workshop light like the photo: a 3 x 3 grid under the LED panels
            for (float x = -9; x <= 9; x += 9)
                for (float z = 5; z <= 19; z += 7)
                {
                    var l = new GameObject("Light" + i++).AddComponent<Light>();
                    l.transform.SetParent(transform, false);
                    l.transform.localPosition = new Vector3(x, H - 0.4f, z);
                    l.type = LightType.Point; l.range = 16; l.intensity = 5.5f; l.color = new Color(1f, 0.98f, 0.95f);
                    l.shadows = i == 5 ? LightShadows.Soft : LightShadows.None;
                }
            // dyno bay: a strong spot on the car plus fill over the bay, the TV wall and the back wall
            var dl = new GameObject("DynoSpot").AddComponent<Light>();
            dl.transform.SetParent(transform, false);
            dl.transform.localPosition = new Vector3(7.5f, H - 0.3f, 24f);
            dl.transform.localRotation = Quaternion.Euler(90, 0, 0);
            dl.type = LightType.Spot; dl.spotAngle = 95; dl.range = 12; dl.intensity = 14f; dl.color = new Color(1f, 0.95f, 0.9f);
            dl.shadows = LightShadows.Soft;
            Vector3[] fill = { new Vector3(2f, H - 0.5f, 25f), new Vector3(10f, H - 0.5f, 30f), new Vector3(-7f, H - 0.5f, 28f), new Vector3(6f, H - 0.5f, 18.5f) };
            foreach (var p in fill)
            {
                var l = new GameObject("DynoFill").AddComponent<Light>();
                l.transform.SetParent(transform, false);
                l.transform.localPosition = p;
                l.type = LightType.Point; l.range = 14; l.intensity = 4.5f; l.color = new Color(0.95f, 0.97f, 1f);
                l.shadows = LightShadows.None;
            }
        }

        /// <summary>A generated 3D workshop item (tool chest, tyres, lift...). Scaled to a real height and set on the floor.</summary>
        Transform Prop(string name, Vector3 pos, float yaw, float height, Vector3 colliderSize = default)
        {
            var prefab = Res.Load<GameObject>("Props/" + name);
            if (prefab == null) return null;
            var holder = new GameObject("Prop_" + name).transform;
            holder.SetParent(transform, false);
            holder.localPosition = pos;
            holder.localRotation = Quaternion.Euler(0, yaw, 0);
            var go = Object.Instantiate(prefab, holder);
            go.transform.localPosition = Vector3.zero; go.transform.localRotation = Quaternion.identity; go.transform.localScale = Vector3.one;
            foreach (var c in go.GetComponentsInChildren<Collider>()) Object.Destroy(c);
            // plain lit materials with the model's own picture (keeps the build free of extra shader variants)
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                var src = r.sharedMaterial;
                Texture tex = null;
                if (src != null)
                    foreach (var prop in new[] { "baseColorTexture", "_BaseMap", "_MainTex" })
                        if (src.HasProperty(prop) && src.GetTexture(prop) != null) { tex = src.GetTexture(prop); break; }
                var m = Res.Mat(Color.white, 0.45f, 0.1f);
                if (tex != null) Res.SetMainTex(m, tex, Vector2.one);
                r.sharedMaterial = m;
            }
            // measure, scale to the wanted height, stand it on the floor, centre it on its spot
            var rs = go.GetComponentsInChildren<Renderer>();
            if (rs.Length == 0) return holder;
            Bounds b = rs[0].bounds;
            foreach (var r in rs) b.Encapsulate(r.bounds);
            float k = height / Mathf.Max(0.01f, b.size.y);
            go.transform.localScale = Vector3.one * k;
            Vector3 centre = holder.InverseTransformPoint(b.center);
            float bottom = (b.center.y - b.extents.y - holder.position.y) * k;
            go.transform.localPosition = new Vector3(-centre.x * k, -bottom, -centre.z * k);
            if (colliderSize != default)
            {
                var bc = holder.gameObject.AddComponent<BoxCollider>();
                bc.size = colliderSize; bc.center = new Vector3(0, colliderSize.y * 0.5f, 0);
            }
            return holder;
        }

        void Props()
        {
            // the generated models are widest along their own Z and face +X; yaw turns that front into the room
            // rolling tool chests beside the bays and at the dyno
            Prop("tool_chest", new Vector3(-12.4f, 0, 15.2f), 0, 1.25f, new Vector3(0.8f, 1.2f, 1.5f));
            Prop("tool_chest", new Vector3(1.2f, 0, 21.5f), 30, 1.25f, new Vector3(0.8f, 1.2f, 1.5f));
            Prop("tool_chest", new Vector3(12.6f, 0, 14f), 180, 1.25f, new Vector3(0.8f, 1.2f, 1.5f));
            // tyre stacks
            Prop("tyre_stack", new Vector3(12.6f, 0, 10.5f), 20, 1.0f, new Vector3(0.75f, 1f, 0.75f));
            Prop("tyre_stack", new Vector3(12.5f, 0, 11.6f), 70, 1.0f, new Vector3(0.75f, 1f, 0.75f));
            Prop("tyre_stack", new Vector3(-12.6f, 0, 30.5f), 10, 1.0f, new Vector3(0.75f, 1f, 0.75f));
            Prop("tyre_stack", new Vector3(-11.6f, 0, 31.6f), 120, 1.0f, new Vector3(0.75f, 1f, 0.75f));
            // a two-post lift in the third bay (posts left and right of the bay)
            Prop("lift", new Vector3(4.5f, 0, 9f), 90, 3.4f);
            // engine on a stand, workbenches, oil drums
            Prop("engine_stand", new Vector3(-3.5f, 0, 30.5f), 160, 1.35f, new Vector3(0.8f, 1.3f, 1.1f));
            Prop("workbench", new Vector3(5.5f, 0, 1.0f), -90, 1.05f, new Vector3(0.7f, 1f, 1.3f));
            Prop("workbench", new Vector3(-12.9f, 0, 25f), 0, 1.05f, new Vector3(0.7f, 1f, 1.3f));
            Prop("oil_drums", new Vector3(12.4f, 0, 32.4f), 30, 1.05f, new Vector3(1.1f, 1f, 1.2f));
            Prop("oil_drums", new Vector3(-12.6f, 0, 2f), 200, 1.05f, new Vector3(1.1f, 1f, 1.2f));

            // more of the same so the room looks like a busy shop; the drive path from the shutter
            // (x -7..-1, z 0..14), the display spot, the lifts and the dyno bay stay clear
            Prop("engine_stand", new Vector3(-9f, 0, 21.5f), 40, 1.35f, new Vector3(0.8f, 1.3f, 1.1f));
            Prop("tool_chest", new Vector3(-12.4f, 0, 20.3f), 0, 1.25f, new Vector3(0.8f, 1.2f, 1.5f));
            Prop("tool_chest", new Vector3(12.6f, 0, 18f), 180, 1.25f, new Vector3(0.8f, 1.2f, 1.5f));
            Prop("tyre_stack", new Vector3(12.7f, 0, 6.4f), 45, 1.0f, new Vector3(0.75f, 1f, 0.75f));
            Prop("tyre_stack", new Vector3(12.7f, 0, 7.5f), 100, 1.0f, new Vector3(0.75f, 1f, 0.75f));
            Prop("tyre_stack", new Vector3(1.4f, 0, 33.1f), 15, 1.0f, new Vector3(0.75f, 1f, 0.75f));
            Prop("workbench", new Vector3(-1.2f, 0, 33.3f), 90, 1.05f, new Vector3(0.7f, 1f, 1.3f));
            Prop("oil_drums", new Vector3(-4.2f, 0, 33.1f), 10, 1.05f, new Vector3(1.1f, 1f, 1.2f));
            Prop("oil_drums", new Vector3(10.8f, 0, 1.0f), 160, 1.05f, new Vector3(1.1f, 1f, 1.2f));
        }

        void Banners()
        {
            // banners on the walls (original brands drawn for the game) + the real LSX logo
            string[] names = { "banner_lsx", "banner_wheels", "banner_tires", "banner_apex", "banner_flag", "banner_dyno",
                               "banner_apex2", "banner_torq", "banner_nitro", "banner_dynomax", "banner_dynomax", "toolwall", "toolwall" };
            Vector3[] pos =
            {
                new Vector3(0, 4.4f, D - 0.08f), new Vector3(-7f, 4.4f, D - 0.08f), new Vector3(-W / 2 + 0.08f, 4.2f, 14f),
                new Vector3(-W / 2 + 0.08f, 4.2f, 22f), new Vector3(5f, 4.4f, D - 0.08f), new Vector3(W / 2 - 0.08f, 4.2f, 29f),
                new Vector3(-W / 2 + 0.08f, 4.4f, 18f), new Vector3(-W / 2 + 0.08f, 4.4f, 27f), new Vector3(-11f, 4.4f, D - 0.08f),
                new Vector3(9.5f, 4.5f, D - 0.08f), new Vector3(W / 2 - 0.08f, 4.6f, 20f),
                new Vector3(-W / 2 + 0.07f, 2.75f, 8.2f), new Vector3(5.5f, 2.6f, 0.07f),
            };
            float[] yaw = { 0, 0, -90, -90, 0, 90, -90, -90, 0, 0, 90, -90, 180 };
            float[] tall = { 1.4f, 1.4f, 1.4f, 1.4f, 1.4f, 1.4f, 2.0f, 2.0f, 2.0f, 2.0f, 1.8f, 2.3f, 2.3f };
            for (int k = 0; k < names.Length; k++)
            {
                var t = Res.Tex("Gen/" + names[k]);
                if (t == null) continue;
                var q = GameObject.CreatePrimitive(PrimitiveType.Quad);
                Object.Destroy(q.GetComponent<Collider>());
                q.name = names[k];
                q.transform.SetParent(transform, false);
                q.transform.localPosition = pos[k];
                q.transform.localRotation = Quaternion.Euler(0, yaw[k], 0);
                float aspect = (float)t.width / t.height;
                q.transform.localScale = new Vector3(tall[k] * aspect, tall[k], 1);
                var m = Res.Mat(Color.white, 0.3f);
                Res.SetMainTex(m, t, Vector2.one);
                q.GetComponent<Renderer>().sharedMaterial = m;
            }
            // the old hand-drawn banners that share a wall spot with a new one move aside
            var logo = Res.Tex("Art/lsx-logo");
            if (logo)
            {
                var q = GameObject.CreatePrimitive(PrimitiveType.Quad);
                Object.Destroy(q.GetComponent<Collider>());
                q.name = "LSX_Logo_Wall";
                q.transform.SetParent(transform, false);
                q.transform.localPosition = new Vector3(-4f, 5.2f, 0.12f);
                q.transform.localRotation = Quaternion.Euler(0, 180, 0);
                q.transform.localScale = new Vector3(4.6f, 4.6f * 292f / 900f, 1);
                var m = Res.Mat(Color.white, 0.8f, 0.3f);
                Res.SetMainTex(m, logo, Vector2.one);
                m.SetFloat("_AlphaClip", 1f); m.SetFloat("_Cutoff", 0.3f); m.EnableKeyword("_ALPHATEST_ON");
                q.GetComponent<Renderer>().sharedMaterial = m;
            }
        }
    }
}
