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
        /// <summary>Hide the FPS readout (video recordings: frame capture slows the screen, not the game clock).</summary>
        public static bool HideFps;
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
            fps = UIKit.Label("FPS", root, new Vector2(0.5f, 1), new Vector2(0.5f, 1), new Vector2(0, -14), new Vector2(240, 44), "FPS --", 30, new Color(0.78f, 0.93f, 1f), TextAnchor.MiddleCenter, Res.TitleFont);

            // GARAGE button top-right
            UIKit.Btn("GarageBtn", root, new Vector2(1, 1), new Vector2(1, 1), new Vector2(-28, -24), new Vector2(250, 86), "GARAGE", () => OnGarage?.Invoke(), new Color(0.24f, 0.63f, 1f), 40);

            // minimap
            map = gameObject.AddComponent<Minimap>();
            map.Build(root, player);

            // blue flame analog dials bottom-right (above the pedals): speedometer with a needle,
            // a smaller rev counter up-left of it, the gear in a round badge and a small digital speed
            sp = UIKit.Rect("Speedo", root, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-200, 310), new Vector2(320, 320));
            sp.localScale = Vector3.one * 0.85f;   // the whole dial group at 85%, 40 px lower (Hamad); scales towards the bottom-right pivot
            var mid = new Vector2(0.5f, 0.5f);
            UIKit.Img("SpeedFace", sp, mid, mid, Vector2.zero, new Vector2(320, 320), Color.white, GaugeSprite("gauge_speed"));
            var tach = UIKit.Rect("Tach", sp, mid, mid, new Vector2(197, 108), new Vector2(196, 196));   // rev counter up-right, at the screen edge
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
            Color night = new Color(0.02f, 0.04f, 0.11f), ice = new Color(0.78f, 0.93f, 1f), flameBlue = new Color(0.24f, 0.63f, 1f);
            var box = UIKit.Img("SpeedBox", sp, mid, mid, new Vector2(0, -91), new Vector2(104, 42), new Color(0.01f, 0.03f, 0.09f, 0.6f), UIKit.RoundedSprite);   // see-through like the dial faces
            box.type = Image.Type.Sliced;
            speed = UIKit.Label("Speed", box.transform, mid, mid, Vector2.zero, new Vector2(104, 42), "0", 36, ice, TextAnchor.MiddleCenter, Res.TitleFont);
            var gb = UIKit.Img("GearBadge", sp, mid, mid, new Vector2(141, -56), new Vector2(72, 72), new Color(flameBlue.r, flameBlue.g, flameBlue.b, 0.85f), UIKit.CircleSprite);
            UIKit.Img("GearInner", gb.transform, mid, mid, Vector2.zero, new Vector2(64, 64), new Color(night.r, night.g, night.b, 0.62f), UIKit.CircleSprite);
            gear = UIKit.Label("Gear", gb.transform, mid, mid, Vector2.zero, new Vector2(72, 72), "1", 46, ice, TextAnchor.MiddleCenter, Res.TitleFont);
            gear.GetComponent<Shadow>().enabled = false;
            // nitro bar under the speedo
            // thin chrome frame around a night-blue track, flame-blue fill (same set as the dials)
            nframe = UIKit.Img("NitroFrame", root, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-187, 280),   /* centred under the speedo */ new Vector2(298, 24), new Color(0.82f, 0.86f, 0.92f, 0.95f), UIKit.RoundedSprite);
            nframe.type = Image.Type.Sliced;
            var nb = UIKit.Img("NitroBg", nframe.transform, mid, mid, Vector2.zero, new Vector2(292, 18), new Color(0.01f, 0.03f, 0.09f, 0.95f), UIKit.RoundedSprite);
            nb.type = Image.Type.Sliced;
            nitroFill = UIKit.Img("Nitro", nb.transform, new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(2, 0), new Vector2(288, 12), flameBlue, Res.White);
            nitroFill.type = Image.Type.Filled; nitroFill.fillMethod = Image.FillMethod.Horizontal;
            nlbl = UIKit.Label("NitroLbl", root, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-68, 276), new Vector2(110, 32), "NOS", 28, ice, TextAnchor.MiddleLeft, Res.TitleFont);   // right of the bar, clear of the touch NOS button

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
            nosBtn = UIKit.Hold("Nitro", t, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-600, 250), new Vector2(150, 150), "NOS", v => PlayerInput.TouchNitro = v, new Color(0.2f, 0.7f, 1f));
            UIKit.Hold("Handbrake", t, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-540, 50), new Vector2(150, 150), "E-BRK", v => PlayerInput.TouchHandbrake = v, new Color(1f, 0.7f, 0.1f));
        }

        public void SetVisible(bool v) { if (canvas) canvas.gameObject.SetActive(v); }
        public void SetTouchVisible(bool v) { if (touchRoot) touchRoot.SetActive(v); }
        public Minimap Map => map;

        RectTransform sp; Image nframe; Text nlbl;
        HoldButton nosBtn; float nosFlash; bool nosHooked;

        void Update()
        {
            // the full map screen hides the dials and the NOS bar
            bool mapOpen = map != null && map.IsOpen;
            if (sp && sp.gameObject.activeSelf == mapOpen) { sp.gameObject.SetActive(!mapOpen); nframe.gameObject.SetActive(!mapOpen); nlbl.gameObject.SetActive(!mapOpen); }
            if (fps && fps.gameObject.activeSelf == HideFps) fps.gameObject.SetActive(!HideFps);
            fpsFrames++; fpsAccum += Time.unscaledDeltaTime; fpsTimer += Time.unscaledDeltaTime;
            if (fpsTimer > 0.5f)
            {
                float f = fpsFrames / Mathf.Max(0.001f, fpsAccum);
                fps.text = "FPS " + Mathf.RoundToInt(f);
                fps.color = f >= 50 ? new Color(0.78f, 0.93f, 1f) : f >= 30 ? new Color(1f, 0.9f, 0.4f) : new Color(1f, 0.4f, 0.35f);
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
            // NOS: the bar pulses while it burns; the button flashes once when the tank is full again
            if (!nosHooked) { nosHooked = true; car.OnNitroFull += () => nosFlash = 1f; }
            nitroFill.color = car.NitroActive ? Color.Lerp(new Color(0.24f, 0.63f, 1f), Color.white, 0.5f + 0.5f * Mathf.Sin(Time.time * 18f)) : new Color(0.24f, 0.63f, 1f);
            if (nosBtn && nosFlash > 0f) { nosFlash = Mathf.Max(0f, nosFlash - Time.deltaTime * 1.6f); float s = 1f + 0.22f * Mathf.Sin(nosFlash * Mathf.PI); nosBtn.transform.localScale = new Vector3(s, s, 1f); }
        }
    }
}
