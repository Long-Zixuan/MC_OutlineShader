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
```

双距离确认的原理：纹理细节空间频率高，隔 4 像素就衰减；物体轮廓空间频率低，隔 4 像素依然存在。两个距离都超过门限才画线。

亮度处理用 `sqrt(c) * 1.12`（gamma 2.0 + 约 12% 曝光补偿）。**不能去掉**——原版 `ColorPostProcessing` 自带色调映射，替换它之后必须自己做，否则画面会严重偏暗。

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

## 原始素材

Java 版源码保留在工作区 `../shaders/`（`final.fsh`、`gbuffers_textured.fsh`、`commonSettings.glsl` 等）。
原版材质备份在 `../_material_backup/`（用于恢复游戏目录）。
