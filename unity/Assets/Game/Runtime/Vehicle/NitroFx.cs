using UnityEngine;

namespace HMD
{
    /// <summary>
    /// NOS look on the player car: blue-white flames out of the exhaust while the nitro burns. Two small additive
    /// particle systems at the tail (cheap on phones: 60 particles each, no lights, no shadows).
    /// Exhaust spots: child objects named like an exhaust/muffler/tip if the model has them, else the lower rear corners.
    /// </summary>
    public class NitroFx : MonoBehaviour
    {
        CarController car;
        ParticleSystem[] flames;

        void Start()
        {
            car = GetComponent<CarController>();
            var spots = FindExhausts();
            flames = new ParticleSystem[spots.Length];
            for (int i = 0; i < spots.Length; i++) flames[i] = MakeFlame(spots[i]);
        }

        Vector3[] FindExhausts()
        {
            // local space of the car: +Z forward
            var b = new Bounds(Vector3.zero, Vector3.zero); bool any = false;
            var hits = new System.Collections.Generic.List<Vector3>();
            foreach (var r in GetComponentsInChildren<MeshRenderer>())
            {
                if (r.GetComponentInParent<WheelCollider>() != null) continue;
                string n = r.name.ToLowerInvariant();
                var lb = LocalBounds(r);
                if (n.Contains("exhaust") || n.Contains("muffler") || n.Contains("tailpipe")) hits.Add(new Vector3(lb.center.x, lb.center.y, lb.min.z));
                if (n.Contains("wheel") || n.Contains("tire") || n.Contains("tyre") || n.Contains("rim") || n.Contains("shadow") || n.Contains("beam") || n.Contains("glow") || n.Contains("arch")) continue;
                if (!any) { b = lb; any = true; } else b.Encapsulate(lb);
            }
            if (hits.Count > 0 && hits.Count <= 4) return hits.ToArray();
            if (!any) b = new Bounds(new Vector3(0, 0.6f, 0), new Vector3(1.8f, 1.2f, 4.5f));
            float y = b.min.y + b.size.y * 0.24f, z = b.min.z + 0.02f, x = b.extents.x * 0.17f;   // most cars here have the tips near the middle
            return new[] { new Vector3(-x, y, z), new Vector3(x, y, z) };
        }

        Bounds LocalBounds(Renderer r)
        {
            // the mesh's own box, carried into the car's space corner by corner (the car may be turned in the world)
            var lb = r.localBounds; var m = transform.worldToLocalMatrix * r.transform.localToWorldMatrix;
            var b = new Bounds(m.MultiplyPoint3x4(lb.center), Vector3.zero);
            for (int i = 0; i < 8; i++)
                b.Encapsulate(m.MultiplyPoint3x4(lb.center + Vector3.Scale(lb.extents, new Vector3((i & 1) == 0 ? -1 : 1, (i & 2) == 0 ? -1 : 1, (i & 4) == 0 ? -1 : 1))));
            return b;
        }

        ParticleSystem MakeFlame(Vector3 local)
        {
            var go = new GameObject("NitroFlame");
            go.transform.SetParent(transform, false);
            go.transform.localPosition = local;
            go.transform.localRotation = Quaternion.LookRotation(Vector3.back);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.startLifetime = new ParticleSystem.MinMaxCurve(0.06f, 0.12f);
            main.startSpeed = new ParticleSystem.MinMaxCurve(8f, 13f);
            main.startSize = new ParticleSystem.MinMaxCurve(0.1f, 0.2f);
            main.startColor = new Color(0.45f, 0.7f, 1f, 0.9f);
            main.maxParticles = 60;
            main.simulationSpace = ParticleSystemSimulationSpace.Local;
            var em = ps.emission; em.rateOverTime = 0f;
            var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.Cone; sh.angle = 3f; sh.radius = 0.02f;
            var sz = ps.sizeOverLifetime; sz.enabled = true; sz.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 1f, 1, 0.3f));
            var col = ps.colorOverLifetime; col.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(new Color(0.85f, 0.95f, 1f), 0), new GradientColorKey(new Color(0.2f, 0.45f, 1f), 0.5f), new GradientColorKey(new Color(0.5f, 0.2f, 1f), 1) },
                      new[] { new GradientAlphaKey(1, 0), new GradientAlphaKey(0.7f, 0.5f), new GradientAlphaKey(0, 1) });
            col.color = g;
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = Res.Particle(new Color(1.6f, 1.8f, 2.4f), Res.SoftDot);   // HDR tint so it blooms a little
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            ps.Play();
            return ps;
        }

        void Update()
        {
            if (car == null || flames == null) return;
            float rate = car.NitroActive ? 420f : 0f;
            foreach (var f in flames) { if (f == null) continue; var em = f.emission; em.rateOverTime = rate; }
        }
    }
}
