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

                // dark wheel well behind the cut-out, so the arches are not see-through
                var well = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                Object.DestroyImmediate(well.GetComponent<Collider>());
                well.name = "Well";
                well.transform.SetParent(holder, false);
                well.transform.localPosition = new Vector3((left ? -1 : 1) * Mathf.Max(0.2f, x - tyreW * 0.7f), wpos.y + 0.03f, wpos.z);
                well.transform.localRotation = Quaternion.Euler(0, 0, 90);
                well.transform.localScale = new Vector3(r * 2.25f, 0.02f, r * 2.25f);
                well.GetComponent<Renderer>().sharedMaterial = wellMat;
            }

            car.Setup(spec);
            car.shadow = Res.ContactShadow(root.transform, halfW * 2f * 1.6f, L * 1.3f, Mathf.Min(yF - rF, yR - rR) + 0.03f).transform;

            // --- lights
            AddLights(root.transform, spec, L, halfW, height, player);

            if (player)
            {
                var au = root.AddComponent<CarAudio>();
                au.Setup(car, true);
                root.AddComponent<CarFx>().Setup(car);
            }
            return car;
        }

        static void AddLights(Transform root, CarSpec spec, float L, float halfW, float h, bool player)
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
                }
            }
            // tail glow: soft red light on the road behind (looks great on wet asphalt) and two glow sprites
            var tail = new GameObject("TailGlow");
            tail.transform.SetParent(lights, false);
            tail.transform.localPosition = new Vector3(0, h * 0.45f, -L * 0.5f - 0.3f);
            var tl = tail.AddComponent<Light>();
            tl.type = LightType.Point;
            tl.range = player ? 7f : 4f;
            tl.intensity = 1.2f;
            tl.color = new Color(1f, 0.05f, 0.03f);
            tl.shadows = LightShadows.None;
            tl.renderMode = player ? LightRenderMode.ForcePixel : LightRenderMode.Auto;
            cl.tail = tl;
            for (int s = -1; s <= 1; s += 2)
            {
                var q = GameObject.CreatePrimitive(PrimitiveType.Quad);
                Object.DestroyImmediate(q.GetComponent<Collider>());
                q.name = "TailSprite";
                q.transform.SetParent(lights, false);
                q.transform.localPosition = new Vector3(s * halfW * 0.7f, h * 0.55f, -L * 0.5f - 0.02f);
                q.transform.localScale = new Vector3(0.38f, 0.16f, 1);
                var m = Res.Particle(new Color(1f, 0.08f, 0.05f, 0.85f) * 2.2f, Res.SoftDot);
                var r = q.GetComponent<Renderer>();
                r.sharedMaterial = m;
                r.shadowCastingMode = ShadowCastingMode.Off;
                cl.tailSprites.Add(r);
            }
        }

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
        public static GameObject BuildTraffic(string id, Transform parent, Color paint)
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
                    string k = "lod_" + id;
                    if (!bodyMats.TryGetValue(k, out var mats))
                    {
                        var mat = Res.Mat(Color.white, 0.8f, 0.3f);
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
            // tail lights so traffic reads at night
            for (int s = -1; s <= 1; s += 2)
            {
                var q = GameObject.CreatePrimitive(PrimitiveType.Quad);
                Object.DestroyImmediate(q.GetComponent<Collider>());
                q.transform.SetParent(go.transform, false);
                q.transform.localPosition = new Vector3(s * halfW * 0.7f, h * 0.55f, -L * 0.5f - 0.02f);
                q.transform.localScale = new Vector3(0.34f, 0.14f, 1);
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
            return go;
        }

        static Material trafficTail, trafficHead;
        static Material TrafficTail => trafficTail ? trafficTail : (trafficTail = Res.Particle(new Color(1f, 0.06f, 0.04f, 0.9f) * 2f, Res.SoftDot));
        static Material TrafficHead => trafficHead ? trafficHead : (trafficHead = Res.Particle(new Color(1f, 0.96f, 0.85f, 0.95f) * 2.5f, Res.SoftDot));
    }

    /// <summary>Head lights, tail lights and brake lights.</summary>
    public class CarLights : MonoBehaviour
    {
        public readonly List<Light> heads = new List<Light>();
        public Light tail;
        public readonly List<Renderer> tailSprites = new List<Renderer>();
        CarController car;
        MaterialPropertyBlock mpb;

        void Start() { car = GetComponent<CarController>(); mpb = new MaterialPropertyBlock(); }

        void Update()
        {
            if (car == null) return;
            bool braking = car.brake > 0.1f || car.handbrake;
            if (tail) tail.intensity = braking ? 3.5f : 1.0f;
            float k = braking ? 4.5f : 1.8f;
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
        public static Texture2D Recolor(Texture src, Color key, Color paint)
        {
            int w = Mathf.Min(src.width, 2048), h = Mathf.Min(src.height, 2048);
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
