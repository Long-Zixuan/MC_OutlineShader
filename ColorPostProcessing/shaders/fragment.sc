$input v_texcoord0

#include "bgfx_shader.sh"

SAMPLER2D(s_ColorTexture, 1);

// colour-edge outline.
// ColorPostProcessing normally does tonemapping + gamma; replacing it means we
// must do gamma ourselves or the linear scene comes out very dark.
// sqrt() == gamma 2.0, close enough to 1/2.2 and compiles cleanly on SM5.0.
#define THRESHOLD 0.18
#define OUTLINE_COL 0.15
#define OFFSET_PX 1.5

vec3 gamma(vec3 c) {
    // gamma 2.0 with a small exposure lift (~+12%)
    return sqrt(max(c, vec3(0.0, 0.0, 0.0))) * 1.12;
}

void main() {
    vec2 uv = v_texcoord0.xy;
    vec4 col = texture2D(s_ColorTexture, uv);
    col.rgb = gamma(col.rgb);

    vec2 off = vec2(OFFSET_PX / 1920.0, OFFSET_PX / 1080.0);

    vec3 cL = gamma(texture2D(s_ColorTexture, vec2(uv.x - off.x, uv.y)).rgb);
    vec3 cR = gamma(texture2D(s_ColorTexture, vec2(uv.x + off.x, uv.y)).rgb);
    vec3 cD = gamma(texture2D(s_ColorTexture, vec2(uv.x, uv.y - off.y)).rgb);
    vec3 cU = gamma(texture2D(s_ColorTexture, vec2(uv.x, uv.y + off.y)).rgb);

    float dL = length(col.rgb - cL);
    float dR = length(col.rgb - cR);
    float dD = length(col.rgb - cD);
    float dU = length(col.rgb - cU);

    float maxDiff = max(max(dL, dR), max(dD, dU));

    if (maxDiff > THRESHOLD) {
        col.rgb *= OUTLINE_COL;
    }

    gl_FragColor = col;
}
