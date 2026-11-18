using UnityEngine;
using UnityEngine.UI;

namespace HMD
{
    /// <summary>
    /// Where you are: when you drive into another part of Dubai its name shows small in the top-left corner (under the radio), fades in, stays about 3 seconds and fades out (Hamad: "not big, just so you know where you are").
    /// The area is the nearest district centre from the city plan; a new one must stay nearest for a second (no
    /// flicker on a border), and the same name does not show again until you have been somewhere else.
    /// (Arabic under the name is left out: the UI text here cannot join Arabic letters correctly.)
    /// </summary>
    public class DistrictLabel : MonoBehaviour
    {
        public static DistrictLabel I;
        CanvasGroup group; Text label;
        string current, candidate; float candT, showT;

        public static void Ensure(Transform parent)
        {
            if (I != null || NewCity.I == null || NewCity.I.districts.Count == 0) return;
            I = new GameObject("DistrictLabel").AddComponent<DistrictLabel>();
            I.transform.SetParent(parent, false);
            I.Build();
        }

        void Build()
        {
            var canvas = UIKit.MakeCanvas("DistrictUI", 11);
            canvas.transform.SetParent(transform, false);
            // top-left corner under the radio row: clear of the GARAGE button, the map and the dials
            var panel = UIKit.Rect("District", canvas.transform, new Vector2(0, 1), new Vector2(0, 1), new Vector2(32, -112), new Vector2(700, 56));
            group = panel.gameObject.AddComponent<CanvasGroup>(); group.alpha = 0; group.blocksRaycasts = false; group.interactable = false;
            label = UIKit.Label("Name", panel, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(700, 56), "", 36, new Color(1f, 0.93f, 0.8f), TextAnchor.MiddleLeft, Res.TitleFont);
            label.raycastTarget = false;
            var o = label.gameObject.AddComponent<Outline>(); o.effectColor = new Color(0, 0, 0, 0.85f); o.effectDistance = new Vector2(2, -2);
        }

        void Update()
        {
            var g = Game.I; var nc = NewCity.I;
            if (g == null || g.car == null || nc == null) return;
            bool driving = g.state == Game.State.Drive;
            if (driving)
            {
                Vector3 p = g.car.transform.position; string best = null; float bd = float.MaxValue;
                foreach (var d in nc.districts) { float q = (d.pos.x - p.x) * (d.pos.x - p.x) + (d.pos.z - p.z) * (d.pos.z - p.z); if (q < bd) { bd = q; best = d.name; } }
                if (best != current)
                {
                    if (best != candidate) { candidate = best; candT = 0; }
                    candT += Time.deltaTime;
                    if (candT > 1f) { current = best; candidate = null; label.text = best.ToUpperInvariant(); showT = 3.8f; Debug.Log("[HMD] district: " + best); }
                }
                else candidate = null;
            }
            if (showT > 0) showT -= Time.deltaTime;
            float a = showT > 3.4f ? (3.8f - showT) / 0.4f : showT < 0.7f ? showT / 0.7f : 1f;
            group.alpha = driving ? Mathf.Clamp01(a) : 0f;
        }
    }
}
