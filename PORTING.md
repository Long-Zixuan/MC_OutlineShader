# 移植对照（Outline Shader → 网易我的世界）

本文件记录“原文件 → 新文件”的对应关系，以及每一处**接口替换**。原则：

1. 描边/核心数学 **逐行保留**，不改公式、不改阈值、不改采样偏移。
2. 只替换引擎接口（纹理名、uniform 来源、GLSL ES 语法、参数注入方式）。
3. 引擎给不了的数据（阴影贴图、lightmap、法线）单独说明，不用“假算法”冒充。

---

## 1. 文件映射

| 原包文件 | 新文件 | 处理 |
|---|---|---|
| `shaders/final.fsh` | `addon/OutlineShaderNE_Res/shaders/glsl/outline_shader_ne.fragment` | 描边主算法逐行移植 |
| `shaders/final.vsh` | 无 | 网易后处理使用内置 `shaders/uv_fullscreen.vertex`，不需要自定义顶点着色器 |
| `shaders/commonSettings.glsl` | `addon/OutlineShaderNE_Beh/OutlineShaderScript/ShaderSettings.py` | `#define` 变成 Python 选项表 |
| `shaders/shaders.properties` | 同上 + `OutlineShaderNEClient.RegisterSettings()` | `sliders` / `screen` 变成设置页控件 |
| `shaders/gbuffers_textured.fsh` 的纹理描边段 | `outline_shader_ne.fragment` 的 `getTEXTURETextureOutline()` | 函数体保留，采样源改为屏幕颜色 |
| `shaders/gbuffers_textured.fsh` 的 cel 段 | `outline_shader_ne.fragment` 的 `CEL` 分支 | 保留 `cel_ramp.png` + `alpha * 1.2`，改为亮度分级 |
| `shaders/gbuffers_*.fsh` 的纸世界 | `outline_shader_ne.fragment` 的 `PAPER_WORLD` 分支 | `finalColor.rgb = vec3(1.0)` |
| `shaders/gbuffers_textured.fsh` 的阴影段 | `addon/OutlineShaderNE_Res/shaders/glsl/shadow_shader_ne.fragment` | 引擎无 shadow map，改为深度屏幕空间近似（见 §4） |
| `shaders/texture/cel_ramp.png` | `addon/OutlineShaderNE_Res/textures/outline_shader/cel_ramp.png` | 原文件原样复制 |
| `shaders/lang/*.lang` | 不需要 | 网易设置页的文案直接写在 `ShaderSettings.py` |
| — | `materials/postprocess.material` | 新增 2 个后处理材质（其余 17 个为官方原样保留） |
| — | `OutlineShaderNEClient.py` | 设置页 ↔ 后处理 uniform 的桥 |
| — | `manifest.json` / `world_*_packs.json` | 网易基岩版附加包清单 |

---

## 2. `final.fsh` → `outline_shader_ne.fragment`

### 2.1 原样保留的代码

以下片段与原文件**逐字符一致**（`validate_port.py` 会检查）：

```glsl
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
```

```glsl
float screenSpaceToViewSpace(float depth, mat4 projInv) {
	depth = depth * 2.0 - 1.0;
	return projInv[3].z / (projInv[2].w * depth + projInv[3].w);
}
```

以及 `main()` 里的：

```glsl
float depth = texture2D(TEXTURE_2, texcoord).r;
depth = screenDepth2LinearDepth(depth);

float depthLeft  = texture2D(TEXTURE_2, vec2(texcoord.x + (RIM_OFFECT / viewWidth)  * SCREEN_VALUE, texcoord.y)).r;
float depthRight = texture2D(TEXTURE_2, vec2(texcoord.x - (RIM_OFFECT / viewWidth)  * SCREEN_VALUE, texcoord.y)).r;
float depthUp    = texture2D(TEXTURE_2, vec2(texcoord.x, texcoord.y + (RIM_OFFECT / viewHeight) * SCREEN_VALUE)).r;
float depthDown  = texture2D(TEXTURE_2, vec2(texcoord.x, texcoord.y - (RIM_OFFECT / viewHeight) * SCREEN_VALUE)).r;

depthLeft  = screenDepth2LinearDepth(depthLeft);
depthRight = screenDepth2LinearDepth(depthRight);
depthUp    = screenDepth2LinearDepth(depthUp);
depthDown  = screenDepth2LinearDepth(depthDown);

float rimIntensityV = getRimIntensity(depthLeft,depthRight,depth);
float rimIntensityH = getRimIntensity(depthUp,depthDown,depth);
float rimIntensity  = max(rimIntensityV,rimIntensityH);

vec4 outlineCol = vec4(OUTLINE_COL,OUTLINE_COL,OUTLINE_COL,1);
```

`screenDepth2LinearDepth` 的数学也保留：

```glsl
float viewDepth = screenSpaceToViewSpace(depth, gbufferProjectionInverse);
float linearDepth = max(-viewDepth, 0.0);
float actualMaxDistance = float(far);
...
linearDepth /= actualMaxDistance;
linearDepth = 1.0 - linearDepth;
```

### 2.2 接口替换清单

| 原代码 | 新代码 | 说明 |
|---|---|---|
| `uniform sampler2D colortex0;` | `LAYOUT_BINDING(0) uniform sampler2D TEXTURE_0;` | 后处理上一 pass 颜色 |
| `uniform sampler2D depthtex0;` | `LAYOUT_BINDING(2) uniform sampler2D TEXTURE_2;` | 深度（材质里 `depth_enable: true`） |
| `uniform mat4 gbufferProjectionInverse;` | `mat4 gbufferProjectionInverse;` + `LINEAR_DEPTH=ON` 时 `main(){ gbufferProjectionInverse = inverse(PROJ); }` | 名字保留，函数体零改动 |
| `uniform float far;` | `#define far (max(FAR_CHUNKS_DISTANCE, 16.0))` | 网易每帧 uniform，与引擎深度远平面一致 |
| `uniform float viewWidth;` | `#define viewWidth (max(g_screenSize.x, 1.0))` | 全屏颜色缓冲尺寸（`TEXTURE_DIMENSIONS.xy`，异常时用 UV 导数） |
| `uniform float viewHeight;` | `#define viewHeight (max(g_screenSize.y, 1.0))` | 同上 |
| `#define THRESHOLD ...` | `#define THRESHOLD (EXTRA_VECTOR1.x)` | Python `SetParameter` |
| `#define RIM_OFFECT ...` | `#define RIM_OFFECT (EXTRA_VECTOR1.y)` | 同上 |
| `#define OUTLINE_COL ...` | `#define OUTLINE_COL (EXTRA_VECTOR1.z)` | 同上 |
| `#define OUTLINE_MODE INSIDE` | `#define OUTLINE_MODE (EXTRA_VECTOR1.w)` | Python 传 `+1 / -1` |
| `#define LINEAR_DEPTH OFF` | `#define LINEAR_DEPTH (EXTRA_VECTOR2.x)` | `0.0 / 1.0` |
| `#define ENABLE_TEXTURE_OUTLINES` | `#define ENABLE_TEXTURE_OUTLINES (EXTRA_VECTOR2.y)` | 同上 |
| `#define TEXTURE_OUTLINE_STRENGTH` | `#define TEXTURE_OUTLINE_STRENGTH (EXTRA_VECTOR2.z)` | 同上 |
| `#define OUTLINE_THICKNESS` | `#define OUTLINE_THICKNESS (EXTRA_VECTOR2.w)` | 同上 |
| `#define CEL` | `#define CEL (EXTRA_VECTOR3.x)` | 同上 |
| `#define PAPER_WORLD` | `#define PAPER_WORLD (EXTRA_VECTOR3.y)` | 同上 |
| `varying vec2 texcoord;` | `#define texcoord uv` | 网易全屏头文件里叫 `uv`；用宏保持原变量名 |
| `texture(colortex0, texcoord)` | `texture2D(TEXTURE_0, texcoord)` | GLSL ES |
| `texture(depthtex0, ...)` | `texture2D(TEXTURE_2, ...)` | GLSL ES |
| `textureSize(texture, 0)` | `TEXTURE_DIMENSIONS.xy` | GLSL ES |
| `gl_FragData[0] = ...` | `gl_FragColor = ...` | GLSL ES |
| `if(rimIntensity == 1)` | `if(rimIntensity >= 0.5)` | 值只可能是 0/1，等价；避免浮点相等比较 |
| 早退 `return` | 先算完 `finalColor`，最后统一乘 `outlineCol` | 与原包 `gbuffers → final` 的先后顺序一致 |

**没有改动**：`SCREEN_VALUE = 2000`、`THRESHOLD` 判定方向、`OUTLINE_MODE`
符号、`rampValue` 0.0001/0.001、`isRamp` 逻辑、`outlineCol` 的灰度乘色。

### 2.3 新增的顺序（纸世界/纹理描边/卡通）

原包里这些效果发生在 `gbuffers_textured.fsh`（写 `colortex0`），`final.fsh`
只做深度描边。移植后只有一次全屏 pass，所以按原顺序拼接：

```
colortex0 (= TEXTURE_0)
    ↓ PAPER_WORLD ? 白色
    ↓ CEL ? cel_ramp 三段亮度
    ↓ ENABLE_TEXTURE_OUTLINES ? 4 邻域颜色边缘 mix(0.05)
    ↓ 深度描边 ? *= OUTLINE_COL
输出
```

这就是原包 `gbuffers_*` + `final.fsh` 的实际顺序的等价合并。

---

## 3. `shaders.properties` → 设置页

原 `sliders` / `screen` 的 18 个参数全部保留，顺序按原界面分组：

```
Shadow:
  ENABLE_SHADOWS
  SOFT_SHADOWS
  shadowMapResolution
  SHADOW_DISTANCE
  SHADOW_BRIGHTNESS
  BLOCK_LIGHT_INTENSITY
  BLOCK_LIGHT_SHADOW_BOOST
Outline:
  THRESHOLD
  RIM_OFFECT
  OUTLINE_COL
  LINEAR_DEPTH
  OUTLINE_MODE
TextureOutline:
  ENABLE_TEXTURE_OUTLINES
  TEXTURE_OUTLINE_STRENGTH
  OUTLINE_THICKNESS
Style:
  CEL
  PAPER_WORLD
  Shininess
```

> 按需求，`TextureOutline` 的 3 项在设置页标记为 `"hidden": True`，不再显示；
> 参数仍以默认值（关闭 / 0.8 / 0.5）传给着色器。需要恢复时去掉 `hidden` 即可。
> 所有离散选项（含原下拉框 `OUTLINE_MODE`、`shadowMapResolution`、
> `SHADOW_DISTANCE`）都改用整数滑条，避免部分 SDK 的下拉框选中文字空白；
> 设置页只保留中文参数名，不再显示档位说明文字，档位值见 README 的参数表。

控件类型映射：

| 原版 | 网易控件 | 说明 |
|---|---|---|
| `[OFF ON]` 开关 | `AddToggle` | 例如 `CEL`、`PAPER_WORLD` |
| 固定档位滑条（如 `[0.0 0.25 0.5 0.75 1.0]`） | `AddSlider(step=len-1)` | 存的是**档位下标**，Python 再映射回原值 |
| `[INSIDE OUTSIDE]` 多选 | `AddSlider(step=1)` | 0=INSIDE，1=OUTSIDE |
| `const int shadowMapResolution = 1024` | `AddSlider(step=4)` | 0=512 … 4=8192 |
| `SHADOW_DISTANCE` 16 档 | `AddSlider(step=15)` | 0=AUTO，1=64 … 15=512 |

所有档位表都在 `ShaderSettings.py`，与 `commonSettings.glsl` / `final.fsh`
的注释候选值一一对应；`validate_port.py` 会逐项比对。

---

## 4. 阴影参数到底接到了哪里

原 `gbuffers_textured.fsh`：

```
shadowtex0 / shadowtex1 / shadowcolor0 / shadowModelView / shadowProjection
PCF_SAMPLE / PCF_BLUR_RADIUS / SHADOW_DISTORTION / FAR_DISTANCE_BIAS_*
```

网易基岩版（非渲染龙）后处理只有 `TEXTURE_0`（颜色）、`TEXTURE_1`（原始颜色）、
`TEXTURE_2`（深度），没有阴影贴图、lightmap、法线。因此：

| 原参数 | 新接法 | 备注 |
|---|---|---|
| `ENABLE_SHADOWS` | 开启深度屏幕空间遮蔽 pass | 默认 OFF，与原包一致 |
| `SOFT_SHADOWS` | 采样半径 4px → 9px | 对应“软” |
| `shadowMapResolution` | 采样数 4 → 8（512→8192） | 仅质量档位 |
| `SHADOW_DISTANCE` | 遮蔽衰减距离；`-1` = 不衰减 | 语义从“阴影贴图覆盖距离”改为“屏幕空间遮蔽作用距离” |
| `SHADOW_BRIGHTNESS` | 被遮蔽像素乘 `mix(1, value, occ)` | 与原“阴影中亮度乘数”直觉一致 |
| `BLOCK_LIGHT_INTENSITY` | 亮像素（近似火把光）乘该强度 | 原版乘的是 block light 贡献 |
| `BLOCK_LIGHT_SHADOW_BOOST` | 遮蔽越强，亮像素额外乘得越多 | 对应“背光面方块光增强” |
| `Shininess` | 亮部 `pow(luma, 16)` 加高光 | 没有水面法线，做“亮部高光”近似 |

如果以后网易开放阴影贴图/延迟管线，只需把 `shadow_shader_ne.fragment` 的
遮蔽项替换回原 `sPCF` 代码；参数接口不用改。

---

## 5. Python 侧接口

| 目的 | 接口 | 代码位置 |
|---|---|---|
| 注册设置页 | `CreateNeteaseWindow(...).RegisterSettingInst(...)` | `OutlineShaderNEClient.RegisterSettings` |
| 开关/滑条/下拉 | `AddToggle` / `AddSlider` / `AddDropDown` | 同上 |
| 控件顺序 | `priority` 参数（按 `CONTROLS` 下标） | `ShaderSettings.CONTROLS` |
| 加后处理 | `CreatePostProcess(...).AddPostProcess(dict, -1)` | `OutlineShaderNEClient._ensure_processes` |
| 改参数 | `SetParameter(process, paramName, [vec4])` | `OutlineShaderNEClient.Apply` |
| 开关后处理 | `SetEnableByName(process, bool)` | 同上 |
| 持久化 | `CreateConfigClient(...).Get/SetConfigData(..., isGlobal=True)` | `_load_config` / `_save_config` |
| 时机 | `UiInitFinished` 注册；`OnScriptTickClient` 兜底重试 | `OnUiInitFinished` / `OnScriptTickClient` |

参数打包（每个后处理最多 4 个 `EXTRA_VECTOR`，这里各用 2~3 个）：

```
outline_shader_ne_outline:
  EXTRA_VECTOR1 = (THRESHOLD, RIM_OFFECT, OUTLINE_COL, OUTLINE_MODE)
  EXTRA_VECTOR2 = (LINEAR_DEPTH, ENABLE_TEXTURE_OUTLINES,
                   TEXTURE_OUTLINE_STRENGTH, OUTLINE_THICKNESS)
  EXTRA_VECTOR3 = (CEL, PAPER_WORLD, 0, 0)
  bindTexture[0] = textures/outline_shader/cel_ramp  -> TEXTURE_3

outline_shader_ne_shadow:
  EXTRA_VECTOR1 = (ENABLE_SHADOWS, SHADOW_BRIGHTNESS, SHADOW_DISTANCE, SOFT_SHADOWS)
  EXTRA_VECTOR2 = (shadowMapResolution, BLOCK_LIGHT_INTENSITY,
                   BLOCK_LIGHT_SHADOW_BOOST, Shininess)
```

`paras` 的顺序就是 `EXTRA_VECTOR` 的顺序；每个 `value` 是长度 4 的数组。

---

## 6. 资源包材质

`materials/postprocess.material` 是网易 `vanilla_netease` 的**扁平格式**
（顶层直接是材质名，没有 `"materials"` 包裹）。为保证不破坏官方后处理
（默认开启的 bloom 依赖 `threashold_pick`、`daul_blur_*` 等），本项目
**原样复制了官方 17 个材质**，再追加：

```json
"outline_shader_ne_outline": {
    "vertexShader": "shaders/uv_fullscreen.vertex",
    "fragmentShader": "shaders/outline_shader_ne.fragment",
    "vertexFields": [{"field": "Position"}, {"field": "UV0"}],
    "samplerStates": [ ... 0 Bilinear / 1 Bilinear / 2 Point / 3 Bilinear ... ],
    "states": ["DisableDepthTest"],
    "msaaSupport": "Both"
}
```

`materials/common.json` 只列出本包的 `materials/postprocess.material`。网易的材质
加载表是**按包叠加**的：基础包仍然加载自己的 `entity/terrain/...`，本包只负责
把自己新增的材质文件挂进去。之前担心的“覆盖原版材质表”不会发生；如果某个 SDK
版本表现相反，删掉这个 `common.json` 也能靠官方 `vanilla_netease` 的同名条目
加载 `postprocess.material`。

### 着色器路径解析

网易材质里的 `fragmentShader` 写的是**逻辑路径**，引擎会在目录和文件名之间插入
`glsl/`：

| 材质里的路径 | 实际文件 |
|---|---|
| `shaders/uv_fullscreen.vertex` | `shaders/glsl/uv_fullscreen.vertex` |
| `shaders/tutorial/old_tv.fragment`（官方内置） | `shaders/tutorial/glsl/old_tv.fragment` |
| `shaders/outline_shader_ne.fragment`（本项目） | `shaders/glsl/outline_shader_ne.fragment` |
| `shaders/shadow_shader_ne.fragment`（本项目） | `shaders/glsl/shadow_shader_ne.fragment` |

所以本项目把两个 `.fragment` 放在 `shaders/glsl/`，材质里写不带 `glsl/` 的路径，
与官方 `postprocess.material` 的写法完全一致。**不要把 `.fragment` 直接放在
`shaders/` 根目录**，也不要写成 `shaders/glsl/...`（部分版本会二次插入 `glsl/`）。

---

## 7. 已知差异 / 未移植

| 项 | 状态 | 原因 |
|---|---|---|
| `final.fsh` 深度描边 | ✅ 逐行移植 | — |
| `PAPER_WORLD` | ✅ 等价实现 | 原写白在 gbuffers，后处理里写白等价 |
| `ENABLE_TEXTURE_OUTLINES` | ⚠️ 屏幕空间近似 | 后处理拿不到 block texture |
| `CEL` | ⚠️ 亮度分级近似 | 后处理拿不到 lightmap |
| `ENABLE_SHADOWS` 及 7 个阴影参数 | ⚠️ 屏幕空间遮蔽近似 | 网易无 shadow map |
| `Shininess` | ⚠️ 亮部高光近似 | 无水面法线/光照方向 |
| `COLORED_SHADOWS` / `PCF_SAMPLE` / `PCF_BLUR_RADIUS` / `ENABLE_DIRECTIONAL_LIGHTING` / `GRAY_BIAS_*` / `ENABLE_VORONOI_DISTORTION` / `SHADOW_DISTORTION` / `FAR_DISTANCE_BIAS_*` | ❌ 未做运行时开关 | 原 `shaders.properties` 界面未暴露；16 float/后处理 的预算不够；如需要可再拆一个后处理 |
| 天气/云/天空/水材质 | ❌ 未改 | 原包这些 program 只做透传；后处理方案不需要逐 program 覆盖 |
| 手柄/UI/物品栏 | ❌ 不处理 | 后处理只作用于世界画面 |

---

## 8. 验证清单（进游戏后）

1. 暂停菜单 → 模组 → 描边光影 → 页面能打开，26 行控件都在。
2. 默认（阴影关、纹理描边关、CEL 关、纸世界关）：画面出现黑色描边，
   描边宽度约 2px（`RIM_OFFECT=0.001`）。
3. 拖 `OUTLINE_COL` 到 0.1 / 0.9：描边由黑变浅。
4. 切 `OUTLINE_MODE`：INSIDE/OUTSIDE 描边位置翻转。
5. 开 `PAPER_WORLD`：世界变白底黑线。
6. 开 `ENABLE_TEXTURE_OUTLINES`：方块纹理内部出现细线；调粗细/强度有变化。
7. 开 `CEL`：画面出现 3 段明暗分层。
8. 开 `ENABLE_SHADOWS`：暗部（物体接触处/角落）变暗；调 `SHADOW_BRIGHTNESS`
   到 1.0 时遮蔽消失，到 0.0 时最黑。
9. 退出重进：设置保持。
10. 关总开关：画面恢复原版。

---

## 9. 参考

- 网易通用设置接口规范（`RegisterSettingInst` / `AddToggle` / `AddSlider` /
  `AddDropDown` / `SetLockSettingComp` 等）
- 网易材质与着色器文档（`post_process.json`、`postprocess.material`、
  `EXTRA_VECTOR`、`bindTexture`、`depth_enable`）
- 网易后处理 ModAPI（`AddPostProcess` / `SetParameter` / `SetEnableByName` /
  `InsertPassToPostprocess` / `GetPostProcessOrder`）
- 官方 `vanilla_netease/materials/postprocess.material` 与
  `graphics_settings/post_process.json`（本项目保留了其 17 个内置材质）
