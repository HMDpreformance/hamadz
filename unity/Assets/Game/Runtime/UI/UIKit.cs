using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace HMD
{
    /// <summary>Helpers to build UGUI from code.</summary>
    public static class UIKit
    {
        public static Canvas MakeCanvas(string name, int order = 0)
        {
            var go = new GameObject(name);
            var c = go.AddComponent<Canvas>();
            c.renderMode = RenderMode.ScreenSpaceOverlay;
            c.sortingOrder = order;
            var s = go.AddComponent<CanvasScaler>();
            s.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            s.referenceResolution = new Vector2(1920, 1080);
            s.matchWidthOrHeight = 0.6f;
            go.AddComponent<GraphicRaycaster>();
            if (Object.FindAnyObjectByType<EventSystem>() == null)
            {
                var es = new GameObject("EventSystem");
                es.AddComponent<EventSystem>();
                es.AddComponent<StandaloneInputModule>();
            }
            return c;
        }

        public static RectTransform Rect(string name, Transform parent, Vector2 anchor, Vector2 pivot, Vector2 pos, Vector2 size)
        {
            var go = new GameObject(name, typeof(RectTransform));
            var rt = (RectTransform)go.transform;
            rt.SetParent(parent, false);
            rt.anchorMin = rt.anchorMax = anchor;
            rt.pivot = pivot;
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            return rt;
        }

        public static void Stretch(RectTransform rt)
        {
            rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one;
            rt.offsetMin = rt.offsetMax = Vector2.zero;
        }

        public static Image Img(string name, Transform parent, Vector2 anchor, Vector2 pivot, Vector2 pos, Vector2 size, Color c, Sprite s = null)
        {
            var rt = Rect(name, parent, anchor, pivot, pos, size);
            var im = rt.gameObject.AddComponent<Image>();
            im.sprite = s;
            im.color = c;
            return im;
        }

        public static Text Label(string name, Transform parent, Vector2 anchor, Vector2 pivot, Vector2 pos, Vector2 size, string text, int fontSize, Color c, TextAnchor align = TextAnchor.MiddleCenter, Font font = null)
        {
            var rt = Rect(name, parent, anchor, pivot, pos, size);
            var t = rt.gameObject.AddComponent<Text>();
            t.font = font ? font : Res.Font;
            t.fontSize = fontSize;
            t.color = c;
            t.alignment = align;
            t.text = text;
            t.raycastTarget = false;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            var sh = rt.gameObject.AddComponent<Shadow>();
            sh.effectColor = new Color(0, 0, 0, 0.7f);
            sh.effectDistance = new Vector2(2, -2);
            return t;
        }

        /// <summary>A button with a label; style: dark glass panel with a coloured edge.</summary>
        public static Button Btn(string name, Transform parent, Vector2 anchor, Vector2 pivot, Vector2 pos, Vector2 size, string text, System.Action onClick, Color? accent = null, int fontSize = 36)
        {
            var im = Img(name, parent, anchor, pivot, pos, size, new Color(0.02f, 0.03f, 0.05f, 0.72f), RoundedSprite);
            im.type = Image.Type.Sliced;
            var edge = Img("Edge", im.transform, new Vector2(0.5f, 0), new Vector2(0.5f, 0), Vector2.zero, new Vector2(size.x - 16, 5), accent ?? new Color(0.24f, 0.63f, 1f));
            var b = im.gameObject.AddComponent<Button>();
            var cb = b.colors; cb.pressedColor = new Color(0.7f, 0.7f, 0.7f); b.colors = cb;
            if (onClick != null) b.onClick.AddListener(() => onClick());
            var l = Label("Text", im.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, size, text, fontSize, Color.white);
            return b;
        }

        public static HoldButton Hold(string name, Transform parent, Vector2 anchor, Vector2 pivot, Vector2 pos, Vector2 size, string text, System.Action<bool> onChange, Color tint)
        {
            var im = Img(name, parent, anchor, pivot, pos, size, new Color(tint.r, tint.g, tint.b, 0.28f), CircleSprite);
            var ring = Img("Ring", im.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, size, new Color(tint.r, tint.g, tint.b, 0.85f), RingSprite);
            ring.raycastTarget = false;
            Label("Text", im.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, size, text, (int)(size.y * 0.3f), Color.white, TextAnchor.MiddleCenter, Res.TitleFont);
            var h = im.gameObject.AddComponent<HoldButton>();
            h.onChange = onChange;
            h.bg = im;
            h.baseAlpha = 0.28f;
            return h;
        }

        static Sprite circle, ring, rounded;
        public static Sprite CircleSprite => circle ? circle : (circle = MakeShape(128, (d, r) => d < r - 1 ? 1 : Mathf.Clamp01(r - d)));
        public static Sprite RingSprite => ring ? ring : (ring = MakeShape(128, (d, r) => Mathf.Clamp01(1 - Mathf.Abs(d - (r - 5)) / 3f)));
        public static Sprite RoundedSprite
        {
            get
            {
                if (rounded) return rounded;
                const int n = 64, rad = 16;
                var t = new Texture2D(n, n, TextureFormat.RGBA32, false);
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        float cx = Mathf.Clamp(x, rad, n - 1 - rad), cy = Mathf.Clamp(y, rad, n - 1 - rad);
                        float d = Vector2.Distance(new Vector2(x, y), new Vector2(cx, cy));
                        t.SetPixel(x, y, new Color(1, 1, 1, Mathf.Clamp01(rad - d)));
                    }
                t.Apply();
                rounded = Sprite.Create(t, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f), 100, 0, SpriteMeshType.FullRect, new Vector4(rad, rad, rad, rad));
                return rounded;
            }
        }

        static Sprite MakeShape(int n, System.Func<float, float, float> alpha)
        {
            var t = new Texture2D(n, n, TextureFormat.RGBA32, false);
            float r = n * 0.5f;
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), new Vector2(r, r));
                    t.SetPixel(x, y, new Color(1, 1, 1, alpha(d, r)));
                }
            t.Apply();
            t.wrapMode = TextureWrapMode.Clamp;
            return Sprite.Create(t, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f));
        }

        /// <summary>A triangle arrow sprite pointing up.</summary>
        static Sprite arrow;
        public static Sprite ArrowSprite
        {
            get
            {
                if (arrow) return arrow;
                const int n = 64;
                var t = new Texture2D(n, n, TextureFormat.RGBA32, false);
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        float fy = (y + 0.5f) / n, fx = Mathf.Abs((x + 0.5f) / n - 0.5f) * 2;
                        float inside = fx < (1 - fy) * 0.95f && fy > 0.08f ? 1 : 0;
                        // notch at the back
                        if (fy < 0.3f && fx < (0.3f - fy) * 2.2f) inside = 0;
                        t.SetPixel(x, y, new Color(1, 1, 1, inside));
                    }
                t.Apply();
                arrow = Sprite.Create(t, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f));
                return arrow;
            }
        }
    }

    /// <summary>A button you hold down (pedals, steering).</summary>
    public class HoldButton : MonoBehaviour, IPointerDownHandler, IPointerUpHandler, IPointerExitHandler
    {
        public System.Action<bool> onChange;
        public Image bg;
        public float baseAlpha = 0.28f;
        bool down;

        public void OnPointerDown(PointerEventData e) => Set(true);
        public void OnPointerUp(PointerEventData e) => Set(false);
        public void OnPointerExit(PointerEventData e) { if (down && e.pointerId < 0) Set(false); }

        void Set(bool v)
        {
            if (down == v) return;
            down = v;
            onChange?.Invoke(v);
            if (bg) { var c = bg.color; c.a = v ? 0.6f : baseAlpha; bg.color = c; }
        }

        void OnDisable() => Set(false);
    }
}
