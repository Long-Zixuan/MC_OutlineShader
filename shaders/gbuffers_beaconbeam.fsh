#version 120
#include "commonSettings.glsl"
uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
	vec4 color = texture2D(texture, texcoord) * glcolor;

/* DRAWBUFFERS:0 */
	gl_FragData[0] = color; //gcolor
	if(PAPER_WORLD == ON)
    {
        gl_FragData[0] = vec4(1,1,1,1);
    }
}