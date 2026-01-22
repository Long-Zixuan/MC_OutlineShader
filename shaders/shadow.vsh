#version 130
#include "commonSettings.glsl"

#define LIGHT_DIRECTION_OFFSET 0.04 //[0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1]

uniform vec3 shadowLightPosition;

out vec2 uv0;

void main() {
    uv0 = gl_MultiTexCoord0.xy;
    
    vec4 worldPos = gl_Vertex;
    vec3 lightDir = normalize(shadowLightPosition);
    worldPos.xyz -= lightDir * LIGHT_DIRECTION_OFFSET;
    
	gl_Position = gl_ModelViewProjectionMatrix * worldPos;

	// Apply distortion immediately after transformation
	gl_Position.xyz = distortShadow(gl_Position.xyz);

	// Then apply the Iris corrections
	gl_Position.xy /= mix(1.0, length(gl_Position.xy), 0.85);
	
}
