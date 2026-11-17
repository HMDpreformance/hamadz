// Wet asphalt for the night city: the normal URP Lit lighting (Forward+, lamps, shadows, probes)
// plus a planar mirror of the city (rendered by PlanarReflection.cs into _HMD_PlanarTex).
// Rough asphalt blurs the mirror into long vertical streaks (neon, lamps, tail lights); puddles from
// a world-space noise mask are sharp mirrors; rain ripples bend the reflection. Wetness is global
// (_HMD_Wetness: rain 1, dry ~0.3) so one value drives every road. Same properties and cbuffer as
// URP Lit, so materials keep their textures and the SRP batcher still works.
Shader "HMD/WetRoad"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)
        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        _GlossMapScale("Smoothness Scale", Range(0.0, 1.0)) = 1.0
        _SmoothnessTextureChannel("Smoothness texture channel", Float) = 0
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _MetallicGlossMap("Metallic", 2D) = "white" {}
        _SpecColor("Specular", Color) = (0.2, 0.2, 0.2)
        _SpecGlossMap("Specular", 2D) = "white" {}
        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0
        _BumpScale("Scale", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}
        _Parallax("Scale", Range(0.005, 0.08)) = 0.005
        _ParallaxMap("Height Map", 2D) = "black" {}
        _OcclusionStrength("Strength", Range(0.0, 1.0)) = 1.0
        _OcclusionMap("Occlusion", 2D) = "white" {}
        [HDR] _EmissionColor("Color", Color) = (0,0,0)
        _EmissionMap("Emission", 2D) = "white" {}
        _DetailMask("Detail Mask", 2D) = "white" {}
        _DetailAlbedoMapScale("Scale", Range(0.0, 2.0)) = 1.0
        _DetailAlbedoMap("Detail Albedo x2", 2D) = "linearGrey" {}
        _DetailNormalMapScale("Scale", Range(0.0, 2.0)) = 1.0
        [Normal] _DetailNormalMap("Normal Map", 2D) = "bump" {}
        _ClearCoatMask("_ClearCoatMask", Float) = 0.0
        _ClearCoatSmoothness("_ClearCoatSmoothness", Float) = 0.0
        _Surface("__surface", Float) = 0.0
        _Blend("__blend", Float) = 0.0
        _Cull("__cull", Float) = 2.0
        [ToggleUI] _AlphaClip("__clip", Float) = 0.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _SrcBlendAlpha("__srcA", Float) = 1.0
        [HideInInspector] _DstBlendAlpha("__dstA", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
        [HideInInspector] _BlendModePreserveSpecular("_BlendModePreserveSpecular", Float) = 1.0
        [HideInInspector] _AlphaToMask("__alphaToMask", Float) = 0.0
        [ToggleUI] _ReceiveShadows("Receive Shadows", Float) = 1.0
        _QueueOffset("Queue offset", Float) = 0.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "UniversalMaterialType" = "Lit" "IgnoreProjector" = "True" }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex LitPassVertex
            #pragma fragment WetFragment

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_ATLAS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Fog.hlsl"
            #pragma multi_compile_instancing

            #define REQUIRES_WORLD_SPACE_POS_INTERPOLATOR
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitForwardPass.hlsl"

            // globals set from C# (not in the material cbuffer, so batching is unchanged)
            TEXTURE2D(_HMD_PlanarTex); SAMPLER(sampler_HMD_PlanarTex);
            float _HMD_PlanarOn;      // 1 when the mirror texture is valid this frame
            float _HMD_Wetness;       // 0 dry .. 1 soaked
            float _HMD_RainAmount;    // ripple strength
            float4 _HMD_Grid;         // road pitch, road centre offset, road half width, unused

            float hash21(float2 p) { p = frac(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return frac(p.x * p.y); }
            float vnoise(float2 p)
            {
                float2 i = floor(p), f = frac(p);
                f = f * f * (3 - 2 * f);
                return lerp(lerp(hash21(i), hash21(i + float2(1, 0)), f.x), lerp(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), f.x), f.y);
            }

            void WetFragment(Varyings input, out half4 outColor : SV_Target0)
            {
                UNITY_SETUP_INSTANCE_ID(input);

                SurfaceData surfaceData;
                InitializeStandardLitSurfaceData(input.uv, surfaceData);

                // puddles: large soft patches, more of them the wetter it is
                float2 wp = input.positionWS.xz;
                // small varied puddles; big mirror pools only in the gutters along the kerb and on crossings
                float n = vnoise(wp * 0.33) * 0.55 + vnoise(wp * 1.05) * 0.3 + vnoise(wp * 0.09) * 0.15;
                float pitch = max(_HMD_Grid.x, 1.0), half_ = _HMD_Grid.z;
                float2 m = wp + _HMD_Grid.y;
                m = abs(m - pitch * round(m / pitch));               // distance to the nearest road centre line, per axis
                float2 inRoad = step(m, half_);
                float2 gutter = smoothstep(3.2, 0.4, half_ - m) * inRoad;
                float spot = max(max(gutter.x, gutter.y), inRoad.x * inRoad.y * 0.75);
                float thr = lerp(0.74, 0.5, spot);
                float puddle = smoothstep(thr - 0.04, thr + 0.07, n) * _HMD_Wetness;
                float wet = saturate(_HMD_Wetness);

                // wet asphalt: darker, smoother; puddles flat and glassy
                surfaceData.albedo *= lerp(1.0, 0.55, wet) * lerp(1.0, 0.7, puddle);
                surfaceData.smoothness = lerp(surfaceData.smoothness, 0.82, wet);
                surfaceData.smoothness = lerp(surfaceData.smoothness, 0.97, puddle);
                surfaceData.normalTS = normalize(lerp(surfaceData.normalTS, half3(0, 0, 1), saturate(wet * 0.5 + puddle)));

                InputData inputData;
                InitializeInputData(input, surfaceData.normalTS, inputData);
                InitializeBakedGIData(input, inputData);

                half4 color = UniversalFragmentPBR(inputData, surfaceData);

                UNITY_BRANCH
                if (_HMD_PlanarOn > 0.5 && wet > 0.01)
                {
                    float2 suv = GetNormalizedScreenSpaceUV(input.positionCS);
                    // ripples (rain) + asphalt grain bend the mirror
                    float t = _Time.y;
                    float2 rip = float2(vnoise(wp * 7.3 + t * 2.3) - 0.5, vnoise(wp * 7.9 - t * 2.1) - 0.5) * _HMD_RainAmount;
                    float2 grain = (vnoise(wp * 9.0) - 0.5).xx;
                    float rough = 1.0 - puddle;
                    float2 off = rip * 0.0035 + grain * 0.003 * rough;
                    float2 ruv = float2(suv.x, suv.y) + off;

                    // rough road: average taps stretched vertically into streaks; puddle: one sharp tap
                    half3 refl = 0;
                    float spread = 0.06 * rough;
                    float lod = 3.6 * rough;
                    [unroll] for (int k = -3; k <= 3; k++)
                    {
                        float w = 1.0 - abs(k) / 4.0;
                        refl += SAMPLE_TEXTURE2D_LOD(_HMD_PlanarTex, sampler_HMD_PlanarTex, ruv + float2(0, k * spread / 3.0), lod).rgb * w;
                    }
                    refl /= 4.0;   // sum of weights (0.25+0.5+0.75+1+0.75+0.5+0.25)

                    float3 V = normalize(GetWorldSpaceViewDir(input.positionWS));
                    float ndv = saturate(dot(float3(0, 1, 0), V));
                    float fres = pow(1.0 - ndv, 2.0);
                    float rk = wet * lerp(0.26, 1.0, puddle) * lerp(0.3, 0.85, fres);
                    color.rgb = color.rgb * (1.0 - 0.45 * rk) + refl * rk;
                }

                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                color.a = 1;
                outColor = color;
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/SHADOWCASTER"
        UsePass "Universal Render Pipeline/Lit/DEPTHONLY"
        UsePass "Universal Render Pipeline/Lit/DEPTHNORMALS"
    }
    FallBack "Universal Render Pipeline/Lit"
}
