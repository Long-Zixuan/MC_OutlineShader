#version 120
#include "commonSettings.glsl"
uniform sampler2D texture;

uniform float blindness;
uniform int isEyeInWater;

varying vec4 glcolor;
varying vec2 texcoord;

void main()
{
    vec3 light = vec3(1.-blindness);
    vec4 col = glcolor * vec4(light,1) * texture2D(texture,texcoord);

    float fog = (isEyeInWater>0) ? 1.-exp(-gl_FogFragCoord * gl_Fog.density):
    clamp((gl_FogFragCoord-gl_Fog.start) * gl_Fog.scale, 0., 1.);

    col.rgb = mix(col.rgb, gl_Fog.color.rgb, fog);

    gl_FragData[0] = col;
    if(PAPER_WORLD == ON)
    {
        gl_FragData[0] = vec4(1,1,1,1);
    }
}
