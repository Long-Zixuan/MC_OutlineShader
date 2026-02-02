#version 120

#define FALLOFF_CURVE 0.0 // [-10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
//#define x linearDepth
#define a actualMaxDistance
#define p FALLOFF_CURVE

#define OFF 0
#define ON 1
#define LINEAR_DEPTH OFF // [OFF ON]
/////

#define THRESHOLD 0.0001 // [0.00001 0.0001 0.0002 0.001 0.002 0.01]
#define RIM_OFFECT 0.001 // [0.0001 0.0002 0.0005 0.001 0.002 0.003 0.004 0.005 0.01]
#define OUTLINE_COL 0.3 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9]
#define OUTSIDE  -1
#define INSIDE 1
#define OUTLINE_MODE INSIDE // [INSIDE OUTSIDE]
//#define RAMP_VALUE 0.0001
#define SCREEN_VALUE 2000

uniform float far;
uniform sampler2D depthtex0;

uniform sampler2D colortex0;

uniform float viewHeight;
uniform float viewWidth;

vec2 texelStep = 1.0 / vec2(viewWidth, viewHeight);
const float lumaThreshold = 0.5;
const float mulReduce = 1.0 / 8.0;
const float minReduce = 1.0 / 128.;
const float maxSpan = 8.0;

uniform mat4 gbufferProjectionInverse;
varying vec2 texcoord;

/* DRAWBUFFERS:0 */

float getRimIntensity(float depthOft1,float depthOft2,float depth)
{
   float depthDiffer1 = (depthOft1 - depth) * OUTLINE_MODE;
   float depthDiffer2 = (depthOft2 - depth) * OUTLINE_MODE;

   float rimIntensity1 = step(THRESHOLD,depthDiffer1);
   float rimIntensity2 = step(THRESHOLD,depthDiffer2);
   float rimIntensity = max(rimIntensity1,rimIntensity2);
   float rampValue = 0.0001;
   if(LINEAR_DEPTH == ON)
   {
      rampValue = 0.001;
   }
   //rampValue = rampValue * (1 + depth * 1);
   float isRamp = step(rampValue,abs(depthDiffer1+depthDiffer2));

   return min(rimIntensity,isRamp);
}

float screenSpaceToViewSpace(float depth, mat4 projInv) {
	depth = depth * 2.0 - 1.0;
	return projInv[3].z / (projInv[2].w * depth + projInv[3].w);
}

float screenDepth2LinearDepth(float depth)
{
   if(LINEAR_DEPTH == OFF)
   {
      return depth;
   }
   float viewDepth = screenSpaceToViewSpace(depth, gbufferProjectionInverse);
   float linearDepth = max(-viewDepth, 0.0);
   float actualMaxDistance = float(far);
   if(FALLOFF_CURVE != 0.0)
   {
      linearDepth = (exp(p * (linearDepth / a)) - 1.0) / (exp(p) - 1.0);
   } else 
   {
      linearDepth /= actualMaxDistance;
   }
   linearDepth = 1.0 - linearDepth;
   return linearDepth;
}


void main() 
{
	gl_FragData[0] = texture(colortex0, texcoord);
   float depth = texture(depthtex0, texcoord).r;
   depth = screenDepth2LinearDepth(depth);

   float depthLeft = texture(depthtex0, vec2(texcoord.x + (RIM_OFFECT / viewWidth) * SCREEN_VALUE ,texcoord.y)).r;
   float depthRight = texture(depthtex0, vec2(texcoord.x - (RIM_OFFECT / viewWidth) * SCREEN_VALUE ,texcoord.y )).r;
   float depthUp = texture(depthtex0, vec2(texcoord.x,texcoord.y + (RIM_OFFECT / viewHeight) * SCREEN_VALUE )).r;
   float depthDown = texture(depthtex0, vec2(texcoord.x,texcoord.y - (RIM_OFFECT / viewHeight) * SCREEN_VALUE )).r;

   depthLeft = screenDepth2LinearDepth(depthLeft);
   depthRight = screenDepth2LinearDepth(depthRight);
   depthUp = screenDepth2LinearDepth(depthUp);
   depthDown = screenDepth2LinearDepth(depthDown);

   float rimIntensityV = getRimIntensity(depthLeft,depthRight,depth);

   float rimIntensityH = getRimIntensity(depthUp,depthDown,depth);

   float rimIntensity = max(rimIntensityV,rimIntensityH);

   vec4 outlineCol = vec4(OUTLINE_COL,OUTLINE_COL,OUTLINE_COL,1);

   if(rimIntensity == 1)
   {
      gl_FragData[0] = texture(colortex0, texcoord) * outlineCol;
      return;
   }

}

//LZX vscode 2025/03/24

//||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
//||||--==||||||||||||||||------==||||||||||----------==||||
//||||--==||||||||||||||------------==||||||------------==||
//||||--==|||||||||||||---==||||----==||||||--==||||----==||
//||||--==|||||||||||||---==||||||||||||||||--------------||
//||||--==|||||||||||||---==||||----==||||||----------==||||
//||||------------==||||------------==||||||--==||||||||||||
//||||------------==||||||------==||||||||||--==||||||||||||
//||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
//|||||||||||||||||LZX.Celluloid.Project||||||||||||||||||||