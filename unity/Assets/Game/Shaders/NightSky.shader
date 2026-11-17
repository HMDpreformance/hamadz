// Night sky for the city: deep blue zenith, a warm orange-pink glow of city light near the horizon,
// slow drifting cloud layers lit from below by that glow, and a few twinkling stars between the clouds.
// Procedural, so there is no texture to load and it costs one pass.
Shader "HMD/NightSky"
{
    Properties
    {
        _Zenith ("Zenith", Color) = (0.008, 0.012, 0.045, 1)
        _Horizon ("Horizon", Color) = (0.07, 0.055, 0.12, 1)
        _Glow ("City glow", Color) = (0.42, 0.2, 0.16, 1)
        _CloudDark ("Cloud dark", Color) = (0.05, 0.05, 0.085, 1)
        _CloudLit ("Cloud lit from below", Color) = (0.36, 0.19, 0.19, 1)
        _Cover ("Cloud cover", Range(0, 1)) = 0.52
        _Stars ("Stars", Range(0, 3)) = 1.2
        _Exposure ("Exposure", Range(0, 4)) = 1
    }
    SubShader
    {
        Tags { "Queue" = "Background" "RenderType" = "Background" "PreviewType" = "Skybox" "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
            float4 _Zenith, _Horizon, _Glow, _CloudDark, _CloudLit;
            float _Cover, _Stars, _Exposure;
            CBUFFER_END

            struct A { float4 pos : POSITION; };
            struct V { float4 pos : SV_POSITION; float3 dir : TEXCOORD0; };

            V vert(A i)
            {
                V o;
                o.pos = TransformObjectToHClip(i.pos.xyz);
                o.dir = i.pos.xyz;
                return o;
            }

            float hash(float2 p) { p = frac(p * float2(233.34, 851.73)); p += dot(p, p + 23.45); return frac(p.x * p.y); }
            float hash3(float3 p) { p = frac(p * 0.3183099 + 0.1); p *= 17.0; return frac(p.x * p.y * p.z * (p.x + p.y + p.z)); }
            float noise(float2 p)
            {
                float2 i = floor(p), f = frac(p);
                f = f * f * (3 - 2 * f);
                return lerp(lerp(hash(i), hash(i + float2(1, 0)), f.x), lerp(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y);
            }
            float fbm(float2 p)
            {
                float v = 0, a = 0.5;
                [unroll] for (int k = 0; k < 5; k++) { v += a * noise(p); p = p * 2.03 + 17.1; a *= 0.5; }
                return v;
            }

            half4 frag(V i) : SV_Target
            {
                float3 d = normalize(i.dir);
                float h = d.y;
                float up = saturate(h);

                // base gradient + city glow hugging the horizon
                float3 col = lerp(_Horizon.rgb, _Zenith.rgb, pow(up, 0.45));
                float glow = exp(-up * 9.0) * (h > -0.05 ? 1 : 0);
                col += _Glow.rgb * glow;

                // stars (above the haze only)
                float3 sp = d * 220.0;
                float3 cell = floor(sp);
                float s = hash3(cell);
                float3 fr = frac(sp) - 0.5;
                float star = step(0.9965, s) * saturate(1 - length(fr) * 3.2);
                star *= 0.6 + 0.4 * sin(_Time.y * (2 + s * 5) + s * 40);
                col += star * _Stars * smoothstep(0.08, 0.35, up);

                // two cloud layers projected on a high plane, drifting slowly
                float2 uv = d.xz / (h + 0.12);
                float t = _Time.y;
                float c1 = fbm(uv * 0.55 + float2(t * 0.006, t * 0.002));
                float c2 = fbm(uv * 1.4 - float2(t * 0.004, -t * 0.003) + 31.7);
                float dens = saturate((c1 * 0.7 + c2 * 0.45) - (1.05 - _Cover));
                dens = smoothstep(0.0, 0.25, dens) * smoothstep(0.0, 0.12, h);
                // lit from below by the city: brighter and warmer towards the horizon, thin edges glow more
                float lit = exp(-up * 2.2) * 0.8 + 0.25;
                float3 cloud = lerp(_CloudDark.rgb, _CloudLit.rgb, lit) * (0.75 + 0.5 * (1 - dens));
                col = lerp(col, cloud, dens * 0.95);

                // below the horizon: dark city haze (mostly hidden by the ground)
                col = lerp(col, _Horizon.rgb * 0.6 + _Glow.rgb * 0.25, saturate(-h * 8));
                return half4(col * _Exposure, 1);
            }
            ENDHLSL
        }
    }
    Fallback Off
}
