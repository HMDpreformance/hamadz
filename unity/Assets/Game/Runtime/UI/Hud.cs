using UnityEngine;
using UnityEngine.UI;

namespace HMD
{
    /// <summary>
    /// Driving HUD (layout from the MC3 reference shots, kept from the Godot game): FPS counter in the
    /// top middle, GARAGE button, round minimap with the LSX wrench marker (and an arrow on the rim when
    /// the garage is off the map; tap it for the full-screen city map), big yellow speedo with a rev
    /// ring and gear badge, nitro bar, and touch pedals and steering.
    /// </summary>
    public class Hud : MonoBehaviour
    {
        public System.Action OnGarage;
        public CarController car;
        Canvas canvas;
        Text fps, speed, gear, unit;
        Image rev, nitroFill;
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

            // speedo bottom-right (above the pedals)
            var sp = UIKit.Rect("Speedo", root, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-40, 360), new Vector2(330, 330));
            var bgRing = UIKit.Img("RingBg", sp, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(320, 320), new Color(0, 0, 0, 0.45f), UIKit.CircleSprite);
            rev = UIKit.Img("Rev", sp, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(320, 320), new Color(1f, 0.82f, 0.1f), UIKit.RingSprite);
            rev.type = Image.Type.Filled;
            rev.fillMethod = Image.FillMethod.Radial360;
            rev.fillOrigin = (int)Image.Origin360.Bottom;
            rev.fillClockwise = true;
            speed = UIKit.Label("Speed", sp, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0, 18), new Vector2(300, 130), "0", 118, new Color(1f, 0.85f, 0.15f), TextAnchor.MiddleCenter, Res.TitleFont);
            unit = UIKit.Label("Unit", sp, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0, -52), new Vector2(200, 40), "KM/H", 30, Color.white);
            var gb = UIKit.Img("GearBadge", sp, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0, -106), new Vector2(76, 62), new Color(1f, 0.82f, 0.1f), UIKit.RoundedSprite);
            gb.type = Image.Type.Sliced;
            gear = UIKit.Label("Gear", gb.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(76, 62), "1", 48, Color.black, TextAnchor.MiddleCenter, Res.TitleFont);
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
            float r = Mathf.InverseLerp(car.spec.rpmIdle, car.spec.rpmRedline, car.Rpm);
            rev.fillAmount = r * 0.75f;
            rev.color = r > 0.9f ? new Color(1f, 0.2f, 0.15f) : new Color(1f, 0.82f, 0.1f);
            nitroFill.fillAmount = car.NitroAmount;
        }
    }
}
