using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace HMD
{
    /// <summary>
    /// Round minimap that turns with the car. The LSX garage shows as a red wrench marker; when it is
    /// off the map, an arrow on the rim points to it. Tap the minimap for the full-screen map, which
    /// has a GO TO GARAGE button.
    /// </summary>
    public class Minimap : MonoBehaviour, IPointerClickHandler
    {
        public System.Action OnGoGarage;
        Transform player;
        RawImage mapImg, bigImg;
        RectTransform rotor, garageIcon, edgeArrow, bigPlayer, bigGarage;
        GameObject big;
        Texture2D tex;
        const float Size = 300f;          // on-screen diameter
        const float ViewMetres = 360f;    // world metres across the minimap
        const int TexSize = 1024;
        float worldMin, worldSize;

        public void Build(Transform root, Transform playerT)
        {
            player = playerT;
            worldMin = -City.Road - 20f;
            worldSize = City.Extent + City.Road + 40f;
            tex = DrawMap();

            var frame = UIKit.Img("Minimap", root, Vector2.zero, Vector2.zero, new Vector2(48, 268), new Vector2(Size + 14, Size + 14), new Color(0, 0, 0, 0.6f), UIKit.CircleSprite);
            var maskImg = UIKit.Img("Mask", frame.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(Size, Size), Color.white, UIKit.CircleSprite);
            maskImg.gameObject.AddComponent<Mask>().showMaskGraphic = false;
            rotor = UIKit.Rect("Rotor", maskImg.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(Size, Size) * 1.5f);
            var ri = new GameObject("Map", typeof(RectTransform)).AddComponent<RawImage>();
            ri.transform.SetParent(rotor, false);
            UIKit.Stretch(ri.rectTransform);
            ri.texture = tex;
            ri.raycastTarget = false;
            mapImg = ri;
            garageIcon = UIKit.Img("Garage", rotor, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(46, 46), Color.white, WrenchSprite).rectTransform;
            var ring = UIKit.Img("Ring", frame.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(Size + 14, Size + 14), new Color(1f, 0.82f, 0.1f, 0.9f), UIKit.RingSprite);
            ring.raycastTarget = false;
            var me = UIKit.Img("Player", frame.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(30, 34), new Color(1f, 0.85f, 0.1f), UIKit.ArrowSprite);
            me.raycastTarget = false;
            edgeArrow = UIKit.Img("GarageArrow", frame.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(34, 34), new Color(1f, 0.15f, 0.12f), UIKit.ArrowSprite).rectTransform;
            edgeArrow.GetComponent<Image>().raycastTarget = false;
            frame.gameObject.AddComponent<MinimapTap>().map = this;
            UIKit.Label("N", frame.transform, new Vector2(0.5f, 1), new Vector2(0.5f, 0.5f), new Vector2(0, -4), new Vector2(40, 30), "", 22, Color.white);

            // full-screen map
            var bigRt = UIKit.Rect("BigMap", root, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero);
            UIKit.Stretch(bigRt);
            big = bigRt.gameObject;
            var dim = big.AddComponent<Image>(); dim.color = new Color(0, 0, 0, 0.82f);
            var bi = new GameObject("Map", typeof(RectTransform)).AddComponent<RawImage>();
            bi.transform.SetParent(bigRt, false);
            bi.rectTransform.anchorMin = bi.rectTransform.anchorMax = new Vector2(0.5f, 0.5f);
            bi.rectTransform.sizeDelta = new Vector2(940, 940);
            bi.texture = tex;
            bigImg = bi;
            bigGarage = UIKit.Img("Garage", bi.transform, new Vector2(0, 0), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(60, 60), Color.white, WrenchSprite).rectTransform;
            bigPlayer = UIKit.Img("Player", bi.transform, new Vector2(0, 0), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(40, 46), new Color(1f, 0.85f, 0.1f), UIKit.ArrowSprite).rectTransform;
            UIKit.Label("Title", bigRt, new Vector2(0.5f, 1), new Vector2(0.5f, 1), new Vector2(0, -20), new Vector2(800, 60), "DUBAI  ·  NIGHT CITY", 44, Color.white, TextAnchor.MiddleCenter, Res.TitleFont);
            UIKit.Btn("GoGarage", bigRt, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-40, 40), new Vector2(380, 96), "GO TO GARAGE", () => { Close(); OnGoGarage?.Invoke(); }, new Color(0.95f, 0.1f, 0.1f), 38);
            UIKit.Btn("Close", bigRt, new Vector2(1, 1), new Vector2(1, 1), new Vector2(-40, -30), new Vector2(200, 86), "CLOSE", Close, Color.white, 36);
            big.SetActive(false);
        }

        public void OnPointerClick(PointerEventData e) => Open();
        public void Open() { big.SetActive(true); }
        public void Close() { big.SetActive(false); }
        public bool IsOpen => big != null && big.activeSelf;

        Vector2 ToUV(Vector3 w) => new Vector2((w.x - worldMin) / worldSize, (w.z - worldMin) / worldSize);

        void LateUpdate()
        {
            if (player == null || City.I == null) return;
            // minimap: map texture slides under the player and turns with the car (heading up)
            float px = Size * 1.5f;   // rotor size in pixels
            float metresPerPx = ViewMetres / Size;
            float worldPx = worldSize / metresPerPx;   // full map in minimap pixels
            Vector2 uv = ToUV(player.position);
            mapImg.rectTransform.anchorMin = mapImg.rectTransform.anchorMax = new Vector2(0.5f, 0.5f);
            mapImg.rectTransform.sizeDelta = new Vector2(worldPx, worldPx);
            mapImg.rectTransform.anchoredPosition = new Vector2((0.5f - uv.x) * worldPx, (0.5f - uv.y) * worldPx);
            rotor.localRotation = Quaternion.Euler(0, 0, player.eulerAngles.y);

            Vector3 g = City.I.GarageDoor;
            Vector3 d = g - player.position;
            Vector2 local = new Vector2(d.x, d.z) / metresPerPx;
            garageIcon.anchoredPosition = local;
            garageIcon.localRotation = Quaternion.Euler(0, 0, -player.eulerAngles.y);
            float r = Size * 0.5f - 20f;
            // rotate into screen space to check if it's inside the circle
            Vector2 screen = Rotate(local, player.eulerAngles.y);
            bool inside = screen.magnitude < r;
            garageIcon.gameObject.SetActive(inside);
            edgeArrow.gameObject.SetActive(!inside);
            if (!inside)
            {
                Vector2 dir = screen.normalized;
                edgeArrow.anchoredPosition = dir * (Size * 0.5f + 4f);
                edgeArrow.localRotation = Quaternion.Euler(0, 0, Mathf.Atan2(dir.y, dir.x) * Mathf.Rad2Deg - 90f);
            }

            if (big.activeSelf)
            {
                float s = bigImg.rectTransform.sizeDelta.x;
                bigPlayer.anchoredPosition = ToUV(player.position) * s;
                bigPlayer.localRotation = Quaternion.Euler(0, 0, -player.eulerAngles.y);
                bigGarage.anchoredPosition = ToUV(g) * s;
            }
        }

        static Vector2 Rotate(Vector2 v, float deg)
        {
            float a = deg * Mathf.Deg2Rad, c = Mathf.Cos(a), s = Mathf.Sin(a);
            return new Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
        }

        Texture2D DrawMap()
        {
            var t = new Texture2D(TexSize, TexSize, TextureFormat.RGBA32, true);
            var px = new Color32[TexSize * TexSize];
            Color32 bg = new Color32(14, 18, 28, 255), block = new Color32(30, 36, 52, 255), road = new Color32(120, 128, 140, 255), median = new Color32(70, 90, 70, 255), gar = new Color32(140, 30, 30, 255);
            for (int y = 0; y < TexSize; y++)
                for (int x = 0; x < TexSize; x++)
                {
                    float wx = worldMin + (x + 0.5f) / TexSize * worldSize, wz = worldMin + (y + 0.5f) / TexSize * worldSize;
                    Color32 c = bg;
                    if (wx > -City.Road && wz > -City.Road && wx < City.Extent && wz < City.Extent)
                    {
                        float mx = Mathf.Repeat(wx + City.Road, City.Pitch) - City.Road, mz = Mathf.Repeat(wz + City.Road, City.Pitch) - City.Road;
                        bool onX = mx < 0, onZ = mz < 0;
                        if (onX || onZ)
                        {
                            c = road;
                            float cx = Mathf.Abs(mx + City.Road * 0.5f), cz = Mathf.Abs(mz + City.Road * 0.5f);
                            if ((onX && !onZ && cx < City.Median * 0.5f) || (onZ && !onX && cz < City.Median * 0.5f)) c = median;
                        }
                        else
                        {
                            c = block;
                            int bi = Mathf.FloorToInt((wx + City.Road) / City.Pitch), bj = Mathf.FloorToInt((wz + City.Road) / City.Pitch);
                            if (bi == City.GarageBlock.x && bj == City.GarageBlock.y) c = gar;
                        }
                    }
                    px[y * TexSize + x] = c;
                }
            t.SetPixels32(px);
            t.Apply(true);
            t.wrapMode = TextureWrapMode.Clamp;
            t.filterMode = FilterMode.Trilinear;
            return t;
        }

        static Sprite wrench;
        /// <summary>Red round badge with a white wrench (the garage marker).</summary>
        public static Sprite WrenchSprite
        {
            get
            {
                if (wrench) return wrench;
                const int n = 96;
                var t = new Texture2D(n, n, TextureFormat.RGBA32, false);
                Vector2 c = new Vector2(n / 2f, n / 2f);
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        Vector2 p = new Vector2(x + 0.5f, y + 0.5f);
                        float d = Vector2.Distance(p, c);
                        Color col = new Color(0, 0, 0, 0);
                        if (d < n / 2f - 1) col = new Color(0.85f, 0.08f, 0.06f, 1);
                        if (d < n / 2f - 1 && d > n / 2f - 6) col = Color.white;
                        // wrench in local coords rotated 45 degrees
                        Vector2 q = p - c;
                        float a = -45f * Mathf.Deg2Rad;
                        Vector2 r = new Vector2(q.x * Mathf.Cos(a) - q.y * Mathf.Sin(a), q.x * Mathf.Sin(a) + q.y * Mathf.Cos(a));
                        bool handle = Mathf.Abs(r.x) < 5.5f && r.y > -26 && r.y < 14;
                        Vector2 head = r - new Vector2(0, 20);
                        bool ring = head.magnitude < 13 && !(Mathf.Abs(head.x) < 5 && head.y > -2);
                        if (handle || ring) col = Color.white;
                        t.SetPixel(x, y, col);
                    }
                t.Apply();
                wrench = Sprite.Create(t, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f));
                return wrench;
            }
        }
    }

    public class MinimapTap : MonoBehaviour, IPointerClickHandler
    {
        public Minimap map;
        public void OnPointerClick(PointerEventData e) => map.Open();
    }
}
