using UnityEngine;
using UnityEngine.UI;

namespace HMD
{
    /// <summary>Garage menu: car name and specs, change car, run the dyno, drive out. Shows the dyno result card.</summary>
    public class GarageUI : MonoBehaviour
    {
        public System.Action OnPrev, OnNext, OnDyno, OnDriveOut, OnTv;
        Canvas canvas;
        Text carName, carTag, carStats, result;
        GameObject resultCard, tvBtn, buttons;

        public void Build()
        {
            canvas = UIKit.MakeCanvas("GarageUI", 20);
            canvas.transform.SetParent(transform, false);
            var r = canvas.transform;
            // header with the LSX logo
            var logo = Res.Tex("Art/lsx-logo");
            if (logo)
            {
                var li = UIKit.Img("Logo", r, new Vector2(0, 1), new Vector2(0, 1), new Vector2(36, -26), new Vector2(330, 107), Color.white, Res.ToSprite(logo));
                li.preserveAspect = true;
            }
            carName = UIKit.Label("Name", r, new Vector2(0, 1), new Vector2(0, 1), new Vector2(40, -150), new Vector2(900, 80), "", 72, Color.white, TextAnchor.MiddleLeft, Res.TitleFont);
            carTag = UIKit.Label("Tag", r, new Vector2(0, 1), new Vector2(0, 1), new Vector2(44, -222), new Vector2(900, 40), "", 32, new Color(0.55f, 0.82f, 1f), TextAnchor.MiddleLeft);
            carStats = UIKit.Label("Stats", r, new Vector2(0, 1), new Vector2(0, 1), new Vector2(44, -262), new Vector2(900, 200), "", 30, new Color(0.9f, 0.92f, 0.95f), TextAnchor.UpperLeft);

            buttons = UIKit.Rect("Buttons", r, new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 40), new Vector2(1500, 110)).gameObject;
            var b = buttons.transform;
            UIKit.Btn("Prev", b, new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(0, 0), new Vector2(150, 100), "◀", () => OnPrev?.Invoke(), Color.white, 52);
            UIKit.Btn("Next", b, new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(170, 0), new Vector2(150, 100), "▶", () => OnNext?.Invoke(), Color.white, 52);
            UIKit.Btn("Dyno", b, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(40, 0), new Vector2(380, 100), "DYNO RUN", () => OnDyno?.Invoke(), new Color(0.2f, 0.6f, 1f), 42);
            UIKit.Btn("Drive", b, new Vector2(1, 0.5f), new Vector2(1, 0.5f), new Vector2(0, 0), new Vector2(420, 100), "DRIVE OUT", () => OnDriveOut?.Invoke(), new Color(0.95f, 0.1f, 0.1f), 42);

            resultCard = UIKit.Img("Result", r, new Vector2(1, 1), new Vector2(1, 1), new Vector2(-36, -40), new Vector2(560, 250), new Color(0.02f, 0.03f, 0.05f, 0.8f), UIKit.RoundedSprite).gameObject;
            resultCard.GetComponent<Image>().type = Image.Type.Sliced;
            result = UIKit.Label("Text", resultCard.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(520, 230), "", 38, Color.white);
            resultCard.SetActive(false);
            tvBtn = UIKit.Btn("TV", r, new Vector2(1, 1), new Vector2(1, 1), new Vector2(-36, -310), new Vector2(560, 90), "TAP TO ZOOM THE TV", () => OnTv?.Invoke(), new Color(0.2f, 0.6f, 1f), 34).gameObject;
            tvBtn.SetActive(false);
        }

        public void ShowCar(CarSpec s)
        {
            carName.text = s.name;
            carTag.text = s.tag;
            carStats.text = $"{s.cyl}  ·  {s.drive}\n{s.hp:0} HP   {s.torqueNm:0} NM   {s.weightKg:0} KG\nTOP SPEED {s.topKmh:0} KM/H";
            resultCard.SetActive(false);
            tvBtn.SetActive(false);
        }

        public void ShowResult(float hp, float nm, float rpm)
        {
            result.text = $"<color=#ff4433>{hp:0} HP</color>\n<color=#3399ff>{nm:0} NM</color>\n<size=26>DYNO PULL TO {rpm:0} RPM</size>";
            result.supportRichText = true;
            resultCard.SetActive(true);
            tvBtn.SetActive(true);
        }

        public void SetBusy(bool busy) => buttons.SetActive(!busy);
        public void SetVisible(bool v) { if (canvas) canvas.gameObject.SetActive(v); }
    }
}
