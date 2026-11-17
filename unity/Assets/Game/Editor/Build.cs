using System.IO;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
#if HMD_URP
using UnityEngine.Rendering.Universal;
#endif

namespace HMD.EditorTools
{
    /// <summary>
    /// One-click (or command-line) project setup and builds:
    ///   Unity.exe -batchmode -quit -projectPath unity -executeMethod HMD.EditorTools.Build.Setup
    ///   ... -executeMethod HMD.EditorTools.Build.Windows   (Builds/Win/HMDNightClub.exe)
    ///   ... -executeMethod HMD.EditorTools.Build.Android   (Builds/Android/HMDnightClub-v2.0-b&lt;n&gt;.apk)
    /// Setup copies the game's art and sound from the repo root into Assets/Resources/Imported,
    /// sets the importers, makes the URP pipeline, template materials, the player settings and the scene.
    /// </summary>
    public static class Build
    {
        const string Imp = "Assets/Resources/Imported";
        const string ScenePath = "Assets/Scenes/Main.unity";
        static string RepoRoot => Path.GetFullPath(Path.Combine(Application.dataPath, "..", ".."));

        [MenuItem("HMD/Setup Project")]
        public static void Setup()
        {
            CopyAssets();
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
            FixImporters();
            MakeMetalSmooth();
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
            MakePipeline();
            MakeMaterials();
            PlayerSetup();
            MakeScene();
            AssetDatabase.SaveAssets();
            Debug.Log("[HMD] Setup done");
        }

        // ---------------------------------------------------------------- assets
        static void CopyDir(string from, string to, params string[] patterns)
        {
            from = Path.Combine(RepoRoot, from);
            if (!Directory.Exists(from)) { Debug.LogWarning("[HMD] missing " + from); return; }
            to = Path.Combine(Application.dataPath, "..", to);
            Directory.CreateDirectory(to);
            foreach (var pat in patterns)
                foreach (var f in Directory.GetFiles(from, pat))
                {
                    var dst = Path.Combine(to, Path.GetFileName(f));
                    if (!File.Exists(dst) || new FileInfo(dst).Length != new FileInfo(f).Length) File.Copy(f, dst, true);
                }
        }

        static void CopyAssets()
        {
            CopyDir("unity_cars", Imp + "/Cars", "*.glb", "*_cfg.json");
            CopyDir("w3d/tex", Imp + "/Tex", "*_diff.jpg", "*_nor.jpg", "*_arm.jpg");
            CopyDir("w3d/facade", Imp + "/Facade", "*.jpg");
            CopyDir("w3d/gen", Imp + "/Gen", "*.jpg", "*.png");
            CopyDir("w3d/sky", Imp + "/Sky", "*.hdr");
            CopyDir("unity_assets/tower", Imp + "/Tower", "*.jpg");
            CopyDir("unity_assets/gen", Imp + "/Gen", "*.jpg", "*.png");
            CopyDir("unity_assets/props", Imp + "/Props", "*.glb");
            CopyDir("unity_assets/city", Imp + "/City", "city_part1.glb", "city_part1.json", "map_full.jpg", "map_base.jpg");
            CopyDir("audio/engines", Imp + "/Audio/engines", "*.wav");
            CopyDir("audio/car", Imp + "/Audio/car", "*.wav");
            CopyDir("audio/music", Imp + "/Audio/music", "*.ogg");
            CopyDir("audio", Imp + "/Audio", "*.wav", "*.ogg");
            CopyDir("fonts", Imp + "/Fonts", "*.ttf");
            CopyDir("unity/Assets/Art", Imp + "/Art", "*.png", "*.jpg");
        }

        static void FixImporters()
        {
            foreach (var guid in AssetDatabase.FindAssets("t:Texture", new[] { Imp }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                if (!(AssetImporter.GetAtPath(path) is TextureImporter ti)) continue;
                bool changed = false;
                string name = Path.GetFileNameWithoutExtension(path);
                if (name.EndsWith("_nor") && ti.textureType != TextureImporterType.NormalMap) { ti.textureType = TextureImporterType.NormalMap; changed = true; }
                if ((name.EndsWith("_arm") || name.EndsWith("_ms")) && ti.sRGBTexture) { ti.sRGBTexture = false; changed = true; }
                if (name.EndsWith("_arm") && !ti.isReadable) { ti.isReadable = true; changed = true; }
                if (path.Contains("/Sky/") && ti.textureShape != TextureImporterShape.TextureCube)
                {
                    ti.textureShape = TextureImporterShape.TextureCube;
                    ti.generateCubemap = TextureImporterGenerateCubemap.AutoCubemap;
                    changed = true;
                }
                if ((path.Contains("/Art/") || name == "frond" || name.StartsWith("lsx")) && !ti.alphaIsTransparency) { ti.alphaIsTransparency = true; changed = true; }
                if (ti.maxTextureSize != 2048) { ti.maxTextureSize = 2048; changed = true; }
                bool gauge = name.StartsWith("gauge_");
                if (gauge)
                {
                    // HUD dials: full quality, no mips, clean alpha edges
                    if (ti.mipmapEnabled) { ti.mipmapEnabled = false; changed = true; }
                    if (ti.textureCompression != TextureImporterCompression.Uncompressed) { ti.textureCompression = TextureImporterCompression.Uncompressed; changed = true; }
                    if (!ti.alphaIsTransparency) { ti.alphaIsTransparency = true; changed = true; }
                    if (!ti.sRGBTexture) { ti.sRGBTexture = true; changed = true; }
                    if (ti.filterMode != FilterMode.Bilinear) { ti.filterMode = FilterMode.Bilinear; changed = true; }
                }
                else if (ti.mipmapEnabled == false && !path.Contains("/Art/")) { ti.mipmapEnabled = true; changed = true; }
                if (ti.anisoLevel < 4) { ti.anisoLevel = 8; changed = true; }
                if (changed) ti.SaveAndReimport();
            }
            foreach (var guid in AssetDatabase.FindAssets("t:AudioClip", new[] { Imp }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                if (!(AssetImporter.GetAtPath(path) is AudioImporter ai)) continue;
                var s = ai.defaultSampleSettings;
                bool music = path.Contains("/music/");
                var load = music ? AudioClipLoadType.Streaming : AudioClipLoadType.DecompressOnLoad;
                float q = music ? 0.6f : 0.85f;
                // only reimport when something changed (re-encoding every clip made each build slow)
                if (s.loadType == load && s.compressionFormat == AudioCompressionFormat.Vorbis && Mathf.Abs(s.quality - q) < 0.001f) continue;
                s.loadType = load;
                s.compressionFormat = AudioCompressionFormat.Vorbis;
                s.quality = q;
                ai.defaultSampleSettings = s;
                ai.SaveAndReimport();
            }
        }

        /// <summary>Poly Haven ARM maps (R=AO, G=rough, B=metal) to URP metallic/smoothness (R=metal, A=smoothness).</summary>
        static void MakeMetalSmooth()
        {
            foreach (var guid in AssetDatabase.FindAssets("t:Texture2D", new[] { Imp + "/Tex", Imp + "/Facade" }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                if (!path.EndsWith("_arm.jpg")) continue;
                var outPath = path.Replace("_arm.jpg", "_ms.png");
                if (File.Exists(outPath)) continue;
                var src = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
                if (src == null || !src.isReadable) continue;
                int w = Mathf.Min(src.width, 1024), h = Mathf.Min(src.height, 1024);
                var rt = RenderTexture.GetTemporary(w, h, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear);
                Graphics.Blit(src, rt);
                var prev = RenderTexture.active; RenderTexture.active = rt;
                var t = new Texture2D(w, h, TextureFormat.RGBA32, false, true);
                t.ReadPixels(new Rect(0, 0, w, h), 0, 0);
                RenderTexture.active = prev; RenderTexture.ReleaseTemporary(rt);
                var px = t.GetPixels32();
                for (int i = 0; i < px.Length; i++)
                {
                    var c = px[i];
                    px[i] = new Color32(c.b, c.r, 0, (byte)(255 - c.g));
                }
                t.SetPixels32(px);
                File.WriteAllBytes(outPath, t.EncodeToPNG());
            }
        }

        // ---------------------------------------------------------------- render pipeline
        static void MakePipeline()
        {
#if HMD_URP
            const string dir = "Assets/Settings";
            Directory.CreateDirectory(dir);
            var asset = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(dir + "/HMD_URP.asset");
            if (asset == null)
            {
                ScriptableRendererData data = null;
                // URP's own "create renderer" sets up post-processing data and shaders; it is internal, so call it by reflection
                var m = typeof(UniversalRenderPipelineAsset).GetMethods(BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Public)
                    .FirstOrDefault(x => x.Name == "CreateRendererAsset");
                if (m != null)
                {
                    var ps = m.GetParameters();
                    var args = new object[ps.Length];
                    for (int i = 0; i < ps.Length; i++)
                    {
                        if (i == 0) args[i] = dir + "/HMD_Renderer.asset";
                        else if (ps[i].ParameterType.IsEnum) args[i] = System.Enum.ToObject(ps[i].ParameterType, 1); // UniversalRenderer
                        else if (ps[i].ParameterType == typeof(bool)) args[i] = false;
                        else if (ps[i].HasDefaultValue) args[i] = ps[i].DefaultValue;
                        else args[i] = null;
                    }
                    try { data = m.Invoke(null, args) as ScriptableRendererData; }
                    catch (System.Exception e) { Debug.LogWarning("[HMD] CreateRendererAsset failed: " + e.Message); }
                }
                if (data == null)
                {
                    data = ScriptableObject.CreateInstance<UniversalRendererData>();
                    AssetDatabase.CreateAsset(data, dir + "/HMD_Renderer.asset");
                }
                asset = UniversalRenderPipelineAsset.Create(data);
                AssetDatabase.CreateAsset(asset, dir + "/HMD_URP.asset");
            }
            // renderer: Forward+ so many lamp lights work
            var rd = AssetDatabase.LoadAssetAtPath<ScriptableRendererData>(dir + "/HMD_Renderer.asset");
            if (rd != null)
            {
                var so = new SerializedObject(rd);
                SetInt(so, "m_RenderingMode", 2);
                so.ApplyModifiedPropertiesWithoutUndo();
                // screen-space ambient occlusion: contact darkening under cars, kerbs, props
                if (!rd.rendererFeatures.Any(f => f is ScreenSpaceAmbientOcclusion))
                {
                    var ssao = ScriptableObject.CreateInstance<ScreenSpaceAmbientOcclusion>();
                    ssao.name = "SSAO";
                    AssetDatabase.AddObjectToAsset(ssao, rd);
                    rd.rendererFeatures.Add(ssao);
                    if (AssetDatabase.TryGetGUIDAndLocalFileIdentifier(ssao, out string _, out long localId))
                    {
                        var mapField = typeof(ScriptableRendererData).GetField("m_RendererFeatureMap", BindingFlags.NonPublic | BindingFlags.Instance);
                        if (mapField?.GetValue(rd) is System.Collections.Generic.List<long> map) map.Add(localId);
                    }
                    EditorUtility.SetDirty(rd);
                    AssetDatabase.SaveAssets();
                }
                // tune it through its serialized settings (fields are internal)
                var ssaoF = rd.rendererFeatures.FirstOrDefault(f => f is ScreenSpaceAmbientOcclusion);
                if (ssaoF != null)
                {
                    var fs = new SerializedObject(ssaoF);
                    var s = fs.FindProperty("m_Settings");
                    if (s != null)
                    {
                        var p = s.FindPropertyRelative("Intensity"); if (p != null) p.floatValue = 1.6f;
                        p = s.FindPropertyRelative("Radius"); if (p != null) p.floatValue = 0.45f;
                        p = s.FindPropertyRelative("DirectLightingStrength"); if (p != null) p.floatValue = 0.35f;
                        p = s.FindPropertyRelative("Falloff"); if (p != null) p.floatValue = 60f;
                        fs.ApplyModifiedPropertiesWithoutUndo();
                    }
                }
            }
            var sa = new SerializedObject(asset);
            SetBool(sa, "m_SupportsHDR", true);
            SetInt(sa, "m_MSAA", 1);
            SetFloat(sa, "m_RenderScale", 1f);
            SetBool(sa, "m_MainLightShadowsSupported", true);
            SetInt(sa, "m_MainLightShadowmapResolution", 2048);
            SetInt(sa, "m_AdditionalLightsRenderingMode", 1);
            SetInt(sa, "m_AdditionalLightsPerObjectLimit", 8);
            SetBool(sa, "m_AdditionalLightShadowsSupported", false);
            SetFloat(sa, "m_ShadowDistance", 80f);
            SetInt(sa, "m_ShadowCascadeCount", 2);
            SetBool(sa, "m_SoftShadowsSupported", true);
            SetBool(sa, "m_SupportsCameraDepthTexture", true);
            SetBool(sa, "m_ReflectionProbeBlending", true);
            SetBool(sa, "m_ReflectionProbeBoxProjection", true);
            SetInt(sa, "m_ColorGradingMode", 1);  // HDR grading
            sa.ApplyModifiedPropertiesWithoutUndo();
            GraphicsSettings.defaultRenderPipeline = asset;
            for (int i = 0; i < QualitySettings.names.Length; i++)
            {
                QualitySettings.SetQualityLevel(i, false);
                QualitySettings.renderPipeline = asset;
            }
            EditorUtility.SetDirty(asset);
#else
            Debug.LogWarning("[HMD] URP package is not installed; using the built-in pipeline.");
#endif
        }

        static void SetInt(SerializedObject so, string n, int v) { var p = so.FindProperty(n); if (p != null) { if (p.propertyType == SerializedPropertyType.Enum) p.enumValueIndex = v; else p.intValue = v; } }
        static void SetBool(SerializedObject so, string n, bool v) { var p = so.FindProperty(n); if (p != null) p.boolValue = v; }
        static void SetFloat(SerializedObject so, string n, float v) { var p = so.FindProperty(n); if (p != null) p.floatValue = v; }

        // ---------------------------------------------------------------- materials (templates keep shader variants in the build)
        static void MakeMaterials()
        {
            string dir = Imp + "/Mats";
            Directory.CreateDirectory(dir);
            Directory.CreateDirectory(dir + "/Variants");
            var lit = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
            var unlit = Shader.Find("Universal Render Pipeline/Unlit") ?? Shader.Find("Unlit/Texture");
            var particle = Shader.Find("Universal Render Pipeline/Particles/Unlit") ?? Shader.Find("Particles/Standard Unlit");
            Save(new Material(lit), dir + "/Lit.mat");
            Save(new Material(unlit), dir + "/Unlit.mat");

            var glass = new Material(lit);
            MakeTransparent(glass, false);
            Save(glass, dir + "/Glass.mat");

            var part = new Material(particle);
            MakeTransparent(part, true);
            Save(part, dir + "/Particle.mat");

            // wet road (planar reflections) in every keyword mix the city uses
            var wet = Shader.Find("HMD/WetRoad");
            if (wet != null)
            {
                Save(new Material(wet), dir + "/WetRoad.mat");
                string[][] wetCombos = { new[] { "_NORMALMAP" }, new[] { "_NORMALMAP", "_METALLICSPECGLOSSMAP" }, new[] { "_METALLICSPECGLOSSMAP" } };
                int wk = 0;
                foreach (var c in wetCombos)
                {
                    var m = new Material(wet);
                    foreach (var kw in c) m.EnableKeyword(kw);
                    if (c.Contains("_NORMALMAP")) m.SetTexture("_BumpMap", Texture2D.normalTexture);
                    Save(m, dir + "/Variants/Wet_" + (wk++) + ".mat");
                }
            }
            else Debug.LogWarning("[HMD] HMD/WetRoad shader not found");

            // car paint: URP Complex Lit with a clear coat layer
            var complex = Shader.Find("Universal Render Pipeline/Complex Lit");
            if (complex != null)
            {
                var paint = new Material(complex);
                paint.EnableKeyword("_CLEARCOAT"); paint.SetFloat("_ClearCoat", 1f);
                Save(paint, dir + "/Paint.mat");
                var paintN = new Material(complex);
                paintN.EnableKeyword("_CLEARCOAT"); paintN.SetFloat("_ClearCoat", 1f);
                paintN.EnableKeyword("_NORMALMAP"); paintN.SetTexture("_BumpMap", Texture2D.normalTexture);
                Save(paintN, dir + "/Variants/Paint_N.mat");
            }

            var skyTex = AssetDatabase.LoadAssetAtPath<Cubemap>(Imp + "/Sky/night_sky_2k.hdr");
            var night = Shader.Find("HMD/NightSky");
            if (night != null) Save(new Material(night), dir + "/NightSky.mat");
            var skyShader = Shader.Find("Skybox/Cubemap");
            if (skyShader != null)
            {
                var sky = new Material(skyShader);
                if (skyTex) sky.SetTexture("_Tex", skyTex);
                Save(sky, dir + "/Sky.mat");
            }

            // every keyword combination the game turns on at runtime
            string[][] combos =
            {
                new[] { "_NORMALMAP" }, new[] { "_NORMALMAP", "_METALLICSPECGLOSSMAP" }, new[] { "_EMISSION" },
                new[] { "_NORMALMAP", "_EMISSION" }, new[] { "_NORMALMAP", "_METALLICSPECGLOSSMAP", "_EMISSION" },
                new[] { "_ALPHATEST_ON" }, new[] { "_ALPHATEST_ON", "_EMISSION" }, new[] { "_ALPHATEST_ON", "_NORMALMAP" },
            };
            int k = 0;
            foreach (var c in combos)
            {
                var m = new Material(lit);
                foreach (var kw in c) m.EnableKeyword(kw);
                if (c.Contains("_ALPHATEST_ON")) m.SetFloat("_AlphaClip", 1);
                if (c.Contains("_NORMALMAP")) m.SetTexture("_BumpMap", Texture2D.normalTexture);
                if (c.Contains("_EMISSION")) m.SetColor("_EmissionColor", Color.white);
                Save(m, dir + "/Variants/Lit_" + (k++) + ".mat");
            }
        }

        static void MakeTransparent(Material m, bool additive)
        {
            m.SetFloat("_Surface", 1);
            m.SetFloat("_Blend", additive ? 2 : 0);
            m.SetFloat("_SrcBlend", additive ? (float)BlendMode.SrcAlpha : (float)BlendMode.SrcAlpha);
            m.SetFloat("_DstBlend", additive ? (float)BlendMode.One : (float)BlendMode.OneMinusSrcAlpha);
            m.SetFloat("_ZWrite", 0);
            m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            m.renderQueue = (int)RenderQueue.Transparent;
            m.SetOverrideTag("RenderType", "Transparent");
        }

        static void Save(Material m, string path)
        {
            var old = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (old != null) { EditorUtility.CopySerialized(m, old); EditorUtility.SetDirty(old); }
            else AssetDatabase.CreateAsset(m, path);
        }

        // ---------------------------------------------------------------- player + scene
        static void PlayerSetup()
        {
            PlayerSettings.companyName = "HMDperformance";
            PlayerSettings.productName = "HMD Night Club";
            PlayerSettings.bundleVersion = "2.0";
            // Windows: D3D11 first (the D3D12 driver crashed on quit with the reflection camera + SSAO), D3D12 as fallback
            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.StandaloneWindows64, false);
            PlayerSettings.SetGraphicsAPIs(BuildTarget.StandaloneWindows64, new[] { UnityEngine.Rendering.GraphicsDeviceType.Direct3D11, UnityEngine.Rendering.GraphicsDeviceType.Direct3D12 });
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, "com.redlinefoundry.hmdnightclub");
            PlayerSettings.SetScriptingBackend(BuildTargetGroup.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel26;
            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.Android, false);
            PlayerSettings.SetGraphicsAPIs(BuildTarget.Android, new[] { GraphicsDeviceType.Vulkan, GraphicsDeviceType.OpenGLES3 });
            PlayerSettings.SetMobileMTRendering(BuildTargetGroup.Android, true);
            // old + new input both on (the game reads touches through the classic Input API)
            var ps = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset").FirstOrDefault();
            if (ps != null)
            {
                var so = new SerializedObject(ps);
                var p = so.FindProperty("activeInputHandler");
                if (p != null && p.intValue == 1) { p.intValue = 2; so.ApplyModifiedPropertiesWithoutUndo(); }
            }
            // physics: more solver steps for stable WheelColliders at speed
            Time.fixedDeltaTime = 1f / 100f;
            Physics.defaultSolverIterations = 10;
        }

        static void MakeScene()
        {
            Directory.CreateDirectory("Assets/Scenes");
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var cam = new GameObject("Main Camera", typeof(Camera), typeof(AudioListener));
            cam.tag = "MainCamera";
            cam.AddComponent<CameraRig>();
            new GameObject("Game").AddComponent<Game>();
            EditorSceneManager.SaveScene(scene, ScenePath);
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        }

        // ---------------------------------------------------------------- builds
        [MenuItem("HMD/Build Windows")]
        public static void Windows()
        {
            var opts = new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = "Builds/Win/HMDNightClub.exe",
                target = BuildTarget.StandaloneWindows64,
                options = BuildOptions.None,
            };
            Report(BuildPipeline.BuildPlayer(opts));
        }

        [MenuItem("HMD/Build Android APK")]
        public static void Android()
        {
            int code = PlayerSettings.Android.bundleVersionCode + 1;
            PlayerSettings.Android.bundleVersionCode = code;
            EditorUserBuildSettings.buildAppBundle = false;
            var opts = new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = $"Builds/Android/HMDnightClub-v{PlayerSettings.bundleVersion}-b{code}.apk",
                target = BuildTarget.Android,
                options = BuildOptions.None,
            };
            Report(BuildPipeline.BuildPlayer(opts));
        }

        static void Report(BuildReport r)
        {
            Debug.Log($"[HMD] build {r.summary.result} -> {r.summary.outputPath} ({r.summary.totalSize / (1024 * 1024)} MB, {r.summary.totalErrors} errors)");
            if (Application.isBatchMode && r.summary.result != BuildResult.Succeeded) EditorApplication.Exit(1);
        }

        /// <summary>Setup + Windows build (for screenshots). Use from the command line.</summary>
        public static void SetupAndWindows() { Setup(); Windows(); }
    }
}
