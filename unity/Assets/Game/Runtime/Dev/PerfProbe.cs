using System.Collections;
using System.Collections.Generic;
using System.Text;
using Unity.Profiling;
using UnityEngine;
#if HMD_URP
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
#endif

namespace HMD
{
    /// <summary>
    /// Frame-cost probe (dev only). -hmdperf on the command line, or PerfProbe.Run() from the Editor in Play mode.
    /// Parks the car at fixed spots (Business Bay, Downtown, the E11, Marina, the LSX garage), frames the chase view,
    /// and for each spot records CPU main / render thread and GPU frame time, draw calls, SetPass calls, batches,
    /// triangles and GC allocation per frame; then switches each suspect off on its own (planar mirror, paint probe,
    /// lamp lights, other lights, rain, halos, post, HDR, building models, palms, ...) and logs the change.
    /// Also lists the visible triangles per group. Results: "[HMD] perf" log lines and perf.txt (Editor: Temp/).
    /// </summary>
    public class PerfProbe : MonoBehaviour
    {
        public static bool Wanted => System.Environment.CommandLine.Contains("-hmdperf");
        public static string Only;      // run just this spot (Editor convenience)
        public static string OnlyToggles;   // comma list of toggle names (empty = all)
        public static bool Shots = true, AB = true, Drive = true;
        public static int TargetPixels;   // > 0: render scale set so the frame has this many pixels (equal GPU load between runs)
        public static string Tag = "before";
        public static bool Busy;

        public static void Run()
        {
            if (Game.I == null || Busy) return;
            Game.I.gameObject.AddComponent<PerfProbe>();
        }

        ProfilerRecorder dc, sp, bt, tri, gc, mainT;
        readonly StringBuilder log = new StringBuilder();
        Game g;

        void Log(string s) { Debug.Log("[HMD] perf " + s); log.AppendLine(s); }

        IEnumerator Start()
        {
            Busy = true;
            g = Game.I;
            while (g.state != Game.State.Drive && g.state != Game.State.Intro) yield return null;
            while (g.state == Game.State.Intro) yield return null;
            dc = ProfilerRecorder.StartNew(ProfilerCategory.Render, "Draw Calls Count");
            sp = ProfilerRecorder.StartNew(ProfilerCategory.Render, "SetPass Calls Count");
            bt = ProfilerRecorder.StartNew(ProfilerCategory.Render, "Batches Count");
            tri = ProfilerRecorder.StartNew(ProfilerCategory.Render, "Triangles Count");
            gc = ProfilerRecorder.StartNew(ProfilerCategory.Memory, "GC Allocated In Frame");
            mainT = ProfilerRecorder.StartNew(ProfilerCategory.Internal, "Main Thread", 15);
            int oldFps = Application.targetFrameRate;
            Application.targetFrameRate = -1; QualitySettings.vSyncCount = 0;   // uncapped while measuring
            g.car.inputLocked = true;
            Log($"=== {Tag}  mobile={GfxSetup.IsMobile} screen={Screen.width}x{Screen.height} {SystemInfo.graphicsDeviceName} {SystemInfo.graphicsDeviceType}");
#if HMD_URP
            float oldScale = -1f;
            if (TargetPixels > 0 && GraphicsSettings.currentRenderPipeline is UniversalRenderPipelineAsset urpT)
            { oldScale = urpT.renderScale; urpT.renderScale = Mathf.Clamp(Mathf.Sqrt(TargetPixels / (float)(Screen.width * Screen.height)), 0.1f, 2f); }
            if (GraphicsSettings.currentRenderPipeline is UniversalRenderPipelineAsset urp0)
                Log($"meshLodThreshold={QualitySettings.meshLodThreshold} lodBias={QualitySettings.lodBias} pixels={(int)(Screen.width * Screen.height * urp0.renderScale * urp0.renderScale)}");
            if (GraphicsSettings.currentRenderPipeline is UniversalRenderPipelineAsset urp1)
                Log($"urp renderScale={urp1.renderScale:F2} hdr={urp1.supportsHDR} msaa={urp1.msaaSampleCount} srpBatcher={GraphicsSettings.useScriptableRenderPipelineBatching} shadowDist={urp1.shadowDistance}");
#endif
            foreach (var spot in Spots())
            {
                if (!string.IsNullOrEmpty(Only) && spot.name != Only) continue;
                Park(spot.p, spot.dir);
                yield return Settle(90);
                var b = new Sample(); yield return Measure(b, 180);
                Log($"--- {spot.name} at ({spot.p.x:F0},{spot.p.y:F0},{spot.p.z:F0})");
                Log("base            " + b);
                if (Drive)
                {
                    // the same view moving at 100 km/h along the road (the paint probe and culling work as when driving)
                    var dv = new Sample(); yield return Measure(dv, 150, spot.p, spot.dir);
                    Log("driving 100     " + dv);
                    Park(spot.p, spot.dir); yield return Settle(30);
                }
                Census();
                if (Shots) yield return Shot(spot.name);
                if (!AB) continue;
                foreach (var t in Toggles())
                {
                    if (!string.IsNullOrEmpty(OnlyToggles) && System.Array.IndexOf(OnlyToggles.Split(','), t.name) < 0) continue;
                    var undo = t.off();
                    if (undo == null) { Log($"{t.name,-15} (n/a)"); continue; }
                    yield return Settle(20);
                    var s = new Sample(); yield return Measure(s, 120);
                    undo();
                    yield return Settle(10);
                    Log($"{t.name,-15} {s}   d: cpu {s.cpu - b.cpu:+0.00;-0.00} gpu {s.gpu - b.gpu:+0.00;-0.00} ms, dc {s.dc - b.dc:+0;-0}, tris {(s.tri - b.tri) / 1000f:+0;-0}k");
                }
            }
            Application.targetFrameRate = oldFps;
            g.car.inputLocked = false;
#if HMD_URP
            if (oldScale > 0f && GraphicsSettings.currentRenderPipeline is UniversalRenderPipelineAsset urpR) urpR.renderScale = oldScale;
#endif
            string path = Application.isEditor ? System.IO.Path.Combine(Application.dataPath, "../Temp/perf_" + Tag + ".txt")
                                               : System.IO.Path.Combine(Application.dataPath, "../perf_" + Tag + ".txt");
            System.IO.File.WriteAllText(path, log.ToString());
            Debug.Log("[HMD] perf done -> " + System.IO.Path.GetFullPath(path));
            dc.Dispose(); sp.Dispose(); bt.Dispose(); tri.Dispose(); gc.Dispose(); mainT.Dispose();
            Busy = false;
            Destroy(this);
        }

        // ------------------------------------------------------------------ spots
        struct Spot { public string name; public Vector3 p, dir; }

        IEnumerable<Spot> Spots()
        {
            var nc = g.newCity;
            if (nc == null) yield break;
            var want = new (string name, string district, string cls)[]
            { ("business_bay", "Business Bay", "main"), ("downtown", "Downtown Dubai", "main"), ("e11", "", "highway"), ("marina", "Dubai Marina", "main") };
            foreach (var w in want)
            {
                Vector3 centre = Vector3.zero; bool found = w.district == "";
                foreach (var d in nc.districts) if (d.name == w.district) { centre = d.pos; found = true; }
                if (!found) continue;
                NewCity.Road best = null; int bi = 0; float bd = float.MaxValue;
                foreach (var rd in nc.roads)
                {
                    if (rd.cls != w.cls || rd.pts.Count < 6) continue;
                    if (w.cls == "highway" && rd.name != "E11") continue;
                    for (int i = 3; i < rd.pts.Count - 3; i++)
                    {
                        float dd = w.district == "" ? Mathf.Abs(rd.pts[i].x - 2000f) : new Vector2(rd.pts[i].x - centre.x, rd.pts[i].z - centre.z).sqrMagnitude;
                        if (dd < bd) { bd = dd; best = rd; bi = i; }
                    }
                }
                if (best == null) continue;
                var dir = best.pts[bi + 1] - best.pts[bi - 1]; dir.y = 0; dir.Normalize();
                var side = Vector3.Cross(Vector3.up, dir);
                yield return new Spot { name = w.name, p = best.pts[bi] + side * Mathf.Max(1.8f, best.width * 0.25f), dir = dir };
            }
            // LSX: on the road in front of the door, looking along it
            if (nc.NearestLane(nc.Garage + Vector3.back * 20f, Vector3.right, out var lp, out var lr))
                yield return new Spot { name = "lsx", p = lp, dir = lr * Vector3.forward };
        }

        void Park(Vector3 p, Vector3 dir)
        {
            var car = g.car;
            car.Teleport(NewCity.Surface(p) + Vector3.up * 0.6f, Quaternion.LookRotation(dir));
            car.Body.linearVelocity = Vector3.zero; car.Body.angularVelocity = Vector3.zero;
            var s = NewCity.Surface(p);
            g.rig.SetFixed(s - dir * 7.5f + Vector3.up * 2.3f, s + dir * 30f + Vector3.up * 1.2f, false);
        }

        static IEnumerator Settle(int frames) { for (int i = 0; i < frames; i++) yield return null; }

        // ------------------------------------------------------------------ measuring
        class Sample
        {
            public float cpu, render, gpu, frame, dc, sp, bt, tri, gc; public int n;
            public override string ToString() =>
                $"frame {frame,6:F2} ms (cpu main {cpu,5:F2}, render {render,5:F2}, gpu {gpu,5:F2})  dc {dc,5:F0} setpass {sp,4:F0} batches {bt,5:F0} tris {tri / 1e6f,5:F2}M  gc {gc / 1024f,5:F1} KB/f";
        }

        readonly FrameTiming[] ft = new FrameTiming[1];

        IEnumerator Measure(Sample s, int frames, Vector3? driveFrom = null, Vector3 dir = default)
        {
            float t = 0f;
            for (int i = 0; i < frames; i++)
            {
                if (driveFrom.HasValue)
                {
                    t += Time.deltaTime;
                    var p = driveFrom.Value + dir * (27.8f * t);
                    var sp0 = NewCity.Surface(p);
                    g.car.Teleport(sp0 + Vector3.up * 0.6f, Quaternion.LookRotation(dir));
                    g.car.Body.linearVelocity = Vector3.zero;
                    g.rig.SetFixed(sp0 - dir * 7.5f + Vector3.up * 2.3f, sp0 + dir * 30f + Vector3.up * 1.2f, false);
                }
                yield return null;
                FrameTimingManager.CaptureFrameTimings();
                if (FrameTimingManager.GetLatestTimings(1, ft) > 0)
                {
                    s.cpu += (float)ft[0].cpuMainThreadFrameTime; s.render += (float)ft[0].cpuRenderThreadFrameTime; s.gpu += (float)ft[0].gpuFrameTime;
                }
                s.frame += Time.unscaledDeltaTime * 1000f;
                s.dc += dc.LastValue; s.sp += sp.LastValue; s.bt += bt.LastValue; s.tri += tri.LastValue; s.gc += gc.LastValue;
                s.n++;
            }
            float k = 1f / Mathf.Max(1, s.n);
            s.cpu *= k; s.render *= k; s.gpu *= k; s.frame *= k; s.dc *= k; s.sp *= k; s.bt *= k; s.tri *= k; s.gc *= k;
        }

        /// <summary>Visible renderers and triangles per group (a renderer counts when any camera saw it last frame).</summary>
        void Census()
        {
            var groups = new SortedDictionary<string, (int n, long tris, HashSet<Material> mats)>();
            int lights = 0, shadowLights = 0;
            foreach (var l in FindObjectsByType<Light>(FindObjectsSortMode.None))
                if (l.isActiveAndEnabled) { lights++; if (l.shadows != LightShadows.None) shadowLights++; }
            long total = 0; int visible = 0, all = 0;
            foreach (var r in FindObjectsByType<MeshRenderer>(FindObjectsSortMode.None))
            {
                if (!r.enabled || !r.gameObject.activeInHierarchy) continue;
                all++;
                if (!r.isVisible) continue;
                var mf = r.GetComponent<MeshFilter>(); if (mf == null || mf.sharedMesh == null) continue;
                visible++;
                long t = 0; var m = mf.sharedMesh;
                for (int i = 0; i < m.subMeshCount; i++) t += m.GetIndexCount(i) / 3;
                string grp = Group(r.transform);
                groups.TryGetValue(grp, out var e);
                e.mats ??= new HashSet<Material>();
                foreach (var mt in r.sharedMaterials) if (mt) e.mats.Add(mt);
                groups[grp] = (e.n + 1, e.tris + t, e.mats);
                total += t;
            }
            Log($"census: {all} active mesh renderers, {visible} visible, {total / 1e6f:F2}M visible tris (mesh sum), {lights} lights on ({shadowLights} with shadows)");
            foreach (var kv in groups)
                if (kv.Value.tris > 20000 || kv.Value.n > 40)
                    Log($"   {kv.Key,-24} {kv.Value.n,5} renderers {kv.Value.tris / 1000f,8:F0}k tris {kv.Value.mats.Count,4} mats");
        }

        string Group(Transform t)
        {
            if (g.car && t.IsChildOf(g.car.transform)) return "player car";
            var p = t; string under = null;
            while (p.parent != null) { under = p.name; p = p.parent; }
            string root = p.name;
            if (under != null)
            {
                int u = under.IndexOf('_'); string head = u > 0 ? under.Substring(0, u) : under;
                return root + "/" + head;
            }
            return root;
        }

        IEnumerator Shot(string name)
        {
            yield return new WaitForEndOfFrame();
            var tex = ScreenCapture.CaptureScreenshotAsTexture();
            string dir = Application.isEditor ? System.IO.Path.Combine(Application.dataPath, "../Temp/perfshots") : System.IO.Path.Combine(Application.dataPath, "../Shots");
            System.IO.Directory.CreateDirectory(dir);
            System.IO.File.WriteAllBytes(System.IO.Path.Combine(dir, $"perf_{Tag}_{name}.jpg"), tex.EncodeToJPG(90));
            Destroy(tex);
        }

        // ------------------------------------------------------------------ the suspects, one at a time
        struct Toggle { public string name; public System.Func<System.Action> off; }

        IEnumerable<Toggle> Toggles()
        {
            yield return new Toggle { name = "-planar", off = () => GoOff(PlanarReflection.I ? PlanarReflection.I.gameObject : null) };
            yield return new Toggle { name = "-probe", off = () => GoOff(GameObject.Find("CamProbe")) };
            yield return new Toggle { name = "-lamplights", off = LampsOff };
            yield return new Toggle { name = "-otherlights", off = OtherLightsOff };
            yield return new Toggle { name = "-rain", off = RainOff };
            yield return new Toggle { name = "-halos", off = () => GoOff(GameObject.Find("LampHalos")) };
            yield return new Toggle { name = "-buildings", off = () => GoOff(GameObject.Find("BuildingModels")) };
            yield return new Toggle { name = "-palms", off = () => GoOff(GameObject.Find("PalmModels")) };
            yield return new Toggle { name = "-dresscells", off = () => ByPrefix("Dress_") };
            yield return new Toggle { name = "-propcells", off = () => ByPrefix("Props_") };
            yield return new Toggle { name = "-plots", off = () => ByPrefix("Plots_") };
            yield return new Toggle { name = "-playercar", off = CarOff };
            yield return new Toggle { name = "-hud", off = () => GoOff(g.hud ? g.hud.gameObject : null) };
#if HMD_URP
            yield return new Toggle { name = "-post", off = () => { var d = g.rig.Cam.GetUniversalAdditionalCameraData(); d.renderPostProcessing = false; return () => d.renderPostProcessing = true; } };
            yield return new Toggle { name = "-hdr", off = () => { var u = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset; if (!u) return null; u.supportsHDR = false; return () => u.supportsHDR = true; } };
            yield return new Toggle { name = "renderscale.5", off = () => { var u = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset; if (!u) return null; float o = u.renderScale; u.renderScale = 0.5f; return () => u.renderScale = o; } };
#endif
            yield return new Toggle { name = "farclip600", off = () => { var c = g.rig.Cam; float o = c.farClipPlane; c.farClipPlane = 600f; return () => c.farClipPlane = o; } };
#if HMD_URP
            yield return new Toggle { name = "-ssao", off = () => { var gx = GfxSetup.I; if (gx == null || !gx.Ssao) return null; gx.SetSsao(false); return () => gx.SetSsao(true); } };   // main camera's renderer 1 -> 0, never the feature
#endif
        }

#if HMD_URP
        public static ScriptableRendererFeature Feature(string name)
        {
            var u = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;
            if (u == null) return null;
            foreach (var d in u.rendererDataList)
                if (d != null) foreach (var f in d.rendererFeatures) if (f != null && f.name == name) return f;
            return null;
        }
#endif

        static System.Action GoOff(GameObject go)
        {
            if (go == null || !go.activeSelf) return null;
            go.SetActive(false);
            return () => go.SetActive(true);
        }

        System.Action ByPrefix(string prefix)
        {
            var list = new List<GameObject>();
            foreach (var t in FindObjectsByType<Transform>(FindObjectsSortMode.None))
                if (t.name.StartsWith(prefix) && t.gameObject.activeSelf) list.Add(t.gameObject);
            if (list.Count == 0) return null;
            foreach (var go in list) go.SetActive(false);
            return () => { foreach (var go in list) if (go) go.SetActive(true); };
        }

        static System.Action LampsOff()
        {
            var ll = FindAnyObjectByType<LampLights>();
            if (ll == null) return null;
            var on = new List<Light>();
            foreach (var l in ll.GetComponentsInChildren<Light>()) if (l.enabled) { on.Add(l); l.enabled = false; }
            ll.enabled = false;
            return () => { ll.enabled = true; foreach (var l in on) l.enabled = true; };
        }

        static System.Action OtherLightsOff()
        {
            var ll = FindAnyObjectByType<LampLights>();
            var on = new List<Light>();
            foreach (var l in FindObjectsByType<Light>(FindObjectsSortMode.None))
            {
                if (!l.enabled || l.type == LightType.Directional) continue;
                if (ll && l.transform.IsChildOf(ll.transform)) continue;
                on.Add(l); l.enabled = false;
            }
            if (on.Count == 0) return null;
            return () => { foreach (var l in on) if (l) l.enabled = true; };
        }

        static System.Action RainOff()
        {
            var w = FindAnyObjectByType<Weather>();
            if (w == null) return null;
            var kids = new List<GameObject>();
            foreach (Transform t in w.transform) if (t.gameObject.activeSelf) { kids.Add(t.gameObject); t.gameObject.SetActive(false); }
            w.enabled = false;
            return () => { w.enabled = true; foreach (var k in kids) k.SetActive(true); };
        }

        System.Action CarOff()
        {
            var rs = new List<Renderer>();
            foreach (var r in g.car.GetComponentsInChildren<Renderer>()) if (r.enabled) { rs.Add(r); r.enabled = false; }
            return () => { foreach (var r in rs) r.enabled = true; };
        }
    }
}
