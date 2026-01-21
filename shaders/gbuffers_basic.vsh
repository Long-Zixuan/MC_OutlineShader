#version 120

attribute vec2 mc_Entity;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
varying vec4 color;
varying vec2 lmcoord;
varying vec4 glcolor;

void main()
{

    vec3 pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
	// Calculate distance from camera for distance-based effects
    float distanceFromCamera = length(pos);
    pos = mat3(gbufferModelViewInverse) * pos  + gbufferModelViewInverse[3].xyz;
    vec3 h = pos+cameraPosition;
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(pos,1);
    gl_FogFragCoord = length(pos);
    
    color = gl_Color;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
}