# Outline Shader NE（描边光影 网易我的世界 · 基岩版组件）

把原 OptiFine/Iris 光影包 **Outline Shader** 移植到
**网易《我的世界》中国版**（基岩引擎 / ModSDK，Python 2 + GLSL 材质系统）。

- 描边算法 **逐行保留** 原 `shaders/final.fsh` 的数学（`getRimIntensity`、
  `screenSpaceToViewSpace`、`screenDepth2LinearDepth`、四个 `RIM_OFFECT`
  深度采样、`OUTLINE_MODE`、`SCREEN_VALUE`、纸世界、纹理描边）。
- 只改引擎接口：`colortex0 → TEXTURE_0`、`depthtex0 → TEXTURE_2`、
  `gbufferProjectionInverse → inverse(PROJ)`、`far → FAR_CHUNKS_DISTANCE`、
  `#define → EXTRA_VECTOR`。
- 原版 18 个可调参数全部接入；按需求把纹理描边 3 项从设置页隐藏（参数保留默认值），
  其余 15 项 + 一个总开关通过自定义 UI 调节，改动即时生效并持久化。
- 设置入口保留在官方「暂停菜单 → 模组」通用设置页里，点「打开设置」后进入自定义面板；
  面板支持滚动/比例布局，**Esc 或底部「关闭」按钮**都能退出。
- 所有新增文件都在 **`ne_be/`** 下。

> 包名、脚本根目录、UI 命名空间、材质/后处理名、贴图路径都加了 `LS` 前缀
> （`LSOutlineShaderNE` / `LSOutlineShaderScript` / `ls_outline_shader`），
> 避免和其他描边/光影组件撞名。

---

## 1. 目录结构

```
ne_be/
├── addon/                                  # 直接把这一层导入 MC Studio（本地导入 → AddOn）
│   ├── LSOutlineShaderNE_Beh/                # 行为包（逻辑）
│   │   ├── manifest.json
│   │   ├── entities/
│   │   └── LSOutlineShaderScript/
│   │       ├── __init__.py
│   │       ├── modMain.py                  # Mod 入口，注册客户端系统
│   │       ├── LSOutlineShaderNEClient.py    # 设置页入口 + 后处理参数驱动
│   │       ├── LSOutlineShaderUIScreen.py    # 自定义设置面板（ScreenNode）
│   │       ├── LSPrefs.py                    # 全局 PlayerPrefs/ConfigClient 存储
│   │       └── ShaderSettings.py             # 参数表 / 默认值 / 后处理描述
│   └── LSOutlineShaderNE_Res/                # 资源包（GLSL + UI）
│       ├── manifest.json
│       ├── materials/
│       │   ├── common.json                 # 声明加载本包的 postprocess.material
│       │   └── postprocess.material        # 官方 17 个后处理材质 + 本模组 2 个
│       ├── shaders/glsl/
│       │   ├── ls_outline_shader_ne.fragment  # 描边（原 final.fsh 的移植）
│       │   └── ls_shadow_shader_ne.fragment   # 阴影参数（屏幕空间近似）
│       ├── ui/
│       │   ├── _ui_defs.json               # UI 文件注册表
│       │   └── ls_outline_shader.json         # 自定义设置面板（按比例自适应）
│       └── textures/ls_outline_shader/
│           ├── cel_ramp.png                # 原包 cel_ramp.png
│           ├── icon.png                    # 模组/设置页图标
│           ├── logo.png                    # 屏幕左下角 logo（屏幕宽 12%）
│           ├── panel_bg.png                # 面板深色半透明底
│           ├── button_bg.png               # 按钮半透明底
│           └── close_bg.png                # 底部「关闭」按钮深红底
├── tools/validate_port.py                  # 离线自测（不需要开游戏）
├── README.md
└── PORTING.md                              # 逐文件 / 逐行移植对照
```

---

## 2. 安装（MC Studio）

### 方式 0：直接导入 `addon` 文件夹（推荐）

MC Studio 的 AddOn 导入单位是**一个包含行为包 + 资源包两个文件夹的根目录**。
本项目的这个根目录就是：

```
ne_be/addon/
├── LSOutlineShaderNE_Beh/     # 行为包
└── LSOutlineShaderNE_Res/     # 资源包
```

1. MC Studio → 作品库 → **基岩版组件** → 右上角 **「本地导入」** → 选
   **`ne_be/addon` 文件夹**。
2. 导入后「更多 → 打开目录」，确认：
   - `LSOutlineShaderNE_Beh/` 下有 `manifest.json`、`entities/`、`LSOutlineShaderScript/`
   - `LSOutlineShaderNE_Res/` 下有 `manifest.json`、`materials/`、`shaders/`、`textures/`
3. 直接「开发测试」→ 新建测试存档。

> 不要选 `ne_be` 根目录（里面还有 README/PORTING/tools），也不要单独选
> `LSOutlineShaderNE_Beh` 或 `LSOutlineShaderNE_Res`；MC Studio 需要的是同时包含
> 行为包和资源包的 `addon` 这一层。

### 方式 1：并入已有的 MC Studio 工程

1. MC Studio → 作品库 → 基岩版组件 → 新建「空白附加包」。
2. 「更多 → 打开目录」，得到自动带后缀的
   `behavior_pack_xxx/`、`resource_pack_xxx/`。
3. 把 `ne_be/addon/LSOutlineShaderNE_Beh/LSOutlineShaderScript/` 整个复制进
   `behavior_pack_xxx/`。
4. 确认 `behavior_pack_xxx/entities/` 存在（空目录即可）；没有就新建一个，
   这是网易识别“行为包”的标记。
5. 把 `ne_be/addon/LSOutlineShaderNE_Res/materials/`、`shaders/`、`textures/`、
   `ui/`、`pack_icon.png` 复制进 `resource_pack_xxx/`（有同名文件时覆盖）。
6. `manifest.json` 建议保留 MC Studio 生成的那份；本项目包内的 manifest 也是
   `format_version: 1`，需要替换时保持 UUID/版本与工程一致即可。
7. 启动开发测试。

> `LSOutlineShaderScript` 这个脚本根目录名会参与通用设置页的归属判断，
> 发布前请确认它不与其它模组重名。

### 发布时改一处

`RegisterSettingInst` 的第一个参数在正式服应传 **开平 ItemID**；开发环境的
ModPC 用命名空间即可。位置：

`LSOutlineShaderScript/ShaderSettings.py` → `MOD_NAMESPACE`
（或直接在 `LSOutlineShaderNEClient.RegisterSettings()` 里替换）。

---

## 3. 设置入口与自定义面板

进入游戏后：**暂停菜单 → 模组 → 描边光影 → 打开设置**。
通用设置页会关闭，弹出右侧半透明的自定义面板：

- 左侧直接看到游戏画面，参数改动立即写入后处理。
- 屏幕右侧整条上下都是半透明黑底，参数面板叠在上面，不会出现黑底和文字错位。
- 右侧面板按屏幕宽度 42% 自适应（最大 360），手机和 PC 都会缩放。
- 行高按面板高度百分比排布，15 行参数在手机/PC 上都完整显示，不会被截断。
- 每个数值项显示实际值，用 `-` / `+` 按档位调整，不再出现 `0..N` 的滑条档位号。
- 描边模式是「内侧 / 外侧」两个按钮，选中的那个带 `●`。
- 面板底部是整条深红「关闭」按钮，点一下回到游戏；**Esc 也可以退出**；屏幕左下角是 `LONGY SOFTWARE` logo（屏幕宽 12%、高 5%）。

面板布局：

```
×  描边光影
启用描边光影              [关]
描边
  描边阈值      -  0.0001  +
  描边偏移      -  0.001   +
  描边颜色      -  0.3     +
  描边模式      [● 内侧] [外侧]
  线性深度                [关]
风格
  卡通渲染                [关]
  纸世界                  [关]
  水面高光      -  0.0     +
阴影
  启用阴影                [关]
  软阴影                  [开]
  阴影分辨率    -  1024    +
  阴影距离      -  自动    +
  阴影亮度      -  0.6     +
  方块光强度    -  0.8     +
  方块光增强    -  1.25    +
[ LONGY SOFTWARE ]
```

### 3.1 描边 Outline

| 控件 | 原版键 | 默认 | 原版候选值 | 说明 |
|---|---|---|---|---|
| 描边阈值 | `THRESHOLD` | `0.0001` | 0.00001 / 0.0001 / 0.0002 / 0.001 / 0.002 / 0.01 | 深度差超过该值才画线 |
| 描边偏移 | `RIM_OFFECT` | `0.001` | 0.0001 … 0.01（9 档） | 采样偏移，默认约 2 像素 |
| 描边颜色 | `OUTLINE_COL` | `0.3` | 0.1 … 0.9（9 档） | 原版为灰度乘数，越小越黑 |
| 描边模式 | `OUTLINE_MODE` | `内侧` | 内侧 / 外侧（两个按钮） | 内/外描边 |
| 线性深度 | `LINEAR_DEPTH` | `OFF` | OFF / ON | 用线性深度代替原始深度 |

### 3.2 纹理描边 Texture Outline（已隐藏）

纹理描边相关项（`ENABLE_TEXTURE_OUTLINES`、`TEXTURE_OUTLINE_STRENGTH`、
`OUTLINE_THICKNESS`）没有放进自定义面板，参数保持默认值（关闭 / 0.8 / 0.5）。
需要显示时，在 `ShaderSettings.UI_ROWS` 里加回对应行，并同步
`ui/ls_outline_shader.json`（或重新生成 UI JSON）。

### 3.3 风格化 Style

| 控件 | 原版键 | 默认 | 说明 |
|---|---|---|---|
| 卡通渲染 | `CEL` | `OFF` | 用 `cel_ramp.png` 对画面亮度做 3 段分级 |
| 纸世界 | `PAPER_WORLD` | `OFF` | 世界只剩白底 + 描边 |
| 水面高光 | `Shininess` | `0.0` | 0.0 / 0.25 / 0.5 / 0.75 / 1.0 |

### 3.4 阴影 Shadow（屏幕空间近似）

| 控件 | 原版键 | 默认 | 原版候选值 |
|---|---|---|---|
| 启用阴影 | `ENABLE_SHADOWS` | `OFF` | OFF / ON |
| 软阴影 | `SOFT_SHADOWS` | `ON` | OFF / ON |
| 阴影分辨率 | `shadowMapResolution` | `1024` | 512 / 1024 / 2048 / 4096 / 8192 |
| 阴影距离 | `SHADOW_DISTANCE` | `-1 (AUTO)` | -1 / 64 … 512（16 档） |
| 阴影亮度 | `SHADOW_BRIGHTNESS` | `0.60` | 0.00 … 1.00（步长 0.05） |
| 方块光强度 | `BLOCK_LIGHT_INTENSITY` | `0.8` | 0.0 / 0.25 / 0.5 / 0.75 / 0.8 / 0.85 / 1.0 / 1.25 / 1.5 / 2.0 |
| 方块光阴影增强 | `BLOCK_LIGHT_SHADOW_BOOST` | `1.25` | 1.0 / 1.1 / 1.25 / 1.5 / 1.75 / 2.0 / 2.5 |

外加一个 **总开关**（`MASTER`），用于快速对比开关光影；原包没有这一项。

### 3.5 左下角 logo

logo 已移出设置面板，放在**屏幕左下角**（红圈位置）：
`textures/ls_outline_shader/logo.png`，宽度取屏幕的 12%、高 5%，手机和 PC 都会缩放，
不会挡住面板里的选项。通用设置页/模组列表图标仍是 `icon.png`（256×256）。

### 3.6 全局设置存储

网易 ModSDK 没有单独命名为 `PlayerPrefs` 的客户端组件；官方的全局键值存储是
`CreateConfigClient(...).GetConfigData/SetConfigData(..., isGlobal=True)`。
本项目把它封装成 `LSPrefs.py`，并固定 `isGlobal=True`：

- **全局统一**：所有存档共用一份设置，不随存档切换；
- 每次 `- / +`、开关、模式切换都**立即写入**，关闭面板/Esc 时再写一次；
- 重新进入任何存档都会自动读取；
- 首次运行会把旧键 `outline_shader_ne_settings_v1` 迁移到
  `ls_outline_shader_ne_settings_v1`；
- 日志里对应 `PlayerPrefs GetConfigData / SetConfigData failed`。

---

## 4. 实现要点（为什么这样移植）

### 4.1 描边：完整算法，原样保留

原 `final.fsh` 的核心段落（`getRimIntensity`、`screenSpaceToViewSpace`、
`screenDepth2LinearDepth`、4 次深度采样、`vec4 outlineCol`、`rimIntensity` 判定）
在新文件里是同一段代码。为了不改算法又能在网易引擎里跑，换了这些“接口”：

| 原版 | 网易版 | 原因 |
|---|---|---|
| `uniform sampler2D colortex0` | `TEXTURE_0` | 后处理链上一 pass 的颜色 |
| `uniform sampler2D depthtex0` | `TEXTURE_2` | 后处理深度图（`depth_enable: true`） |
| `uniform mat4 gbufferProjectionInverse` | 全局 `gbufferProjectionInverse`，`LINEAR_DEPTH=ON` 时在 `main()` 里 `= inverse(PROJ)` | 网易没有这个 uniform；名字保留，函数体不用动 |
| `uniform float far` | `FAR_CHUNKS_DISTANCE` | 网易内置 uniform（与引擎深度远平面一致） |
| `uniform float viewWidth/viewHeight` | `TEXTURE_DIMENSIONS.xy`（异常时 UV 导数回退） | 全屏颜色缓冲尺寸 |
| `#define` 参数 | `EXTRA_VECTOR1..3` | Python 运行时改参数 |
| `texture()` / `textureSize()` | `texture2D()` / `TEXTURE_DIMENSIONS` | GLSL ES 接口 |
| `gl_FragData[0]` | `gl_FragColor` | GLSL ES 接口 |
| `texture.gbuffers.gaux3`（cel_ramp） | `bindTexture` 槽 3 → `TEXTURE_3` | 后处理外部贴图 |

### 4.2 纹理描边 / 纸世界 / 卡通渲染

- **纸世界**：原版在 `gbuffers_*.fsh` 里把输出改成白色；后处理里等价地先
  `finalColor.rgb = vec3(1.0)`，再走纹理描边和深度描边。
- **纹理描边**：`getTEXTURETextureOutline` 的函数体（4 邻域、`maxDiff * 4.0`、
  `mix(..., vec3(0.05), outline)`）保留，但采样源从“方块贴图”换成“屏幕颜色”
  ——后处理阶段拿不到方块贴图，这是引擎能力边界，不是算法改写。
- **卡通渲染**：保留 `cel_ramp.png` 与 `alpha * 1.2`，按原版的三段 ramp 对
  画面亮度分级（原版作用于 lightmap，后处理里没有 lightmap）。

### 4.3 阴影：为什么是近似

原版阴影依赖 `shadowtex0/shadowtex1/shadowcolor0`、`shadowProjection`、
PCF 采样，这些是 OptiFine/Iris 的延迟管线专有数据。网易基岩版（非渲染龙）
的后处理只提供颜色、原始颜色、深度三张图，**没有阴影贴图、没有 lightmap、
没有法线**。所以 `ls_shadow_shader_ne.fragment` 用深度做屏幕空间遮蔽，把
`ENABLE_SHADOWS / SHADOW_BRIGHTNESS / SHADOW_DISTANCE / SOFT_SHADOWS /
shadowMapResolution / BLOCK_LIGHT_* / Shininess` 全部接进去，保证每个滑块
都有实际效果；它不冒充原版的 shadow map 算法。详见 `PORTING.md`。

---

## 5. 性能建议

- 本模组默认只跑 **1 个全屏 pass**（描边）；`ENABLE_SHADOWS=OFF` 时阴影 pass 被
  Python 自动 `SetEnableByName(False)`，不产生开销。
- 打开阴影或 `Shininess > 0` 才会启用第 2 个 pass；移动端建议：
  `shadowMapResolution=512/1024`、关闭 `SOFT_SHADOWS`、`SHADOW_DISTANCE` 设 64~96。
- 纹理描边/卡通渲染是纯全屏计算，开销固定，与分辨率成正比。
- 若只想看描边，保持 `PAPER_WORLD=OFF`、`CEL=OFF`、`ENABLE_TEXTURE_OUTLINES=OFF`。

---

## 6. 已知限制

1. **阴影不是 shadow map**：网易旧渲染器不暴露阴影贴图，阴影项由深度屏幕空间
   遮蔽近似；`shadowMapResolution` 只影响采样数，`SHADOW_DISTANCE` 只影响衰减
   距离，`BLOCK_LIGHT_*` 用“亮像素”近似方块光。
2. **纹理描边是屏幕空间颜色边缘**，不是原版对 block texture 的 4 邻域采样。
3. **CEL 是画面亮度分级**，不是原版对 lightmap 的 ramp。
4. **Shininess 是亮部高光近似**，没有水面法线/光照方向。
5. 原 `shaders.properties` 界面外的隐藏 `#define`（`COLORED_SHADOWS`、
   `PCF_SAMPLE`、`PCF_BLUR_RADIUS`、`ENABLE_DIRECTIONAL_LIGHTING`、
   `GRAY_BIAS_*`、`ENABLE_VORONOI_DISTORTION` 等）未做成运行时开关；如需要
   可继续加控件，但要重新分配 `EXTRA_VECTOR`（每个后处理最多 16 个 float）。
6. 后处理作用于世界画面，不改变物品栏 / 聊天 / UI。
7. 仅适用于**非渲染龙**（OpenGL 材质系统）的网易基岩版；RenderDragon 的
   ShaderSDK/CSS 是另一套接口（`StandardSurfaceOutput`），不能直接加载本 GLSL。

---

## 7. 离线自检

不需要打开游戏：

```bash
python ne_be/tools/validate_port.py
```

会检查：原版描边代码是否逐行保留、18 个参数选项表、默认值、入口按钮、
自定义 UI JSON 的命名空间/面板/控件路径、`_ui_defs.json`、logo 贴图、
后处理描述是否可 JSON 序列化、材质与贴图是否齐全。

## 8. 排错

| 现象 | 先检查 |
|---|---|
| 暂停菜单 → 模组里没有本模组 | 脚本目录/`modMain.py`/各层 `__init__.py` 是否正确；日志里有没有 `client system ready`；正式服把 `MOD_NAMESPACE` 换成开平 ItemID |
| 有「打开设置」按钮，但点了没反应 | 看日志 `open settings button clicked` / `RegisterUI` / `CloseSettingUI` / `PushScreen`；确认 `ui/_ui_defs.json` 和 `ui/ls_outline_shader.json` 在资源包里 |
| 自定义面板没出现 | 日志里有没有 `RegisterUI -> True`、`PushScreen called` 和 `custom UI created`；检查 `UI_JSON_DEF = "ls_outline_shader.main"` 与 JSON 的 namespace/根节点是否一致 |
| 面板出现了，但背后还是暂停菜单 | `CloseSettingUI`/`PopTopUI` 没关掉原生界面；先按 Esc 回到游戏，再重开面板 |
| 面板按钮没反应 | 日志里有没有 `UI control missing`；`ButtonPath` 是否传到回调；按钮是否是 `type: button` |
| 面板文字空白 | Python 2 的 ModAPI 要 UTF-8 `str`；代码已用 `ShaderSettings.api_text()` 统一编码。新增按钮/文本后重启开发测试 |
| 有面板，但画面完全没变化 | 资源包是否启用；日志里有没有 `AddPostProcess ... failed` / `post-process not ready`；是否运行在**渲染龙**客户端（本项目只支持非渲染龙的 GLSL 材质管线） |
| 描边位置/宽度不对 | 先调 `描边偏移`；`TEXTURE_DIMENSIONS` 异常时着色器会用 UV 导数回退 |
| 描边出现在物体内侧/外侧相反 | 在面板里切换「内侧 / 外侧」 |
| 开「线性深度」后描边异常 | 网易的投影矩阵约定与 OptiFine 不完全相同，建议保持关闭 |
| CEL 打开后发黑 | `TEXTURE_3`（cel_ramp）没绑上；着色器已内置 85/128/170 的程序化 ramp 回退 |
| 阴影/高光参数没反应 | 阴影 pass 只在「启用阴影」或「水面高光>0」时启用；且它是屏幕空间近似，不是原版 shadow map |
| 改了设置重进游戏丢失 | 设置应写入全局 PlayerPrefs（`ConfigClient(isGlobal=True)`）；看日志 `PlayerPrefs GetConfigData / SetConfigData failed`，确认 `ls_outline_shader_ne_settings_v1` 写入成功 |

日志前缀统一为 `[LSOutlineShaderNE]`。

### 8.1 “模组列表为空 + 没有描边”的排查顺序

这两件事通常来自同一个原因：**行为包里的 Python 根本没跑起来**。描边不是资源包
自己生效的，而是 `LSOutlineShaderNEClient` 调 `AddPostProcess` 加进去的。

先按顺序确认：

1. **测试环境**：必须用 MC Studio 的「开发测试 / ModPC」。正式版客户端不执行
   本地行为包里的 Python，直接丢包进去只会加载资源包，模组列表会是空的。
2. **两个包都激活**：世界设置 → 行为包 / 资源包，两边都要在 **Active**。
   只激活资源包 = 有 GLSL 但没有 Python，所以没有描边；只激活行为包 = 没有资源包，
   `AddPostProcess` 找不到材质。
3. **目录层级**：`manifest.json` 和 `entities/` 必须在**包文件夹的根目录**，
   不能出现 `behavior_packs/LSOutlineShaderNE_Beh/ne_be/...` 这种多套一层。
4. **behavior_pack 下的 `entities/` 必须存在**（空目录也算），这是网易区分
   行为包/资源包的标记；没有它，行为包可能根本不被识别。
5. **看日志**（MC Studio 的“脚本与测试工具”，过滤 `LSOutlineShaderNE`）：

| 日志停在哪 | 说明 |
|---|---|
| 完全没有 `modMain.py imported` | 行为包没有被加载：结构、`manifest.json`、世界激活、或测试环境不对 |
| 有 `modMain.py imported`，没有 `mod init (client)` | `@Mod.Binding` / SDK 导入失败，看同页 Traceback（旧 SDK 可能用 `common.mod`，代码已做回退） |
| 有 `mod init (client)`，没有 `client system ready` | `RegisterSystem` 的类路径/文件/`__init__.py` 不对 |
| 有 `client system ready`，没有 `settings page registered` | `RegisterSettingInst` 返回 None：命名空间/ItemID 或 UI 初始化时机问题 |
| 有 `settings page registered`，没有 `AddPostProcess(outline) -> True` | 资源包未激活，或 `materials/postprocess.material` 没被加载/覆盖 |
| `AddPostProcess(outline) -> False` | 材质名对不上或材质文件没进资源包；检查 `postprocess.material` 里有没有 `ls_outline_shader_ne_outline` |
| `AddPostProcess` 为 True 但仍无描边 | 检查是否 RenderDragon 客户端；确认 `ls_outline_shader_ne.fragment` 在资源包 `shaders/glsl/` 下 |

6. **MC Studio 报「至少一个资源或行为包加载失败」**：先检查 `manifest.json`。
   中国版 MC Studio 用 `"format_version": 1`；同时**审核端要求**
   `header.min_engine_version >= [1, 18, 0]`（缺失会报打包错误 37）。
   本项目两个 manifest 都是 `format_version: 1` + `min_engine_version: [1,18,0]`。
   其次检查：资源包根目录有没有 `textures/`，行为包根目录有没有 `entities/`。

> 注意：暂停菜单 →「模组」里的列表是**通用设置页列表**，只有调用了
> `RegisterSettingInst` 的模组才会出现；世界设置里的「行为包/资源包」列表是
> 另一回事，两个都要看。

---

## 9. TODO
1.BUG：切换维度后无法打开设置UI
2.阴影效果改善
