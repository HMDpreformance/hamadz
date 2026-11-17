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
        List<Vector3> heads;
        Transform cam;
        float timer;

        public void Setup(City c, Transform camT) => Setup(c.lampHeads, camT);

        List<bool> cool;   // per head: highway LED (cool white) instead of sodium
        static readonly Color Sodium = new Color(1f, 0.6f, 0.27f), Led = new Color(0.8f, 0.89f, 1f);

        public void Setup(List<Vector3> lampHeads, Transform camT, List<bool> coolHeads = null)
        {
            heads = lampHeads; cam = camT; cool = coolHeads != null && coolHeads.Count == lampHeads.Count ? coolHeads : null;
            // Forward+ renderer: no per-object light limit, so a bigger pool lights more of the road ahead
            int n = GfxSetup.IsMobile ? 12 : 40;
            for (int i = 0; i < n; i++)
            {
                var l = new GameObject("Lamp" + i).AddComponent<Light>();
                l.transform.SetParent(transform, false);
                l.type = LightType.Spot;
                l.transform.rotation = Quaternion.Euler(90, 0, 0);
                // a tighter cone with a soft edge: a bright pool under each lamp and darker road between them
                l.spotAngle = 118; l.innerSpotAngle = 38;
                l.range = 24f;
                l.intensity = 34f;
                l.color = Sodium;
                l.shadows = LightShadows.None;
                pool.Add(l);
            }
            Halos();
        }

        bool Cool(int i) => cool != null && cool[i];

        /// <summary>A soft glow sprite around every lamp head (the wet air catching the light). One static particle each.</summary>
        void Halos()
        {

            if (heads == null || heads.Count == 0) return;
            var go = new GameObject("LampHalos");
            go.transform.SetParent(transform, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.loop = false; main.playOnAwake = false;
            main.maxParticles = heads.Count;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.startLifetime = 1e6f;
            main.startSpeed = 0f;
            main.simulationSpeed = 0.0001f;   // effectively frozen, but still "playing" so bounds and culling stay valid
            main.cullingMode = ParticleSystemCullingMode.AlwaysSimulate;
            var em = ps.emission; em.enabled = false;
            var shape = ps.shape; shape.enabled = false;
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.renderMode = ParticleSystemRenderMode.Billboard;
            r.sharedMaterial = Res.Particle(Color.white, Res.SoftDot);   // colour per particle (sodium / LED)
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            r.maxParticleSize = 0.5f;
            var parts = new ParticleSystem.Particle[heads.Count];
            for (int i = 0; i < heads.Count; i++)
            {
                parts[i].position = heads[i] + Vector3.down * 0.15f;
                parts[i].startSize = Cool(i) ? 3.8f : 3.4f;
                parts[i].startColor = Cool(i) ? new Color(0.78f, 0.88f, 1f, 0.2f) : new Color(1f, 0.66f, 0.34f, 0.24f);
                parts[i].remainingLifetime = 1e6f;
                parts[i].startLifetime = 1e6f;
            }
            ps.Play();
            ps.SetParticles(parts, parts.Length);
        }

        void Update()
        {
            if (heads == null || cam == null) return;
            timer -= Time.deltaTime;
            if (timer > 0) return;
            timer = 0.5f;
            Vector3 p = cam.position;

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
                if (on)
                {
                    int h = best[k]; var l = pool[k];
                    l.transform.position = heads[h];
                    bool c = Cool(h);
                    // highway LED poles are 12 m tall: a wider, stronger, cooler pool
                    l.color = c ? Led : Sodium; l.intensity = c ? 75f : 40f; l.range = c ? 38f : 26f; l.spotAngle = c ? 124f : 118f;
                }
            }
        }
    }
}
