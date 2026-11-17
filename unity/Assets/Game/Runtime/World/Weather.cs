using UnityEngine;

namespace HMD
{
    /// <summary>
    /// The weather changes while you drive: most of the time the night is dry with a light sheen on the
    /// asphalt, and now and then a shower comes in, lasts a few minutes and passes. The rain fades in and
    /// out, and the road dries slowly after it. (Hamad 2026-11-17: "not always raining, sometimes yes sometimes no".)
    /// </summary>
    public class Weather : MonoBehaviour
    {
        public const float RainChance = 0.25f;     // chance that a drive starts in a shower, and that the next spell is one
        float amount, nextChange; bool forced; float wetNow;
        public static float Wetness { get; private set; }
        public static bool Raining { get; private set; }

        ParticleSystem rain, rainFar, splash;
        Transform follow;
        /// <summary>Road sheen on a dry night (0 = matte, 1 = soaked). 0.3 read as rain on dry nights; 0.12 is a light sheen.</summary>
        public const float DrySheen = 0.12f;

        public void Setup(Transform cam, bool? force = null)
        {
            follow = cam;
            forced = force.HasValue;
            Raining = force ?? (Random.value < RainChance);
            amount = Raining ? 1f : 0f;
            Wetness = wetNow = Raining ? 1f : 0f;
            nextChange = Time.time + (Raining ? Random.Range(90f, 240f) : Random.Range(150f, 420f));
            if (!rain) MakeRain();
            ApplyRoad();
        }

        void MakeRain()
        {
            // near layer: thin soft streaks round the camera; far layer: fainter, wider, so the rain has depth
            rain = RainLayer("Rain", new Vector3(36, 1, 36), 0.018f, 1f, new Color(0.8f, 0.84f, 0.92f, 0.22f), 2400);
            rainFar = RainLayer("RainFar", new Vector3(110, 1, 110), 0.04f, 1.6f, new Color(0.7f, 0.74f, 0.85f, 0.1f), 3000);
            // splashes: tiny flat rings popping on the road round the car
            var go = new GameObject("RainSplash");
            go.transform.SetParent(transform, false);
            splash = go.AddComponent<ParticleSystem>();
            splash.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = splash.main;
            main.startLifetime = 0.28f; main.startSpeed = 0f;
            main.startSize = new ParticleSystem.MinMaxCurve(0.12f, 0.35f);
            main.startColor = new Color(0.85f, 0.88f, 0.95f, 0.4f);
            main.maxParticles = 900; main.simulationSpace = ParticleSystemSimulationSpace.World;
            var em = splash.emission; em.rateOverTime = 0;
            var sh = splash.shape; sh.shapeType = ParticleSystemShapeType.Box; sh.scale = new Vector3(22, 22, 0.01f);
            go.transform.rotation = Quaternion.Euler(90, 0, 0);
            var sz = splash.sizeOverLifetime; sz.enabled = true; sz.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 0.3f, 1, 1.2f));
            var col = splash.colorOverLifetime; col.enabled = true;
            var gr = new Gradient(); gr.SetKeys(new[] { new GradientColorKey(Color.white, 0), new GradientColorKey(Color.white, 1) }, new[] { new GradientAlphaKey(1, 0), new GradientAlphaKey(0, 1) });
            col.color = gr;
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.renderMode = ParticleSystemRenderMode.HorizontalBillboard;
            r.sharedMaterial = Res.Particle(Color.white, Res.SoftDot);
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            splash.Play();
        }

        ParticleSystem RainLayer(string name, Vector3 box, float width, float length, Color c, int max)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.startLifetime = 1.2f;
            main.startSpeed = new ParticleSystem.MinMaxCurve(19f, 25f);
            main.startSize3D = true;
            main.startSizeX = width; main.startSizeY = 0.75f * length; main.startSizeZ = width;
            main.startColor = c;
            main.maxParticles = max;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            var em = ps.emission; em.rateOverTime = max * 0.75f;
            var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.Box; sh.scale = box;
            go.transform.rotation = Quaternion.Euler(90, 0, 0);
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.renderMode = ParticleSystemRenderMode.Stretch;
            r.velocityScale = 0.035f; r.lengthScale = 1f;
            r.sharedMaterial = Res.Particle(Color.white, Res.SoftDot);
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            ps.Play();
            return ps;
        }

        void ApplyRoad()
        {
            // the asphalt material is shared, so one change shows on every road
            // the WetRoad shader does the wet look (darker, glossy, puddles, mirror); dry roads keep a soft sheen
            Shader.SetGlobalFloat("_HMD_Wetness", Raining ? 1f : DrySheen);
            Shader.SetGlobalFloat("_HMD_RainAmount", Raining ? 1f : 0f);
            Shader.SetGlobalVector("_HMD_Grid", new Vector4(City.Pitch, City.Road * 0.5f, City.Road * 0.5f, 0));
            var city = City.I;
            if (city == null) return;
            var asphalt = city.transform.Find("Asphalt");
            if (asphalt == null) return;
            var m = asphalt.GetComponent<Renderer>().sharedMaterial;
            float smooth = 0.45f;
            m.SetFloat("_Smoothness", smooth);
            m.SetFloat("_GlossMapScale", smooth);
            Res.SetColor(m, new Color(0.55f, 0.55f, 0.58f));
        }

        void LateUpdate()
        {
            if (!rain || !follow) return;
            // a new spell of weather every few minutes (not when -rain / -dry forces it for screenshots)
            if (!forced && Time.time > nextChange)
            {
                Raining = !Raining && Random.value < RainChance * 1.6f;
                nextChange = Time.time + (Raining ? Random.Range(90f, 240f) : Random.Range(150f, 420f));
            }
            amount = Mathf.MoveTowards(amount, Raining ? 1f : 0f, Time.deltaTime / 18f);            // fades over 18 s
            wetNow = Mathf.MoveTowards(wetNow, Raining ? 1f : 0f, Time.deltaTime / (Raining ? 25f : 150f));   // the road dries slowly
            Wetness = wetNow;
            Shader.SetGlobalFloat("_HMD_Wetness", Mathf.Lerp(DrySheen, 1f, wetNow));
            Shader.SetGlobalFloat("_HMD_RainAmount", amount);
            RenderSettings.fogDensity = Mathf.Lerp(0.0024f, 0.0046f, amount);   // light mist in a shower
            var em = rain.emission; em.rateOverTime = 1800f * amount;
            var ef = rainFar.emission; ef.rateOverTime = 2250f * amount;
            // no rain indoors: the workshop interior lives far away from the city (z = -3000)
            bool indoors = follow.position.z < -1500f;
            bool show = !indoors && amount > 0.01f;
            foreach (var ps in new[] { rain, rainFar, splash })
                if (ps.gameObject.activeSelf != show) ps.gameObject.SetActive(show);
            if (show)
            {
                rain.transform.position = follow.position + follow.forward * 8f + Vector3.up * 14f;
                rainFar.transform.position = follow.position + follow.forward * 30f + Vector3.up * 18f;
                // splashes on the ground in front of and round the camera
                Vector3 c = follow.position + Vector3.ProjectOnPlane(follow.forward, Vector3.up).normalized * 7f;
                float gy = Physics.Raycast(c + Vector3.up * 5f, Vector3.down, out var hit, 30f) ? hit.point.y : follow.position.y - 1.5f;
                splash.transform.position = new Vector3(c.x, gy + 0.04f, c.z);
                var es = splash.emission; es.rateOverTime = 1500f * amount * wetNow;
            }
        }
    }
}
