$input v_texcoord0

#include "bgfx_shader.sh"

SAMPLER2D(s_ColorTexture, 1);

// colour-edge outline with dual-distance confirmation.
// ColorPostProcessing normally does tonemapping + gamma; replacing it means we
// must do gamma ourselves or the linear scene comes out very dark.
// sqrt() == gamma 2.0, close enough to 1/2.2 and compiles cleanly on SM5.0.
// The lift term brightens midtones while leaving highlights untouched, which
// matches the vanilla exposure/tonemap far better than a flat multiplier.
#define THRESHOLD_NEAR 0.18
#define THRESHOLD_FAR  0.10
#define OUTLINE_COL    0.15
#define OFFSET_PX      1.5
#define OFFSET_FAR_PX  4.0

#define EXPOSURE_BASE  1.12
#define EXPOSURE_LIFT  0.45

vec3 gamma(vec3 c) {
    // gamma 2.0
    vec3 s = sqrt(max(c, vec3(0.0, 0.0, 0.0)));
    // stronger lift in the darks, fading to just EXPOSURE_BASE at pure white
    vec3 lift = vec3(EXPOSURE_BASE + EXPOSURE_LIFT * (1.0 - s.x),
                     EXPOSURE_BASE + EXPOSURE_LIFT * (1.0 - s.y),
                     EXPOSURE_BASE + EXPOSURE_LIFT * (1.0 - s.z));
    return clamp(s * lift, vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0));
}

float maxNeighbourDiff(vec2 uv, vec2 off, vec3 base) {
    vec3 cL = gamma(texture2D(s_ColorTexture, vec2(uv.x - off.x, uv.y)).rgb);
    vec3 cR = gamma(texture2D(s_ColorTexture, vec2(uv.x + off.x, uv.y)).rgb);
    vec3 cD = gamma(texture2D(s_ColorTexture, vec2(uv.x, uv.y - off.y)).rgb);
    vec3 cU = gamma(texture2D(s_ColorTexture, vec2(uv.x, uv.y + off.y)).rgb);

    float dL = length(base - cL);
    float dR = length(base - cR);
    float dD = length(base - cD);
    float dU = length(base - cU);

    return max(max(dL, dR), max(dD, dU));
}

void main() {
    vec2 uv = v_texcoord0.xy;
    vec4 col = texture2D(s_ColorTexture, uv);
    col.rgb = gamma(col.rgb);

    vec2 offNear = vec2(OFFSET_PX     / 1920.0, OFFSET_PX     / 1080.0);
    vec2 offFar  = vec2(OFFSET_FAR_PX / 1920.0, OFFSET_FAR_PX / 1080.0);

    float dNear = maxNeighbourDiff(uv, offNear, col.rgb);
    float dFar  = maxNeighbourDiff(uv, offFar,  col.rgb);

    // require the edge to survive at both scales: filters texture detail
    if (dNear > THRESHOLD_NEAR && dFar > THRESHOLD_FAR) {
        col.rgb *= OUTLINE_COL;
    }

    gl_FragColor = col;
}
