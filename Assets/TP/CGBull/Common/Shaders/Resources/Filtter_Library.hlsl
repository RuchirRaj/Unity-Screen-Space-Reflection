#ifndef _Filtter_Library_
#define _Filtter_Library_

#include "Common.hlsl"


//////Color filter
inline half HdrWeight4(half3 Color, half Exposure)
{
    return rcp(Luma4(Color) * Exposure + 4);
}

inline half HdrWeightY(half Color, half Exposure)
{
    return rcp(Color * Exposure + 4);
}

inline half3 RGBToYCoCg(half3 RGB)
{
    half Y = dot(RGB, half3(1, 2, 1));
    half Co = dot(RGB, half3(2, 0, -2));
    half Cg = dot(RGB, half3(-1, 2, -1));

    half3 YCoCg = half3(Y, Co, Cg);
    return YCoCg;
}

inline half3 YCoCgToRGB(half3 YCoCg)
{
    half Y = YCoCg.x * 0.25;
    half Co = YCoCg.y * 0.25;
    half Cg = YCoCg.z * 0.25;

    half R = Y + Co - Cg;
    half G = Y + Cg;
    half B = Y - Co - Cg;

    half3 RGB = half3(R, G, B);
    return RGB;
}

//////Sampler filter
void Bicubic2DCatmullRom(in float2 UV, in float2 Size, in float2 InvSize, out float2 Sample[3], out float2 Weight[3])
{
    UV *= Size;

    float2 tc = floor(UV - 0.5) + 0.5;
    float2 f = UV - tc;
    float2 f2 = f * f;
    float2 f3 = f2 * f;

    float2 w0 = f2 - 0.5 * (f3 + f);
    float2 w1 = 1.5 * f3 - 2.5 * f2 + 1;
    float2 w3 = 0.5 * (f3 - f2);
    float2 w2 = 1 - w0 - w1 - w3;

    Weight[0] = w0;
    Weight[1] = w1 + w2;
    Weight[2] = w3;

    Sample[0] = tc - 1;
    Sample[1] = tc + w2 / Weight[1];
    Sample[2] = tc + 2;

    Sample[0] *= InvSize;
    Sample[1] *= InvSize;
    Sample[2] *= InvSize;
}

#define BICUBIC_CATMULL_ROM_SAMPLES 5

struct FCatmullRomSamples
{
    // Constant number of samples (BICUBIC_CATMULL_ROM_SAMPLES)
    uint Count;

    // Constant sign of the UV direction from master UV sampling location.
    int2 UVDir[BICUBIC_CATMULL_ROM_SAMPLES];

    // Bilinear sampling UV coordinates of the samples
    float2 UV[BICUBIC_CATMULL_ROM_SAMPLES];

    // Weights of the samples
    float Weight[BICUBIC_CATMULL_ROM_SAMPLES];

    // Final multiplier (it is faster to multiply 3 RGB values than reweights the 5 weights)
    float FinalMultiplier;
};

FCatmullRomSamples GetBicubic2DCatmullRomSamples(float2 UV, float2 Size, in float2 InvSize)
{
    FCatmullRomSamples Samples;
    Samples.Count = BICUBIC_CATMULL_ROM_SAMPLES;

    float2 Weight[3];
    float2 Sample[3];
    Bicubic2DCatmullRom(UV, Size, InvSize, Sample, Weight);

    // Optimized by removing corner samples
    Samples.UV[0] = float2(Sample[1].x, Sample[0].y);
    Samples.UV[1] = float2(Sample[0].x, Sample[1].y);
    Samples.UV[2] = float2(Sample[1].x, Sample[1].y);
    Samples.UV[3] = float2(Sample[2].x, Sample[1].y);
    Samples.UV[4] = float2(Sample[1].x, Sample[2].y);

    Samples.Weight[0] = Weight[1].x * Weight[0].y;
    Samples.Weight[1] = Weight[0].x * Weight[1].y;
    Samples.Weight[2] = Weight[1].x * Weight[1].y;
    Samples.Weight[3] = Weight[2].x * Weight[1].y;
    Samples.Weight[4] = Weight[1].x * Weight[2].y;

    Samples.UVDir[0] = int2(0, -1);
    Samples.UVDir[1] = int2(-1, 0);
    Samples.UVDir[2] = int2(0, 0);
    Samples.UVDir[3] = int2(1, 0);
    Samples.UVDir[4] = int2(0, 1);

    // Reweight after removing the corners
    float CornerWeights;
    CornerWeights = Samples.Weight[0];
    CornerWeights += Samples.Weight[1];
    CornerWeights += Samples.Weight[2];
    CornerWeights += Samples.Weight[3];
    CornerWeights += Samples.Weight[4];
    Samples.FinalMultiplier = 1 / CornerWeights;

    return Samples;
}

half4 Texture2DSampleBicubic(Texture2D Tex, SamplerState Sampler, half2 UV, half2 Size, in half2 InvSize)
{
	FCatmullRomSamples Samples = GetBicubic2DCatmullRomSamples(UV, Size, InvSize);

	half4 OutColor = 0;
	for (uint i = 0; i < Samples.Count; i++)
	{
		OutColor += Tex.SampleLevel(Sampler, Samples.UV[i], 0) * Samples.Weight[i];
	}
	OutColor *= Samples.FinalMultiplier;

	return OutColor;
}

half4 Texture2DSampleBicubic(sampler2D Tex, half2 UV, half2 Size, in half2 InvSize)
{
	FCatmullRomSamples Samples = GetBicubic2DCatmullRomSamples(UV, Size, InvSize);

	half4 OutColor = 0;
	for (uint i = 0; i < Samples.Count; i++)
	{
		OutColor += tex2Dlod(Tex, half4(Samples.UV[i], 0.0, 0.0)) * Samples.Weight[i];
	}
	OutColor *= Samples.FinalMultiplier;

	return OutColor;
}

//////Sharpe filter
inline half Sharpe(sampler2D sharpColor, half sharpness, half2 Resolution, half2 UV)
{
    half2 step = 1 / Resolution.xy;

    half3 texA = tex2D(sharpColor, UV + half2(-step.x, -step.y) * 1.5);
    half3 texB = tex2D(sharpColor, UV + half2(step.x, -step.y) * 1.5);
    half3 texC = tex2D(sharpColor, UV + half2(-step.x, step.y) * 1.5);
    half3 texD = tex2D(sharpColor, UV + half2(step.x, step.y) * 1.5);

    half3 around = 0.25 * (texA + texB + texC + texD);
    half4 center = tex2D(sharpColor, UV);

    half3 color = center.rgb + (center.rgb - around) * sharpness;
    return half4(color, center.a);
}

//////Bilateral filter
#define Blur_Sharpness 5
#define Blur_Radius 0.05
#define Blur_Size 12

inline half CrossBilateralWeight_1(half x, half Sharp)
{
    return 0.39894 * exp(-0.5 * x * x / (Sharp * Sharp)) / Sharp;
}

inline half CrossBilateralWeight_2(half3 v, half Sharp)
{
    return 0.39894 * exp(-0.5 * dot(v, v) / (Sharp * Sharp)) / Sharp;
}

inline half4 BilateralClearUp(sampler2D Color, half2 Resolution, half2 uv)
{
    half4 originColor = tex2D(Color, uv);

    half kernel[Blur_Size];
    const int kernelSize = (Blur_Size - 1) / 2;

    //UNITY_UNROLL
    for (int j = 0; j <= kernelSize; j++)
    {
        kernel[kernelSize + j] = kernel[kernelSize - j] = CrossBilateralWeight_1(half(j), Blur_Sharpness);
    }

    half weight, Num_Weight;
    half4 blurColor, final_colour;

    //UNITY_UNROLL
    for (int i = -kernelSize; i <= kernelSize; i++)
    {
        //UNITY_UNROLL
        for (int j = -kernelSize; j <= kernelSize; j++)
        {
            blurColor = tex2Dlod(Color, half4( ( (uv * Resolution) + half2( half(i), half(j) ) ) / Resolution, 0, 0) );
            weight = CrossBilateralWeight_2(blurColor - originColor, Blur_Radius) * kernel[kernelSize + j] * kernel[kernelSize + i];
            Num_Weight += weight;
            final_colour += weight * blurColor;
        }
    }
    return final_colour / Num_Weight;
}

///////////////Temporal filter
#ifndef AA_Filter
    #define AA_Filter 1
#endif

#ifndef AA_BicubicFilter
    #define AA_BicubicFilter 0
#endif

#if defined(UNITY_REVERSED_Z)
    #define COMPARE_DEPTH(a, b) step(b, a)
#else
    #define COMPARE_DEPTH(a, b) step(a, b)
#endif

half2 ReprojectedMotionVectorUV(sampler2D _DepthTexture, half2 uv, half2 screenSize)
{
    half neighborhood[9];
    neighborhood[0] = tex2D(_DepthTexture, uv + (int2(-1, -1) / screenSize)).z;
    neighborhood[1] = tex2D(_DepthTexture, uv + (int2(0, -1) / screenSize)).z;
    neighborhood[2] = tex2D(_DepthTexture, uv + (int2(1, -1) / screenSize)).z;
    neighborhood[3] = tex2D(_DepthTexture, uv + (int2(-1, 0) / screenSize)).z;
    neighborhood[5] = tex2D(_DepthTexture, uv + (int2(1, 0) / screenSize)).z;
    neighborhood[6] = tex2D(_DepthTexture, uv + (int2(-1, 1) / screenSize)).z;
    neighborhood[7] = tex2D(_DepthTexture, uv + (int2(0, -1) / screenSize)).z;
    neighborhood[8] = tex2D(_DepthTexture, uv + (int2(1, 1) / screenSize)).z;

    half3 result = half3(0, 0, tex2D(_DepthTexture, uv).z);
    result = lerp(result, half3(-1, -1, neighborhood[0]), COMPARE_DEPTH(neighborhood[0], result.z));
    result = lerp(result, half3(0, -1, neighborhood[1]), COMPARE_DEPTH(neighborhood[1], result.z));
    result = lerp(result, half3(1, -1, neighborhood[2]), COMPARE_DEPTH(neighborhood[2], result.z));
    result = lerp(result, half3(-1, 0, neighborhood[3]), COMPARE_DEPTH(neighborhood[3], result.z));
    result = lerp(result, half3(1, 0, neighborhood[5]), COMPARE_DEPTH(neighborhood[5], result.z));
    result = lerp(result, half3(-1, 1, neighborhood[6]), COMPARE_DEPTH(neighborhood[6], result.z));
    result = lerp(result, half3(0, -1, neighborhood[7]), COMPARE_DEPTH(neighborhood[7], result.z));
    result = lerp(result, half3(1, 1, neighborhood[8]), COMPARE_DEPTH(neighborhood[8], result.z));

    return (uv + result.xy * screenSize);
}

inline void ResolverAABB(sampler2D currColor, half Sharpness, half ExposureScale, half AABBScale, half2 uv, half2 TexelSize, inout half Variance, inout half4 MinColor, inout half4 MaxColor, inout half4 FilterColor)
{
    const int2 SampleOffset[9] = {int2(-1.0, -1.0), int2(0.0, -1.0), int2(1.0, -1.0), int2(-1.0, 0.0), int2(0.0, 0.0), int2(1.0, 0.0), int2(-1.0, 1.0), int2(0.0, 1.0), int2(1.0, 1.0)};

    half4 SampleColors[9];

    for(uint i = 0; i < 9; i++) {
        #if AA_BicubicFilter
            SampleColors[i] = Texture2DSampleBicubic(currColor, uv + ( SampleOffset[i] / TexelSize), BicubicSize.xy, BicubicSize.zw);
        #else
            SampleColors[i] = tex2D( currColor, uv + ( SampleOffset[i] / TexelSize) );
        #endif
    }

    #if AA_Filter
        half SampleWeights[9];
        for(uint j = 0; j < 9; j++) {
            SampleWeights[j] = HdrWeight4(SampleColors[j].rgb, ExposureScale);
        }

        half TotalWeight = 0;
        for(uint k = 0; k < 9; k++) {
            TotalWeight += SampleWeights[k];
        }  

        SampleColors[4] = (SampleColors[0] * SampleWeights[0] + SampleColors[1] * SampleWeights[1] + SampleColors[2] * SampleWeights[2] 
                        +  SampleColors[3] * SampleWeights[3] + SampleColors[4] * SampleWeights[4] + SampleColors[5] * SampleWeights[5] 
                        +  SampleColors[6] * SampleWeights[6] + SampleColors[7] * SampleWeights[7] + SampleColors[8] * SampleWeights[8]) / TotalWeight;
    #endif

    half4 m1 = 0.0; half4 m2 = 0.0;
    for(uint x = 0; x < 9; x++)
    {
        m1 += SampleColors[x];
        m2 += SampleColors[x] * SampleColors[x];
    }

    half4 mean = m1 / 9.0;
    half4 stddev = sqrt( (m2 / 9.0) - pow2(mean) );
        
    MinColor = mean - AABBScale * stddev;
    MaxColor = mean + AABBScale * stddev;

    FilterColor = SampleColors[4];
    MinColor = min(MinColor, FilterColor);
    MaxColor = max(MaxColor, FilterColor);

    half4 TotalVariance = 0;
    for(uint z = 0; z < 9; z++)
    {
        TotalVariance += pow2(SampleColors[z] - mean);
    }
    Variance = saturate( Luminance(TotalVariance / 4) * 256 );
    Variance *= FilterColor.a;
}

//////Sharpening
/*
    //half4 corners = 4 * (TopLeft + BottomRight) - 2 * filterColor;
    //filterColor += (filterColor - (corners * 0.166667)) * 2.718282 * (Sharpness * 0.25);

    half TotalVariance = 0;
    for(uint z = 0; z < 9; z++)
    {
        TotalVariance += pow2(Luminance(SampleColors[z]) - Luminance(mean));
    }
    Variance = saturate((TotalVariance / 9) * 256) * FilterColor.a;
*/

#endif