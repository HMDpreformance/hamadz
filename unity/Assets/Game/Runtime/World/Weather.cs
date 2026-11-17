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

        ParticleSystem rain;
        Transform follow;

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
            var go = new GameObject("Rain");
            go.transform.SetParent(transform, false);
            rain = go.AddComponent<ParticleSystem>();
            rain.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = rain.main;
            main.startLifetime = 1.1f;
            main.startSpeed = 22f;
            main.startSize3D = true;
            main.startSizeX = 0.025f; main.startSizeY = 0.7f; main.startSizeZ = 0.025f;
            main.startColor = new Color(0.75f, 0.8f, 0.9f, 0.35f);
            main.maxParticles = 2500;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            var em = rain.emission; em.rateOverTime = 1800;
            var sh = rain.shape; sh.shapeType = ParticleSystemShapeType.Box; sh.scale = new Vector3(40, 1, 40);
            go.transform.rotation = Quaternion.Euler(90, 0, 0);
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.renderMode = ParticleSystemRenderMode.Stretch;
            r.velocityScale = 0.04f; r.lengthScale = 1f;
            r.sharedMaterial = Res.Particle(Color.white, Res.SoftDot);
            rain.Play();
        }

        void ApplyRoad()
        {
            // the asphalt material is shared, so one change shows on every road
            // the WetRoad shader does the wet look (darker, glossy, puddles, mirror); dry roads keep a soft sheen
            Shader.SetGlobalFloat("_HMD_Wetness", Raining ? 1f : 0.3f);
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
            Shader.SetGlobalFloat("_HMD_Wetness", Mathf.Lerp(0.3f, 1f, wetNow));
            Shader.SetGlobalFloat("_HMD_RainAmount", amount);
            RenderSettings.fogDensity = Mathf.Lerp(0.0024f, 0.0042f, amount);
            var em = rain.emission; em.rateOverTime = 1800f * amount;
            // no rain indoors: the workshop interior lives far away from the city (z = -3000)
            bool indoors = follow.position.z < -1500f;
            bool show = !indoors && amount > 0.01f;
            if (rain.gameObject.activeSelf != show) rain.gameObject.SetActive(show);
            if (show) rain.transform.position = follow.position + follow.forward * 8f + Vector3.up * 14f;
        }
    }
}
