#version 120

#define FALLOFF_CURVE 0.0 // [-10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
//#define x linearDepth
#define a actualMaxDistance
#define p FALLOFF_CURVE

#define TRUE 1
#define FALSE 0

#define OFF 0
#define ON 1
/////

#define THRESHOLD 0.0001 // [0.005 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1]
#define RIM_OFFECT 0.0003 // [0.0003 0.0004 0.0005 0.001 0.002 0.003 0.004 0.005 0.01]
#define OUTLINE_COL 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9]
//#define RAMP_VALUE 0.0001
#define SCREEN_VALUE 2000

#define OutlineDepthMultiplier 2.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define OutlineDepthBias 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define BAD_LINE_VALUE 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]


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

float screenSpaceToViewSpace(float depth, mat4 projInv) {
	depth = depth * 2.0 - 1.0;
	return projInv[3].z / (projInv[2].w * depth + projInv[3].w);
}

float screenDepth2LinearDepth(float depth)
{
   float viewDepth = screenSpaceToViewSpace(depth, gbufferProjectionInverse);
   float linearDepth = max(-viewDepth, 0.0);
   float actualMaxDistance = float(far);
   if(FALLOFF_CURVE != 0.0)
   {
      linearDepth = (exp(p * (linearDepth / a)) - 1.0) / (exp(p) - 1.0);
   } 
   else 
   {
      linearDepth /= actualMaxDistance;
   }
   linearDepth = 1.0 - linearDepth;
   return linearDepth;
}

float SobelDepth(float ldc, float ldl, float ldr, float ldu, float ldd)
{
   return abs(ldl - ldc) +
      abs(ldr - ldc) +
      abs(ldu - ldc) +
      abs(ldd - ldc);
}

float SobelSampleDepth(vec2 uv, vec3 offset)
{
   float pixelCenter = screenDepth2LinearDepth(texture(depthtex0, uv).r);
   float pixelLeft = screenDepth2LinearDepth(texture(depthtex0, uv - offset.xz).r);
   float pixelRight = screenDepth2LinearDepth(texture(depthtex0, uv + offset.xz).r);
   float pixelUp = screenDepth2LinearDepth(texture(depthtex0, uv + offset.zy).r);
   float pixelDown = screenDepth2LinearDepth(texture(depthtex0, uv - offset.zy).r);

   return SobelDepth(pixelCenter, pixelLeft, pixelRight, pixelUp, pixelDown);
}

// ===== 视频播放：按时间逐帧采样视频图集，判断像素是否位于黑色区域 =====
uniform sampler2D colortex1;      // 视频帧图集纹理(由 shaders.properties 绑定 texture/video.png)
uniform float frameTimeCounter;   // 游戏运行时间(秒)，由 OptiFine/Iris 提供

#define VIDEO_DURATION 217.766667 // 视频总时长(秒)
#define VIDEO_FRAMES  3840        // 提取到的帧数
#define VIDEO_GRID_X  62          // 图集列数
#define VIDEO_GRID_Y  62          // 图集行数
#define VIDEO_ATLAS_W 5952        // 图集像素宽(= GRID_X * 96)
#define VIDEO_ATLAS_H 3348        // 图集像素高(= GRID_Y * 54)

float isInBlack(vec2 uv)
{
	// 循环播放：由当前时间算出对应的帧号
	float f = floor(mod(frameTimeCounter, VIDEO_DURATION) / VIDEO_DURATION * float(VIDEO_FRAMES));

	// 帧号 -> 图集格子(第 0 帧在图集左上角)
	float col = mod(f, float(VIDEO_GRID_X));
	float row = floor(f / float(VIDEO_GRID_X));

	// OpenGL 纹理 v=0 在图像底部，而全屏 pass 的 uv.y=0 在屏幕顶部，两者方向相反
	float vRow = float(VIDEO_GRID_Y) - 1.0 - row;

	vec2 cell = 1.0 / vec2(float(VIDEO_GRID_X), float(VIDEO_GRID_Y));
	vec2 px   = 1.0 / vec2(float(VIDEO_ATLAS_W), float(VIDEO_ATLAS_H));

	// 把屏幕 uv 映射到当前格子的内部，内缩半个像素避免相邻帧串色
	vec2 atlasUV = vec2(col, vRow) * cell
	             + px * 0.5
	             + vec2(uv.x, 1.0 - uv.y) * (cell - px);

	// 读取灰度帧的亮度，判断是否位于黑色区域
	float luma = texture2D(colortex1, atlasUV).r;
	if (luma < lumaThreshold) return float(TRUE);
	return float(FALSE);
}


void main() 
{
	vec4 sceneColor = texture(colortex0, texcoord);

   vec3 offset = vec3((1.0 / viewWidth), (1.0 / viewHeight), 0.0) * RIM_OFFECT * SCREEN_VALUE;

   float sobelDepth = SobelSampleDepth(texcoord, offset);

   sobelDepth = pow(clamp(sobelDepth, 0.0, 1.0) * OutlineDepthMultiplier, OutlineDepthBias);

   vec4 outlineCol = vec4(OUTLINE_COL,OUTLINE_COL,OUTLINE_COL,1);

   vec4 color = mix(sceneColor, outlineCol, sobelDepth);
   if(isInBlack(texcoord) == TRUE)
   {
      color.x = 1 - color.x;
      color.y = 1 - color.y;
      color.z = 1 - color.z;
   }
   gl_FragData[0] = color;
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