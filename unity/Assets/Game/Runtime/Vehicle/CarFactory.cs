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
            foundLamps = default;
            var prefab = Res.Load<GameObject>("Cars/" + id);
            if (prefab != null)
            {
                var model = Object.Instantiate(prefab, holder);
                model.name = "Model";
                model.transform.localPosition = Vector3.zero;
                model.transform.localRotation = Quaternion.identity;
                model.transform.localScale = Vector3.one * L;
                foundLamps = LampFinder.Find(id, model, root.transform, L);   // before repaint: lens colours from the original texture
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
            var style = id == "classic" ? WheelMesh.Style.Classic : id == "suv" || id == "pickup" ? WheelMesh.Style.Deep6 : id == "muscle" ? WheelMesh.Style.Deep6 : id == "exotic" || id == "euro" || id == "sport" ? WheelMesh.Style.Split5 : WheelMesh.Style.Mesh10;
            Color rimCol = id == "classic" ? new Color(0.95f, 0.95f, 0.97f) : id == "tuner" ? new Color(0.12f, 0.12f, 0.13f) : id == "pickup" ? new Color(0.88f, 0.89f, 0.92f) : id == "sport" ? new Color(0.72f, 0.74f, 0.78f) : new Color(0.55f, 0.56f, 0.6f);   // pickup polished chrome, sport silver
            var wheelMats = WheelMesh.Materials(rimCol, id == "exotic" ? new Color(0.95f, 0.75f, 0.05f) : id == "pickup" ? new Color(0.12f, 0.12f, 0.13f) : new Color(0.75f, 0.04f, 0.04f));
            var wellMat = Res.Mat(new Color(0.012f, 0.012f, 0.014f), 0.05f, 0f);

            for (int i = 0; i < 4; i++)
            {
                bool front = i < 2, left = i % 2 == 0;
                float r = front ? rF : rR;
                float tw = front ? tyreW : tyreW * (id == "sport" ? 1.18f : 1f);   // wide rear tyres on the sports car
                float x = (front ? xF : xR) - tw * 0.5f;
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
                var realWheel = RealWheel(id);
                if (realWheel != null)
                {
                    // real 3D wheel (unit diameter, axle along X, outer face at x = 0 looking +X): scale to the tyre,
                    // outer face on the tyre face, mirrored on the left side
                    var rw = Object.Instantiate(realWheel, vis.transform);
                    rw.name = "Mesh";
                    float k = 2f * r;
                    rw.transform.localPosition = new Vector3((left ? -1 : 1) * tw * 0.5f, 0, 0);
                    rw.transform.localRotation = Quaternion.identity;
                    // the glTF import can come in mirrored on X: the body must lie on -X behind the outer face (x = 0)
                    float flip = RealWheelFlip(realWheel);
                    rw.transform.localScale = new Vector3((left ? -1 : 1) * k * flip, k, k);
                    foreach (var c in rw.GetComponentsInChildren<Collider>()) Object.DestroyImmediate(c);
                    foreach (var wr0 in rw.GetComponentsInChildren<Renderer>()) { wr0.sharedMaterials = RealWheelMats(id, wr0.sharedMaterials); wr0.shadowCastingMode = ShadowCastingMode.On; }
                }
                else
                {
                var mesh = new GameObject("Mesh");
                mesh.transform.SetParent(vis.transform, false);
                mesh.transform.localScale = new Vector3(left ? -1 : 1, 1, 1);
                mesh.AddComponent<MeshFilter>().sharedMesh = WheelMesh.Get(r, tw, style);
                var mr = mesh.AddComponent<MeshRenderer>();
                mr.sharedMaterials = wheelMats;
                }
                car.wheelVisuals[i] = vis.transform;

                // dark matte arch liner: a cylinder around the wheel drawn from the inside only (front faces culled),
                // so only its far inner wall and inner end show behind the tyre. It never catches light (unlit black).
                var well = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                Object.DestroyImmediate(well.GetComponent<Collider>());
                well.GetComponent<MeshFilter>().sharedMesh = HalfLinerMesh();   // upper part only: never below the sill
                well.name = "ArchLiner";
                well.transform.SetParent(holder, false);
                float linerW = tw * 1.7f;
                well.transform.localPosition = new Vector3((left ? -1 : 1) * Mathf.Max(0.2f, x - tw * 0.55f), wpos.y + 0.03f, wpos.z);
                well.transform.localRotation = Quaternion.Euler(0, 0, 90);
                well.transform.localScale = new Vector3(r * 2.35f, linerW * 0.5f, r * 2.35f);   // a little bigger than the tyre, stays inside the body   // cylinder: y scale is half its length
                var wr = well.GetComponent<Renderer>();
                wr.sharedMaterial = LinerMat;
                wr.shadowCastingMode = ShadowCastingMode.Off;
                // thin black trim ring over the arch at the fender face: hides the ragged cut edge of the body
                var trim = new GameObject("ArchTrim");
                trim.transform.SetParent(holder, false);
                trim.transform.localPosition = new Vector3((left ? -1 : 1) * (x + tw * 0.5f + 0.012f), wpos.y, wpos.z);
                trim.AddComponent<MeshFilter>().sharedMesh = ArchTrimMesh(r * 1.04f, r * 1.2f);
                var trr = trim.AddComponent<MeshRenderer>();
                trr.sharedMaterial = TrimMat; trr.shadowCastingMode = ShadowCastingMode.Off;
            }

            car.Setup(spec);
            car.shadow = Res.ContactShadow(root.transform, halfW * 2f * 1.6f, L * 1.3f, Mathf.Min(yF - rF, yR - rR) + 0.03f).transform;

            // --- lights
            AddLights(root.transform, spec, L, halfW, height, player, Mathf.Min(yF - rF, yR - rR) + 0.05f);

            if (player)
            {
                // soft key light over the player car (racing-game trick): the paint reads at night without lighting the street
                // the car body lives on its own layer (9), so these lights touch only the car, never the street
                foreach (var r in holder.GetComponentsInChildren<Renderer>(true)) r.gameObject.layer = CarLayer;
                CarLight(root.transform, "CarKeyLight", new Vector3(0, height + 2.4f, L * 0.1f), Mathf.Max(6f, L * 1.3f), 3.6f, new Color(0.85f, 0.9f, 1f));
                // rim lights low behind and at the rear quarters: the chase camera sees the tail and flanks
                CarLight(root.transform, "CarRimRear", new Vector3(0, height * 0.7f, -L * 0.95f), Mathf.Max(4f, L * 0.9f), 4f, new Color(0.7f, 0.8f, 1f));
                CarLight(root.transform, "CarRimL", new Vector3(-halfW * 2.6f, height * 0.9f, -L * 0.2f), Mathf.Max(4f, L * 0.8f), 3f, new Color(1f, 0.75f, 0.55f));
                CarLight(root.transform, "CarRimR", new Vector3(halfW * 2.6f, height * 0.9f, -L * 0.2f), Mathf.Max(4f, L * 0.8f), 3f, new Color(0.6f, 0.8f, 1f));
            }
            if (player)
            {
                var au = root.AddComponent<CarAudio>();
                au.Setup(car, true);
                root.AddComponent<CarFx>().Setup(car);
            }
            return car;
        }

        static (List<LampFinder.Lens> tail, List<LampFinder.Lens> head) foundLamps;

        static Mesh halfLiner;
        /// <summary>
        /// The arch liner shape: the upper part of a unit cylinder (same axes as Unity's primitive: axis Y, radius 0.5,
        /// y -1..1; "up" after the liner's 90 degree roll is +X), from a little below the axle round over the top.
        /// The full cylinder hung below the sills and showed as a dark second tyre beside each wheel (Hamad: "more than 4 wheels").
        /// </summary>
        static Mesh HalfLinerMesh()
        {
            if (halfLiner != null) return halfLiner;
            const int seg = 24; float a0 = -100f * Mathf.Deg2Rad, a1 = 100f * Mathf.Deg2Rad;
            var v = new List<Vector3>(); var n = new List<Vector3>(); var t = new List<int>();
            for (int i = 0; i <= seg; i++)
            {
                float a = Mathf.Lerp(a0, a1, i / (float)seg); var d = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a));
                v.Add(d * 0.5f + Vector3.down); n.Add(d); v.Add(d * 0.5f + Vector3.up); n.Add(d);
            }
            for (int i = 0; i < seg; i++) { int a = i * 2, b = a + 2; t.AddRange(new[] { a, a + 1, b, b, a + 1, b + 1 }); }   // outward front faces
            foreach (float y in new[] { -1f, 1f })
            {
                int c = v.Count; v.Add(new Vector3(0, y, 0)); n.Add(new Vector3(0, y, 0));
                for (int i = 0; i <= seg; i++) { float a = Mathf.Lerp(a0, a1, i / (float)seg); v.Add(new Vector3(Mathf.Cos(a) * 0.5f, y, Mathf.Sin(a) * 0.5f)); n.Add(new Vector3(0, y, 0)); }
                for (int i = 0; i < seg; i++) { if (y > 0) t.AddRange(new[] { c, c + 2 + i, c + 1 + i }); else t.AddRange(new[] { c, c + 1 + i, c + 2 + i }); }
            }
            halfLiner = new Mesh { name = "HalfLiner" };
            halfLiner.SetVertices(v); halfLiner.SetNormals(n); halfLiner.SetTriangles(t, 0); halfLiner.RecalculateBounds();
            return halfLiner;
        }

        static readonly Dictionary<string, Mesh> trimMeshes = new Dictionary<string, Mesh>();
        /// <summary>A flat half ring in the Y/Z plane over the top of a wheel (from just below the axle in front to just below it behind).</summary>
        static Mesh ArchTrimMesh(float rIn, float rOut)
        {
            string key = rIn.ToString("F3") + rOut.ToString("F3");
            if (trimMeshes.TryGetValue(key, out var m)) return m;
            var v = new List<Vector3>(); var t = new List<int>();
            const int n = 28;
            for (int i = 0; i <= n; i++)
            {
                float a = Mathf.Lerp(-12f, 192f, i / (float)n) * Mathf.Deg2Rad;
                var d = new Vector3(0, Mathf.Sin(a), Mathf.Cos(a));
                v.Add(d * rIn); v.Add(d * rOut);
                if (i > 0) { int b = i * 2; t.AddRange(new[] { b - 2, b - 1, b, b - 1, b + 1, b }); }
            }
            m = new Mesh { name = "archtrim" };
            m.SetVertices(v); m.SetTriangles(t, 0); m.RecalculateNormals(); m.RecalculateBounds();
            trimMeshes[key] = m;
            return m;
        }
        static Material trimMat;
        static Material TrimMat { get { if (trimMat == null) { trimMat = Res.UnlitMat(new Color(0.01f, 0.01f, 0.012f)); trimMat.SetFloat("_Cull", 0f); } return trimMat; } }

        /// <summary>The real 3D wheel model for the main cars (null: use the procedural wheel).</summary>
        static GameObject RealWheel(string id) =>
            id == "sport" ? Res.Load<GameObject>("Cars/wheel_sport") : id == "pickup" ? Res.Load<GameObject>("Cars/wheel_truck") : null;

        static Texture2D MetalFromBrightness(Texture src)
        {
            const int S = 512;
            var rt = RenderTexture.GetTemporary(S, S, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
            Graphics.Blit(src, rt);
            var prev = RenderTexture.active; RenderTexture.active = rt;
            var t = new Texture2D(S, S, TextureFormat.RGBA32, true, true);
            t.ReadPixels(new Rect(0, 0, S, S), 0, 0);
            RenderTexture.active = prev; RenderTexture.ReleaseTemporary(rt);
            var px = t.GetPixels32();
            for (int i = 0; i < px.Length; i++)
            {
                Color c = px[i];
                Color.RGBToHSV(c, out float hh, out float ss, out float vv);
                float metalK = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(0.28f, 0.55f, vv)) * (1f - Mathf.InverseLerp(0.25f, 0.5f, ss));
                byte mt = (byte)(metalK * 0.75f * 255), sm = (byte)(Mathf.Lerp(0.22f, 0.78f, metalK) * 255);
                px[i] = new Color32(mt, mt, mt, sm);
            }
            t.SetPixels32(px); t.Apply(true);
            return t;
        }

        static readonly Dictionary<GameObject, float> wheelFlip = new Dictionary<GameObject, float>();
        static float RealWheelFlip(GameObject prefab)
        {
            if (wheelFlip.TryGetValue(prefab, out var f)) return f;
            float cx = 0; int n = 0;
            foreach (var mf in prefab.GetComponentsInChildren<MeshFilter>())
            {
                if (mf.sharedMesh == null) continue;
                var b = mf.sharedMesh.bounds;
                cx += prefab.transform.InverseTransformPoint(mf.transform.TransformPoint(b.center)).x; n++;
            }
            f = n > 0 && cx / n > 0 ? -1f : 1f;
            Debug.Log($"[HMD] wheel {prefab.name}: centre x {(n > 0 ? cx / n : 0):F3} -> flip {f}");
            wheelFlip[prefab] = f;
            return f;
        }

        static readonly Dictionary<string, Material[]> wheelMatCache = new Dictionary<string, Material[]>();
        /// <summary>Lit copies of the wheel model's materials: metal parts bright (not a pure mirror, which shows the dark
        /// night and reads black), a little self light from their own texture; rubber matte.</summary>
        static Material[] RealWheelMats(string id, Material[] src)
        {
            string key = id + src.Length + (src.Length > 0 && src[0] ? src[0].name : "");
            if (wheelMatCache.TryGetValue(key, out var hit)) return hit;
            var outM = new Material[src.Length];
            for (int i = 0; i < src.Length; i++)
            {
                var s = src[i];
                var tex = FindTex(s, "baseColorTexture", "_BaseMap", "_MainTex");
                Color col = s && s.HasProperty("_BaseColor") ? s.GetColor("_BaseColor") : Color.white;
                float metal = s && s.HasProperty("_Metallic") ? s.GetFloat("_Metallic") : 0f;
                var nrm = FindTex(s, "normalTexture", "_BumpMap");
                string mn = s ? s.name.ToLowerInvariant() : "";
                bool rubber = mn.Contains("tire") || mn.Contains("tyre") || mn.Contains("rubber");
                bool isMetal = !rubber && (metal > 0.3f || mn.Contains("rim") || mn.Contains("metal") || mn.Contains("chrome") || mn.Contains("spoke"));
                Debug.Log($"[HMD] wheel mat {id}: {mn} metallic={metal:F2} tex={(tex ? tex.name : "-")} -> metal={isMetal}");
                var m = Res.Mat(col, isMetal ? 0.72f : 0.25f, isMetal ? 0.55f : 0f);
                if (tex) { Res.SetMainTex(m, tex, Vector2.one); if (isMetal) Res.SetEmission(m, Color.white * 0.06f, tex); }
                if (!isMetal && !rubber && tex)
                {
                    // one texture for tyre and rim: derive a metal/smoothness map from it (bright grey = polished metal,
                    // dark = rubber), so the rim shines and the tyre stays matte
                    m.SetTexture("_MetallicGlossMap", MetalFromBrightness(tex));
                    m.EnableKeyword("_METALLICSPECGLOSSMAP");
                    m.SetFloat("_Smoothness", 1f); m.SetFloat("_Metallic", 1f);
                    Res.SetEmission(m, Color.white * 0.05f, tex);
                }
                if (nrm) { m.SetTexture("_BumpMap", nrm); m.EnableKeyword("_NORMALMAP"); }
                outM[i] = m;
            }
            wheelMatCache[key] = outM;
            return outM;
        }

        public const int CarLayer = 9;

        static void CarLight(Transform root, string name, Vector3 pos, float range, float intensity, Color c)
        {
            var l = new GameObject(name).AddComponent<Light>();
            l.transform.SetParent(root, false);
            l.transform.localPosition = pos;
            l.type = LightType.Point; l.range = range; l.intensity = intensity; l.color = c;
            l.shadows = LightShadows.None;
            l.renderMode = LightRenderMode.ForcePixel;
            l.cullingMask = 1 << CarLayer;
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
                    var hl = foundLamps.head != null ? foundLamps.head.Find(l => l.centre.x * s > 0) : default;
                    if (foundLamps.head != null && hl.size.x > 0)
                    {
                        // a wide cluster takes in the chrome grille too: the lamp is its outer end
                        Vector3 hc = hl.centre;
                        if (hl.size.x > 0.4f) hc.x = Mathf.Sign(hc.x) * (Mathf.Abs(hc.x) + hl.size.x * 0.5f - 0.17f);
                        hc.y += hl.size.y * 0.2f;   // the lens itself is the upper part of the clear area (the lower part is bumper trim)
                        go.transform.localPosition = hc;
                        cl.headGlows.Add(Sprite(lights, "HeadGlow", hc + Vector3.forward * 0.2f, true, new Vector2(Mathf.Min(hl.size.x, 0.3f), Mathf.Min(hl.size.y, 0.16f)), HeadGlowMat));
                    }
                    else
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
            bool roundLamps = spec.id == "sport";
            if (foundLamps.tail != null && foundLamps.tail.Count >= 2)
            {
                // measured on the real lenses: same place, same shape
                foreach (var lens in foundLamps.tail)
                {
                    // a tall lamp (pickup) wraps round the body corner: centre the glow on the rear lens, not the side strip
                    Vector3 lc = lens.centre;
                    if (lens.size.y > lens.size.x * 1.6f) lc.x -= Mathf.Sign(lc.x) * lens.size.x * 0.3f;
                    cl.tailSprites.Add(Sprite(lights, "TailLamp", lc + Vector3.back * 0.03f, false, lens.size * 1.05f + Vector2.one * 0.01f, roundLamps ? roundMat : tailMat));
                }
            }
            else
                foreach (var lamp in TailLamps(spec.id))
                    for (int s = -1; s <= 1; s += 2)
                        cl.tailSprites.Add(Sprite(lights, "TailLamp", new Vector3(s * halfW * lamp.x, h * lamp.y, -L * 0.5f + lamp.z), false, new Vector2(lamp.w, lamp.hgt), lamp.round ? roundMat : tailMat));
        }

        struct Lamp { public float x, y, z, w, hgt; public bool round; public Lamp(float x, float y, float z, float w, float h, bool r) { this.x = x; this.y = y; this.z = z; this.w = w; hgt = h; round = r; } }

        static Lamp[] TailLamps(string id)
        {
            switch (id)
            {
                case "sport": return new[] { new Lamp(0.48f, 0.67f, 0.05f, 0.24f, 0.24f, true), new Lamp(0.76f, 0.67f, 0.11f, 0.24f, 0.24f, true) };   // four round lamps
                case "pickup": return new[] { new Lamp(0.93f, 0.66f, -0.06f, 0.15f, 0.42f, false) };   // tall vertical lamps on the bed corners
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
        static Material BeamMat => beamMat ? beamMat : (beamMat = Res.Particle(new Color(1f, 0.92f, 0.78f, 0.08f), Res.SoftDot));

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
                        if (tex != null) { Res.SetMainTex(m, tex, Vector2.one); Res.SetEmission(m, Color.white * 0.06f, tex); }   // a touch of self light: the paint colour never sinks to black at night
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
            float k = braking ? 2.2f : 0.9f;   // dim lamp bar when cruising, bright when braking
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
