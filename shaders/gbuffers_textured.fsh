#version 130
#include "commonSettings.glsl"

#define VORONOI_BLOCK_DISTORTION 1 // Enable voronoi block distortion [0 1]

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
varying float emissiveFlag;

// Shadow sampling array https://github.com/jhk2/glsandbox/blob/master/kgl/samples/shadow/pcss.glsl
const vec2 offsets[64] = vec2[64](
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
    vec2(0.5485036, 0.8288581),
    vec2(-0.2023022, -0.9551743),
    vec2(0.165668, -0.6428169),
    vec2(0.2866438, -0.5012833),
    vec2(-0.5582264, 0.2904861),
    vec2(-0.2522391, 0.401359),
    vec2(-0.428396, 0.1072979),
    vec2(-0.06261792, 0.3012581),
    vec2(0.08908027, -0.8632499),
    vec2(0.9636437, 0.05915006),
    vec2(0.8639213, -0.309005),
    vec2(-0.03422072, 0.6843638),
    vec2(-0.3734946, -0.8823979),
    vec2(-0.3939881, 0.6955767),
    vec2(-0.4499089, 0.4563405),
    vec2(0.07500362, 0.9114207),
    vec2(-0.9658601, -0.1423837),
    vec2(-0.7199838, 0.4981934),
    vec2(-0.8982374, 0.2422346),
    vec2(-0.8048639, 0.01885651),
    vec2(-0.8975322, 0.4377489),
    vec2(-0.7135055, 0.1895568),
    vec2(0.4507209, -0.3764598),
    vec2(-0.395958, -0.3309633),
    vec2(-0.6084799, 0.02532744),
    vec2(-0.2037191, 0.5817568),
    vec2(0.4493394, -0.6441184),
    vec2(0.3147424, -0.7852007),
    vec2(-0.5738106, 0.6372389),
    vec2(0.5161195, -0.8321754),
    vec2(0.6553722, -0.6201068),
    vec2(-0.2554315, 0.8326268),
    vec2(-0.5080366, 0.8539945)
);

#define rot2D(r) mat2(cos(r), sin(r), -sin(r), cos(r))


// PCF shadow sampling function
float sPCF(sampler2D sTex, vec3 sSPos, float bRad){
    float sMap = 0.0;
    float bNoise = texture(noisetex, gl_FragCoord.xy / vec2(noiseTextureResolution)).r;
    for(int i = 0; i < PCF_SAMPLE; i++){
        sMap += step(sSPos.z, texture(sTex, sSPos.xy + (rot2D(bNoise * 6.28318531) * offsets[i] * bRad)).r);
    }
    return sMap / PCF_SAMPLE;
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
    {
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
    }
    return off;
}

vec2 off(vec2 p,vec3 s)
{
    return voronoi(p,s.xy+s.yz);
}


/* RENDERTARGETS:0,4 */
void main()
{
    vec3 dir = normalize((gbufferModelViewInverse * vec4(shadowLightPosition,0)).xyz);
    float flip = clamp(dir.y/.1,-1.,1.); dir *= flip;
    vec3 norm = normalize(cross(dFdx(world),dFdy(world)));
#ifdef IS_IRIS
    #if LAMBERT_MODE == HALF_LAMBERT
    float lambert = (id>1.5)?dir.y*.5+.5:dot(norm,dir)*0.5+0.5;
    #endif
    #if LAMBERT_MODE == LAMBERT
    float lambert = (id>1.5)?dir.y:dot(norm,dir);
    #endif
#else
    #if LAMBERT_MODE == HALF_LAMBERT
    float lambert = dir.y*.5+.5;
    #endif
    #if LAMBERT_MODE == LAMBERT
    float lambert = (id>1.5)?dir.y:dot(norm,dir);
    #endif
#endif
    float sun = exp((dot(reflect(normalize(world),norm),dir)-1.)*15.*(1.5-.5*flip));
    vec4 shine = vec4(vec3(sun)*flip*flip,0)*Shininess*step(.9,id)*step(id,1.1);

    // Fog calculation
    float zSky = clamp(dot(normalize(vPos), normalize(upPosition)), 0.0, 1.0);
    vec3 skyFog = mix(fogColor, skyColor, zSky);
    
    // texture sampling with optional voronoi distortion
    vec2 res = vec2(textureSize(texture,0));
    vec4 col;
    
    // Declare voronoi variables once at the top level
    #if ENABLE_VORONOI_DISTORTION == 1 && VORONOI_BLOCK_DISTORTION == 1
        vec2 cell = coord0*res;
        vec2 floo = floor(cell);
        vec2 mi = floor(floo/16.)*16.;
        vec2 ma = mi+15.;
        vec3 dif = floor(vert);
        vec2 shift = off(cell,dif);
        vec2 off1 = clamp(shift,mi,ma)/res;
        vec2 gx = dFdx(coord0);
        vec2 gy = dFdy(coord0);
        
        // Apply voronoi distortion
        col = textureGrad(texture,off1,gx,gy);
        if (id<1.5) col = mix(textureGrad(texture,coord0,gx,gy),col,col.a);
    #else
        // Standard texture sampling without distortion
        col = texture2D(texture, coord0);
    #endif
    
    // STORE ORIGINAL TEXTURE DATA FOR EMISSIVE DETECTION
    vec4 originalTexture = col; // Store the pure texture color
    float originalTextureBrightness = dot(originalTexture.rgb, vec3(0.299, 0.587, 0.114));
    
    // Apply vertex color (biome tinting)
    col.rgb *= color.rgb;

    #ifdef IS_IRIS

    #else
    //col.rgb *= vec3(1.3);
    #endif
    
    // Apply gray bias BEFORE lighting calculations

    // SHADOW CALCULATION
	vec3 sLight = vec3(1.0);

	#if ENABLE_SHADOWS == 1
		if(length(world) < shadowDistance && id != 1.0){
			if(length(world) < shadowDistance){
				vec3 sWorld = vec3(shadowModelView * vec4(world, 1.0));
				vec3 sClip = vec3(shadowProjection * vec4(sWorld, 1.0));

				// Apply distortion to shadow coordinates (your existing approach)
				sClip.xyz = distortShadow(sClip.xyz);

				// Improved bias calculation that accounts for distortion
				float sBias = 0.0;
				switch(shadowMapResolution){
					case 2048: sBias = 0.0047296875; break;
					case 4096: sBias = 0.004653125; break;
					case 8192: sBias = 0.004520703125; break;
					default: sBias = 0.00480625;
				}

				float dist = mix(1.0, length(sClip.xy), 0.85);
				sClip.xy /= dist;
				
				// Scale bias by distortion amount AND distance (improved for far distances)
				float distortScale = 1.0 + (dist - 1.0) * 0.5; // Base distortion scaling
				
				// Add additional scaling for far distances where vertex distortion is extreme
				float worldDistance = length(world);
				float farDistanceScale = 1.0;
				if (worldDistance > FAR_DISTANCE_BIAS_START) {
					farDistanceScale = 1.0 + (worldDistance - FAR_DISTANCE_BIAS_START) / FAR_DISTANCE_BIAS_RANGE;
					farDistanceScale = min(farDistanceScale, FAR_DISTANCE_BIAS_MAX);
				}
				
				sBias *= distortScale * farDistanceScale;
				
				sClip.z -= (dist * dist * sBias) / clamp(dot(normalize(shadowLightPosition), normalize(upPosition)), 0.0, 1.0);
				
				// normal-based bias with distance scaling
				float ndotl = max(dot(normalize(N.xyz), normalize(shadowLightPosition)), 0.001);
				float finalBias = sBias * (1.0 / ndotl) * (dist * 0.3) * farDistanceScale; // Apply distance scaling here too
				sClip.z -= finalBias;
				
				vec3 sSPos = sClip.xyz * 0.5 + 0.5;

				#if SOFT_SHADOWS == 1
					float bRad = PCF_BLUR_RADIUS / shadowMapResolution;
					float sMap0 = sPCF(shadowtex0, sSPos, bRad);
					float sMap1 = sPCF(shadowtex1, sSPos, bRad);
				#else
					float sMap0 = step(sSPos.z, texture(shadowtex0, sSPos.xy).r);
					float sMap1 = step(sSPos.z, texture(shadowtex1, sSPos.xy).r);
				#endif

				#if COLORED_SHADOWS == 1
					vec4 sMapC = texture2D(shadowcolor0, sSPos.xy);
					sLight = mix(sLight, sMapC.rgb, sqrt(sMapC.a * 2.0)) * (sMap1 - sMap0);
					sLight += sMap0;
				#else
					sLight = vec3(sMap1 + sMap0) * 0.5;
				#endif
			}

			// directional lighting
			if(N.a < 1.0){
				sLight = sLight * clamp(dot(normalize(shadowLightPosition), N.xyz), 0.0, 1.0) * 2.0;
			}
		}
	#endif

	// LIGHTING CALCULATION
	float sBright = mix(SHADOW_BRIGHTNESS, 1.0, rainStrength);
	float lVis = texture2D(lightmap, vec2(0.0, coord1.y)).r;

	// Always sample at FULL block light coordinate to get the proper lightmap value
	vec3 lMapFull = texture2D(lightmap, vec2(coord1.x, coord1.y * sBright)).rgb;
	vec3 lMapAmbient = texture2D(lightmap, vec2(0.0, coord1.y * sBright)).rgb;

	// Calculate the block light contribution (difference between full and ambient)
	vec3 blockLightContribution = lMapFull - lMapAmbient;

	// Scale the contribution by intensity, then add back to ambient
	vec3 lMap = lMapAmbient + (blockLightContribution * BLOCK_LIGHT_INTENSITY);

	lMap *= color.a;
	sBright += (1.0 - lVis) * (1.0 - sBright);
	lMap += sLight * (1.0 - sBright);

    vec3 shad;
    
    // Non-emissive blocks: normal lighting
    #if ENABLE_DIRECTIONAL_LIGHTING == 1
        shad = mix(skyColor*.5+.2,vec3(1),lambert) * lMap;
    #else
        shad = vec3(1) * lMap;
    #endif

    #if CEL == 1
        float x = (lambert > -0.1) ? 1 : 0.5;
        if(lMap.r > 1)
        {
            lMap = vec3(1.2);
        }
        else if(lMap.r > 0.7)
        {
            lMap = vec3(0.8);
        }
        else if(lMap.r > 0.4)
        {
            lMap = vec3(0.6);
        }
        else
        {
            lMap = vec3(0.4);
        }
        shad = mix(skyColor,vec3(1),x) * lMap;
    #endif
    
        
    col *= vec4(shad*(1.-blindness),1) + shine;

    // Apply entity color
    col.rgb = mix(col.rgb,entityColor.rgb,entityColor.a);
    
    // Apply fog
    float farDist = far;
    float fogDist = clamp(length(world) / farDist, 0.0, 1.0);
        fogDist = (isEyeInWater == 1) ? fogDist : pow(fogDist, 3.0);
    col.rgb = mix(col.rgb, skyFog, fogDist);
	
    // Store ORIGINAL texture color (before lighting) in colortex4
    vec4 originalTextureColor = originalTexture * vec4(color.rgb, 1.0);
    
    // Apply lighting to get final shadowed color
    vec3 finalColor = col.rgb; // This already has shadows applied
    
    // Output final lit color to colortex0, original color to colortex4
    gl_FragData[0] = vec4(finalColor, col.a);
	gl_FragData[1] = vec4(originalTextureColor.rgb, 1.0);
}
