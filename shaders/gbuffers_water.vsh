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
varying float terrainFlag;

void main()
{
    // Calculate vPos early for compatibility
    vPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    
    vec3 pos = vPos;
    pos = mat3(gbufferModelViewInverse) * pos + gbufferModelViewInverse[3].xyz;
    vert = (gl_ModelViewMatrix * gl_Vertex).xyz-(gl_NormalMatrix * gl_Normal)/32.;
    vert = mat3(gbufferModelViewInverse) * vert + gbufferModelViewInverse[3].xyz + cameraPosition;
    
    // Calculate distance from camera for distance-based effects
    float distanceFromCamera = length(pos);
    
    // Determine block type
    float isWater = float(mc_Entity.x == 1.0);
    float isGlass = float(mc_Entity.x == 4.0);

    // Per-face normal in view space, N.a is the water flag. N was never written
    // before, so the shadow bias in gbuffers_water.fsh read an undefined varying, and
    // the oldLighting compensation there needs the real block face direction.
    vec3 nView = gl_NormalMatrix * gl_Normal;
    float nLen = length(nView);
    N.xyz = (nLen > 1e-5) ? nView / nLen : vec3(0.0, 1.0, 0.0);
    N.a = isWater;

    // Terrain-only flag, same test as gbuffers_textured.vsh: the per-face brightness
    // that `oldLighting=true` bakes into gl_Color only exists on terrain. Entity models,
    // particles and the entity shadow blob get neither mc_Entity.y nor at_midBlock.
    terrainFlag = max(
        step(0.5, abs(mc_Entity.y)),
        step(1e-6, dot(at_midBlock.xyz, at_midBlock.xyz))
    );
    
    float c = fract(pos.y+cameraPosition.y);
    c *= min(10.-c/.1,1.);
        
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(pos,1);
    gl_FogFragCoord = length(pos);
    
    color = gl_Color;
    world = pos; // Use final distorted position
    coord0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    coord1 = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    id = mc_Entity.x;
}