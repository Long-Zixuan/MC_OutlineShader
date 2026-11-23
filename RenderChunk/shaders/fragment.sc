$input v_color0, v_ditheringAndMaskTinting, v_fog, v_lightmapUV, v_texcoord0, v_worldPos

#include "bgfx_shader.sh"

uniform vec4 FogColor;
uniform vec4 LightWorldSpaceDirection;

SAMPLER2D(s_LightMapTexture, 0);
SAMPLER2D(s_MatTexture, 1);
SAMPLER2D(s_SeasonsTexture, 2);

// ---- texture outline settings (ported from commonSettings.glsl) ----
#define ENABLE_TEXTURE_OUTLINES 1
#define TEXTURE_OUTLINE_STRENGTH 0.8
#define OUTLINE_THICKNESS 0.1

// Terrain atlas resolution, replaces Java's textureSize(texture, 0).
#define ATLAS_SIZE 256.0

// ---- lighting settings (ported from commonSettings.glsl) ----
#define ENABLE_DIRECTIONAL_LIGHTING 1
#define HALF_LAMBERT 0
#define LAMBERT 1
#define LAMBERT_MODE HALF_LAMBERT
#define SHADOW_BRIGHTNESS 0.6
#define BLOCK_LIGHT_INTENSITY 1.5

// getTEXTURETextureOutline() - port of gbuffers_textured.fsh.
float getTEXTURETextureOutline(vec2 texCoord, vec4 originalColor) {
    vec2 res = vec2(ATLAS_SIZE, ATLAS_SIZE);
    vec2 texelSize = vec2(1.0 / res.x, 1.0 / res.y) * OUTLINE_THICKNESS;
    texelSize = vec2(texelSize.x * 0.3, texelSize.y * 0.3);

    vec4 colorRight = texture2D(s_MatTexture, vec2(texCoord.x + texelSize.x, texCoord.y));
    vec4 colorDown = texture2D(s_MatTexture, vec2(texCoord.x, texCoord.y + texelSize.y));
    vec4 colorLeft = texture2D(s_MatTexture, vec2(texCoord.x - texelSize.x, texCoord.y));
    vec4 colorUp = texture2D(s_MatTexture, vec2(texCoord.x, texCoord.y - texelSize.y));

    float diffRight = length(originalColor.rgb - colorRight.rgb);
    float diffDown = length(originalColor.rgb - colorDown.rgb);
    float diffLeft = length(originalColor.rgb - colorLeft.rgb);
    float diffUp = length(originalColor.rgb - colorUp.rgb);

    float maxDiff = max(max(diffRight, diffDown), max(diffLeft, diffUp));
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
    vec4 originalTexture = texture2D(s_MatTexture, v_texcoord0);

    #if defined(ALPHA_TEST_PASS)
        if (originalTexture.a < 0.5) {
            discard;
        }
    #endif

    vec4 col = originalTexture * v_color0;

    // ================= directional lighting =================
    vec3 dir = normalize(LightWorldSpaceDirection.xyz);
    float flip = clamp(dir.y / 0.1, -1.0, 1.0);
    dir *= flip;

    vec3 norm = normalize(cross(dFdx(v_worldPos), dFdy(v_worldPos)));

    #if LAMBERT_MODE == HALF_LAMBERT
        float lambert = pow(dot(norm, dir) * 0.5 + 0.5, 2.0);
    #else
        float lambert = dot(norm, dir);
    #endif

    vec3 lMapFull = texture2D(s_LightMapTexture, v_lightmapUV).rgb;
    vec3 lMapAmbient = texture2D(s_LightMapTexture, vec2(0.0, v_lightmapUV.y)).rgb;
    vec3 blockLightContribution = max(vec3(0.0, 0.0, 0.0), lMapFull - lMapAmbient);
    float lVis = lMapAmbient.r;

    float sBright = SHADOW_BRIGHTNESS;
    sBright += (1.0 - lVis) * (1.0 - sBright);

    vec3 skyLight = lMapAmbient;
    vec3 blockLight = blockLightContribution * BLOCK_LIGHT_INTENSITY;
    vec3 sLight = vec3(1.0, 1.0, 1.0);
    skyLight += sLight * (1.0 - sBright);

    vec3 shad;
    #if ENABLE_DIRECTIONAL_LIGHTING == 1
        vec3 lambertCol = vec3(lambert, lambert, lambert);
        vec3 skyColor = FogColor.rgb;
        vec3 shadowColor = skyColor * 0.5 + 0.2;
        vec3 litFactor = shadowColor * (vec3(1.0, 1.0, 1.0) - lambertCol) + lambertCol;
        shad = litFactor * skyLight + blockLight;
    #else
        shad = vec3(1.0, 1.0, 1.0) * skyLight + blockLight;
    #endif

    col.rgb *= shad;

    // gbuffers_textured.fsh: apply texture outline
    #if ENABLE_TEXTURE_OUTLINES == 1
        float textureOutline = getTEXTURETextureOutline(v_texcoord0, originalTexture);
        float outline = textureOutline * TEXTURE_OUTLINE_STRENGTH;
        col.rgb = mix(col.rgb, vec3(0.05, 0.05, 0.05), outline);
    #endif

    // FIX: pass macro is TRANSPARENT_PASS (not TRANSPARENT); keep alpha on translucent passes
    #if !defined(TRANSPARENT_PASS)
        col.a = 1.0;
    #endif

    col.rgb = mix(col.rgb, FogColor.rgb, v_fog.a);
    gl_FragColor = col;
#endif
}
