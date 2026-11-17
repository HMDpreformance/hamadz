using UnityEngine;
using UnityEngine.Rendering;
#if HMD_URP
using UnityEngine.Rendering.Universal;
#endif

namespace HMD
{
    /// <summary>
    /// The look: night sky, moonlight with soft shadows, purple-blue haze, a reflection probe that
    /// follows the camera (neon and lamps reflect in paint and on the road), HDR bloom, filmic tone
    /// mapping, a little vignette and colour grading. Phones run at 60 fps with a render scale picked
    /// for the device; PCs get full resolution and more shadow distance.
    /// </summary>
    public class GfxSetup : MonoBehaviour
    {
        public static bool IsMobile => Application.isMobilePlatform;
        ReflectionProbe probe;
        Transform follow;
        int probeFrame;

        public void Setup(Camera cam)
        {
            Application.targetFrameRate = 60;
            QualitySettings.vSyncCount = 0;
            Screen.sleepTimeout = SleepTimeout.NeverSleep;

            // sky + ambient
            var nightSky = Res.Load<Material>("Mats/NightSky");
            var skyMat = Res.Load<Material>("Mats/Sky");
            if (nightSky != null && nightSky.shader.isSupported)
            {
                // procedural night: clouds lit by the city glow, stars, warm horizon
                var ns = new Material(nightSky);
                ns.SetFloat("_Exposure", 2.6f);
                ns.SetFloat("_Cover", 0.6f);
                RenderSettings.skybox = ns;
                cam.clearFlags = CameraClearFlags.Skybox;
            }
            else if (skyMat != null)
            {
                var sky = new Material(skyMat);
                sky.SetFloat("_Exposure", 0.26f);   // deep night, not dusk
                sky.SetColor("_Tint", new Color(0.36f, 0.4f, 0.7f));
                RenderSettings.skybox = sky;
                cam.clearFlags = CameraClearFlags.Skybox;
            }
            else
            {
                cam.clearFlags = CameraClearFlags.SolidColor;
                cam.backgroundColor = new Color(0.03f, 0.035f, 0.07f);
            }
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.27f, 0.3f, 0.46f);
            RenderSettings.ambientEquatorColor = new Color(0.32f, 0.26f, 0.32f);
            RenderSettings.ambientGroundColor = new Color(0.15f, 0.13f, 0.15f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.ExponentialSquared;
            RenderSettings.fogColor = new Color(0.085f, 0.08f, 0.15f);
            RenderSettings.fogDensity = Weather.Raining ? 0.0042f : 0.0024f;
            RenderSettings.defaultReflectionMode = DefaultReflectionMode.Custom;

            // moon
            var moon = new GameObject("Moon").AddComponent<Light>();
            moon.transform.SetParent(transform, false);
            moon.type = LightType.Directional;
            moon.transform.rotation = Quaternion.Euler(52, -35, 0);
            moon.color = new Color(0.55f, 0.62f, 0.85f);
            moon.intensity = 0.9f;
            moon.shadows = LightShadows.Soft;
            moon.shadowStrength = 0.75f;
            RenderSettings.sun = moon;

            QualitySettings.shadowDistance = IsMobile ? 45f : 110f;
            QualitySettings.pixelLightCount = IsMobile ? 6 : 16;
            QualitySettings.lodBias = IsMobile ? 1f : 2f;

            // reflections: one realtime probe around the camera, updated a face at a time
            probe = new GameObject("CamProbe").AddComponent<ReflectionProbe>();
            probe.transform.SetParent(transform, false);
            probe.mode = ReflectionProbeMode.Realtime;
            probe.refreshMode = ReflectionProbeRefreshMode.ViaScripting;
            probe.timeSlicingMode = ReflectionProbeTimeSlicingMode.IndividualFaces;
            probe.resolution = IsMobile ? 64 : 256;
            probe.size = new Vector3(400, 200, 400);
            probe.boxProjection = false;
            probe.farClipPlane = 300f;
            probe.importance = 1;
            probe.hdr = true;
            follow = cam.transform;

            cam.allowHDR = true;
            cam.allowMSAA = !IsMobile;
#if HMD_URP
            var data = cam.GetUniversalAdditionalCameraData();
            data.renderPostProcessing = true;
            data.antialiasing = IsMobile ? AntialiasingMode.FastApproximateAntialiasing : AntialiasingMode.SubpixelMorphologicalAntiAliasing;
            data.renderShadows = true;
            if (GraphicsSettings.currentRenderPipeline is UniversalRenderPipelineAsset urp)
            {
                urp.renderScale = IsMobile ? PickRenderScale() : 1f;
                urp.shadowDistance = QualitySettings.shadowDistance;
                urp.supportsHDR = true;
            }
            BuildVolume();
#endif
            // the wet road mirror
            if (PlanarReflection.Wanted)
                new GameObject("PlanarReflection").AddComponent<PlanarReflection>().Setup(cam);
        }

        static float PickRenderScale()
        {
            // phones have very high-res screens: render around 900-1000 px tall, then upscale
            float h = Mathf.Min(Screen.width, Screen.height);
            return Mathf.Clamp(980f / Mathf.Max(1f, h), 0.6f, 1f);
        }

#if HMD_URP
        void BuildVolume()
        {
            var go = new GameObject("PostFX");
            go.transform.SetParent(transform, false);
            var vol = go.AddComponent<Volume>();
            vol.isGlobal = true;
            vol.priority = 1;
            var profile = ScriptableObject.CreateInstance<VolumeProfile>();
            // soft wide bloom: lights glow into the wet air without blowing out
            var bloom = profile.Add<Bloom>(true);
            bloom.intensity.Override(IsMobile ? 0.8f : 0.95f);
            bloom.threshold.Override(1.1f);
            bloom.scatter.Override(0.78f);
            bloom.tint.Override(new Color(1f, 0.93f, 0.88f));
            bloom.highQualityFiltering.Override(!IsMobile);
            var tone = profile.Add<Tonemapping>(true);
            tone.mode.Override(TonemappingMode.ACES);
            var ca = profile.Add<ColorAdjustments>(true);
            ca.postExposure.Override(0.7f);
            ca.contrast.Override(18f);
            ca.saturation.Override(12f);
            // street-racer night grade: teal shadows, warm orange highlights
            var split = profile.Add<SplitToning>(true);
            nightGrade = split;
            split.shadows.Override(new Color(0.18f, 0.48f, 0.55f));
            split.highlights.Override(new Color(0.85f, 0.55f, 0.3f));
            split.balance.Override(-15f);
            var smh = profile.Add<ShadowsMidtonesHighlights>(true);
            smh.shadows.Override(new Vector4(0.92f, 1.0f, 1.08f, 0f));
            smh.highlights.Override(new Vector4(1.06f, 1.0f, 0.94f, 0f));
            var wb = profile.Add<WhiteBalance>(true);
            wb.temperature.Override(-4f);
            wb.tint.Override(4f);
            var vig = profile.Add<Vignette>(true);
            vig.intensity.Override(0.32f);
            vig.smoothness.Override(0.5f);
            if (!IsMobile)
            {
                var ab = profile.Add<ChromaticAberration>(true);
                ab.intensity.Override(0.05f);
                // no motion blur: URP only has camera-only blur, which smears the player car (it moves with the camera)
                var grain = profile.Add<FilmGrain>(true);
                grain.type.Override(FilmGrainLookup.Thin1);
                grain.intensity.Override(0.12f);
                grain.response.Override(0.85f);
            }
            vol.sharedProfile = profile;
        }
#endif

        void LateUpdate()
        {
            if (probe == null || follow == null) return;
            probe.transform.position = follow.position + Vector3.up * 1.5f;
            // refresh a full probe every few frames (time-sliced faces keep it cheap)
            if (++probeFrame % (IsMobile ? 6 : 2) == 0) probe.RenderProbe();
        }

#if HMD_URP
        SplitToning nightGrade;
#endif
        public void SetProbeActive(bool v)
        {
            if (probe) probe.gameObject.SetActive(v);
#if HMD_URP
            if (nightGrade != null) nightGrade.active = v;   // teal/orange street grade outside, neutral white light in the workshop
#endif
            if (PlanarReflection.I) PlanarReflection.I.SetActive(v);   // no road mirror needed inside the workshop
        }
    }
}
