// UI image that fades out towards the edge of a circle (the minimap): fully see-through at the rim, mostly solid in
// the middle, so the map blends into the street like the see-through dial faces. _Center and _Radius are in screen
// pixels and are set every frame by Minimap.cs.
Shader "HMD/UIRadialFade"
{
    Properties
    {
        [PerRendererData] _MainTex ("Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)
        _Center ("Centre (px)", Vector) = (0,0,0,0)
        _Radius ("Radius (px)", Float) = 150
        _Inner ("Fade starts (0..1 of radius)", Float) = 0.45
        _MaxAlpha ("Alpha in the middle", Float) = 0.85
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent" "CanUseSpriteAtlas"="True" }
        Cull Off Lighting Off ZWrite Off ZTest [unity_GUIZTestMode]
        Blend SrcAlpha OneMinusSrcAlpha
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex; float4 _MainTex_ST;
            fixed4 _Color; float4 _Center; float _Radius, _Inner, _MaxAlpha;
            struct a2v { float4 vertex : POSITION; float4 color : COLOR; float2 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; fixed4 color : COLOR; float2 uv : TEXCOORD0; };
            v2f vert(a2v i) { v2f o; o.pos = UnityObjectToClipPos(i.vertex); o.uv = TRANSFORM_TEX(i.uv, _MainTex); o.color = i.color * _Color; return o; }
            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 c = tex2D(_MainTex, i.uv) * i.color;
                float2 p = i.pos.xy;
                #if UNITY_UV_STARTS_AT_TOP
                if (_ProjectionParams.x < 0) p.y = _ScreenParams.y - p.y;
                #endif
                float d = distance(p, _Center.xy) / max(1.0, _Radius);
                c.a *= _MaxAlpha * (1.0 - smoothstep(_Inner, 1.0, d));
                return c;
            }
            ENDCG
        }
    }
}
