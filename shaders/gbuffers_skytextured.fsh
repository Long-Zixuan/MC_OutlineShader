#version 120
#include "commonSettings.glsl"
uniform sampler2D texture;
uniform float blindness;
uniform int isEyeInWater;

varying vec4 glcolor;
varying vec2 texcoord;
varying vec2 originalTexcoord;

/* RENDERTARGETS:0,4 */

void main()
{
    vec3 light = vec3(1.-blindness);
    vec4 col;
    
    // Store original texture color before any processing
    vec4 originalTextureColor = texture2D(texture, texcoord);
    
    col = glcolor * vec4(light,1) * originalTextureColor;

    // Write to colortex0 (final color)
    gl_FragData[0] = col;
    
    // Write to colortex4 (original texture color with shadow info)
    // Sky elements are never shadowed, so shadow strength = 1.0
    gl_FragData[1] = vec4(originalTextureColor.rgb * glcolor.rgb, 1.0);
    if(PAPER_WORLD == ON)
    {
        gl_FragData[0] = vec4(1,1,1,1);
    }
}