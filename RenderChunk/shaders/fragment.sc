$input v_color0, v_ditheringAndMaskTinting, v_fog, v_lightmapUV, v_texcoord0, v_worldPos

#include "bgfx_shader.sh"

uniform vec4 FogColor;

SAMPLER2D(s_LightMapTexture, 0);
SAMPLER2D(s_MatTexture, 1);
SAMPLER2D(s_SeasonsTexture, 2);

// ---- texture outline settings (ported from commonSettings.glsl) ----
#define ENABLE_TEXTURE_OUTLINES 1
#define TEXTURE_OUTLINE_STRENGTH 0.8
#define OUTLINE_THICKNESS 0.1

// Terrain atlas resolution, replaces Java's textureSize(texture, 0).
#define ATLAS_SIZE 256.0

// getTEXTURETextureOutline() - port of gbuffers_textured.fsh.
// Only change: textureSize(texture, 0) -> ATLAS_SIZE constant.
float getTEXTURETextureOutline(vec2 texCoord, vec4 originalColor) {
    vec2 res = vec2(ATLAS_SIZE, ATLAS_SIZE);
    vec2 texelSize = vec2(1.0 / res.x, 1.0 / res.y) * OUTLINE_THICKNESS;

    // Use much smaller sampling - only 1-2 pixels to stay within texture boundaries
    texelSize = vec2(texelSize.x * 0.3, texelSize.y * 0.3);

    // Sample surrounding pixels
    vec4 colorRight = texture2D(s_MatTexture, vec2(texCoord.x + texelSize.x, texCoord.y));
    vec4 colorDown = texture2D(s_MatTexture, vec2(texCoord.x, texCoord.y + texelSize.y));
    vec4 colorLeft = texture2D(s_MatTexture, vec2(texCoord.x - texelSize.x, texCoord.y));
    vec4 colorUp = texture2D(s_MatTexture, vec2(texCoord.x, texCoord.y - texelSize.y));

    // Calculate color differences
    float diffRight = length(originalColor.rgb - colorRight.rgb);
    float diffDown = length(originalColor.rgb - colorDown.rgb);
    float diffLeft = length(originalColor.rgb - colorLeft.rgb);
    float diffUp = length(originalColor.rgb - colorUp.rgb);

    float maxDiff = max(max(diffRight, diffDown), max(diffLeft, diffUp));

    // Make it dramatic but keep the smooth gradations
    return clamp(maxDiff * 4.0, 0.0, 1.0);
}

void main() {
#if defined(DEPTH_ONLY_OPAQUE_PASS) || defined(DEPTH_ONLY_ALPHA_TEST_PASS)
    #if defined(DEPTH_ONLY_ALPHA_TEST_PASS)
        if (texture2D(s_MatTexture, v_texcoord0).a < 0.5) {
            discard;
        }
    #endif
    gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);
#else
    // original texture (before lighting) - used for lighting and the outline
    vec4 originalTexture = texture2D(s_MatTexture, v_texcoord0);

    #if defined(ALPHA_TEST_PASS)
        if (originalTexture.a < 0.5) {
            discard;
        }
    #endif

    vec4 col = originalTexture * v_color0;
    col.rgb *= texture2D(s_LightMapTexture, v_lightmapUV).rgb;

    // gbuffers_textured.fsh: apply texture outline
    #if ENABLE_TEXTURE_OUTLINES == 1
        float textureOutline = getTEXTURETextureOutline(v_texcoord0, originalTexture);
        float outline = textureOutline * TEXTURE_OUTLINE_STRENGTH;
        col.rgb = mix(col.rgb, vec3(0.05, 0.05, 0.05), outline);
    #endif

    #if !defined(TRANSPARENT_PASS)
        col.a = 1.0;
    #endif

    col.rgb = mix(col.rgb, FogColor.rgb, v_fog.a);
    gl_FragColor = col;
#endif
}
