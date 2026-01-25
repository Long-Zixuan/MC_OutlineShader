#version 120

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec4 glcolor;
varying vec2 texcoord;
varying vec2 originalTexcoord; // Pass original coords to fragment shader


// Function to create 2D rotation matrix
mat2 rotate2D(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c);
}

void main()
{
    vec3 pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    pos = (gbufferModelViewInverse * vec4(pos,1)).xyz;

    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(pos,1);

    glcolor = gl_Color;
    
    // Get the original texture coordinates
    originalTexcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    
    texcoord = originalTexcoord;
}