Shader "Custom/CityClip"
{
    Properties
    {
        _BaseMap ("Albedo (A = alpha)", 2D) = "white" {}
        _BaseColor ("Color", Color) = (1,1,1,1)
        _Opacity ("Opacity", Range(0,1)) = 1
        [Toggle(_ALPHATEST_ON)] _AlphaClip ("Alpha Clipping (cutout)", Float) = 0
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull Mode", Float) = 2

        // Driven by CityClipShaderGUI (Surface Type dropdown)
        [HideInInspector] _Surface ("Surface", Float) = 0
        [HideInInspector] _SrcBlend ("Src Blend", Float) = 1
        [HideInInspector] _DstBlend ("Dst Blend", Float) = 0
        [HideInInspector] _ZWrite ("ZWrite", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _Opacity;
            half   _Cutoff;
            half   _Surface;
        CBUFFER_END

        // ---- Global parameters (set from CityClipController) ----
        float4 _MagicCenter;
        float4 _MagicHalfSize;
        float  _MagicCorner;
        float  _MagicWaveAmp;
        float  _MagicWaveFreq;
        float  _MagicWaveSpeed;
        float  _MagicEdgeWidth;
        float4 _MagicEdgeColor;
        float  _MagicEdgeIntensity;

        float Hash21(float2 p)
        {
            p = frac(p * float2(123.34, 456.21));
            p += dot(p, p + 45.32);
            return frac(p.x * p.y);
        }

        float ValueNoise(float2 p)
        {
            float2 i = floor(p);
            float2 f = frac(p);
            f = f * f * (3.0 - 2.0 * f);
            float a = Hash21(i);
            float b = Hash21(i + float2(1, 0));
            float c = Hash21(i + float2(0, 1));
            float d = Hash21(i + float2(1, 1));
            return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
        }

        // < 0 inside (visible), > 0 outside (clipped)
        float MagicDistance(float3 positionWS)
        {
            // No controller running or mask released -> don't clip anything
            if (_MagicHalfSize.x <= 0.0001) return -1000.0;

            float2 p = positionWS.xz - _MagicCenter.xz;

            float2 q = abs(p) - (_MagicHalfSize.xy - _MagicCorner);
            float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - _MagicCorner;

            float t = _Time.y * _MagicWaveSpeed;
            float n  = ValueNoise(p * _MagicWaveFreq + t) * 2.0 - 1.0;
            n += (ValueNoise(p * _MagicWaveFreq * 2.3 - t * 1.3) * 2.0 - 1.0) * 0.5;
            float w = sin((p.x + p.y) * _MagicWaveFreq * 1.5 + t * 2.0) * 0.5;

            return d + (n + w) * _MagicWaveAmp;
        }

        // Texture alpha * color alpha * opacity slider
        half SurfaceAlpha(float2 uv)
        {
            return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv).a * _BaseColor.a * _Opacity;
        }
        ENDHLSL

        // ===================== Main lit pass =====================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(OUT.positionWS);
                OUT.normalWS   = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv         = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float d = MagicDistance(IN.positionWS);
                clip(-d);

                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                half alpha = tex.a * _Opacity;

            #if defined(_ALPHATEST_ON)
                clip(alpha - _Cutoff);
            #endif

                // Flip the normal on back faces so double-sided lighting is correct
                float3 n = normalize(IN.normalWS);
                n *= IS_FRONT_VFACE(facing, 1.0, -1.0);

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                half3 lighting = mainLight.color * saturate(dot(n, mainLight.direction))
                                 * mainLight.shadowAttenuation;
                lighting += SampleSH(n);

                half3 col = tex.rgb * lighting;

                // Glowing band hugging the cut edge
                float edge = saturate(1.0 + d / max(_MagicEdgeWidth, 1e-4));
                edge = pow(edge, 3.0);
                col += _MagicEdgeColor.rgb * edge * _MagicEdgeIntensity;

                // Opaque: alpha is irrelevant. Transparent: keep the glow band visible.
                half outAlpha = _Surface > 0.5 ? saturate(alpha + edge) : 1.0h;
                return half4(col, outAlpha);
            }
            ENDHLSL
        }

        // ===================== Shadow caster =====================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float2 uv         : TEXCOORD1;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float3 posWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 nWS   = TransformObjectToWorldNormal(IN.normalOS);

            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDir = normalize(_LightPosition - posWS);
            #else
                float3 lightDir = _LightDirection;
            #endif

                float4 posCS = TransformWorldToHClip(ApplyShadowBias(posWS, nWS, lightDir));
            #if UNITY_REVERSED_Z
                posCS.z = min(posCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                posCS.z = max(posCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                OUT.positionCS = posCS;
                OUT.positionWS = posWS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                clip(-MagicDistance(IN.positionWS));
            #if defined(_ALPHATEST_ON)
                clip(SurfaceAlpha(IN.uv) - _Cutoff);
            #endif
                return 0;
            }
            ENDHLSL
        }

        // ===================== Depth only =====================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ColorMask 0
            ZWrite On
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _ALPHATEST_ON

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float2 uv         : TEXCOORD1;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(OUT.positionWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                clip(-MagicDistance(IN.positionWS));
            #if defined(_ALPHATEST_ON)
                clip(SurfaceAlpha(IN.uv) - _Cutoff);
            #endif
                return 0;
            }
            ENDHLSL
        }
    }

    CustomEditor "CityClipShaderGUI"
}
