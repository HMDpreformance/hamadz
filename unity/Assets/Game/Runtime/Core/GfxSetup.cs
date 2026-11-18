using UnityEngine;
using UnityEngine.Rendering;
#if HMD_URP
using UnityEngine.Rendering.Universal;
#endif

namespace HMD
{
    /// <summary>The command line, read once. System.Environment.CommandLine joins the arguments into a new string on every
    /// call, so asking it every frame made garbage each frame (GC pauses on phones).</summary>
    public static class Cmd
    {
        static string line;
        public static string Line => line ??= System.Environment.CommandLine;
        public static bool Has(string flag) => Line.Contains(flag);
    }

    /// <summary>
    /// The look: night sky, moonlight with soft shadows, purple-blue haze, a reflection probe that
    /// follows the camera (neon and lamps reflect in paint and on the road), HDR bloom, filmic tone
    /// mapping, a little vignette and colour grading. Phones run at 60 fps with a render scale picked
    /// for the device; PCs get full resolution and more shadow distance.
    /// </summary>
    public class GfxSetup : MonoBehaviour
    {
        /// <summary>Phone settings. -mobile on the command line (or ForceMobile in the Editor) runs the exact phone path
        /// on a PC, to measure and look at it without a phone.</summary>
        public static bool IsMobile => ForceMobile || (isMobile ??= Application.isMobilePlatform || Cmd.Has("-mobile")
            || (Application.isEditor && PlayerPrefs.GetInt("hmd_mobile", 0) == 1));   // Editor: survives the Play-mode reload
        static bool? isMobile;   // worked out once: many scripts ask every frame (the command line is rebuilt as a new string per call)
        public static bool ForceMobile;
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
                // Dubai at night: a deep blue sky with a soft orange city glow low on the horizon, not a red sunset band
                ns.SetColor("_Zenith", new Color(0.006f, 0.012f, 0.05f));
                ns.SetColor("_Horizon", new Color(0.04f, 0.055f, 0.12f));
                ns.SetColor("_Glow", new Color(0.26f, 0.14f, 0.08f));
                ns.SetColor("_CloudDark", new Color(0.05f, 0.06f, 0.1f));
                ns.SetColor("_CloudLit", new Color(0.22f, 0.17f, 0.2f));
                RenderSettings.skybox = ns;
                sky = ns;
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
            // near-neutral night ambient: the strong blue tinted every road and pavement navy; the sky itself stays blue
            RenderSettings.ambientSkyColor = new Color(0.24f, 0.25f, 0.31f);
            RenderSettings.ambientEquatorColor = new Color(0.28f, 0.25f, 0.25f);
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
            moon.color = new Color(0.6f, 0.64f, 0.74f);   // pale moonlight, much less blue (roads read neutral grey)
            moon.intensity = 0.9f;
            // no moon shadows: in a lit city at night they add little, cost frame time, and one stray soft shadow
            // showed as a dark blob on a Business Bay road
            moon.shadows = LightShadows.None;
            moon.shadowStrength = 0.75f;
            RenderSettings.sun = moon;

            QualitySettings.shadowDistance = IsMobile ? 45f : 110f;
            QualitySettings.pixelLightCount = IsMobile ? 6 : 16;
            QualitySettings.lodBias = IsMobile ? 1f : 2f;
            // Mesh LODs (MeshLodStore): how much screen-space error a coarser level may have before the renderer keeps the
            // finer one. Phones: 4 (measured at Marina: 6.3M -> 2.3M triangles a frame; a pixel diff against 1 shows the
            // towers, palms and car unchanged, only rain and far haze noise, like two shots at the same setting).
            QualitySettings.meshLodThreshold = IsMobile ? 4f : 1f;

            // reflections: one realtime probe around the camera, updated a face at a time
            probe = new GameObject("CamProbe").AddComponent<ReflectionProbe>();
            probe.transform.SetParent(transform, false);
            probe.mode = ReflectionProbeMode.Realtime;
            probe.refreshMode = ReflectionProbeRefreshMode.ViaScripting;
            probe.timeSlicingMode = ReflectionProbeTimeSlicingMode.IndividualFaces;
            probe.resolution = IsMobile ? 64 : 256;
            probe.size = new Vector3(400, 200, 400);
            probe.boxProjection = false;
            probe.farClipPlane = IsMobile ? 150f : 300f;   // phones: only the nearby street in the paint reflections
            probe.importance = 1;
            probe.hdr = true;
            follow = cam.transform;

            // phones: the night haze (exp2, 0.0024) has fully covered everything by about 1.3 km, so draw no further
            if (IsMobile) cam.farClipPlane = Mathf.Min(cam.farClipPlane, 1600f);
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
            mainCam = cam;
            ssao = FindFeature("SSAO");
            RenderPipelineManager.beginCameraRendering += OnBeginCamera;
            RenderPipelineManager.endCameraRendering += OnEndCamera;
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
            // lamps, signs and lit windows are well above 1 (HDR): a threshold of 1 lets them bloom hard while lit
            // walls and road (below 1) stay crisp; less scatter keeps the glow round the light instead of a wash
            bloom.intensity.Override(IsMobile ? 0.9f : 1.15f);
            bloom.threshold.Override(1.0f);
            bloom.scatter.Override(0.66f);
            bloom.tint.Override(new Color(1f, 0.93f, 0.88f));
            bloom.highQualityFiltering.Override(!IsMobile);
            var tone = profile.Add<Tonemapping>(true);
            tone.mode.Override(TonemappingMode.ACES);
            var ca = profile.Add<ColorAdjustments>(true);
            ca.postExposure.Override(0.6f);
            ca.contrast.Override(26f);
            ca.saturation.Override(12f);
            // street-racer night grade: teal shadows, warm orange highlights
            var split = profile.Add<SplitToning>(true);
            nightGrade = split;
            split.shadows.Override(new Color(0.34f, 0.44f, 0.48f));   // a hint of teal in the shadows, not a navy wash
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

        Material sky;
        /// <summary>Where the sky glows most (the Downtown towers); set by the game once the city is built.</summary>
        public static Vector3? SkyGlowCentre;

        void LateUpdate()
        {
            if (sky != null && follow != null)
            {
                if (SkyGlowCentre.HasValue)
                {
                    var d = SkyGlowCentre.Value - follow.position;
                    // strongest from outside Downtown; standing among the towers the whole horizon glows a little
                    float dist = new Vector2(d.x, d.z).magnitude;
                    sky.SetVector("_GlowDir", new Vector4(d.x, 0, d.z, 0));
                    sky.SetFloat("_GlowBoost", Mathf.Lerp(0.4f, 1.1f, Mathf.InverseLerp(150f, 900f, dist)));
                }
                else sky.SetFloat("_GlowBoost", 0f);
            }
            if (probe == null || follow == null) return;
            if (!IsMobile)
            {
                probe.transform.position = follow.position + Vector3.up * 1.5f;
                if (++probeFrame % 2 == 0) probe.RenderProbe();
                return;
            }
            // phones: the probe sees the street round the camera, which only changes when the camera moves. Re-render it
            // when the camera has moved ProbeStep metres (at speed that is as often as before: every 12 frames was ~11 m
            // at 100 km/h and 30 fps), or every few seconds when standing (lights and traffic still change). One render
            // at a time: a new render is only started once the time-sliced one before it has finished.
            if (!probe.isActiveAndEnabled) { probeRender = 0; probeAt = new Vector3(1e6f, 0, 0); return; }   // workshop: redo on the way out
            if (probeRender != 0 && !probe.IsFinishedRendering(probeRender)) return;
            float moved = (follow.position - probeAt).sqrMagnitude;
            probeIdle += Time.deltaTime;
            if (moved < ProbeStep * ProbeStep && probeIdle < 4f) return;
            probe.transform.position = follow.position + Vector3.up * 1.5f;
            probeAt = follow.position; probeIdle = 0f;
            probeRender = probe.RenderProbe();
        }

        const float ProbeStep = 11f;
        Vector3 probeAt = new Vector3(1e6f, 0, 0);
        float probeIdle;
        int probeRender;

#if HMD_URP
        // SSAO (DepthNormals prepass + full-screen AO) only for the main view. The road mirror (a fifth of the
        // resolution, blurred) and the paint probe (64 px) cannot show AO, but each paid a full extra geometry pass for it.
        ScriptableRendererFeature ssao;
        Camera mainCam;
        float lodBiasMain, meshLodMain;
        void OnBeginCamera(ScriptableRenderContext ctx, Camera cam)
        {
            if (ssao != null) ssao.SetActive(cam == mainCam && !PerfProbe.SsaoOff);
            if (cam == mainCam) return;
            // mirror and probe: coarser mesh LODs (same textures and glow; both are drawn small and soft)
            if (cam.cameraType == CameraType.Reflection || (PlanarReflection.I && PlanarReflection.I.IsCamera(cam)))
            {
                lodBiasMain = QualitySettings.lodBias; meshLodMain = QualitySettings.meshLodThreshold;
                QualitySettings.lodBias = lodBiasMain * 0.7f;
                QualitySettings.meshLodThreshold = meshLodMain * 4f;
                lodPushed = true;
            }
        }
        bool lodPushed;
        void OnEndCamera(ScriptableRenderContext ctx, Camera cam)
        {
            if (!lodPushed) return;
            lodPushed = false;
            QualitySettings.lodBias = lodBiasMain; QualitySettings.meshLodThreshold = meshLodMain;
        }
        void OnDestroy()
        {
            RenderPipelineManager.beginCameraRendering -= OnBeginCamera;
            RenderPipelineManager.endCameraRendering -= OnEndCamera;
            if (ssao != null) ssao.SetActive(true);
        }

        static ScriptableRendererFeature FindFeature(string name)
        {
            if (!(GraphicsSettings.currentRenderPipeline is UniversalRenderPipelineAsset u)) return null;
            foreach (var d in u.rendererDataList)
                if (d != null) foreach (var f in d.rendererFeatures) if (f != null && f.name == name) return f;
            return null;
        }
#endif

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
