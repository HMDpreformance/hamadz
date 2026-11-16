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
            car.transform.SetPositionAndRotation(pos + Vector3.up * 0.02f, rot);

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
            cam.SetFixed(car.transform.position + side * 5.2f + car.transform.forward * -1.0f + Vector3.up * 1.0f, car.transform.position + Vector3.up * 0.5f);
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
            cam.SetFixed(shop.Tv.position - shop.Tv.forward * 1.75f, shop.Tv.position);
        }

        void ShowTv(Texture2D t, string text)
        {
            var m = shop.TvScreen.sharedMaterial;
            if (t != null) { Res.SetMainTex(m, t, Vector2.one); Res.SetColor(m, Color.white); }
            else { Res.SetMainTex(m, Texture2D.blackTexture, Vector2.one); Res.SetColor(m, new Color(0.03f, 0.05f, 0.08f)); }
        }

        /// <summary>Draws the dyno sheet: grid, red power curve, blue torque curve, peak markers and numbers.</summary>
        public static Texture2D DrawGraph(List<Vector3> s, CarSpec spec)
        {
            const int W = 1024, H = 576;
            var t = new Texture2D(W, H, TextureFormat.RGBA32, true);
            var px = new Color32[W * H];
            Color32 bg = new Color32(8, 12, 20, 255);
            for (int i = 0; i < px.Length; i++) px[i] = bg;
            int left = 90, right = W - 70, bottom = 70, top = H - 60;
            float maxRpm = spec.rpmRedline, maxHp = 0, maxNm = 0;
            foreach (var v in s) { maxHp = Mathf.Max(maxHp, v.y); maxNm = Mathf.Max(maxNm, v.z); }
            float yMax = Mathf.Ceil(Mathf.Max(maxHp, maxNm) * 1.15f / 100f) * 100f;
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
            Color32 grid = new Color32(40, 52, 70, 255);
            for (int k = 0; k <= 10; k++)
            {
                float x = Mathf.Lerp(left, right, k / 10f); Line(x, bottom, x, top, grid, 0);
                float y = Mathf.Lerp(bottom, top, k / 10f); Line(left, y, right, y, grid, 0);
            }
            Line(left, bottom, right, bottom, new Color32(160, 170, 190, 255), 1);
            Line(left, bottom, left, top, new Color32(160, 170, 190, 255), 1);
            float X(float rpm) => Mathf.Lerp(left, right, rpm / maxRpm);
            float Y(float v) => Mathf.Lerp(bottom, top, v / yMax);
            for (int i = 1; i < s.Count; i++)
            {
                Line(X(s[i - 1].x), Y(s[i - 1].z), X(s[i].x), Y(s[i].z), new Color32(40, 150, 255, 255), 2);
                Line(X(s[i - 1].x), Y(s[i - 1].y), X(s[i].x), Y(s[i].y), new Color32(255, 50, 40, 255), 2);
            }
            t.SetPixels32(px);
            t.Apply(true);
            return t;
        }

        public IReadOnlyList<Vector3> Samples => samples;
    }
}
