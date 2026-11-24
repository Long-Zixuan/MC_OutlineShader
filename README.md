# Outline Shader — Better RenderDragon 移植版

把 Java 版（Iris/OptiFine）NPR 描边光影移植到 Minecraft Bedrock **26.50**。

包含两个材质，分别对应两条渲染路径：

| 材质 | 描边方式 | 生效场景 |
|---|---|---|
| `ColorPostProcessing` | 颜色边缘描边（双距离确认） | 灵动视效（延迟/后处理链） |
| `RenderChunk` | 纹理描边（`getTEXTURETextureOutline`） | 普通画质（前向渲染） |

---

## 工程结构

```
BE/
├── project.json                  # lazurite 配置（合并 vanilla + 编译平台）
├── build.bat                     # 一键构建 + 打包
├── package.ps1                   # 把 build/*.material.bin 打进 mcpack
├── .gitignore
├── OutlineShader.mcpack          # 产物
│
├── ColorPostProcessing/
│   └── shaders/
│       ├── fragment.sc           # 颜色描边（双距离确认）
│       ├── vertex.sc             # 全屏 quad
│       ├── varying.def.sc
│       └── bgfx_shader.sh
│
├── RenderChunk/
│   └── shaders/
│       ├── fragment.sc           # 纹理描边（从 gbuffers_textured.fsh 移植）
│       ├── vertex.sc             # 顶点变换（实例化 + v26 UV 解包 + 雾）
│       ├── varying.def.sc
│       └── bgfx_shader.sh
│
└── vanilla/                      # lazurite merge source（原版材质，勿删）
    ├── ColorPostProcessing.material.bin
    └── RenderChunk.material.bin
```

---

## 构建

```
build.bat
```

依赖：
- Python 3.10
- `lazurite==0.10.0`（`pip install lazurite==0.10.0`）
- `env\shaderc.exe`（bgfx 1.18.121，来自 veka0/bgfx-mcbe）

  > 从 `shaderc-win-x64.zip` 解压出来是 `shadercRelease.exe`，需要**改名为 `shaderc.exe`**，
  > 否则 `build.bat` 找不到。`env/` 在 `.gitignore` 里，删掉后需重新下载。

- `dxc.exe`（Windows SDK，用于 SM60/SM65 的 DXIL）

产物：`OutlineShader.mcpack`

> `package.ps1` 会自动打包 `build/` 下的**所有**材质。
> 新增材质只需建 `<名字>/shaders/` + `vanilla/<名字>.material.bin`，无需改脚本。

---

## 关键参数

### ColorPostProcessing（颜色描边）

```glsl
#define THRESHOLD_NEAR 0.18   // 近距门限
#define THRESHOLD_FAR  0.10   // 远距门限
#define OUTLINE_COL    0.15   // 线条暗度
#define OFFSET_PX      1.5    // 近距采样（像素）
#define OFFSET_FAR_PX  4.0    // 远距采样（像素）

#define EXPOSURE_BASE  1.12   // 基础曝光
#define EXPOSURE_LIFT  0.45   // 中间调提亮强度
```

**双距离确认**：纹理细节空间频率高，隔 4 像素就衰减；物体轮廓空间频率低，隔 4 像素依然存在。两个距离都超过门限才画线。

```glsl
float dNear = maxNeighbourDiff(uv, offNear, col.rgb);   // 1.5px
float dFar  = maxNeighbourDiff(uv, offFar,  col.rgb);   // 4.0px
if (dNear > THRESHOLD_NEAR && dFar > THRESHOLD_FAR) col.rgb *= OUTLINE_COL;
```

| 情况 | `dNear` | `dFar` | 结果 |
|---|---|---|---|
| 草叶/叶子纹理 | 大 | 小 | 不画线 |
| 方块与背景交界 | 大 | 大 | 画线 |
| 平坦同色区域 | 小 | 小 | 不画线 |

**亮度处理**（`gamma()` 函数）：原版 `ColorPostProcessing` 自带色调映射，替换它之后必须自己做，否则画面会严重偏暗。

```glsl
vec3 gamma(vec3 c) {
    vec3 s = sqrt(max(c, vec3(0.0)));          // gamma 2.0
    vec3 lift = vec3(EXPOSURE_BASE + EXPOSURE_LIFT * (1.0 - s.x), ...);
    return clamp(s * lift, vec3(0.0), vec3(1.0));
}
```

为什么不是均匀提亮：原版色调映射是「中间调提得多、高光压得住」，而 `sqrt(c) * 常数` 是均匀的，补不回中间调的损失。当前曲线的效果：

| 原亮度 | 旧 `*1.12` | 现在 | 变化 |
|---|---|---|---|
| 0.2（暗部） | 0.224 | 0.272 | +21% |
| 0.5（中间调） | 0.560 | 0.658 | +18% |
| 0.8（亮部） | 0.896 | 0.941 | +5% |
| 1.0（纯白） | 1.0（clipped） | 1.0 | 不变 |

调参：`EXPOSURE_LIFT` 越大提得越多（0.45 → 0.70 约再提 10%，降到 0.25 则变暗）。

### RenderChunk（纹理描边）

```glsl
#define ENABLE_TEXTURE_OUTLINES    1
#define TEXTURE_OUTLINE_STRENGTH   0.8
#define OUTLINE_THICKNESS          0.1
#define ATLAS_SIZE                 256.0
```

`ATLAS_SIZE` 替代了 Java 版的 `textureSize(texture, 0)`（GLSL 100 分支没有这个函数）。

---

## 重要说明

### 1. BRD 的资源包替换对这两个材质不生效

实测 BRD v1.7.5 的 `readFile` hook 从未命中材质加载，`logs.txt` 里 0 条 `Loaded` 记录。资源包里的材质不会被应用。

**可用做法是直接覆盖游戏目录：**

```
<游戏目录>\data\renderer\materials\ColorPostProcessing.material.bin
<游戏目录>\data\renderer\materials\RenderChunk.material.bin
```

已实测有效（替换后画面立即变化）。

### 2. 深度描边无法实现

已完整验证两个版本：

| 版本 | 结论 |
|---|---|
| 26.50 | 有深度的材质（`DeferredShading`、`RenderChunkForwardPBR` 等）替换后不生效；能生效的 `ColorPostProcessing` 只绑定了画面颜色，其余 5 个槽位全是空/未绑定 |
| 1.16.100 | 可覆盖材质引用的着色器，但表面着色器拿不到深度；引擎内部的 `depth_of_field` 等 pass 无法覆盖 |

深度缓冲确实存在（`depth_of_field.fragment.hlsl` 源码里有 `MakeDepthLinear(TEXTURE_1.Sample(...))`），但它只绑定给引擎内部 pass，那些 pass 的着色器不从资源包加载。

### 3. 颜色描边的固有限制

颜色法无法区分「两个同色物体的前后交界」。例如绿草贴绿草、灰石贴灰石，这些位置不会产生描边线。这是方法本身的边界，不是实现问题。

---

## 改动记录

### 从 Java 版移植的部分

| Java 源文件 | 移植到 | 说明 |
|---|---|---|
| `gbuffers_textured.fsh` 的 `getTEXTURETextureOutline()` | `RenderChunk/shaders/fragment.sc` | 纹理描边，逻辑原样保留 |
| `final.fsh` 的深度描边 | — | **无法移植**（拿不到深度） |
| `shadow.vsh` 的 `distortShadow()` | — | **无法移植**（阴影图渲染与采样都在引擎内部） |

### 相对 Java 版必须做的适配

| 项目 | Java 版 | Bedrock 版 | 原因 |
|---|---|---|---|
| 纹理尺寸 | `textureSize(texture, 0)` | 常量 `ATLAS_SIZE 256.0` | GLSL 100 没有 `textureSize` |
| 深度来源 | `depthtex1`/`depthtex2` | 无 | 引擎不暴露 |
| 光照计算 | `gbuffers_*.fsh` 内联 | 引擎内部 | 材质不控制光照 |

### ColorPostProcessing 的迭代

| 版本 | 亮度处理 | 边缘判定 | 结果 |
|---|---|---|---|
| v1 | `sqrt(c) * 1.12` | `maxDiff > 0.18` | 满屏噪点（纹理细节被当边缘） |
| v2 | ACES tonemap | DoG 软阈值 | 偏暗，效果不如 v1 |
| v3 | `sqrt(c) * 1.12` | 阈值提到 `0.40` | 噪点少了但轮廓也丢了 |
| **v4（当前）** | **`sqrt(c)` + 中间调提亮** | **双距离确认** | 噪点少、轮廓保留、亮度接近原版 |

关键教训：

- **不要动 `sqrt(c) * 1.12` 的整体思路**，只需在它基础上做亮度补偿（换成 ACES 反而偏暗）
- **单一阈值区分不了「纹理细节」和「物体轮廓」**——必须用空间频率（双距离）
- 提亮必须**按亮度分布**做，均匀系数补不回中间调

---

## 原始素材

Java 版源码（`final.fsh`、`gbuffers_textured.fsh`、`commonSettings.glsl`、`shadow.vsh` 等）在原项目目录，不在本工程内。
原版材质备份在 `vanilla/`（`ColorPostProcessing.material.bin`、`RenderChunk.material.bin`），用于重新构建时的 merge source。

> 恢复游戏目录时，把 `vanilla/` 里的两个文件复制回
> `<游戏目录>\data\renderer\materials\` 即可。
