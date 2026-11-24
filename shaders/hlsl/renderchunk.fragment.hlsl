#include "ShaderConstants.fxh"
#include "util.fxh"

// ---- texture outline settings (ported from commonSettings.glsl) ----
#define ENABLE_TEXTURE_OUTLINES 1
#define TEXTURE_OUTLINE_STRENGTH 0.8f
#define OUTLINE_THICKNESS 0.1f

// Terrain atlas resolution, replaces Java's textureSize(texture, 0).
#define ATLAS_SIZE 256.0f

struct PS_Input
{
	float4 position : SV_Position;

#ifndef BYPASS_PIXEL_SHADER
	lpfloat4 color : COLOR;
	snorm float2 uv0 : TEXCOORD_0_FB_MSAA;
	snorm float2 uv1 : TEXCOORD_1_FB_MSAA;
#endif

#ifdef FOG
	float4 fogColor : FOG_COLOR;
#endif
};

struct PS_Output
{
	float4 color : SV_Target;
};

// getTEXTURETextureOutline() - port of gbuffers_textured.fsh.
// Only change: textureSize(texture, 0) -> ATLAS_SIZE constant.
float getTEXTURETextureOutline(float2 texCoord, float4 originalColor)
{
	float2 res = float2(ATLAS_SIZE, ATLAS_SIZE);
	float2 texelSize = (1.0f / res) * OUTLINE_THICKNESS;

	// Use much smaller sampling - only 1-2 pixels to stay within texture boundaries
	texelSize = texelSize * 0.3f;

	// Sample surrounding pixels
	float4 colorRight = TEXTURE_0.Sample(TextureSampler0, float2(texCoord.x + texelSize.x, texCoord.y));
	float4 colorDown  = TEXTURE_0.Sample(TextureSampler0, float2(texCoord.x, texCoord.y + texelSize.y));
	float4 colorLeft  = TEXTURE_0.Sample(TextureSampler0, float2(texCoord.x - texelSize.x, texCoord.y));
	float4 colorUp    = TEXTURE_0.Sample(TextureSampler0, float2(texCoord.x, texCoord.y - texelSize.y));

	// Calculate color differences
	float diffRight = length(originalColor.rgb - colorRight.rgb);
	float diffDown  = length(originalColor.rgb - colorDown.rgb);
	float diffLeft  = length(originalColor.rgb - colorLeft.rgb);
	float diffUp    = length(originalColor.rgb - colorUp.rgb);

	float maxDiff = max(max(diffRight, diffDown), max(diffLeft, diffUp));

	// Make it dramatic but keep the smooth gradations
	return saturate(maxDiff * 4.0f);
}

ROOT_SIGNATURE
void main(in PS_Input PSInput, out PS_Output PSOutput)
{
#ifdef BYPASS_PIXEL_SHADER
    PSOutput.color = float4(0.0f, 0.0f, 0.0f, 0.0f);
    return;
#else

#if USE_TEXEL_AA
	float4 diffuse = texture2D_AA(TEXTURE_0, TextureSampler0, PSInput.uv0 );
#else
	float4 diffuse = TEXTURE_0.Sample(TextureSampler0, PSInput.uv0);
#endif

#ifdef SEASONS_FAR
	diffuse.a = 1.0f;
#endif

#if USE_ALPHA_TEST
	#ifdef ALPHA_TO_COVERAGE
		#define ALPHA_THRESHOLD 0.05
	#else
		#define ALPHA_THRESHOLD 0.5
	#endif
	if(diffuse.a < ALPHA_THRESHOLD)
		discard;
#endif

#if defined(BLEND)
	diffuse.a *= PSInput.color.a;
#endif

#if !defined(ALWAYS_LIT)
	diffuse = diffuse * TEXTURE_1.Sample(TextureSampler1, PSInput.uv1);
#endif

#ifndef SEASONS
	#if !USE_ALPHA_TEST && !defined(BLEND)
		diffuse.a = PSInput.color.a;
	#endif	

	diffuse.rgb *= PSInput.color.rgb;
#else
	float2 seasonsUV = PSInput.color.xy;
	diffuse.rgb *= lerp(1.0f, TEXTURE_2.Sample(TextureSampler2, seasonsUV).rgb*2.0f, PSInput.color.b);
	diffuse.rgb *= PSInput.color.aaa;
	diffuse.a = 1.0f;
#endif

	// gbuffers_textured.fsh: apply texture outline
#if ENABLE_TEXTURE_OUTLINES == 1
	float4 outlineSource = TEXTURE_0.Sample(TextureSampler0, PSInput.uv0);
	float textureOutline = getTEXTURETextureOutline(PSInput.uv0, outlineSource);
	float outline = textureOutline * TEXTURE_OUTLINE_STRENGTH;
	diffuse.rgb = lerp(diffuse.rgb, float3(0.05f, 0.05f, 0.05f), outline);
#endif

#ifdef FOG
	diffuse.rgb = lerp( diffuse.rgb, PSInput.fogColor.rgb, PSInput.fogColor.a );
#endif

	PSOutput.color = diffuse;

#ifdef VR_MODE
	// On Rift, the transition from 0 brightness to the lowest 8 bit value is abrupt, so clamp to 
	// the lowest 8 bit value.
	PSOutput.color = max(PSOutput.color, 1 / 255.0f);
#endif

#endif // BYPASS_PIXEL_SHADER
}
