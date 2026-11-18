using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.Rendering;
using UnityEngine.UI;
#if HMD_URP
using UnityEngine.Rendering.Universal;
#endif

namespace HMD
{
    /// <summary>
    /// PERF panel for measuring on the phone itself: long-press the FPS readout (about a second) to open or close it.
    /// Each button switches one cost on or off at once (never per camera or per frame), so the player can tap through them
    /// on the S21 and read the frame rate. The top lines show the GPU, graphics API, screen and render size, average and
    /// minimum FPS over the last 5 s, CPU and GPU frame time (FrameTimingManager, when the GPU driver reports it) and the
    /// Android thermal status. Everything starts at full quality, and nothing is saved: a restart is full quality again.
    /// </summary>
    public class PerfPanel : MonoBehaviour
    {
        public static PerfPanel I;
        Canvas canvas;
        Text info;
        readonly List<System.Action> refresh = new List<System.Action>();

        public static void Toggle()
        {
            if (I == null) I = new GameObject("PerfPanel").AddComponent<PerfPanel>();
            I.SetOpen(I.canvas == null || !I.canvas.gameObject.activeSelf);
        }

        void SetOpen(bool open)
        {
            if (canvas == null) Build();
            canvas.gameObject.SetActive(open);
            foreach (var r in refresh) r();
        }

        // ------------------------------------------------------------------ frame rate over the last 5 s
        const int N = 1024;
        readonly float[] dts = new float[N];
        int head, count;
        float infoTimer, thermalTimer;
        int thermal = -1;
        readonly FrameTiming[] timings = new FrameTiming[1];
        double cpuMs, gpuMs;

        void Update()
        {
            float dt = Time.unscaledDeltaTime;
            dts[head] = dt; head = (head + 1) % N; if (count < N) count++;
            FrameTimingManager.CaptureFrameTimings();
            if (FrameTimingManager.GetLatestTimings(1, timings) > 0)
            {
                cpuMs = Mathf.Lerp((float)cpuMs, (float)timings[0].cpuFrameTime, 0.1f);
                gpuMs = Mathf.Lerp((float)gpuMs, (float)timings[0].gpuFrameTime, 0.1f);
            }
            if (canvas == null || !canvas.gameObject.activeSelf) return;
            thermalTimer -= dt;
            if (thermalTimer <= 0f) { thermalTimer = 2f; thermal = ThermalStatus(); }
            infoTimer -= dt;
            if (infoTimer > 0f) return;
            infoTimer = 0.5f;
            float sum = 0f, worst = 0f; int n = 0;
            for (int i = 0; i < count && sum < 5f; i++)
            {
                float d = dts[(head - 1 - i + N) % N];
                sum += d; n++; if (d > worst) worst = d;
            }
            float avg = n / Mathf.Max(0.001f, sum), min = 1f / Mathf.Max(0.0001f, worst);
            int rw = Screen.width, rh = Screen.height;
#if HMD_URP
            if (GraphicsSettings.currentRenderPipeline is UniversalRenderPipelineAsset u) { rw = (int)(rw * u.renderScale); rh = (int)(rh * u.renderScale); }
#endif
            string th = thermal < 0 ? "n/a" : thermal switch { 0 => "none", 1 => "light", 2 => "moderate", 3 => "SEVERE", 4 => "CRITICAL", 5 => "EMERGENCY", _ => "SHUTDOWN" };
            info.text =
                $"{SystemInfo.graphicsDeviceName}  |  {SystemInfo.graphicsDeviceType}\n" +
                $"screen {Screen.width}x{Screen.height}  render {rw}x{rh}  ({Screen.currentResolution.refreshRateRatio.value:0} Hz)\n" +
                $"5 s: avg {avg:0.0} fps   min {min:0.0} fps\n" +
                $"CPU {(cpuMs > 0 ? cpuMs.ToString("0.0") : "-")} ms   GPU {(gpuMs > 0 ? gpuMs.ToString("0.0") : "-")} ms   thermal {th}";
        }

        /// <summary>Android PowerManager.getCurrentThermalStatus (API 29+): 0 none .. 6 shutdown; -1 when not available.</summary>
        static int ThermalStatus()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            try
            {
                using var up = new AndroidJavaClass("com.unity3d.player.UnityPlayer");
                using var act = up.GetStatic<AndroidJavaObject>("currentActivity");
                using var pm = act.Call<AndroidJavaObject>("getSystemService", "power");
                return pm.Call<int>("getCurrentThermalStatus");
            }
            catch { return -1; }
#else
            return -1;
#endif
        }

        // ------------------------------------------------------------------ layout
        void Build()
        {
            canvas = UIKit.MakeCanvas("PerfPanelCanvas", 30);
            canvas.transform.SetParent(transform, false);
            var top = new Vector2(0.5f, 1f);
            var bg = UIKit.Img("Panel", canvas.transform, top, top, new Vector2(0, -64), new Vector2(980, 700), new Color(0.01f, 0.02f, 0.05f, 0.82f), UIKit.RoundedSprite);
            bg.type = Image.Type.Sliced;
            var p = bg.transform;
            UIKit.Label("Title", p, new Vector2(0, 1), new Vector2(0, 1), new Vector2(24, -12), new Vector2(400, 44), "PERF", 34, new Color(0.78f, 0.93f, 1f), TextAnchor.MiddleLeft, Res.TitleFont);
            UIKit.Btn("Close", p, new Vector2(1, 1), new Vector2(1, 1), new Vector2(-14, -10), new Vector2(150, 56), "CLOSE", () => SetOpen(false), new Color(1f, 0.4f, 0.35f), 28);
            info = UIKit.Label("Info", p, new Vector2(0, 1), new Vector2(0, 1), new Vector2(24, -64), new Vector2(930, 150), "", 26, Color.white, TextAnchor.UpperLeft);

            var gx = GfxSetup.I;
            int i = 0;
            void Add(string name, System.Func<string> state, System.Action tap)
            {
                int col = i % 3, row = i / 3; i++;
                var b = UIKit.Btn(name, p, new Vector2(0, 1), new Vector2(0, 1), new Vector2(24 + col * 314, -230 - row * 92), new Vector2(300, 78), name, null, new Color(0.24f, 0.63f, 1f), 28);
                var label = b.GetComponentInChildren<Text>();
                System.Action upd = () => label.text = name + "  " + state();
                b.onClick.AddListener(() => { tap(); upd(); });
                refresh.Add(upd);
            }
            string On(bool v) => v ? "ON" : "off";

#if HMD_URP
            Add("SSAO", () => gx ? On(gx.Ssao) : "n/a", () => { if (gx) gx.SetSsao(!gx.Ssao); });
#endif
            Add("MIRROR", () => PlanarReflection.I ? On(!PlanarReflection.PanelOff) : "n/a",
                () => { if (PlanarReflection.I) PlanarReflection.I.SetPanelOff(!PlanarReflection.PanelOff); });
#if HMD_URP
            Add("PROBE", () => gx ? On(gx.ProbeOn) : "n/a", () => { if (gx) gx.SetProbe(!gx.ProbeOn); });
            Add("BLOOM", () => gx ? On(gx.BloomOn) : "n/a", () => { if (gx) gx.SetBloom(!gx.BloomOn); });
            Add("HDR", () => Urp ? On(Urp.supportsHDR) : "n/a", () => { if (Urp) Urp.supportsHDR = !Urp.supportsHDR; });
            Add("STOP NaN", () => gx ? On(gx.StopNaN) : "n/a", () => { if (gx) gx.SetStopNaN(!gx.StopNaN); });
#endif
            Add("RAIN", () => rainOff == null ? (Object.FindAnyObjectByType<Weather>() ? "ON" : "n/a") : "off", ToggleRain);
            Add("TRAFFIC", () => trafficOff != null ? "off" : TrafficObjects().Count > 0 ? "ON" : "n/a", ToggleTraffic);
            Add("MESH LOD", MeshLodState, ToggleMeshLod);
#if HMD_URP
            Add("SCALE", () => Urp ? (scaleIdx == 0 ? $"auto {Urp.renderScale:0.00}" : Urp.renderScale.ToString("0.0")) : "n/a", CycleScale);
#endif
            Add("FPS CAP", () => Application.targetFrameRate.ToString(), CycleCap);
            float h = 230 + ((i + 2) / 3) * 92 + 10;
            bg.rectTransform.sizeDelta = new Vector2(980, h);
        }

#if HMD_URP
        static UniversalRenderPipelineAsset Urp => GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;
        static readonly float[] Scales = { 0f, 1f, 0.9f, 0.8f, 0.7f };   // 0 = the one picked for this device at start
        int scaleIdx;
        void CycleScale()
        {
            if (!Urp) return;
            scaleIdx = (scaleIdx + 1) % Scales.Length;
            Urp.renderScale = scaleIdx == 0 ? GfxSetup.AutoRenderScale : Scales[scaleIdx];
        }
#endif

        static readonly int[] Caps = { 60, 30, 45 };
        int capIdx;
        void CycleCap()
        {
            capIdx = (capIdx + 1) % Caps.Length;
            Application.targetFrameRate = Caps[capIdx];
        }

        // "full": the finest level everywhere (a threshold of ~0; Unity keeps it just above 0, so the state is kept here)
        float meshLodOn = -1f;
        bool meshLodFull;
        string MeshLodState() => meshLodFull ? "full" : QualitySettings.meshLodThreshold.ToString("0.#");
        void ToggleMeshLod()
        {
            if (!meshLodFull) { meshLodOn = QualitySettings.meshLodThreshold; QualitySettings.meshLodThreshold = 0f; meshLodFull = true; }
            else { QualitySettings.meshLodThreshold = meshLodOn > 0f ? meshLodOn : (GfxSetup.IsMobile ? 4f : 1f); meshLodFull = false; }
        }

        System.Action rainOff;
        void ToggleRain()
        {
            if (rainOff != null) { rainOff(); rainOff = null; return; }
            var w = Object.FindAnyObjectByType<Weather>();
            if (w == null) return;
            var kids = new List<GameObject>();
            foreach (Transform t in w.transform) if (t.gameObject.activeSelf) { kids.Add(t.gameObject); t.gameObject.SetActive(false); }
            w.enabled = false;
            rainOff = () => { if (w) w.enabled = true; foreach (var k in kids) if (k) k.SetActive(true); };
        }

        System.Action trafficOff;
        static List<GameObject> TrafficObjects()
        {
            var l = new List<GameObject>();
            foreach (var t in Object.FindObjectsByType<Traffic>(FindObjectsSortMode.None)) if (t.gameObject.activeSelf) l.Add(t.gameObject);
            var parked = GameObject.Find("Parked");
            if (parked) l.Add(parked);
            return l;
        }
        void ToggleTraffic()
        {
            if (trafficOff != null) { trafficOff(); trafficOff = null; return; }
            var l = TrafficObjects();
            if (l.Count == 0) return;
            foreach (var go in l) go.SetActive(false);
            trafficOff = () => { foreach (var go in l) if (go) go.SetActive(true); };
        }
    }

    /// <summary>Long press (0.8 s) on a UI element; used on the HUD's FPS readout to open the perf panel.</summary>
    public class LongPress : MonoBehaviour, IPointerDownHandler, IPointerUpHandler, IPointerExitHandler
    {
        public System.Action onLongPress;
        float downAt = -1f;
        public void OnPointerDown(PointerEventData e) => downAt = Time.unscaledTime;
        public void OnPointerUp(PointerEventData e) => downAt = -1f;
        public void OnPointerExit(PointerEventData e) => downAt = -1f;
        void Update()
        {
            if (downAt < 0f || Time.unscaledTime - downAt < 0.8f) return;
            downAt = -1f;
            onLongPress?.Invoke();
        }
    }
}
