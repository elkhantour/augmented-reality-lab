Shader "Custom/CartoonWaterfall"
{
    Properties
    {
        [Header(Colors)]
        _TopColor ("Top Color (A = opacity)", Color) = (0.55, 0.92, 1.0, 0.85)
        _BottomColor ("Bottom Color (A = opacity)", Color) = (0.15, 0.55, 0.85, 0.95)
        _Opacity ("Overall Opacity", Range(0,1)) = 1
        _BandCount ("Color Bands (0 = smooth)", Range(0,8)) = 3
        [Toggle] _FlipV ("Flip Fall Direction (if UVs run upside down)", Float) = 0

        [Header(Streaks)]
        _StreakColor ("Streak Color (A = strength)", Color) = (1,1,1,0.45)
        _StreakCount ("Streak Count (across width)", Float) = 8
        _StreakStretch ("Streak Stretch (higher = shorter)", Float) = 1.5
        _StreakThreshold ("Streak Threshold", Range(0,1)) = 0.6
        _StreakSoftness ("Streak Edge Softness", Range(0.001,0.3)) = 0.03
        _FlowSpeed ("Fall Speed", Float) = 0.8

        [Header(Foam)]
        _FoamColor ("Foam Color", Color) = (1,1,1,1)
        _TopFoamWidth ("Top Lip Foam Height", Range(0,0.5)) = 0.06
        _BottomFoamHeight ("Bottom Splash Foam Height", Range(0,0.6)) = 0.18
        _FoamNoiseScale ("Foam Noise Scale", Float) = 6
        _FoamWobble ("Foam Edge Wobble", Range(0,0.5)) = 0.15

        [Header(Ragged Sides)]
        _SideCut ("Side Cut", Range(0,0.8)) = 0.08
        _SideFoamWidth ("Side Foam Width", Range(0,0.5)) = 0.06
        _EdgeWobble ("Side Wobble", Range(0,0.6)) = 0.18
        _EdgeNoiseScale ("Side Wobble Scale", Float) = 4

        [Header(Contact Foam)]
        _FoamWidth ("Contact Foam Width", Float) = 0.3

        [Header(Options)]
        [Toggle(_USE_DEPTH)] _UseDepth ("Contact Foam (needs Depth Texture)", Float) = 1
        [Toggle(_USE_CITY_MASK)] _UseCityMask ("Clip With City Mask", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "Waterfall"
            Tags { "LightMode"="UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _USE_DEPTH
            #pragma shader_feature_local_fragment _USE_CITY_MASK

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4  _TopColor;
                half4  _BottomColor;
                half   _Opacity;
                float  _BandCount;
                float  _FlipV;

                half4  _StreakColor;
                float  _StreakCount;
                float  _StreakStretch;
                half   _StreakThreshold;
                half   _StreakSoftness;
                float  _FlowSpeed;

                half4  _FoamColor;
                float  _TopFoamWidth;
                float  _BottomFoamHeight;
                float  _FoamNoiseScale;
                float  _FoamWobble;

                float  _SideCut;
                float  _SideFoamWidth;
                float  _EdgeWobble;
                float  _EdgeNoiseScale;

                float  _FoamWidth;
            CBUFFER_END

            // ---- City mask globals (same ones CityClipController sets) ----
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

            // Identical to CityClip.shader so the cut edge matches the island
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
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 uvScale    : TEXCOORD1; // xy = uv, z = object scale
                float4 screenPos  : TEXCOORD2;
                float  eyeDepth   : TEXCOORD3;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float3 posWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionWS = posWS;
                OUT.positionCS = TransformWorldToHClip(posWS);
                OUT.screenPos  = ComputeScreenPos(OUT.positionCS);
                OUT.eyeDepth   = -TransformWorldToView(posWS).z;

                float objScale = max(length(float3(UNITY_MATRIX_M._m00, UNITY_MATRIX_M._m10, UNITY_MATRIX_M._m20)), 1e-5);
                OUT.uvScale = float3(IN.uv, objScale);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
            #if defined(_USE_CITY_MASK)
                float md = MagicDistance(IN.positionWS);
                clip(-md);
            #endif

                float u = IN.uvScale.x;
                float v = lerp(IN.uvScale.y, 1.0 - IN.uvScale.y, _FlipV); // v = 1 at the top
                float t = _Time.y * _FlowSpeed;

                // ---------- Ragged sides: wobbling cut, scrolling downward ----------
                float side = min(u, 1.0 - u) * 2.0; // 0 at the sides, 1 in the middle
                float sideSeed = step(0.5, u) * 10.0 + 3.1; // left and right wobble differently
                float wob = (ValueNoise(float2(v * _EdgeNoiseScale + t, sideSeed)) - 0.5) * _EdgeWobble;
                float sideV = side + wob;
                clip(sideV - _SideCut);
                float sideFoam = step(sideV, _SideCut + _SideFoamWidth);

                // ---------- Base color: banded top-to-bottom gradient ----------
                float g = v;
                if (_BandCount > 0.5)
                    g = round(g * _BandCount) / _BandCount;
                half4 col = lerp(_BottomColor, _TopColor, g);

                // ---------- Falling streaks: stretched noise scrolling downward ----------
                float s1 = ValueNoise(float2(u * _StreakCount, v * _StreakStretch + t));
                float s2 = ValueNoise(float2(u * _StreakCount * 1.9 + 7.3, v * _StreakStretch * 0.8 + t * 1.4));
                float streak = smoothstep(_StreakThreshold, _StreakThreshold + _StreakSoftness, (s1 + s2) * 0.5);
                streak *= _StreakColor.a;
                col.rgb = lerp(col.rgb, _StreakColor.rgb, streak);
                col.a   = lerp(col.a, 1.0, streak);

                // ---------- Foam: top lip, bottom splash, sides, and contact with geometry ----------
                float foamN = ValueNoise(float2(u * _FoamNoiseScale, v * _FoamNoiseScale * 0.5 + t * 0.8));
                float foamWob = (foamN - 0.5) * _FoamWobble;

                float topFoam    = step(1.0 - _TopFoamWidth, v + foamWob);
                float bottomFoam = step(v + foamWob, _BottomFoamHeight);
                float foam = max(max(topFoam, bottomFoam), sideFoam);

            #if defined(_USE_DEPTH)
                float2 suv = IN.screenPos.xy / IN.screenPos.w;
                float sceneEye = LinearEyeDepth(SampleSceneDepth(suv), _ZBufferParams);
                float diff = max(sceneEye - IN.eyeDepth, 0.0) / IN.uvScale.z;
                float contact = step(diff / max(_FoamWidth, 1e-4), foamN);
                foam = max(foam, contact);
            #endif

                foam *= _FoamColor.a;
                col.rgb = lerp(col.rgb, _FoamColor.rgb, foam);
                col.a   = lerp(col.a, 1.0, foam);

            #if defined(_USE_CITY_MASK)
                float edge = pow(saturate(1.0 + md / max(_MagicEdgeWidth, 1e-4)), 3.0);
                col.rgb += _MagicEdgeColor.rgb * edge * _MagicEdgeIntensity;
                col.a = saturate(col.a + edge);
            #endif

                col.a *= _Opacity;
                return col;
            }
            ENDHLSL
        }
    }
}
