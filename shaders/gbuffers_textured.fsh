#version 130
#include "commonSettings.glsl"

#define VORONOI_BLOCK_DISTORTION 1 // Enable voronoi block distortion [0 1]

uniform sampler2D noisetex;
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform sampler2D depthtex0;
uniform sampler2D gaux3; //Cel Ramp
uniform sampler2D gaux4; //Toon Ramp
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
varying float terrainFlag;

#if CEL == ON
#define ramptex gaux3
#else
#define ramptex gaux4
#endif

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
    float bNoise = texture2D(noisetex, gl_FragCoord.xy / vec2(noiseTextureResolution)).r;
    for(int i = 0; i < PCF_SAMPLE; i++){
        sMap += step(sSPos.z, texture2D(sTex, sSPos.xy + (rot2D(bNoise * 6.28318531) * offsets[i] * bRad)).r);
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

// Simple texture outline detection with very small sampling to (attempt to) avoid block edges LEGACY FUNCTION
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


/* RENDERTARGETS:0,4 */
void main()
{
    vec3 dir = normalize((gbufferModelViewInverse * vec4(shadowLightPosition,0)).xyz);//将摄像机坐标系下光源向量从摄像机坐标转为世界坐标
    float flip = clamp(dir.y/.1,-1.,1.); dir *= flip;//避免晚上出现反着打光
    vec3 norm = normalize(cross(dFdx(world),dFdy(world)));//对坐标求导 叉乘求法线

    #if LAMBERT_MODE == HALF_LAMBERT
    float lambert = (id>1.5)?pow(dir.y*.5+.5,2):pow(dot(norm,dir)*0.5+0.5,2);
    #endif
    #if LAMBERT_MODE == LAMBERT
    float lambert = (id>1.5)?dir.y:dot(norm,dir);
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

#if ENABLE_SHADOWS == 1
    // `oldLighting=true` (shaders.properties) also leaves vanilla's per-face brightness
    // in gl_Color. That property is pack-global: it is read once when the pack loads and
    // OptiFine/Iris parse it before the option macros, so no option and no #if can turn
    // it off for a single branch. The shadow path below lights the surface itself, so the
    // baked vanilla factor would be applied a second time (up 1.0, down 0.5, sides
    // 0.8 / 0.6) and darken/flatten every face by that amount. Dividing it back out is
    // the per-fragment equivalent of oldLighting=false for this branch; AO and the biome
    // tint are part of gl_Color in both modes and stay.
    // Terrain only: entities, block entities, particles and text carry the vanilla
    // minecraft_mix_light() term instead (handled in the ENABLE_SHADOWS == 0 branch),
    // not the block-orientation multiplier.
    if (terrainFlag >= 0.5) {
        vec3 nWorld = mat3(gbufferModelViewInverse) * N.xyz;
        col.rgb /= vanillaFaceShade(nWorld);
    }
#endif

    // gl_Color.a must reach the output alpha (vanilla does texture.a * Color.a).
    // Terrain / entity models carry a == 1.0 so nothing changes there, but every
    // quad whose render type modulates alpha - the vanilla entity shadow blob,
    // alpha-tinted entity parts, text - needs it, otherwise its alpha collapses
    // to the raw sprite alpha and the soft shadow blob turns into solid black.
    col.a *= color.a;

    // ======================= LIGHTING =======================
    // `shad` is the light factor that is multiplied into the texture color at the end.
    // It is declared inside each branch below.

#if ENABLE_SHADOWS == 0
    // ---------------- Vanilla lighting (shadows disabled) ----------------
    vec3 shad;
    // Minecraft's block renderer bakes the directional shading into the vertex color,
    // NOT into a per-pixel normal:
    //   ModelBlockRenderer.renderModelFaceFlat / renderModelFaceAO
    //     -> BlockAndTintGetter.getShade(Direction, boolean)
    //         down = 0.5, up = 1.0, north/south = 0.8, west/east = 0.6
    //     -> that constant is multiplied with the ambient occlusion and the biome tint
    //     -> putQuadData() writes it as the vertex color
    // The final vanilla pixel is then just:
    //   texture * vertexColor * lightmap
    // OptiFine/Iris expose that same vertex color as `color` (gl_Color), but only
    // when `oldLighting=true` is set in shaders.properties (it is). With the default
    // oldLighting=false the orientation multiplier is dropped and all block faces
    // would get the same brightness, so this setting is required for vanilla parity.
    // Since the multiplier is already in color, no N·L / normal term is needed here.
    // The shadow path above does the opposite: it divides that baked factor back out of
    // col.rgb (vanillaFaceShade()) because it lights the face with its own directional
    // term, which is how oldLighting is effectively switched off for ENABLE_SHADOWS == 1.
    // Note: SHADOW_BRIGHTNESS / BLOCK_LIGHT_INTENSITY / LAMBERT_MODE only belong to
    // the stylised shadowed path below and are intentionally ignored here.
    shad = texture2D(lightmap, coord1.xy).rgb;

    #if CEL == ON
        // Cel shading is an explicit stylistic option; with CEL == OFF the light
        // factor above is exactly the vanilla one.
        float celLight = min(0.9999, max(shad.r, max(shad.g, shad.b)));
        shad = vec3(texture2D(ramptex, vec2(celLight, 0.5)).a * 1.2);
    #endif

    // Vanilla entity lighting: minecraft_mix_light() from
    // assets/minecraft/shaders/include/light.glsl
    //   lightAccum = min(1, (max(0, dot(L0, n)) + max(0, dot(L1, n))) * 0.6 + 0.4)
    // with the two fixed world-space diffuse directions (0.2, 1, -0.7) and
    // (-0.2, 1, 0.7): top bright, bottom dark, sides in between.
    // Terrain is excluded - it already has the per-face factor in gl_Color
    // (oldLighting). Terrain is the only geometry that carries mc_Entity.y (+-1)
    // and at_midBlock, so terrainFlag identifies it (see the vertex shader).
    vec3 normalWorld = mat3(gbufferModelViewInverse) * N.xyz;
    float normalLenSq = dot(normalWorld, normalWorld);
    // Text / billboards have no normal (gl_Normal == 0): normalLenSq is 0 / NaN,
    // so the comparison fails and they stay lightmap-only.
    if (terrainFlag < 0.5 && normalLenSq > 0.5) {
        normalWorld *= inversesqrt(normalLenSq);
        vec3 lightDir0 = normalize(vec3(0.2, 1.0, -0.7));
        vec3 lightDir1 = normalize(vec3(-0.2, 1.0, 0.7));
        float light0 = max(0.0, dot(lightDir0, normalWorld));
        float light1 = max(0.0, dot(lightDir1, normalWorld));
        shad *= min(1.0, (light0 + light1) * 0.6 + 0.4);
    }
#else
    // ---------------- Shadowed / stylised lighting (existing behaviour) ----------------
    #ifdef IS_IRIS

    #else
    //col.rgb *= vec3(1.3);
    #endif
    
    // Apply gray bias BEFORE lighting calculations

    // SHADOW CALCULATION
	vec3 sLight = vec3(1.0);
    
    #if SHADOW_DISTANCE == -1  //-1 mean auto
    float shadowDist = far;
    #else
    float shadowDist = SHADOW_DISTANCE;
    #endif

	#if ENABLE_SHADOWS == 1
		if(length(world) < shadowDist && id != 1.0){
			if(length(world) < shadowDist){
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
					float sMap0 = step(sSPos.z, texture2D(shadowtex0, sSPos.xy).r);
					float sMap1 = step(sSPos.z, texture2D(shadowtex1, sSPos.xy).r);
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

	// Sky light is sampled at its FULL value. `sBright` describes how much of it a
	// *shadowed* surface keeps, so it must not be applied to every pixel: dimming the
	// lightmap globally made the whole daytime lose ~40% of its sky light (day looked
	// like night) and left the sun term without headroom, so lit and shadowed surfaces
	// ended up close in brightness. The per-pixel shadow factor is applied further down.
	vec3 lMapFull = texture2D(lightmap, vec2(coord1.x, coord1.y)).rgb;
	vec3 lMapAmbient = texture2D(lightmap, vec2(0.0, coord1.y)).rgb;

	// Calculate the block light contribution (difference between full and ambient)
	vec3 blockLightContribution = max(vec3(0.0), lMapFull - lMapAmbient);

	// How much of the sun reaches this face: 0 = sunlit, 1 = in shadow or facing away.
	// sLight already carries both the shadow map visibility and the N·L facing term,
	// and it can overshoot 1 on lit faces, hence the clamp.
	float shadowAmount = clamp(1.0 - dot(sLight, vec3(1.0 / 3.0)), 0.0, 1.0);

	// Sky light and block light are kept apart here.
	// The sun terms below (shadow visibility, N·L, LAMBERT_MODE) only describe how
	// much *sky* light reaches a face. Applying them to the block light as well is
	// what made torches almost disappear on back-lit faces: a west/east face already
	// gets 0.6 from the vertex colour, the facing term takes another ~0.5 and the
	// 0.8 intensity left a torch at ~25% of its real strength. Block lights are
	// local, so they are added after the sun terms, at full strength, plus the
	// extra shadow boost while the face receives no sun.
	//
	// gl_Color.a must NOT be used as a light multiplier here.
	// This pack does not enable "separateAo", so the vanilla AO lives in
	// gl_Color.rgb and is already applied above by `col.rgb *= color.rgb`.
	// For terrain gl_Color.a is 1.0, but for the non-terrain programs that share
	// this shader (entities, block entities, the hand, particles) the a component
	// is a tint/alpha value and is frequently 0.0 - multiplying the light by it
	// zeroed both the sky light and the block light term, which turned an entity
	// standing in an occluded spot pitch black while the terrain around it
	// (a == 1.0) stayed correctly lit.
	// Full sky light where the sun reaches the face, only `sBright` of it where the shadow
	// map says the sun is blocked. That is the contrast between light and shadow: the sun
	// term below then adds the direct light on the lit side only, instead of the ambient
	// being equally dimmed everywhere. sLight = visibility * N.L * 2, so * 0.5 gives 0..1.
	vec3 skyLight = lMapAmbient * mix(sBright, 1.0, clamp(dot(sLight, vec3(0.5)), 0.0, 1.0));
	vec3 blockLight = blockLightContribution
		* (BLOCK_LIGHT_INTENSITY * mix(1.0, BLOCK_LIGHT_SHADOW_BOOST, shadowAmount));

	sBright += (1.0 - lVis) * (1.0 - sBright);
	skyLight += sLight * (1.0 - sBright);

    #if CEL == 1
        // Cel shading ramps the light into flat bands. The block light share of the
        // ramp is split off again afterwards, so the sun terms below cannot dim
        // torches while the banding (and the flat colour) of the cel look is kept.
        vec3 totalLight = skyLight + blockLight;
        vec3 ramped = vec3(texture2D(ramptex, vec2(min(0.9999, totalLight.r), 0.5)).a * 1.2);
        float blockShare = clamp(blockLight.r / max(totalLight.r, 1e-4), 0.0, 1.0);
        blockLight = ramped * blockShare;
        skyLight = ramped - blockLight;
    #endif

    vec3 shad;

     // Non-emissive blocks: normal lighting
    #if ENABLE_DIRECTIONAL_LIGHTING == 1
        vec3 lambertCol = texture2D(ramptex,vec2(lambert, 0.5)).rgb;
        shad = ((skyColor*.5+.2) * (vec3(1) - lambertCol) + lambertCol) * skyLight + blockLight;
    #else
        shad = vec3(1) * skyLight + blockLight;
    #endif
        
#endif // ENABLE_SHADOWS == 0

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
    if(PAPER_WORLD == ON)
    {
        finalColor = vec3(1,1,1);
    }

    #if ENABLE_TEXTURE_OUTLINES == 1
        // Get TEXTURE texture outlines only (no block edges)
        float textureOutline = getTEXTURETextureOutline(coord0, originalTexture);
        
        // Apply outline as much darker lines for dramatic effect
        float outline = textureOutline * TEXTURE_OUTLINE_STRENGTH;
        finalColor = mix(finalColor, vec3(0.05, 0.05, 0.05), outline); // Much darker outline color
    #endif
    
    // Output final lit color to colortex0, original color to colortex4
    gl_FragData[0] = vec4(finalColor, col.a);
	gl_FragData[1] = vec4(originalTextureColor.rgb, 1.0);
}
