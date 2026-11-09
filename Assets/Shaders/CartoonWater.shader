Shader "Custom/CartoonWater"
{
    Properties
    {
        [Header(Colors)]
        _ShallowColor ("Shallow Color (A = opacity)", Color) = (0.35, 0.85, 0.95, 0.55)
        _DeepColor ("Deep Color (A = opacity)", Color) = (0.05, 0.35, 0.70, 0.90)
        _Opacity ("Overall Opacity", Range(0,1)) = 1
        _DepthDistance ("Depth Gradient Distance", Float) = 1.0
        _BandCount ("Color Bands (0 = smooth)", Range(0,8)) = 3
        _FlatDepth ("Depth Fallback (no depth texture)", Range(0,1)) = 0.5

        [Header(Shore Foam)]
        _FoamColor ("Foam Color", Color) = (1,1,1,1)
        _FoamWidth ("Foam Width", Float) = 0.3
        _FoamNoiseScale ("Foam Noise Scale", Float) = 3

        [Header(Ripples)]
        _RippleColor ("Ripple Color (A = strength)", Color) = (1,1,1,0.35)
        _RippleScale ("Ripple Scale", Float) = 0.8
        _RippleThreshold ("Ripple Threshold", Range(0,1)) = 0.62
        _RippleSoftness ("Ripple Edge Softness", Range(0.001,0.3)) = 0.02

        [Header(Motion)]
        _FlowSpeed ("Flow Speed", Float) = 0.15
        _WaveHeight ("Wave Height (0 = flat)", Float) = 0.08
        _WaveFreq ("Wave Frequency", Float) = 1.0
        _WaveSpeed ("Wave Speed", Float) = 1.0

        [Header(Options)]
        [Toggle(_USE_DEPTH)] _UseDepth ("Depth Effects (needs Depth Texture)", Float) = 1
        [Toggle(_USE_CITY_MASK)] _UseCityMask ("Clip With City Mask", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "Water"
            Tags { "LightMode"="UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _USE_DEPTH
            #pragma shader_feature_local_fragment _USE_CITY_MASK

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4  _ShallowColor;
                half4  _DeepColor;
                half   _Opacity;
                float  _DepthDistance;
                float  _BandCount;
                half   _FlatDepth;

                half4  _FoamColor;
                float  _FoamWidth;
                float  _FoamNoiseScale;

                half4  _RippleColor;
                float  _RippleScale;
                half   _RippleThreshold;
                half   _RippleSoftness;

                float  _FlowSpeed;
                float  _WaveHeight;
                float  _WaveFreq;
                float  _WaveSpeed;
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

            // Identical to CityClip.shader so the water edge matches the island edge
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
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float4 objData    : TEXCOORD1; // xyz = object-space position, w = object scale
                float4 screenPos  : TEXCOORD2;
                float  eyeDepth   : TEXCOORD3;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float3 pos = IN.positionOS.xyz;

                // Gentle vertex waves (needs a subdivided plane; set Wave Height 0 to disable)
                float tw = _Time.y * _WaveSpeed;
                pos.y += (sin(pos.x * _WaveFreq + tw) + sin(pos.z * _WaveFreq * 1.3 + tw * 1.2))
                         * 0.5 * _WaveHeight;

                float3 posWS = TransformObjectToWorld(pos);
                OUT.positionWS = posWS;
                OUT.positionCS = TransformWorldToHClip(posWS);
                OUT.screenPos  = ComputeScreenPos(OUT.positionCS);
                OUT.eyeDepth   = -TransformWorldToView(posWS).z;

                // Everything below is measured in the water object's own units,
                // so the look stays the same when the whole city is scaled in AR.
                float objScale = max(length(float3(UNITY_MATRIX_M._m00, UNITY_MATRIX_M._m10, UNITY_MATRIX_M._m20)), 1e-5);
                OUT.objData = float4(IN.positionOS.xyz, objScale);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
            #if defined(_USE_CITY_MASK)
                float md = MagicDistance(IN.positionWS);
                clip(-md);
            #endif

                float2 p = IN.objData.xz;
                float t = _Time.y * _FlowSpeed;

                // ---------- Depth: gradient color + shore distance ----------
                float depthT = _FlatDepth;
                float shoreT = 10.0; // far from any shore -> no foam

            #if defined(_USE_DEPTH)
                float2 suv = IN.screenPos.xy / IN.screenPos.w;
                float sceneEye = LinearEyeDepth(SampleSceneDepth(suv), _ZBufferParams);
                float diff = max(sceneEye - IN.eyeDepth, 0.0) / IN.objData.w;
                depthT = saturate(diff / max(_DepthDistance, 1e-4));
                shoreT = diff / max(_FoamWidth, 1e-4);
            #endif

                // Cartoon banding of the depth gradient
                if (_BandCount > 0.5)
                    depthT = round(depthT * _BandCount) / _BandCount;

                half4 col = lerp(_ShallowColor, _DeepColor, depthT);

                // ---------- Ripples: two thresholded noise layers ----------
                float n1 = ValueNoise(p * _RippleScale + float2(t, t * 0.6));
                float n2 = ValueNoise(p * _RippleScale * 1.7 - float2(t * 0.8, t));
                float ripple = smoothstep(_RippleThreshold, _RippleThreshold + _RippleSoftness, (n1 + n2) * 0.5);
                ripple *= _RippleColor.a;
                col.rgb = lerp(col.rgb, _RippleColor.rgb, ripple);
                col.a   = lerp(col.a, 1.0, ripple);

                // ---------- Shore foam: wobbling hard edge where water meets geometry ----------
                float foamNoise = ValueNoise(p * _FoamNoiseScale + float2(t * 0.5, -t * 0.4));
                float foam = step(shoreT, foamNoise) * _FoamColor.a;
                col.rgb = lerp(col.rgb, _FoamColor.rgb, foam);
                col.a   = lerp(col.a, 1.0, foam);

            #if defined(_USE_CITY_MASK)
                // Glow band along the magic cut edge
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
