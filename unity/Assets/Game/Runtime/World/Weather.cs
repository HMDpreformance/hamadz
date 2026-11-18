using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Light rain all the time (Hamad 2026-11-18: "add light rain all time and make the street wet from rain and reflect"):
    /// thin soft streaks round the camera, a fainter far layer for depth, small splashes on the road, a little mist,
    /// and the roads always soaked and glossy so lamps, neon and towers mirror in them. No rain inside the workshop.
    /// -dry (dev flag only) turns it off for comparison shots.
    /// </summary>
    public class Weather : MonoBehaviour
    {
        float amount; float wetNow;
        ParticleSystem[] layers;
        public static float Wetness { get; private set; }
        public static bool Raining { get; private set; }

        ParticleSystem rain, rainFar, splash;
        Transform follow;
        /// <summary>Road sheen on a dry night (0 = matte, 1 = soaked). 0.3 read as rain on dry nights; 0.12 is a light sheen.</summary>
        public const float DrySheen = 0.2f;   // 0.12 left the highway a dull dark band; 0.2 reflects lamps and towers, still clearly dry

        public void Setup(Transform cam, bool? force = null)
        {
            follow = cam;
            Raining = force ?? true;   // always raining unless -dry
            amount = Raining ? 1f : 0f;
            Wetness = wetNow = Raining ? 1f : 0f;
            if (!rain) MakeRain();
            ApplyRoad();
        }

        void MakeRain()
        {
            // near layer: thin soft streaks round the camera; far layer: fainter, wider, so the rain has depth
            rain = RainLayer("Rain", new Vector3(36, 1, 36), 0.018f, 1f, new Color(0.8f, 0.84f, 0.92f, 0.17f), GfxSetup.IsMobile ? 900 : 1600);
            rainFar = RainLayer("RainFar", new Vector3(110, 1, 110), 0.04f, 1.6f, new Color(0.7f, 0.74f, 0.85f, 0.08f), GfxSetup.IsMobile ? 900 : 1800);
            // splashes: tiny flat rings popping on the road round the car
            var go = new GameObject("RainSplash");
            go.transform.SetParent(transform, false);
            splash = go.AddComponent<ParticleSystem>();
            splash.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = splash.main;
            main.startLifetime = 0.28f; main.startSpeed = 0f;
            main.startSize = new ParticleSystem.MinMaxCurve(0.12f, 0.35f);
            main.startColor = new Color(0.85f, 0.88f, 0.95f, 0.4f);
            main.maxParticles = GfxSetup.IsMobile ? 300 : 600; main.simulationSpace = ParticleSystemSimulationSpace.World;
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
            amount = Mathf.MoveTowards(amount, Raining ? 1f : 0f, Time.deltaTime / 4f);
            wetNow = Mathf.MoveTowards(wetNow, Raining ? 1f : 0f, Time.deltaTime / 10f);
            Wetness = wetNow;
            Shader.SetGlobalFloat("_HMD_Wetness", Mathf.Lerp(DrySheen, 1f, wetNow));
            Shader.SetGlobalFloat("_HMD_RainAmount", amount);
            RenderSettings.fogDensity = Mathf.Lerp(0.0024f, 0.0032f, amount);   // a little mist in the light rain
            var em = rain.emission; em.rateOverTime = (GfxSetup.IsMobile ? 650f : 1100f) * amount;   // light rain: thin, not a downpour
            var ef = rainFar.emission; ef.rateOverTime = (GfxSetup.IsMobile ? 650f : 1200f) * amount;
            // no rain indoors: the workshop interior lives far away from the city (z = -3000)
            bool indoors = follow.position.z < -1500f;
            bool show = !indoors && amount > 0.01f;
            if (layers == null) layers = new[] { rain, rainFar, splash };
            foreach (var ps in layers)
                if (ps.gameObject.activeSelf != show) ps.gameObject.SetActive(show);
            if (show)
            {
                rain.transform.position = follow.position + follow.forward * 8f + Vector3.up * 14f;
                rainFar.transform.position = follow.position + follow.forward * 30f + Vector3.up * 18f;
                // splashes on the ground in front of and round the camera
                Vector3 c = follow.position + Vector3.ProjectOnPlane(follow.forward, Vector3.up).normalized * 7f;
                float gy = Physics.Raycast(c + Vector3.up * 5f, Vector3.down, out var hit, 30f) ? hit.point.y : follow.position.y - 1.5f;
                splash.transform.position = new Vector3(c.x, gy + 0.04f, c.z);
                var es = splash.emission; es.rateOverTime = (GfxSetup.IsMobile ? 350f : 700f) * amount * wetNow;
            }
        }
    }
}
