using System.Collections.Generic;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// The city has hundreds of street lamps; phones can't light them all. A small pool of real lights
    /// jumps to the lamps nearest the camera (twice a second), so the road under you is always lit and
    /// shines, while far lamps just glow.
    /// </summary>
    public class LampLights : MonoBehaviour
    {
        readonly List<Light> pool = new List<Light>();
        City city;
        Transform cam;
        float timer;

        public void Setup(City c, Transform camT)
        {
            city = c; cam = camT;
            int n = GfxSetup.IsMobile ? 10 : 24;
            for (int i = 0; i < n; i++)
            {
                var l = new GameObject("Lamp" + i).AddComponent<Light>();
                l.transform.SetParent(transform, false);
                l.type = LightType.Spot;
                l.transform.rotation = Quaternion.Euler(90, 0, 0);
                l.spotAngle = 120; l.innerSpotAngle = 60;
                l.range = 22f;
                l.intensity = 14f;
                l.color = new Color(1f, 0.8f, 0.55f);
                l.shadows = LightShadows.None;
                pool.Add(l);
            }
        }

        void Update()
        {
            if (city == null || cam == null) return;
            timer -= Time.deltaTime;
            if (timer > 0) return;
            timer = 0.5f;
            Vector3 p = cam.position;
            var heads = city.lampHeads;
            // pick the nearest lamps (partial selection is plenty fast for a few hundred lamps)
            var best = new List<int>(pool.Count);
            var dist = new List<float>(pool.Count);
            for (int i = 0; i < heads.Count; i++)
            {
                float d = (heads[i] - p).sqrMagnitude;
                if (best.Count < pool.Count) { best.Add(i); dist.Add(d); continue; }
                int worst = 0;
                for (int k = 1; k < dist.Count; k++) if (dist[k] > dist[worst]) worst = k;
                if (d < dist[worst]) { best[worst] = i; dist[worst] = d; }
            }
            for (int k = 0; k < pool.Count; k++)
            {
                bool on = k < best.Count;
                pool[k].enabled = on;
                if (on) pool[k].transform.position = heads[best[k]];
            }
        }
    }
}
