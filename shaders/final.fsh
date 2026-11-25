#version 120

#define FALLOFF_CURVE 0.0 // [-10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
//#define x linearDepth
#define a actualMaxDistance
#define p FALLOFF_CURVE

#define OFF 0
#define ON 1
#define LINEAR_DEPTH ON // [OFF ON]
/////

#define THRESHOLD 0.0001 // [0.00001 0.0001 0.0002 0.001 0.002 0.01]
#define RIM_OFFECT 0.001 // [0.0001 0.0002 0.0005 0.001 0.002 0.003 0.004 0.005 0.01]
#define OUTLINE_COL 0.3 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9]
#define OUTSIDE  -1
#define INSIDE 1
#define OUTLINE_MODE INSIDE // [INSIDE OUTSIDE]
//#define RAMP_VALUE 0.0001
#define SCREEN_VALUE 2000

//LINEAR DEPTH
#define LinearDepthMultiplier 0.001
#define LinearDepthBias 0.7 
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
      rampValue = pow((1 - depth) * LinearDepthMultiplier, LinearDepthBias);
   }
   //rampValue = rampValue * (1 + depth * 1);
   float isRamp = step(rampValue,abs(depthDiffer1+depthDiffer2));

   //================= 斜面 / 边缘 判别(二阶射影仿射残差) =================
   //透视投影下, 平面在屏幕空间严格满足「1/z 对像素坐标是仿射函数」。
   //所以对 1/z 取二阶差分: 平面(任意朝向、任意视线夹角)恒为 0, 边缘处才等于跳变量级。
   //一阶信息做不到这件事 —— 法线夹角、深度一阶差分和平面朝向共用同一组自由度,
   //陡斜面和浅边缘在数学上可以互相伪装, 所以那一版判据必然失效。
   //w 的取法:
   //  LINEAR_DEPTH = ON : 传入的 depth 是线性深度 1 - d/far, 取倒数还原 1/z;
   //  LINEAR_DEPTH = OFF: 传入的 depth 是窗口深度, 窗口深度本身与 1/z 成仿射, 直接使用;
   //  若 FALLOFF_CURVE != 0, depth 已被该曲线重映射, 需要先反解曲线再代入。
   //注: 两个面相交的折棱(法线不连续)也会被判成边缘; 若要把折棱和遮挡轮廓分开,
   //    需再用 h 与 2h 两个尺度比较残差随 h 的幂次(常数=遮挡边, 正比于 h=折棱)。
   float wC = (LINEAR_DEPTH == ON) ? 1.0 / max(1.0 - depth     , 1e-5) : depth;
   float w1 = (LINEAR_DEPTH == ON) ? 1.0 / max(1.0 - depthOft1 , 1e-5) : depthOft1;
   float w2 = (LINEAR_DEPTH == ON) ? 1.0 / max(1.0 - depthOft2 , 1e-5) : depthOft2;

   float edgeResidual = w1 + w2 - 2.0 * wC;                       //二阶差分: 斜面上精确为 0
   float edgeDenom = abs(w1 - wC) + abs(wC - w2) + abs(wC) * 1e-4; //相对下限, 压住深度量化噪声, 避免 0/0
   float edgeRatio = abs(edgeResidual) / edgeDenom;                //无量纲: 斜面 -> 0, 遮挡边 -> 约 1
   float isEdge = step(0.5, edgeRatio);                            //0 = 斜面(不画线), 1 = 真边缘(画线)

   return min(rimIntensity,isRamp) * isEdge;
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
	gl_FragData[0] = texture2D(colortex0, texcoord);
   float depth = texture2D(depthtex0, texcoord).r;
   depth = screenDepth2LinearDepth(depth);

   float depthLeft = texture2D(depthtex0, vec2(texcoord.x + (RIM_OFFECT / viewWidth) * SCREEN_VALUE ,texcoord.y)).r;
   float depthRight = texture2D(depthtex0, vec2(texcoord.x - (RIM_OFFECT / viewWidth) * SCREEN_VALUE ,texcoord.y )).r;
   float depthUp = texture2D(depthtex0, vec2(texcoord.x,texcoord.y + (RIM_OFFECT / viewHeight) * SCREEN_VALUE )).r;
   float depthDown = texture2D(depthtex0, vec2(texcoord.x,texcoord.y - (RIM_OFFECT / viewHeight) * SCREEN_VALUE )).r;

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
      gl_FragData[0] = texture2D(colortex0, texcoord) * outlineCol;
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