using UnityEngine;
using UnityEngine.UI;

namespace HMD
{
    /// <summary>
    /// Driving HUD (layout from the MC3 reference shots, kept from the Godot game): FPS counter in the
    /// top middle, GARAGE button, round minimap with the LSX wrench marker (and an arrow on the rim when
    /// the garage is off the map; tap it for the full-screen city map), old-school analog speedometer and rev counter
    /// with needles, a round gear badge, nitro bar, and touch pedals and steering.
    /// </summary>
    public class Hud : MonoBehaviour
    {
        public System.Action OnGarage;
        public CarController car;
        Canvas canvas;
        Text fps, speed, gear;
        Image nitroFill;
        RectTransform speedNeedle, revNeedle;
        float speedShown, revShown;
        const float SpeedMax = 280f, TachMax = 9000f;   // the scales printed on the dial faces (tools/make_gauges.py)

        /// <summary>A dial picture from Resources/Imported/Gen as a UI sprite.</summary>
        static Sprite GaugeSprite(string name)
        {
            var t = Res.Tex("Gen/" + name);
            if (t == null) return null;
            t.wrapMode = TextureWrapMode.Clamp;
            return Sprite.Create(t, new Rect(0, 0, t.width, t.height), new Vector2(0.5f, 0.5f));
        }
        Minimap map;
        float fpsTimer, fpsAccum; int fpsFrames;
        GameObject touchRoot;

        public void Build(CarController c, Transform player)
        {
            car = c;
            canvas = UIKit.MakeCanvas("HUD", 10);
            canvas.transform.SetParent(transform, false);
            var root = canvas.transform;

            // FPS: top middle
            fps = UIKit.Label("FPS", root, new Vector2(0.5f, 1), new Vector2(0.5f, 1), new Vector2(0, -14), new Vector2(240, 44), "FPS --", 34, new Color(0.6f, 1f, 0.6f));

            // GARAGE button top-right
            UIKit.Btn("GarageBtn", root, new Vector2(1, 1), new Vector2(1, 1), new Vector2(-28, -24), new Vector2(250, 86), "GARAGE", () => OnGarage?.Invoke(), new Color(0.95f, 0.1f, 0.1f), 40);

            // minimap
            map = gameObject.AddComponent<Minimap>();
            map.Build(root, player);

            // light vintage analog dials bottom-right (above the pedals): ivory speedometer with a needle,
            // a smaller rev counter up-left of it, the gear in a round badge and a small digital speed
            var sp = UIKit.Rect("Speedo", root, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-35, 350), new Vector2(320, 320));
            var mid = new Vector2(0.5f, 0.5f);
            UIKit.Img("SpeedFace", sp, mid, mid, Vector2.zero, new Vector2(320, 320), Color.white, GaugeSprite("gauge_speed"));
            var tach = UIKit.Rect("Tach", sp, mid, mid, new Vector2(-197, 108), new Vector2(196, 196));
            UIKit.Img("TachFace", tach, mid, mid, Vector2.zero, new Vector2(196, 196), Color.white, GaugeSprite("gauge_tach"));
            // red zone: the part of the ring past this car's redline (scale 0..9000 rpm over 270 degrees)
            float redAngle = 225f - 270f * Mathf.Clamp01(c.spec.rpmRedline / TachMax);
            var red = UIKit.Img("RedZone", tach, mid, mid, Vector2.zero, new Vector2(196, 196), Color.white, GaugeSprite("gauge_redarc"));
            red.type = Image.Type.Filled; red.fillMethod = Image.FillMethod.Radial360;
            red.fillOrigin = (int)Image.Origin360.Top; red.fillClockwise = true;
            red.fillAmount = (redAngle + 45f) / 360f;
            red.rectTransform.localEulerAngles = new Vector3(0, 0, redAngle - 90f);
            var needleSprite = GaugeSprite("gauge_needle");
            revNeedle = UIKit.Img("RevNeedle", tach, mid, mid, Vector2.zero, new Vector2(20, 157), Color.white, needleSprite).rectTransform;
            speedNeedle = UIKit.Img("SpeedNeedle", sp, mid, mid, Vector2.zero, new Vector2(32, 256), Color.white, needleSprite).rectTransform;
            Color ivory = new Color(0.93f, 0.9f, 0.82f), ink = new Color(0.15f, 0.13f, 0.12f), chrome = new Color(0.82f, 0.82f, 0.82f);
            var box = UIKit.Img("SpeedBox", sp, mid, mid, new Vector2(0, -91), new Vector2(104, 42), new Color(0.09f, 0.08f, 0.08f, 0.92f), UIKit.RoundedSprite);
            box.type = Image.Type.Sliced;
            speed = UIKit.Label("Speed", box.transform, mid, mid, Vector2.zero, new Vector2(104, 42), "0", 36, new Color(1f, 0.93f, 0.78f), TextAnchor.MiddleCenter, Res.TitleFont);
            var gb = UIKit.Img("GearBadge", sp, mid, mid, new Vector2(-141, -56), new Vector2(72, 72), chrome, UIKit.CircleSprite);
            UIKit.Img("GearInner", gb.transform, mid, mid, Vector2.zero, new Vector2(64, 64), ivory, UIKit.CircleSprite);
            gear = UIKit.Label("Gear", gb.transform, mid, mid, Vector2.zero, new Vector2(72, 72), "1", 46, ink, TextAnchor.MiddleCenter, Res.TitleFont);
            gear.GetComponent<Shadow>().enabled = false;
            // nitro bar under the speedo
            var nb = UIKit.Img("NitroBg", root, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-60, 330), new Vector2(290, 16), new Color(0, 0, 0, 0.5f), UIKit.RoundedSprite);
            nb.type = Image.Type.Sliced;
            nitroFill = UIKit.Img("Nitro", nb.transform, new Vector2(0, 0.5f), new Vector2(0, 0.5f), Vector2.zero, new Vector2(290, 16), new Color(0.1f, 0.75f, 1f), Res.White);
            nitroFill.type = Image.Type.Filled; nitroFill.fillMethod = Image.FillMethod.Horizontal;
            UIKit.Label("NitroLbl", root, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-360, 322), new Vector2(120, 30), "NOS", 26, new Color(0.4f, 0.85f, 1f));

            BuildTouch(root);
        }

        void BuildTouch(Transform root)
        {
            touchRoot = UIKit.Rect("Touch", root, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero).gameObject;
            UIKit.Stretch((RectTransform)touchRoot.transform);
            var t = touchRoot.transform;
            var white = new Color(1f, 1f, 1f);
            UIKit.Hold("Left", t, Vector2.zero, Vector2.zero, new Vector2(40, 36), new Vector2(200, 200), "◀", v => PlayerInput.TouchLeft = v, white);
            UIKit.Hold("Right", t, Vector2.zero, Vector2.zero, new Vector2(270, 36), new Vector2(200, 200), "▶", v => PlayerInput.TouchRight = v, white);
            UIKit.Hold("Gas", t, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-40, 36), new Vector2(230, 230), "GAS", v => PlayerInput.TouchGas = v, new Color(0.2f, 1f, 0.35f));
            UIKit.Hold("Brake", t, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-300, 36), new Vector2(190, 190), "BRAKE", v => PlayerInput.TouchBrake = v, new Color(1f, 0.25f, 0.2f));
            UIKit.Hold("Nitro", t, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-420, 250), new Vector2(150, 150), "NOS", v => PlayerInput.TouchNitro = v, new Color(0.2f, 0.7f, 1f));
            UIKit.Hold("Handbrake", t, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-520, 60), new Vector2(150, 150), "E-BRAKE", v => PlayerInput.TouchHandbrake = v, new Color(1f, 0.7f, 0.1f));
        }

        public void SetVisible(bool v) { if (canvas) canvas.gameObject.SetActive(v); }
        public void SetTouchVisible(bool v) { if (touchRoot) touchRoot.SetActive(v); }
        public Minimap Map => map;

        void Update()
        {
            fpsFrames++; fpsAccum += Time.unscaledDeltaTime; fpsTimer += Time.unscaledDeltaTime;
            if (fpsTimer > 0.5f)
            {
                float f = fpsFrames / Mathf.Max(0.001f, fpsAccum);
                fps.text = "FPS " + Mathf.RoundToInt(f);
                fps.color = f >= 50 ? new Color(0.6f, 1f, 0.6f) : f >= 30 ? new Color(1f, 0.9f, 0.4f) : new Color(1f, 0.4f, 0.35f);
                fpsTimer = 0; fpsFrames = 0; fpsAccum = 0;
            }
            if (car == null) return;
            speed.text = Mathf.RoundToInt(car.SpeedKmh).ToString();
            gear.text = car.Gear < 0 ? "R" : car.Gear == 0 ? "N" : car.Gear.ToString();
            // needles: value 0 points to the lower left (135 degrees), full scale to the lower right, with a little damping
            float k = 1f - Mathf.Exp(-14f * Time.deltaTime);
            speedShown = Mathf.Lerp(speedShown, Mathf.Clamp01(Mathf.Abs(car.SpeedKmh) / SpeedMax), k);
            revShown = Mathf.Lerp(revShown, Mathf.Clamp01(car.Rpm / TachMax), k);
            speedNeedle.localEulerAngles = new Vector3(0, 0, 135f - 270f * speedShown);
            revNeedle.localEulerAngles = new Vector3(0, 0, 135f - 270f * revShown);
            nitroFill.fillAmount = car.NitroAmount;
        }
    }
}
