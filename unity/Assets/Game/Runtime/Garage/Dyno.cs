using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// A real dyno pull: the car sits on the rollers (nose to the room), the camera frames it, the
    /// engine revs up through the rev range with the wheels and rollers spinning, and only THEN the
    /// power and torque graph is drawn on the TV. Tap the TV to zoom in on it.
    /// </summary>
    public class Dyno : MonoBehaviour
    {
        public bool Running { get; private set; }
        public float PeakHp { get; private set; }
        public float PeakNm { get; private set; }
        public System.Action OnDone;

        Workshop shop;
        CarController car;
        CameraRig cam;
        Texture2D graph;
        readonly List<Vector3> samples = new List<Vector3>();   // rpm, hp, Nm

        public void Setup(Workshop w, CameraRig c) { shop = w; cam = c; }

        public void Run(CarController c)
        {
            if (Running) return;
            car = c;
            StartCoroutine(Pull());
        }

        IEnumerator Pull()
        {
            Running = true;
            samples.Clear();
            ShowTv(null, "READY");
            // place the car: driven axle on the rollers
            var spec = car.spec;
            var cfg = CarModelCfg.Load(spec.id);
            float axleZ = cfg != null && cfg.rear != null ? cfg.rear.z * spec.length : -spec.length * 0.3f;
            if (spec.drive == Drive.FWD && cfg != null) axleZ = cfg.front.z * spec.length;
            car.Body.isKinematic = true;
            car.dynoMode = true;
            car.inputLocked = false;
            car.ResetDyno();
            Quaternion rot = shop.DynoRot;
            Vector3 pos = shop.DynoSpot - rot * new Vector3(0, 0, axleZ);
            car.Place(pos + Vector3.up * (car.RestHeight + 0.02f), rot);   // front tyres on the floor, driven tyres on the roller tops
            if (Game.AutoShots) Debug.Log($"[HMD] dyno place: floor={shop.DynoSpot.y:F3} car={car.transform.position.y:F3} rest={car.RestHeight:F3} roller={(shop.Rollers != null ? shop.Rollers[0].position.y : 0):F3} wheelFL={car.wheels[0].transform.position.y:F3} r={car.wheels[0].radius:F3} wheelRL={car.wheels[2].transform.position.y:F3}");

            // camera: low front three-quarter, then it eases round to the side during the pull
            Vector3 side = car.transform.right;
            cam.SetFixed(car.transform.position + car.transform.forward * 4.8f + side * 3.2f + Vector3.up * 1.3f, car.transform.position + Vector3.up * 0.6f);
            yield return new WaitForSeconds(1.6f);

            // short blips, then the full pull
            for (int k = 0; k < 2; k++)
            {
                car.throttle = 0.6f; yield return new WaitForSeconds(0.35f);
                car.throttle = 0f; yield return new WaitForSeconds(0.6f);
            }
            cam.SetFixed(car.transform.position + side * 5.4f + car.transform.forward * -1.0f + Vector3.up * 1.9f, car.transform.position + Vector3.up * 0.35f);   // a bit above, so the tyres on the rollers read clearly
            car.ResetDyno();
            car.throttle = 1f;
            float t = 0;
            while (car.Rpm < spec.rpmRedline * 0.985f && t < 14f)
            {
                t += Time.deltaTime;
                float rpm = car.Rpm;
                if (samples.Count == 0 || rpm - samples[samples.Count - 1].x > 60f)
                {
                    float nm = car.TorqueAt(rpm);
                    samples.Add(new Vector3(rpm, nm * rpm / 7127f, nm));
                }
                SpinRollers();
                cam.Shake(0.15f);
                yield return null;
            }
            car.throttle = 0f;
            float coast = 0;
            while (coast < 2.5f) { coast += Time.deltaTime; SpinRollers(); yield return null; }

            PeakHp = 0; PeakNm = 0;
            foreach (var s in samples) { PeakHp = Mathf.Max(PeakHp, s.y); PeakNm = Mathf.Max(PeakNm, s.z); }
            graph = DrawGraph(samples, spec);
            ShowTv(graph, null);
            // look at the TV from the car
            cam.SetFixed(shop.Tv.position - shop.Tv.forward * 6.5f + Vector3.up * 0.6f + shop.Tv.right * 1.5f, shop.Tv.position);
            yield return new WaitForSeconds(0.5f);
            Running = false;
            OnDone?.Invoke();
        }

        float rollerAngle;
        void SpinRollers()
        {
            if (shop.Rollers == null) return;
            float wheelRadPerSec = car.SpeedKmh / 3.6f / Mathf.Max(0.2f, car.spec.wheelRadius);
            rollerAngle += wheelRadPerSec * car.spec.wheelRadius / 0.19f * Mathf.Rad2Deg * Time.deltaTime;
            foreach (var r in shop.Rollers) r.localRotation = Quaternion.Euler(-rollerAngle, 0, 90);
        }

        public void ZoomTv()
        {
            if (shop == null || shop.Tv == null) return;
            cam.SetFixed(shop.Tv.position - shop.Tv.forward * 3.0f, shop.Tv.position);   // far enough that the whole screen sits between the garage panels
        }

        void ShowTv(Texture2D t, string text)
        {
            var m = shop.TvScreen.sharedMaterial;
            // unlit + HDR tint: the screen glows on its own whatever the room light is, and blooms a little
            if (t != null) { Res.SetMainTex(m, t, Vector2.one); Res.SetColor(m, new Color(1.35f, 1.35f, 1.35f)); }
            else { Res.SetMainTex(m, ReadyTex(), Vector2.one); Res.SetColor(m, new Color(1.25f, 1.25f, 1.25f)); }
        }

        static Texture2D readyTex;
        /// <summary>Standby screen: the empty dyno grid on a blue background (shown before and during the pull).</summary>
        static Texture2D ReadyTex()
        {
            if (readyTex == null) readyTex = DrawGraph(new List<Vector3>(), null);
            return readyTex;
        }

        /// <summary>Draws the dyno sheet: grid, red power curve, blue torque curve, peak markers and numbers.</summary>
        public static Texture2D DrawGraph(List<Vector3> s, CarSpec spec)
        {
            const int W = 1024, H = 576;
            var t = new Texture2D(W, H, TextureFormat.RGBA32, true);
            var px = new Color32[W * H];
            Color32 bg = new Color32(16, 26, 46, 255);
            for (int i = 0; i < px.Length; i++) px[i] = bg;
            int left = 90, right = W - 70, bottom = 70, top = H - 60;
            float maxRpm = spec != null ? spec.rpmRedline : 8000f, maxHp = 0, maxNm = 0;
            foreach (var v in s) { maxHp = Mathf.Max(maxHp, v.y); maxNm = Mathf.Max(maxNm, v.z); }
            float yMax = Mathf.Max(100f, Mathf.Ceil(Mathf.Max(maxHp, maxNm) * 1.15f / 100f) * 100f);
            void P(int x, int y, Color32 c) { if (x >= 0 && y >= 0 && x < W && y < H) px[y * W + x] = c; }
            void Line(float x0, float y0, float x1, float y1, Color32 c, int th)
            {
                int n = Mathf.CeilToInt(Mathf.Max(Mathf.Abs(x1 - x0), Mathf.Abs(y1 - y0))) + 1;
                for (int i = 0; i <= n; i++)
                {
                    float f = i / (float)n;
                    int x = Mathf.RoundToInt(Mathf.Lerp(x0, x1, f)), y = Mathf.RoundToInt(Mathf.Lerp(y0, y1, f));
                    for (int a = -th; a <= th; a++) for (int b = -th; b <= th; b++) P(x + a, y + b, c);
                }
            }
            Color32 grid = new Color32(52, 72, 104, 255);
            for (int k = 0; k <= 10; k++)
            {
                float x = Mathf.Lerp(left, right, k / 10f); Line(x, bottom, x, top, grid, 0);
                float y = Mathf.Lerp(bottom, top, k / 10f); Line(left, y, right, y, grid, 0);
            }
            Line(left, bottom, right, bottom, new Color32(200, 210, 228, 255), 2);
            Line(left, bottom, left, top, new Color32(200, 210, 228, 255), 2);
            float X(float rpm) => Mathf.Lerp(left, right, rpm / maxRpm);
            float Y(float v) => Mathf.Lerp(bottom, top, v / yMax);
            for (int i = 1; i < s.Count; i++)
            {
                Line(X(s[i - 1].x), Y(s[i - 1].z), X(s[i].x), Y(s[i].z), new Color32(60, 170, 255, 255), 4);
                Line(X(s[i - 1].x), Y(s[i - 1].y), X(s[i].x), Y(s[i].y), new Color32(255, 70, 55, 255), 4);
            }
            // peak markers: a white ring on each curve's highest point, with a dashed drop line to the rpm axis
            void Peak(int comp, Color32 c)
            {
                if (s.Count == 0) return;
                int best = 0;
                for (int i = 1; i < s.Count; i++) if (s[i][comp] > s[best][comp]) best = i;
                float px0 = X(s[best].x), py0 = Y(s[best][comp]);
                for (float yy = bottom; yy < py0 - 8; yy += 12) Line(px0, yy, px0, Mathf.Min(yy + 6, py0 - 8), c, 0);
                for (int a = 0; a < 64; a++)
                {
                    float an = a / 64f * Mathf.PI * 2;
                    for (int r = 9; r <= 11; r++)
                        P(Mathf.RoundToInt(px0 + Mathf.Cos(an) * r), Mathf.RoundToInt(py0 + Mathf.Sin(an) * r), new Color32(255, 255, 255, 255));
                }
            }
            Peak(1, new Color32(255, 120, 100, 255));
            Peak(2, new Color32(120, 190, 255, 255));
            // legend swatches top left: red = power, blue = torque
            for (int y = top + 18; y < top + 30; y++) for (int x = left + 10; x < left + 60; x++) P(x, y, new Color32(255, 70, 55, 255));
            for (int y = top + 18; y < top + 30; y++) for (int x = left + 80; x < left + 130; x++) P(x, y, new Color32(60, 170, 255, 255));
            t.SetPixels32(px);
            t.Apply(true);
            return t;
        }

        public IReadOnlyList<Vector3> Samples => samples;
    }
}
