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

        public void Setup(List<Vector3> lampHeads, Transform camT)
        {
            heads = lampHeads; cam = camT;
            int n = GfxSetup.IsMobile ? 10 : 24;
            for (int i = 0; i < n; i++)
            {
                var l = new GameObject("Lamp" + i).AddComponent<Light>();
                l.transform.SetParent(transform, false);
                l.type = LightType.Spot;
                l.transform.rotation = Quaternion.Euler(90, 0, 0);
                l.spotAngle = 130; l.innerSpotAngle = 70;
                l.range = 30f;
                l.intensity = 26f;
                l.color = new Color(1f, 0.8f, 0.55f);
                l.shadows = LightShadows.None;
                pool.Add(l);
            }
            Halos();
        }

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
            r.sharedMaterial = Res.Particle(new Color(1f, 0.72f, 0.42f, 0.22f), Res.SoftDot);
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            r.maxParticleSize = 0.5f;
            var parts = new ParticleSystem.Particle[heads.Count];
            for (int i = 0; i < heads.Count; i++)
            {
                parts[i].position = heads[i] + Vector3.down * 0.15f;
                parts[i].startSize = 3.4f;
                parts[i].startColor = new Color(1f, 0.75f, 0.45f, 0.22f);
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
                if (on) pool[k].transform.position = heads[best[k]];
            }
        }
    }
}
