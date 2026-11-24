$input a_position, a_texcoord0
$output v_texcoord0

#include "bgfx_shader.sh"

void main() {
    // a_position is a 0..1 quad, convert to clip space so it covers the whole screen.
    // (using it directly only filled the top-right quarter, which is why the rest
    //  of the screen kept stale content and the closed menu never went away)
    vec2 ndc = a_position.xy * 2.0 - 1.0;
    gl_Position = vec4(ndc, 0.0, 1.0);
    v_texcoord0 = vec4(a_texcoord0, 0.0, 0.0);
}
