$input a_color0, a_position, a_texcoord0, a_texcoord1
#ifdef INSTANCING
    $input i_data1, i_data2, i_data3
#endif
$output v_color0, v_ditheringAndMaskTinting, v_fog, v_lightmapUV, v_texcoord0, v_worldPos

#include "bgfx_shader.sh"

uniform vec4 FogColor;
uniform vec4 ViewPositionAndTime;
uniform vec4 FogAndDistanceControl;
uniform vec4 RenderChunkFogAlpha;

void main() {
    mat4 model;
#ifdef INSTANCING
    model[0] = vec4(i_data1.x, i_data2.x, i_data3.x, 0.0);
    model[1] = vec4(i_data1.y, i_data2.y, i_data3.y, 0.0);
    model[2] = vec4(i_data1.z, i_data2.z, i_data3.z, 0.0);
    model[3] = vec4(i_data1.w, i_data2.w, i_data3.w, 1.0);
#else
    model = u_model[0];
#endif

    vec3 worldPos = mul(model, vec4(a_position, 1.0)).xyz;

    float camDis = length(ViewPositionAndTime.xyz - worldPos);
    float fogA = clamp(((camDis / FogAndDistanceControl.z) + RenderChunkFogAlpha.x - FogAndDistanceControl.x) / (FogAndDistanceControl.y - FogAndDistanceControl.x), 0.0, 1.0);

    // v26 packed UV unpacking (scalar version, matches vanilla RenderChunk)
    uint tx = uint(round(a_texcoord0.x * 65535.0));
    uint ty = uint(round(a_texcoord0.y * 65535.0));
    float ux = float(tx & 32767u) * 2.0 * 1.525902189314365386962890625e-05;
    float uy = float(ty & 32767u) * 2.0 * 1.525902189314365386962890625e-05;
    ux += 3.0517578125e-05 * (2.0 * float((tx & 32768u) >> 15u) - 1.0);
    uy += 3.0517578125e-05 * (2.0 * float((ty & 32768u) >> 15u) - 1.0);
    vec2 uv0 = vec2(ux, uy);

    uint ly = uint(round(a_texcoord1.y * 65535.0));
    float lmu = float((ly >> 4u) & 15u) * 0.066666670143604278564453125;
    float lmv = float(ly & 15u) * 0.066666670143604278564453125;
    vec2 lmUV = vec2(lmu, lmv);

    v_texcoord0 = uv0;
    v_lightmapUV = lmUV;
    v_color0 = a_color0;
    v_ditheringAndMaskTinting = vec2(0.0, 0.0);
    v_fog = vec4(FogColor.rgb, fogA);
    v_worldPos = worldPos;
    gl_Position = mul(u_viewProj, vec4(worldPos, 1.0));
}
