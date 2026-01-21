#version 120
uniform sampler2D lightmap;
uniform float blindness;
uniform int isEyeInWater;
varying vec2 lmcoord;
varying vec4 glcolor;
void main() {
	vec4 color = glcolor;
	color *= texture2D(lightmap, lmcoord);
	
	//Fog effects
	float fog = (isEyeInWater>0) ? 1.-exp(-gl_FogFragCoord * gl_Fog.density):
	clamp((gl_FogFragCoord-gl_Fog.start) * gl_Fog.scale, 0., 1.);
	color.rgb = mix(color.rgb, gl_Fog.color.rgb, fog);
	color *= vec4(vec3(1.-blindness),1);
	
/* DRAWBUFFERS:0 */
	
	gl_FragData[0] = color; //gcolor
}