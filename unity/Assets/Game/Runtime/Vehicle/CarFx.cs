using UnityEngine;

namespace HMD
{
    /// <summary>Tyre smoke from the rear wheels when they slide, and rain spray at speed on a wet road.</summary>
    public class CarFx : MonoBehaviour
    {
        CarController car;
        ParticleSystem smoke, spray;

        public void Setup(CarController c)
        {
            car = c;
            smoke = Make("Smoke", new Color(0.8f, 0.8f, 0.82f, 0.35f), 2.2f, 1.6f, 0.5f);
            spray = Make("Spray", new Color(0.75f, 0.8f, 0.85f, 0.18f), 0.8f, 1.2f, 3f);
        }

        ParticleSystem Make(string name, Color col, float life, float size, float speed)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            go.transform.localPosition = new Vector3(0, 0.25f, -car.spec.length * 0.33f);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.startLifetime = life;
            main.startSize = new ParticleSystem.MinMaxCurve(size * 0.6f, size * 1.4f);
            main.startSpeed = speed;
            main.startColor = col;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.maxParticles = 300;
            main.gravityModifier = -0.02f;
            var em = ps.emission; em.rateOverTime = 0;
            var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.Box; sh.scale = new Vector3(1.6f, 0.1f, 0.4f);
            var sz = ps.sizeOverLifetime; sz.enabled = true; sz.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 0.5f, 1, 2.5f));
            var ca = ps.colorOverLifetime; ca.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0), new GradientColorKey(Color.white, 1) },
                      new[] { new GradientAlphaKey(1, 0), new GradientAlphaKey(0, 1) });
            ca.color = g;
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = Res.Particle(Color.white, Res.SoftDot);
            ps.Play();
            return ps;
        }

        void Update()
        {
            if (car == null) return;
            var em = smoke.emission;
            em.rateOverTime = car.SpeedKmh > 6 && car.RearSlip > 0.45f && !car.dynoMode ? Mathf.Clamp((car.RearSlip - 0.45f) * 160f, 0, 120) : 0;
            var es = spray.emission;
            es.rateOverTime = Weather.Wetness > 0.5f && !car.dynoMode ? Mathf.Clamp(car.SpeedKmh - 30, 0, 120) * 0.6f * Weather.Wetness : 0;
        }
    }
}
