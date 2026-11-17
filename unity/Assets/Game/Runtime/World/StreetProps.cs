using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace HMD
{
    /// <summary>
    /// Street furniture on the sidewalks: traffic lights at every crossing, bus stops, benches,
    /// kiosks and big lit billboards. The models are generated GLBs in Resources/Imported/Props
    /// (from unity_assets/props). Every prop has a LODGroup that hides it when far, and the
    /// materials are shared and GPU-instanced, so hundreds of them stay cheap on a phone.
    ///
    /// Model fronts (Unity space, after glTFast import), measured in the GLB viewer:
    ///   traffic_light: lamps face -X, the arm runs to +Z, the pole stands 0.27 heights to -Z of the centre
    ///   bus_stop: open side +Z      bench_set: seat faces +Z      kiosk: counter/awning -X
    ///   billboard: panel faces +X and -X
    /// </summary>
    public class StreetProps : MonoBehaviour
    {
        readonly Dictionary<string, Material> mats = new Dictionary<string, Material>();
        readonly Dictionary<string, GameObject> prefabs = new Dictionary<string, GameObject>();
        Material[] ads;
        Material boardBack;

        const float CullDistance = 170f;     // props vanish beyond this (billboards: 3x)

        public void Build(City city)
        {
            float h = City.Block * 0.5f;
            var adList = new List<Material>();
            foreach (var n in new[] { "ad_voltrush", "ad_gripmax", "ad_aurum", "ad_lsx" })
            {
                var t = Res.Tex("Gen/" + n);
                if (t == null) continue;
                var m = Res.Mat(Color.black, 0.3f, 0f);
                Res.SetEmission(m, Color.white * 1.6f, t);
                m.enableInstancing = true;
                adList.Add(m);
            }
            ads = adList.ToArray();
            boardBack = Res.Mat(new Color(0.05f, 0.05f, 0.06f), 0.3f, 0.2f);

            for (int i = 0; i < City.N; i++)
                for (int j = 0; j < City.N; j++)
                {
                    Vector3 c = City.BlockCenter(i, j);
                    bool garage = new Vector2Int(i, j) == City.GarageBlock;
                    int hash = i * 7 + j * 13;

                    // traffic lights: one on each block corner. Each hangs over the lanes of the cars that
                    // come towards it (right-hand traffic) on the far side of the crossing.
                    float e = h - 0.9f;
                    Place("traffic_light", c + new Vector3(-e, 0, e), 0, 7f, new Vector3(0, 0, -0.27f), 0.5f);
                    Place("traffic_light", c + new Vector3(e, 0, -e), 180, 7f, new Vector3(0, 0, -0.27f), 0.5f);
                    Place("traffic_light", c + new Vector3(-e, 0, -e), 270, 7f, new Vector3(0, 0, -0.27f), 0.5f);
                    Place("traffic_light", c + new Vector3(e, 0, e), 90, 7f, new Vector3(0, 0, -0.27f), 0.5f);

                    // bus stop on the north side of every second block, open side to the road
                    if ((i + j) % 2 == 0)
                        Place("bus_stop", c + new Vector3(-h * 0.35f, 0, h - 2.3f), 0, 2.7f, Vector3.zero, 0, new Vector3(4.2f, 2.6f, 1.6f));
                    // benches on the east and west sides
                    Place("bench_set", c + new Vector3(h - 2.6f, 0, -h * 0.3f), 90, 1.05f, Vector3.zero, 0, new Vector3(2f, 1f, 0.8f));
                    Place("bench_set", c + new Vector3(-h + 2.6f, 0, h * 0.3f), 270, 1.05f, Vector3.zero, 0, new Vector3(2f, 1f, 0.8f));
                    // a coffee kiosk on some blocks (south side, counter to the road). Not at the garage door.
                    if (hash % 4 == 1 && !garage)
                        Place("kiosk", c + new Vector3(h * 0.4f, 0, -h + 2.7f), 270, 3.1f, Vector3.zero, 0, new Vector3(2.6f, 3f, 3f));
                    // a big lit billboard on some blocks, the panel across the road so drivers see it
                    if (hash % 3 == 0 && ads.Length > 0)
                    {
                        bool ew = hash % 2 == 0;
                        Vector3 p = ew ? c + new Vector3(h * 0.25f, 0, h - 0.5f) : c + new Vector3(h - 0.5f, 0, -h * 0.25f);
                        Billboard(p, ew ? 0 : 90, ads[(hash / 3) % ads.Length], ads[(hash / 3 + 1) % ads.Length]);
                    }
                }
        }

        /// <summary>Puts a model on its spot: scaled to the height, standing on the sidewalk, turned by yaw.
        /// anchor: where the foot is, from the centre of the model's box, in model heights (model space).</summary>
        Transform Place(string name, Vector3 pos, float yaw, float height, Vector3 anchor, float poleCollider = 0, Vector3 boxCollider = default, float cullMul = 1f)
        {
            if (!prefabs.TryGetValue(name, out var prefab)) { prefab = Res.Load<GameObject>("Props/" + name); prefabs[name] = prefab; }
            if (prefab == null) return null;
            var holder = new GameObject(name).transform;
            holder.SetParent(transform, false);
            holder.position = new Vector3(pos.x, 0.18f, pos.z);   // top of the sidewalk slab
            var go = Instantiate(prefab, holder);
            go.transform.localPosition = Vector3.zero; go.transform.localRotation = Quaternion.identity; go.transform.localScale = Vector3.one;
            foreach (var col in go.GetComponentsInChildren<Collider>()) Destroy(col);
            var rs = go.GetComponentsInChildren<Renderer>();
            if (rs.Length == 0) return holder;
            if (!mats.TryGetValue(name, out var mat))
            {
                Texture tex = null;
                var src = rs[0].sharedMaterial;
                if (src != null)
                    foreach (var prop in new[] { "baseColorTexture", "_BaseMap", "_MainTex" })
                        if (src.HasProperty(prop) && src.GetTexture(prop) != null) { tex = src.GetTexture(prop); break; }
                mat = Res.Mat(Color.white, 0.5f, 0.15f);
                if (tex != null)
                {
                    Res.SetMainTex(mat, tex, Vector2.one);
                    // a little self light from the model's own picture: signal lamps and ad panels read at night
                    Res.SetEmission(mat, Color.white * (name == "traffic_light" ? 0.9f : 0.3f), tex);
                }
                mat.enableInstancing = true;
                mats[name] = mat;
            }
            Bounds b = rs[0].bounds;
            foreach (var r in rs) { r.sharedMaterial = mat; r.shadowCastingMode = ShadowCastingMode.Off; b.Encapsulate(r.bounds); }
            float k = height / Mathf.Max(0.01f, b.size.y);
            go.transform.localScale = Vector3.one * k;
            Vector3 centre = holder.InverseTransformPoint(b.center);
            float bottom = (b.center.y - b.extents.y - holder.position.y) * k;
            go.transform.localPosition = new Vector3(-(centre.x * k + anchor.x * height), -bottom, -(centre.z * k + anchor.z * height));
            holder.rotation = Quaternion.Euler(0, yaw, 0);

            if (poleCollider > 0)
            {
                var bc = holder.gameObject.AddComponent<BoxCollider>();
                bc.size = new Vector3(poleCollider, height, poleCollider); bc.center = new Vector3(0, height * 0.5f, 0);
            }
            else if (boxCollider != default)
            {
                var bc = holder.gameObject.AddComponent<BoxCollider>();
                bc.size = boxCollider; bc.center = new Vector3(0, boxCollider.y * 0.5f, 0);
            }
            Cull(holder.gameObject, rs, Mathf.Max(b.size.x, b.size.y, b.size.z) * k, CullDistance * cullMul);
            return holder;
        }

        /// <summary>One LOD level that switches the renderers off beyond a distance.</summary>
        static void Cull(GameObject go, Renderer[] rs, float size, float distance)
        {
            var lg = go.AddComponent<LODGroup>();
            // screen height of the object at the cull distance, for a 60 degree camera
            float frac = Mathf.Clamp(size / (distance * 1.155f), 0.004f, 0.6f);
            lg.SetLODs(new[] { new LOD(frac, rs) });
            lg.RecalculateBounds();
        }

        /// <summary>A unipole billboard: the generated steel structure plus two lit ad faces.</summary>
        void Billboard(Vector3 pos, float yaw, Material adA, Material adB)
        {
            const float H = 11f;   // the panel is then about 10 m wide: it hangs over the near lanes and just clears the facades
            var holder = Place("billboard", pos, yaw, H, Vector3.zero, 0.9f, default, 3f);
            if (holder == null) return;
            // the model's panel: about 0.95 H wide (along its Z), upper 42% of the height, faces +X and -X
            float w = H * 0.9f, ph = H * 0.4f, y = H * 0.76f, off = H * 0.115f;
            var lg = holder.GetComponent<LODGroup>();
            var lods = lg.GetLODs();
            var list = new List<Renderer>(lods[0].renderers);
            for (int s = -1; s <= 1; s += 2)
            {
                var q = GameObject.CreatePrimitive(PrimitiveType.Quad);
                Destroy(q.GetComponent<Collider>());
                q.name = "Ad";
                q.transform.SetParent(holder, false);
                q.transform.localPosition = new Vector3(s * off, y, 0);
                // a quad shows its picture towards its own -Z: turn that to +X (s = 1) or -X (s = -1)
                q.transform.localRotation = Quaternion.Euler(0, s > 0 ? -90 : 90, 0);
                q.transform.localScale = new Vector3(w, ph, 1);
                var r = q.GetComponent<Renderer>();
                r.sharedMaterial = s > 0 ? adA : adB;
                r.shadowCastingMode = ShadowCastingMode.Off;
                list.Add(r);
            }
            lods[0].renderers = list.ToArray();
            lg.SetLODs(lods);
            lg.RecalculateBounds();
            // light spilling from the board onto the street
            var lgGo = new GameObject("AdLight");
            lgGo.transform.SetParent(holder, false);
            lgGo.transform.localPosition = new Vector3(0, y - 2f, 0);
            var li = lgGo.AddComponent<Light>();
            li.type = LightType.Point; li.range = 26f; li.intensity = 6f;
            li.color = new Color(0.75f, 0.8f, 1f); li.shadows = LightShadows.None;
            lgGo.AddComponent<DistanceLight>().Setup(li, 120f);
        }
    }

    /// <summary>Switches a light off when the camera is far (cheap on a phone).</summary>
    public class DistanceLight : MonoBehaviour
    {
        Light li; float max; Transform cam; float next;
        public void Setup(Light l, float maxDistance) { li = l; max = maxDistance; }
        void Update()
        {
            if (Time.time < next) return;
            next = Time.time + 0.4f + (GetInstanceID() & 7) * 0.03f;
            if (cam == null) { var c = Camera.main; if (c == null) return; cam = c.transform; }
            li.enabled = (cam.position - transform.position).sqrMagnitude < max * max;
        }
    }
}
