Shader "Custom/MapPointerBillboard"
{
    Properties
    {
        _BaseMap ("Icon (A = shape)", 2D) = "white" {}
        _BaseColor ("Tint", Color) = (1,1,1,1)

        [Header(Billboard)]
        [Toggle] _YawOnly ("Stay Upright (turn left/right only)", Float) = 1
        _AnchorY ("Anchor Y (0.5 = bottom edge sits on the pivot)", Range(-0.5, 0.5)) = 0.5
        [Toggle] _ConstantSize ("Constant Screen Size", Float) = 0
        _ScreenHeight ("Screen Height Fraction", Range(0.01, 0.3)) = 0.06

        [Header(Motion)]
        _BobAmount ("Bob Amount (x height)", Range(0, 0.5)) = 0.1
        _BobSpeed ("Bob Speed", Float) = 2

        [Header(Rendering)]
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("Depth Test (Always = on top)", Float) = 4
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.05
        [Toggle(_USE_CITY_MASK)] _UseCityMask ("Hide Outside City Mask", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "Billboard"
            Tags { "LightMode"="UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest [_ZTest]
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _USE_CITY_MASK

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                float  _YawOnly;
                float  _AnchorY;
                float  _ConstantSize;
                float  _ScreenHeight;
                float  _BobAmount;
                float  _BobSpeed;
                half   _Cutoff;
            CBUFFER_END

            // ---- City mask globals (same ones CityClipController sets) ----
            float4 _MagicCenter;
            float4 _MagicHalfSize;
            float  _MagicCorner;
            float  _MagicWaveAmp;
            float  _MagicWaveFreq;
            float  _MagicWaveSpeed;

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

            // Identical to CityClip.shader
            float MagicDistance(float3 positionWS)
            {
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

            struct Attributes
            {
                float4 positionOS : POSITION; // Unity Quad: x and y span -0.5 .. 0.5
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float  maskDist   : TEXCOORD1;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // The object's origin is the pointer's position; the quad is rebuilt around it
                float3 pivotWS = TransformObjectToWorld(float3(0, 0, 0));

                float2 scale = float2(
                    length(float3(UNITY_MATRIX_M._m00, UNITY_MATRIX_M._m10, UNITY_MATRIX_M._m20)),
                    length(float3(UNITY_MATRIX_M._m01, UNITY_MATRIX_M._m11, UNITY_MATRIX_M._m21)));

                float dist = distance(_WorldSpaceCameraPos, pivotWS);
                float2 size = scale;

                // Same on-screen size at any distance
                if (_ConstantSize > 0.5)
                {
                    float h = _ScreenHeight * 2.0 * dist / unity_CameraProjection._m11;
                    size = float2(h * scale.x / max(scale.y, 1e-5), h);
                }

                // Camera axes in world space
                float3 camRight = UNITY_MATRIX_V[0].xyz;
                float3 camUp    = UNITY_MATRIX_V[1].xyz;
                float3 right, up;
                if (_YawOnly > 0.5)
                {
                    right = normalize(float3(camRight.x, 0.0, camRight.z));
                    up    = float3(0, 1, 0);
                }
                else
                {
                    right = camRight;
                    up    = camUp;
                }

                // Little floating animation, phase-shifted per position so pins don't bob in sync
                pivotWS.y += sin(_Time.y * _BobSpeed + pivotWS.x * 3.0 + pivotWS.z * 3.0) * _BobAmount * size.y;

                float2 local = IN.positionOS.xy + float2(0.0, _AnchorY);
                float3 posWS = pivotWS + right * (local.x * size.x) + up * (local.y * size.y);

                OUT.positionCS = TransformWorldToHClip(posWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

            #if defined(_USE_CITY_MASK)
                OUT.maskDist = MagicDistance(pivotWS); // decided per pointer, so an icon is never sliced in half
            #else
                OUT.maskDist = -1.0;
            #endif
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
            #if defined(_USE_CITY_MASK)
                clip(-IN.maskDist);
            #endif
                half4 c = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                clip(c.a - _Cutoff);
                return c;
            }
            ENDHLSL
        }
    }
}
