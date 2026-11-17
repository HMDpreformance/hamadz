using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Rain is rare (12% of drives, like the last Godot build); otherwise the night is dry with a
    /// light sheen on the asphalt. When it rains the road turns glossy and reflective, puddles shine,
    /// and rain streaks fall around the camera.
    /// </summary>
    public class Weather : MonoBehaviour
    {
        public const float RainChance = 0.12f;
        public static float Wetness { get; private set; }
        public static bool Raining { get; private set; }

        ParticleSystem rain;
        Transform follow;

        public void Setup(Transform cam, bool? force = null)
        {
            follow = cam;
            Raining = force ?? (Random.value < RainChance);
            Wetness = Raining ? 1f : 0f;
            if (Raining) MakeRain();
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
            // no rain indoors: the workshop interior lives far away from the city (z = -3000)
            bool indoors = follow.position.z < -1500f;
            if (rain.gameObject.activeSelf == indoors) rain.gameObject.SetActive(!indoors);
            if (!indoors) rain.transform.position = follow.position + follow.forward * 8f + Vector3.up * 14f;
        }
    }
}
