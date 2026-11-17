using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace HMD
{
    /// <summary>
    /// Builds a drivable car: the 3D body (baked wheels already cut out by tools/unity_prep_cars.py),
    /// glossy paint, dark wheel wells, four WheelColliders exactly where the real wheels were, detailed
    /// spinning wheels, head and tail lights, a body collider, physics and engine sound.
    /// </summary>
    public static class CarFactory
    {
        static readonly Dictionary<string, Material[]> bodyMats = new Dictionary<string, Material[]>();

        public static CarController Build(string id, Vector3 pos, Quaternion rot, bool player, Transform parent = null)
        {
            var spec = CarDB.Get(id);
            var cfg = CarModelCfg.Load(id);
            float L = spec.length;

            var root = new GameObject("Car_" + id);
            if (parent) root.transform.SetParent(parent, false);
            root.transform.SetPositionAndRotation(pos, rot);
            var rb = root.AddComponent<Rigidbody>();
            rb.isKinematic = true;   // switched on when the world is ready

            // --- body
            float halfW = 0.95f, height = 1.35f;
            var holder = new GameObject("Body").transform;
            holder.SetParent(root.transform, false);
            var prefab = Res.Load<GameObject>("Cars/" + id);
            if (prefab != null)
            {
                var model = Object.Instantiate(prefab, holder);
                model.name = "Model";
                model.transform.localPosition = Vector3.zero;
                model.transform.localRotation = Quaternion.identity;
                model.transform.localScale = Vector3.one * L;
                ApplyPaint(model, id, cfg, spec);
                foreach (var c in model.GetComponentsInChildren<Collider>()) Object.DestroyImmediate(c);
            }
            else
            {
                // no model imported: a clean placeholder so the game still runs
                MeshBuilder.Cube("Placeholder", holder, new Vector3(0, 0.75f, 0), new Vector3(1.85f, 0.9f, L), Res.Mat(spec.paint, 0.85f, 0.4f));
            }
            if (cfg != null && cfg.size != null && cfg.size.Length == 3)
            {
                halfW = cfg.size[0] * L * 0.5f;
                height = cfg.size[1] * L;
            }

            // --- wheel spots
            float rF = 0.34f, rR = 0.34f, zF = L * 0.32f, zR = -L * 0.3f, yF = 0.34f, yR = 0.34f, xF = halfW - 0.05f, xR = halfW - 0.05f;
            if (cfg != null && cfg.front != null && cfg.rear != null)
            {
                rF = cfg.front.r * L; rR = cfg.rear.r * L;
                zF = cfg.front.z * L; zR = cfg.rear.z * L;
                yF = cfg.front.y * L; yR = cfg.rear.y * L;
                xF = cfg.front.x * L; xR = cfg.rear.x * L;
            }
            float tyreW = Mathf.Clamp(L * 0.055f, 0.22f, 0.3f);
            spec.wheelRadius = (rF + rR) * 0.5f;

            // --- body collider (kept above the wheels so the WheelColliders carry the car)
            var col = new GameObject("Collider");
            col.transform.SetParent(root.transform, false);
            var box = col.AddComponent<BoxCollider>();
            float bottom = Mathf.Max(yF, yR) * 0.9f;
            box.center = new Vector3(0, (bottom + height * 0.92f) * 0.5f, 0);
            box.size = new Vector3(halfW * 1.9f, height * 0.92f - bottom, L * 0.97f);
#if UNITY_6000_0_OR_NEWER
            var pm = new PhysicsMaterial("body") { dynamicFriction = 0.25f, staticFriction = 0.3f, bounciness = 0.05f, frictionCombine = PhysicsMaterialCombine.Minimum };
#else
            var pm = new PhysicMaterial("body") { dynamicFriction = 0.25f, staticFriction = 0.3f, bounciness = 0.05f, frictionCombine = PhysicMaterialCombine.Minimum };
#endif
            box.material = pm;

            var car = root.AddComponent<CarController>();
            var wheelRoot = new GameObject("Wheels").transform;
            wheelRoot.SetParent(root.transform, false);
            var style = id == "classic" ? WheelMesh.Style.Classic : id == "suv" ? WheelMesh.Style.Deep6 : id == "muscle" ? WheelMesh.Style.Deep6 : id == "exotic" || id == "euro" ? WheelMesh.Style.Split5 : WheelMesh.Style.Mesh10;
            Color rimCol = id == "classic" ? new Color(0.95f, 0.95f, 0.97f) : id == "tuner" ? new Color(0.12f, 0.12f, 0.13f) : new Color(0.55f, 0.56f, 0.6f);
            var wheelMats = WheelMesh.Materials(rimCol, id == "exotic" ? new Color(0.95f, 0.75f, 0.05f) : new Color(0.75f, 0.04f, 0.04f));
            var wellMat = Res.Mat(new Color(0.012f, 0.012f, 0.014f), 0.05f, 0f);

            for (int i = 0; i < 4; i++)
            {
                bool front = i < 2, left = i % 2 == 0;
                float r = front ? rF : rR;
                float x = (front ? xF : xR) - tyreW * 0.5f;
                var wpos = new Vector3(left ? -x : x, front ? yF : yR, front ? zF : zR);

                var wcGo = new GameObject((front ? "F" : "R") + (left ? "L" : "R") + "_collider");
                wcGo.transform.SetParent(root.transform, false);
                wcGo.transform.localPosition = wpos;
                var wc = wcGo.AddComponent<WheelCollider>();
                wc.radius = r;
                car.wheels[i] = wc;

                var vis = new GameObject((front ? "F" : "R") + (left ? "L" : "R"));
                vis.transform.SetParent(wheelRoot, false);
                vis.transform.localPosition = wpos;
                var mesh = new GameObject("Mesh");
                mesh.transform.SetParent(vis.transform, false);
                mesh.transform.localScale = new Vector3(left ? -1 : 1, 1, 1);
                mesh.AddComponent<MeshFilter>().sharedMesh = WheelMesh.Get(r, tyreW, style);
                var mr = mesh.AddComponent<MeshRenderer>();
                mr.sharedMaterials = wheelMats;
                car.wheelVisuals[i] = vis.transform;

                // dark matte arch liner: a cylinder around the wheel drawn from the inside only (front faces culled),
                // so only its far inner wall and inner end show behind the tyre. It never catches light (unlit black).
                var well = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                Object.DestroyImmediate(well.GetComponent<Collider>());
                well.name = "ArchLiner";
                well.transform.SetParent(holder, false);
                float linerW = tyreW * 1.7f;
                well.transform.localPosition = new Vector3((left ? -1 : 1) * Mathf.Max(0.2f, x - tyreW * 0.55f), wpos.y + 0.03f, wpos.z);
                well.transform.localRotation = Quaternion.Euler(0, 0, 90);
                well.transform.localScale = new Vector3(r * 2.35f, linerW * 0.5f, r * 2.35f);   // a little bigger than the tyre, stays inside the body   // cylinder: y scale is half its length
                var wr = well.GetComponent<Renderer>();
                wr.sharedMaterial = LinerMat;
                wr.shadowCastingMode = ShadowCastingMode.Off;
            }

            car.Setup(spec);
            car.shadow = Res.ContactShadow(root.transform, halfW * 2f * 1.6f, L * 1.3f, Mathf.Min(yF - rF, yR - rR) + 0.03f).transform;

            // --- lights
            AddLights(root.transform, spec, L, halfW, height, player, Mathf.Min(yF - rF, yR - rR) + 0.05f);

            if (player)
            {
                // soft key light over the player car (racing-game trick): the paint reads at night without lighting the street
                var key = new GameObject("CarKeyLight").AddComponent<Light>();
                key.transform.SetParent(root.transform, false);
                key.transform.localPosition = new Vector3(0, height + 1.6f, -L * 0.15f);
                key.type = LightType.Point; key.range = Mathf.Max(5f, L * 1.1f); key.intensity = 2.2f;
                key.color = new Color(0.82f, 0.9f, 1f); key.shadows = LightShadows.None;
                key.renderMode = LightRenderMode.ForcePixel;
                key.cullingMask = 1 << 0;
            }
            if (player)
            {
                var au = root.AddComponent<CarAudio>();
                au.Setup(car, true);
                root.AddComponent<CarFx>().Setup(car);
            }
            return car;
        }

        static void AddLights(Transform root, CarSpec spec, float L, float halfW, float h, bool player, float groundY)
        {
            var lights = new GameObject("Lights").transform;
            lights.SetParent(root, false);
            var cl = root.gameObject.AddComponent<CarLights>();
            if (player)
            {
                for (int s = -1; s <= 1; s += 2)
                {
                    var go = new GameObject("Head" + (s < 0 ? "L" : "R"));
                    go.transform.SetParent(lights, false);
                    go.transform.localPosition = new Vector3(s * halfW * 0.62f, h * 0.42f, L * 0.5f);
                    go.transform.localRotation = Quaternion.Euler(7, s * 2f, 0);
                    var li = go.AddComponent<Light>();
                    li.type = LightType.Spot;
                    li.range = 55; li.spotAngle = 62; li.innerSpotAngle = 25;
                    li.intensity = 28f;
                    li.color = new Color(1f, 0.95f, 0.86f);
                    li.shadows = LightShadows.None;
                    cl.heads.Add(li);
                    // small lens glow on the lamp
                    cl.headGlows.Add(Sprite(lights, "HeadGlow", new Vector3(s * halfW * 0.64f, h * 0.5f, L * 0.455f), true, new Vector2(0.3f, 0.13f), HeadGlowMat));   // on the real lamps (they sit back on top of the bumper)
                }
                // two long soft light pools on the road ahead (the beams), they shine on the wet asphalt
                for (int s = -1; s <= 1; s += 2)
                {
                    var pool = Sprite(lights, "BeamPool", new Vector3(s * halfW * 0.45f, groundY, L * 0.5f + 8.5f), false, new Vector2(3.4f, 15f), BeamMat);
                    pool.transform.localRotation = Quaternion.Euler(90, s * 3f, 0);
                    cl.pools.Add(pool.transform);
                }
            }
            // tail glow: red light thrown back onto the road behind (a downward spot behind the car, so it does
            // not paint the bumper or plate)
            // (no red tail light any more: the URP spot made a hard red dot on the road at the bottom of the chase
            // view; the lamp glows and their reflection in the wet road give the red behind the car)
            // the lamp glows: a wide soft bar on each lamp, dim when cruising, bright when braking
            // per car: where the lamps are and their shape (x as a fraction of half width, y of height, size in metres)
            var tailMat = Res.Particle(new Color(1f, 0.08f, 0.05f, 0.85f), Res.SoftBox);
            var roundMat = Res.Particle(new Color(1f, 0.08f, 0.05f, 0.85f), Res.SoftDot);
            foreach (var lamp in TailLamps(spec.id))
                for (int s = -1; s <= 1; s += 2)
                {
                    var r = Sprite(lights, "TailLamp", new Vector3(s * halfW * lamp.x, h * lamp.y, -L * 0.5f + lamp.z), false, new Vector2(lamp.w, lamp.hgt), lamp.round ? roundMat : tailMat);
                    cl.tailSprites.Add(r);
                }
        }

        struct Lamp { public float x, y, z, w, hgt; public bool round; public Lamp(float x, float y, float z, float w, float h, bool r) { this.x = x; this.y = y; this.z = z; this.w = w; hgt = h; round = r; } }

        static Lamp[] TailLamps(string id)
        {
            switch (id)
            {
                case "sport": return new[] { new Lamp(0.48f, 0.67f, 0.05f, 0.24f, 0.24f, true), new Lamp(0.76f, 0.67f, 0.11f, 0.24f, 0.24f, true) };   // four round lamps
                case "pickup": return new[] { new Lamp(0.93f, 0.66f, 0.02f, 0.14f, 0.42f, false) };   // tall vertical lamps on the bed corners
                default: return new[] { new Lamp(0.72f, 0.66f, -0.03f, 0.44f, 0.1f, false) };
            }
        }

        /// <summary>A flat glow quad. faceForward: shows its picture to the front (+Z); otherwise to the back (-Z).</summary>
        static Renderer Sprite(Transform parent, string name, Vector3 pos, bool faceForward, Vector2 size, Material m)
        {
            var q = GameObject.CreatePrimitive(PrimitiveType.Quad);
            Object.DestroyImmediate(q.GetComponent<Collider>());
            q.name = name;
            q.transform.SetParent(parent, false);
            q.transform.localPosition = pos;
            if (faceForward) q.transform.localRotation = Quaternion.Euler(0, 180, 0);
            q.transform.localScale = new Vector3(size.x, size.y, 1);
            var r = q.GetComponent<Renderer>();
            r.sharedMaterial = m;
            r.shadowCastingMode = ShadowCastingMode.Off;
            r.receiveShadows = false;
            return r;
        }

        static Material linerMat, headGlowMat, beamMat;
        static Material LinerMat
        {
            get
            {
                if (linerMat != null) return linerMat;
                linerMat = Res.UnlitMat(new Color(0.006f, 0.006f, 0.008f));
                linerMat.SetFloat("_Cull", 1f);   // front faces off: only the inside of the cylinder shows
                return linerMat;
            }
        }
        static Material HeadGlowMat => headGlowMat ? headGlowMat : (headGlowMat = Res.Particle(new Color(1f, 0.95f, 0.85f, 0.9f) * 1.6f, Res.SoftDot));
        static Material BeamMat => beamMat ? beamMat : (beamMat = Res.Particle(new Color(1f, 0.92f, 0.78f, 0.16f), Res.SoftDot));

        /// <summary>Glossy clear-coated paint from the model's own texture. Cars with a key colour get repainted.</summary>
        static void ApplyPaint(GameObject model, string id, CarModelCfg cfg, CarSpec spec)
        {
            foreach (var r in model.GetComponentsInChildren<Renderer>())
            {
                r.shadowCastingMode = ShadowCastingMode.On;
                var src = r.sharedMaterials;
                if (!bodyMats.TryGetValue(id, out var mats) || mats.Length != src.Length)
                {
                    mats = new Material[src.Length];
                    for (int i = 0; i < src.Length; i++)
                    {
                        var s = src[i];
                        var tex = FindTex(s, "baseColorTexture", "_BaseMap", "_MainTex");
                        var nrm = FindTex(s, "normalTexture", "_BumpMap");
                        if (tex != null && cfg != null && !string.IsNullOrEmpty(cfg.key) && ColorUtility.TryParseHtmlString(cfg.key, out var key))
                            tex = Repaint.Recolor(tex, key, spec.paint);
                        var m = Res.Paint(Color.white);   // clear-coated paint, works with any model texture
                        if (tex != null) Res.SetMainTex(m, tex, Vector2.one);
                        if (nrm != null) { m.SetTexture("_BumpMap", nrm); m.SetFloat("_BumpScale", 0.3f); m.EnableKeyword("_NORMALMAP"); }   // baked normal map is noisy: keep it subtle so panels read smooth
                        // the clear coat: high smoothness, environment reflections on
                        m.SetFloat("_EnvironmentReflections", 1f);
                        m.SetFloat("_SpecularHighlights", 1f);
                        mats[i] = m;
                    }
                    bodyMats[id] = mats;
                }
                r.sharedMaterials = mats;
            }
        }

        static Texture FindTex(Material m, params string[] names)
        {
            if (m == null) return null;
            foreach (var n in names) if (m.HasProperty(n) && m.GetTexture(n) != null) return m.GetTexture(n);
            return null;
        }

        /// <summary>A lighter traffic car: the 6,000-triangle model on a kinematic body.</summary>
        public static GameObject BuildTraffic(string id, Transform parent, Color paint, bool lights = true)
        {
            var spec = CarDB.Get(id);
            float L = spec.length;
            var go = new GameObject("Traffic_" + id);
            go.transform.SetParent(parent, false);
            var prefab = Res.Load<GameObject>("Cars/" + id + "_lod") ?? Res.Load<GameObject>("Cars/" + id);
            float halfW = 0.95f, h = 1.35f;
            if (prefab != null)
            {
                var m = Object.Instantiate(prefab, go.transform);
                m.transform.localScale = Vector3.one * L;
                foreach (var c in m.GetComponentsInChildren<Collider>()) Object.DestroyImmediate(c);
                foreach (var r in m.GetComponentsInChildren<Renderer>())
                {
                    var src = r.sharedMaterial;
                    var tex = FindTex(src, "baseColorTexture", "_BaseMap", "_MainTex");
                    string k = "lod_" + id + "_" + ColorUtility.ToHtmlStringRGB(paint);
                    if (!bodyMats.TryGetValue(k, out var mats))
                    {
                        var mat = Res.Mat(Color.white, 0.8f, 0.3f);
                        // repaint the body colour (found automatically in the texture) to this car's paint
                        if (tex && paint != Color.gray) tex = Repaint.RecolorAuto(tex, id, paint, 512) ?? tex;
                        if (tex) Res.SetMainTex(mat, tex, Vector2.one);
                        mats = new[] { mat };
                        bodyMats[k] = mats;
                    }
                    r.sharedMaterial = mats[0];
                    r.shadowCastingMode = ShadowCastingMode.Off;
                }
                var cfg = CarModelCfg.Load(id);
                if (cfg != null && cfg.size != null && cfg.size.Length == 3) { halfW = cfg.size[0] * L * 0.5f; h = cfg.size[1] * L; }
            }
            else MeshBuilder.Cube("Body", go.transform, new Vector3(0, 0.7f, 0), new Vector3(1.8f, 1.2f, L), Res.Mat(paint, 0.8f, 0.3f));
            Res.ContactShadow(go.transform, halfW * 2f * 1.6f, L * 1.3f, 0.045f);
            var bc = go.AddComponent<BoxCollider>();
            bc.center = new Vector3(0, h * 0.5f, 0);
            bc.size = new Vector3(halfW * 2, h, L);
            var rb = go.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            rb.mass = spec.weightKg;
            if (!lights) return go;   // parked: no glows
            // tail lights so traffic reads at night
            for (int s = -1; s <= 1; s += 2)
            {
                var q = GameObject.CreatePrimitive(PrimitiveType.Quad);
                Object.DestroyImmediate(q.GetComponent<Collider>());
                q.transform.SetParent(go.transform, false);
                q.transform.localPosition = new Vector3(s * halfW * 0.72f, h * 0.64f, -L * 0.5f - 0.02f);   // on the real tail lamps
                q.transform.localScale = new Vector3(0.4f, 0.09f, 1);
                q.GetComponent<Renderer>().sharedMaterial = TrafficTail;
                q.GetComponent<Renderer>().shadowCastingMode = ShadowCastingMode.Off;
                var hq = GameObject.CreatePrimitive(PrimitiveType.Quad);
                Object.DestroyImmediate(hq.GetComponent<Collider>());
                hq.transform.SetParent(go.transform, false);
                hq.transform.localPosition = new Vector3(s * halfW * 0.65f, h * 0.45f, L * 0.5f + 0.02f);
                hq.transform.localRotation = Quaternion.Euler(0, 180, 0);
                hq.transform.localScale = new Vector3(0.4f, 0.2f, 1);
                hq.GetComponent<Renderer>().sharedMaterial = TrafficHead;
                hq.GetComponent<Renderer>().shadowCastingMode = ShadowCastingMode.Off;
            }
            // a soft headlight pool on the road ahead (reflects in the wet street)
            var pool = GameObject.CreatePrimitive(PrimitiveType.Quad);
            Object.DestroyImmediate(pool.GetComponent<Collider>());
            pool.transform.SetParent(go.transform, false);
            pool.transform.localPosition = new Vector3(0, 0.05f, L * 0.5f + 6f);
            pool.transform.localRotation = Quaternion.Euler(90, 0, 0);
            pool.transform.localScale = new Vector3(3.6f, 10f, 1);
            pool.GetComponent<Renderer>().sharedMaterial = BeamMat;
            pool.GetComponent<Renderer>().shadowCastingMode = ShadowCastingMode.Off;
            return go;
        }

        static Material trafficTail, trafficHead;
        static Material TrafficTail => trafficTail ? trafficTail : (trafficTail = Res.Particle(new Color(1f, 0.06f, 0.04f, 0.9f) * 1.6f, Res.SoftBox));
        static Material TrafficHead => trafficHead ? trafficHead : (trafficHead = Res.Particle(new Color(1f, 0.96f, 0.85f, 0.95f) * 2.5f, Res.SoftDot));
    }

    /// <summary>Head lights, tail lights and brake lights.</summary>
    public class CarLights : MonoBehaviour
    {
        public readonly List<Light> heads = new List<Light>();
        public Light tail;
        public readonly List<Renderer> tailSprites = new List<Renderer>();
        public readonly List<Transform> pools = new List<Transform>();
        public readonly List<Renderer> headGlows = new List<Renderer>();
        bool lastInside;
        CarController car;
        MaterialPropertyBlock mpb;

        void Start() { car = GetComponent<CarController>(); mpb = new MaterialPropertyBlock(); }

        void Update()
        {
            if (car == null) return;
            // headlights off inside the workshop (it lives far away, at z = -3000)
            bool inside = transform.position.z < -1500f;
            if (inside != lastInside)
            {
                lastInside = inside;
                foreach (var h in heads) if (h) h.enabled = !inside;
                foreach (var p in pools) if (p) p.gameObject.SetActive(!inside);
                foreach (var g in headGlows) if (g) g.enabled = !inside;
            }
            bool braking = car.brake > 0.1f || car.handbrake;
            if (tail) tail.intensity = System.Environment.CommandLine.Contains("-notail") ? 0f : (braking ? 2.4f : 0.5f);
            float k = braking ? 3.6f : 1.1f;   // dim lamp bar when cruising, bright when braking
            foreach (var r in tailSprites)
            {
                r.GetPropertyBlock(mpb);
                mpb.SetColor("_BaseColor", new Color(1f, 0.06f, 0.04f, 0.9f) * k);
                r.SetPropertyBlock(mpb);
            }
        }
    }

    /// <summary>Recolours a body texture: pixels close to the key hue take the new paint, keeping their shading.</summary>
    public static class Repaint
    {
        static readonly Dictionary<string, Color?> autoKeys = new Dictionary<string, Color?>();

        /// <summary>Repaints a body texture whose paint colour is not known: the most common saturated hue in the
        /// texture is taken as the paint (cars are mostly body). Returns null when the texture has no clear paint colour.</summary>
        public static Texture2D RecolorAuto(Texture src, string id, Color paint, int maxSize)
        {
            var cfg = CarModelCfg.Load(id);
            if (cfg != null && !string.IsNullOrEmpty(cfg.key) && ColorUtility.TryParseHtmlString(cfg.key, out var ck)) return Recolor(src, ck, paint, maxSize);
            if (!autoKeys.TryGetValue(id, out var key))
            {
                key = FindPaint(src);
                autoKeys[id] = key;
            }
            return key.HasValue ? Recolor(src, key.Value, paint, maxSize) : null;
        }

        static Color? FindPaint(Texture src)
        {
            int w = Mathf.Min(src.width, 256), h = Mathf.Min(src.height, 256);
            var rt = RenderTexture.GetTemporary(w, h, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
            Graphics.Blit(src, rt);
            var prev = RenderTexture.active; RenderTexture.active = rt;
            var t = new Texture2D(w, h, TextureFormat.RGBA32, false);
            t.ReadPixels(new Rect(0, 0, w, h), 0, 0);
            RenderTexture.active = prev; RenderTexture.ReleaseTemporary(rt);
            var px = t.GetPixels32();
            Object.Destroy(t);
            int[] bins = new int[36]; float[] sv = new float[36]; float[] vv = new float[36];
            foreach (Color c in px)
            {
                Color.RGBToHSV(c, out float hh, out float ss, out float v);
                if (ss < 0.35f || v < 0.2f) continue;
                int b = Mathf.Min(35, (int)(hh * 36));
                bins[b]++; sv[b] += ss; vv[b] += v;
            }
            int best = 0;
            for (int i = 1; i < 36; i++) if (bins[i] > bins[best]) best = i;
            if (bins[best] < px.Length * 0.05f) return null;
            return Color.HSVToRGB((best + 0.5f) / 36f, sv[best] / bins[best], vv[best] / bins[best]);
        }

        public static Texture2D Recolor(Texture src, Color key, Color paint, int maxSize = 2048)
        {
            int w = Mathf.Min(src.width, maxSize), h = Mathf.Min(src.height, maxSize);
            var rt = RenderTexture.GetTemporary(w, h, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
            Graphics.Blit(src, rt);
            var prev = RenderTexture.active;
            RenderTexture.active = rt;
            var t = new Texture2D(w, h, TextureFormat.RGBA32, true);
            t.ReadPixels(new Rect(0, 0, w, h), 0, 0);
            RenderTexture.active = prev;
            RenderTexture.ReleaseTemporary(rt);
            Color.RGBToHSV(key, out float kh, out float ks, out float kv);
            Color.RGBToHSV(paint, out float ph, out float ps, out float pv);
            var px = t.GetPixels32();
            for (int i = 0; i < px.Length; i++)
            {
                Color c = px[i];
                Color.RGBToHSV(c, out float hh, out float ss, out float vv);
                float dh = Mathf.Abs(hh - kh); dh = Mathf.Min(dh, 1 - dh);
                if (dh < 0.07f && ss > 0.25f)
                {
                    float shade = vv / Mathf.Max(0.05f, kv);
                    var nc = Color.HSVToRGB(ph, ps, Mathf.Clamp01(pv * shade));
                    nc.a = c.a;
                    px[i] = nc;
                }
            }
            t.SetPixels32(px);
            t.Apply(true);
            return t;
        }
    }
}
