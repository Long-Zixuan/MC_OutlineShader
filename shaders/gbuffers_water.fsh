#version 130
#include "commonSettings.glsl"

// Water-specific shadow settings
#define WATER_SHADOW_BIAS_MULTIPLIER 0.2 // Increase shadow bias for water [0.0 0.1 0.2 0.3 0.4 0.5]
#define WATER_PCF_SAMPLES 8 // Reduced PCF samples for water to improve performance [8 16 32 64]
#define WATER_SHADOW_SOFTNESS 0.5 // Reduced shadow softness for water [0.0 0.25 0.5 0.75 1.0]

uniform sampler2D noisetex;
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform sampler2D depthtex0;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;  
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjectionInverse;
uniform vec4 entityColor;
uniform vec3 shadowLightPosition;
uniform vec3 skyColor;
uniform vec3 cameraPosition;
uniform ivec2 atlasSize;
uniform float blindness;
uniform int isEyeInWater;
uniform vec2 texelSize;
uniform float viewWidth;
uniform float viewHeight;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform vec3 upPosition;
uniform vec3 fogColor;
uniform float far;

varying vec4 color;
varying vec3 shadowPos;
varying vec3 world;
varying vec3 vert;
varying vec2 coord0;
varying vec2 coord1;
varying float id;
varying vec3 vPos;
varying vec4 N;

// Shadow sampling arrays - using reduced set for water
const vec2 offsets[32] = vec2[32](
    vec2(-0.04117257, -0.1597612),
    vec2(0.06731031, -0.4353096),
    vec2(-0.206701, -0.4089882),
    vec2(0.1857469, -0.2327659),
    vec2(-0.2757695, -0.159873),
    vec2(-0.2301117, 0.1232693),
    vec2(0.05028719, 0.1034883),
    vec2(0.236303, 0.03379251),
    vec2(0.1467563, 0.364028),
    vec2(0.516759, 0.2052845),
    vec2(0.2962668, 0.2430771),
    vec2(0.3650614, -0.1689287),
    vec2(0.5764466, -0.07092822),
    vec2(-0.5563748, -0.4662297),
    vec2(-0.3765517, -0.5552908),
    vec2(-0.4642121, -0.157941),
    vec2(-0.2322291, -0.7013807),
    vec2(-0.05415121, -0.6379291),
    vec2(-0.7140947, -0.6341782),
    vec2(-0.4819134, -0.7250231),
    vec2(-0.7627537, -0.3445934),
    vec2(-0.7032605, -0.13733),
    vec2(0.8593938, 0.3171682),
    vec2(0.5223953, 0.5575764),
    vec2(0.7710021, 0.1543127),
    vec2(0.6919019, 0.4536686),
    vec2(0.3192437, 0.4512939),
    vec2(0.1861187, 0.595188),
    vec2(0.6516209, -0.3997115),
    vec2(0.8065675, -0.1330092),
    vec2(0.3163648, 0.7357415),
    vec2(0.5485036, 0.8288581)
);

#define rot2D(r) mat2(cos(r), sin(r), -sin(r), cos(r))

// Water-specific PCF shadow sampling with reduced samples and increased bias
float sWaterPCF(sampler2D sTex, vec3 sSPos, float bRad){
    float sMap = 0.0;
    float bNoise = texture(noisetex, gl_FragCoord.xy / vec2(noiseTextureResolution)).r;
    int samples = min(WATER_PCF_SAMPLES, PCF_SAMPLE);
    for(int i = 0; i < samples; i++){
        sMap += step(sSPos.z, texture(sTex, sSPos.xy + (rot2D(bNoise * 6.28318531) * offsets[i] * bRad * WATER_SHADOW_SOFTNESS)).r);
    }
    return sMap / float(samples);
}

vec2 hash2(vec2 p)
{
    return fract(cos(p*mat2(85.6,-69.3,74.8,-81.2))*475.);
}

vec2 voronoi(vec2 p,vec2 s)
{
    float d = 2.;
    vec2 off = vec2(.5);
    vec2 f = floor(p);
    for(float i = -1.;i<=1.;i++)
    for(float j = -1.;j<=1.;j++)
    {
        vec2 o = (hash2(f+s+vec2(i,j))-.5)+f+.5+vec2(i,j)-p;
        float t = length(o);
        if (d>t)
        {
            d = t;
            off = f+.5+vec2(i,j);
        }
    }
    return off;
}

vec2 off(vec2 p,vec3 s)
{
    return voronoi(p,s.xy+s.yz);
}

// Simple texture outline detection with very small sampling to avoid block edges
float getTEXTURETextureOutline(vec2 texCoord, vec4 originalColor) {
    vec2 res = vec2(textureSize(texture,0));
    vec2 texelSize = (1.0 / res) * OUTLINE_THICKNESS;
    
    // Use much smaller sampling - only 1-2 pixels to stay within texture boundaries
    texelSize *= 0.3;
    
    // Sample surrounding pixels
    vec4 colorRight = texture2D(texture, texCoord + vec2(texelSize.x, 0.0));
    vec4 colorDown = texture2D(texture, texCoord + vec2(0.0, texelSize.y));
    vec4 colorLeft = texture2D(texture, texCoord - vec2(texelSize.x, 0.0));
    vec4 colorUp = texture2D(texture, texCoord - vec2(0.0, texelSize.y));
    
    // Calculate color differences
    float diffRight = length(originalColor.rgb - colorRight.rgb);
    float diffDown = length(originalColor.rgb - colorDown.rgb);
    float diffLeft = length(originalColor.rgb - colorLeft.rgb);
    float diffUp = length(originalColor.rgb - colorUp.rgb);
    
    float maxDiff = max(max(diffRight, diffDown), max(diffLeft, diffUp));
    
    // Make it dramatic but keep the smooth gradations
    return clamp(maxDiff * 4.0, 0.0, 1.0);
}

// Function to bias mid-tone colors toward white for papery look, including biome-tinted areas
vec3 applyGrayBias(vec3 inputColor, vec3 originalTexture, vec3 vertexColor) {
    // Calculate luminance of both original texture and final color
    float inputLuminance = dot(inputColor, vec3(0.299, 0.587, 0.114));
    float textureLuminance = dot(originalTexture, vec3(0.299, 0.587, 0.114));
    
    // Create a bias curve that maintains luminance ordering
    // Use a smooth curve that approaches 1.0 (white) but never crosses over
    float biasAmount = 0.0;
    
    // Primary bias range for mid-tones
    float inMidToneRange = smoothstep(GRAY_BIAS_RANGE_MIN, GRAY_BIAS_RANGE_MIN + 0.1, textureLuminance) *
                          (1.0 - smoothstep(GRAY_BIAS_RANGE_MAX - 0.1, GRAY_BIAS_RANGE_MAX, textureLuminance));
    
    // Extended bias range for bright tones (reduced strength)
    float inBrightToneRange = smoothstep(GRAY_BIAS_RANGE_MAX - 0.1, GRAY_BIAS_RANGE_MAX + 0.05, textureLuminance) *
                             (1.0 - smoothstep(0.85, 0.95, textureLuminance));
    
    // Combine ranges
    float totalBiasRange = inMidToneRange + inBrightToneRange * 0.4;
    
    // Check if final color is in reasonable range
    float finalInRange = smoothstep(0.15, 0.25, inputLuminance) *
                        (1.0 - smoothstep(0.92, 0.98, inputLuminance));
    
    // Detect biome tinting
    vec3 neutralVertex = vec3(1.0);
    float biomeStrength = length(vertexColor - neutralVertex);
    float isBiomeTinted = smoothstep(0.1, 0.3, biomeStrength);
    
    // Calculate base bias strength
    float baseBiasStrength = GRAY_BIAS_STRENGTH * totalBiasRange * finalInRange;
    
    // Add biome boost
    float biomeBoost = GRAY_BIAS_STRENGTH * 0.4 * isBiomeTinted * finalInRange;
    biomeBoost *= (inMidToneRange + inBrightToneRange * 0.5);
    baseBiasStrength += biomeBoost;
    baseBiasStrength = min(baseBiasStrength, GRAY_BIAS_STRENGTH);
    
    // Create a curve that pushes mid-tones toward white while preserving order
    float newLuminance = inputLuminance;
    if (baseBiasStrength > 0.0) {
        // Use a power curve that maintains ordering
        // Lower values get pushed up more, but never past higher values
        float biasTarget = TEXTURE_PAPER_WHITENESS;
        
        // Create a smooth curve: f(x) = x + (target - x) * bias * (1 - x)
        // This ensures that higher input values always result in higher output values
        float luminanceBias = baseBiasStrength * (1.0 - inputLuminance) * (1.0 - inputLuminance);
        newLuminance = inputLuminance + (biasTarget - inputLuminance) * luminanceBias;
        
        // Ensure we never exceed the target or go below the input
        newLuminance = clamp(newLuminance, inputLuminance, biasTarget);
    }
    
    // Apply the luminance change while preserving color direction
    vec3 result = inputColor;
    if (inputLuminance > 0.001 && newLuminance != inputLuminance) {
        // Scale the color to match the new luminance
        float luminanceScale = newLuminance / inputLuminance;
        result = inputColor * luminanceScale;
        
        // For very gray colors, mix toward the target white to avoid pure scaling
        float grayness = 1.0 - length(inputColor - vec3(inputLuminance));
        grayness = smoothstep(0.8, 1.0, grayness); // Only very gray colors
        
        vec3 targetWhite = vec3(TEXTURE_PAPER_WHITENESS);
        
        // Preserve biome tints in the white target
        if (isBiomeTinted > 0.5) {
            vec3 tintDirection = normalize(vertexColor);
            targetWhite = mix(targetWhite, targetWhite * tintDirection * 1.05, 0.1);
        }
        
        // For very gray areas, blend toward the target white instead of just scaling
        result = mix(result, targetWhite * (newLuminance / TEXTURE_PAPER_WHITENESS), 
                    grayness * baseBiasStrength * 0.3);
    }
    
    // Apply brightness boost
    if (baseBiasStrength > 0.0) {
        float brightnessMultiplier = GRAY_BIAS_BRIGHTNESS_LIFT * (1.0 - smoothstep(0.7, 0.9, newLuminance));
        float brightnessBias = baseBiasStrength * brightnessMultiplier * 0.5;
        result = result * (1.0 + brightnessBias);
    }
    
    return result;
}


/* RENDERTARGETS:0,4 */
void main()
{
    vec3 dir = normalize((gbufferModelViewInverse * vec4(shadowLightPosition,0)).xyz);
    float flip = clamp(dir.y/.1,-1.,1.); dir *= flip;
    vec3 norm = normalize(cross(dFdx(world),dFdy(world)));
    float lambert = (id>1.5)?dir.y*.5+.5:dot(norm,dir)*.5+.5;
    
    // Calculate basic sun reflection first
    float sun = exp((dot(reflect(normalize(world),norm),dir)-1.)*15.*(1.5-.5*flip));

    // Fog calculation (from working implementation)
    float zSky = clamp(dot(normalize(vPos), normalize(upPosition)), 0.0, 1.0);
    vec3 skyFog = mix(fogColor, skyColor, zSky);
	
    
    // Original texture sampling with optional voronoi distortion
    vec2 res = vec2(textureSize(texture,0));
    vec4 col;
    
    // Declare voronoi variables once at the top level

    // Standard texture sampling without distortion
        col = texture2D(texture, coord0);

    // Apply vertex color
    col.rgb *= color.rgb;

    // WATER-SPECIFIC SHADOW CALCULATION
    vec3 sLight = vec3(1.0);
	float shadowFactor = 1.0; // Add this to track shadow strength
	#if ENABLE_SHADOWS == 1
		if(length(world) < shadowDistance){
			vec3 sWorld = vec3(shadowModelView * vec4(world, 1.0));
			vec3 sClip = vec3(shadowProjection * vec4(sWorld, 1.0));

			// Apply distortion to shadow coordinates
			sClip.xyz = distortShadow(sClip.xyz);

			// Water-specific shadow bias calculation - increased bias to prevent banding
			float sBias = 0.0;
			switch(shadowMapResolution){
				case 2048: sBias = 0.0039296875 * WATER_SHADOW_BIAS_MULTIPLIER; break;
				case 4096: sBias = 0.002953125 * WATER_SHADOW_BIAS_MULTIPLIER; break;
				case 8192: sBias = 0.002220703125 * WATER_SHADOW_BIAS_MULTIPLIER; break;
				default: sBias = 0.00480625 * WATER_SHADOW_BIAS_MULTIPLIER;
			}

			float dist = mix(1.0, length(sClip.xy), 0.85);
			sClip.xy /= dist;
			sClip.z -= (dist * dist * sBias) / clamp(dot(normalize(shadowLightPosition), normalize(upPosition)), 0.0, 1.0);
			
			// Modified normal-based bias for water
			float ndotl = max(dot(normalize(N.xyz), normalize(shadowLightPosition)), 0.1); // Increased minimum
			float finalBias = sBias * (1.0 / ndotl) * (dist * 0.3); // Reduced multiplier for water
			sClip.z -= finalBias;
			
			// Additional bias for water to account for wave distortion
			sClip.z -= sBias * 0.5;
			
			vec3 sSPos = sClip.xyz * 0.5 + 0.5;

			// Water-specific shadow sampling with reduced PCF
			#if SOFT_SHADOWS == 1
				float bRad = PCF_BLUR_RADIUS / shadowMapResolution;
				float sMap0 = sWaterPCF(shadowtex0, sSPos, bRad);
				float sMap1 = sWaterPCF(shadowtex1, sSPos, bRad);
			#else
				float sMap0 = step(sSPos.z, texture(shadowtex0, sSPos.xy).r);
				float sMap1 = step(sSPos.z, texture(shadowtex1, sSPos.xy).r);
			#endif

			// Calculate shadow factor for sun glare modulation
			shadowFactor = (sMap1 + sMap0) * 0.5;

			// Colored shadows for water
			#if COLORED_SHADOWS == 1
				vec4 sMapC = texture2D(shadowcolor0, sSPos.xy);
				sLight = mix(sLight, sMapC.rgb, sqrt(sMapC.a * 2.0)) * (sMap1 - sMap0);
				sLight += sMap0;
			#else
				sLight = vec3(sMap1 + sMap0) * 0.5;
			#endif
		}
	#endif

	// Apply shadow-aware sun glare
    vec4 shine = vec4(vec3(sun)*flip*flip,0)*Shininess*step(.9,id)*step(id,1.1) * shadowFactor;
	
	// LIGHTING CALCULATION
	float sBright = mix(SHADOW_BRIGHTNESS, 1.0, rainStrength);
	float lVis = texture2D(lightmap, vec2(0.0, coord1.y)).r;

	float blockLightCoord = coord1.x * BLOCK_LIGHT_INTENSITY;
	blockLightCoord = clamp(blockLightCoord, 0.0, 1.0); // Keep within valid range

	vec3 lMap = texture2D(lightmap, vec2(blockLightCoord, coord1.y * sBright)).rgb;

	lMap *= color.a;
	sBright += (1.0 - lVis) * (1.0 - sBright);
	lMap += sLight * (1.0 - sBright);
    
    // Apply lighting, biome colors, and other effects
    #if ENABLE_DIRECTIONAL_LIGHTING == 1
        vec3 shad = mix(skyColor*.5+.2,vec3(1),lambert) * lMap;
    #else
        vec3 shad = vec3(1) * lMap;
    #endif
    
    col *= vec4(shad*(1.-blindness),1) + shine;

    // Apply entity color
    col.rgb = mix(col.rgb,entityColor.rgb,entityColor.a);

    // Apply fog
    float farDist = far;
    float fogDist = clamp(length(world) / farDist, 0.0, 1.0);
        fogDist = (isEyeInWater == 1) ? fogDist : pow(fogDist, 3.0);
    col.rgb = mix(col.rgb, skyFog, fogDist);
    
	// Get the original texture color before biome tinting for better gray detection
	vec4 originalTexture;
   
    // Store ORIGINAL texture color (before lighting) in colortex4
    vec4 originalTextureColor = originalTexture * vec4(color.rgb, 1.0);
    
    // Apply lighting to get final shadowed color
    vec3 finalColor = col.rgb; // This already has shadows applied
    
    // Output final lit color to colortex0, original color to colortex4
    gl_FragData[0] = vec4(finalColor, col.a);
	gl_FragData[1] = vec4(originalTextureColor.rgb, 1.0);
}
