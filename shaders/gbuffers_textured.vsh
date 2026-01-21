#version 130
#include "commonSettings.glsl"

attribute vec2 mc_Entity;
attribute vec3 mc_midTexCoord;
attribute vec4 at_midBlock;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
uniform float frameTimeCounter;

varying vec4 color;
varying vec3 world;
varying vec3 vert;
varying vec2 coord0;
varying vec2 coord1;
varying float id;
varying vec3 shadowPos;
varying vec3 vPos;
varying vec4 N;
varying float emissiveFlag;

void main()
{
	emissiveFlag = at_midBlock.w;
    // Calculate vPos early for compatibility
    vPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    
    vec3 pos = vPos;
    pos = mat3(gbufferModelViewInverse) * pos + gbufferModelViewInverse[3].xyz;
    vert = (gl_ModelViewMatrix * gl_Vertex).xyz-(gl_NormalMatrix * gl_Normal)/32.;
    vert = mat3(gbufferModelViewInverse) * vert + gbufferModelViewInverse[3].xyz + cameraPosition;
    
    // Calculate distance from camera for distance-based effects
    float distanceFromCamera = length(pos);
    
    float c = fract(pos.y+cameraPosition.y);
    c *= min(10.-c/.1,1.);
    
    float water = float(mc_Entity.x==1.);
    
    // Calculate shadow coordinates
    vec3 sWorld = vec3(shadowModelView * vec4(pos, 1.0));
	vec3 sClip = vec3(shadowProjection * vec4(sWorld, 1.0));

	// Apply distortion BEFORE other transformations
	sClip.xyz = distortShadow(sClip.xyz);
    shadowPos = sClip * 0.5 + 0.5;
    
    // Calculate normal for directional lighting
    N.xyz = normalize(gl_NormalMatrix * gl_Normal);
    N.a = (mc_Entity.x == 1) ? 1.0 : 0.0; // Water flag
        
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(pos,1);
    gl_FogFragCoord = length(pos);
    
    color = gl_Color;
    world = pos; // Keep using distorted position
    coord0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    coord1 = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    id = mc_Entity.x;
}