# 阴影路径的天光 / 阴影配比

> 记录一次修复：开启「阴影」后画面整体偏暗、方块光压过天光、明暗对比拉不开，
> 白天看起来像晚上。
>
> 涉及文件：`shaders/gbuffers_textured.fsh`、`shaders/gbuffers_water.fsh`
>
> 前提：本文件只讨论 `ENABLE_SHADOWS = 1` 的着色路径；`ENABLE_SHADOWS = 0` 的观感要求逐字不变。

---

## 1. 现象

开启「阴影」( `ENABLE_SHADOWS = 1` ) 后：

- 白天整体偏暗：正午晴天，草地/地形的亮度只有原版的一半左右；
- 方块光（火把、灯笼）影响过大：白天也明显抢戏，看起来像「只有方块光在照明」；
- 明暗对比拉不开：被太阳照到的面和阴影里的面亮度接近，看不出光从哪来；
- 关掉阴影（`ENABLE_SHADOWS = 0`）反而正常。
- 期望：白天明亮、天光为主；这种「暗 + 方块光为主」的观感只应该出现在夜里（以及洞穴/下界这类没有天光的地方）。

截图里草簇、羊是有投射阴影的，说明**阴影贴图本身工作正常**，问题出在光照合成，而不是阴影 pass。

---

## 2. 原理

### 2.1 `sBright` 的语义

```glsl
// gbuffers_textured.fsh:415 / gbuffers_water.fsh:254
float sBright = mix(SHADOW_BRIGHTNESS, 1.0, rainStrength);   // 晴天 = 0.60
```

`SHADOW_BRIGHTNESS` 的注释是「How much sky light a surface keeps when it is in shadow」，
也就是**只有被阴影挡住的面**才应该保留这个比例的天光。

### 2.2 光照贴图的两根轴与采样

`lightmap` 是 16×16 的二维表：

| 轴 | 含义 |
| --- | --- |
| X（`coord1.x`） | 方块光 0~15 |
| Y（`coord1.y`） | 天空光 0~15 |

原来的写法把 `sBright` 乘进了**采样坐标**：

```glsl
// 改前
vec3 lMapFull    = texture2D(lightmap, vec2(coord1.x, coord1.y * sBright)).rgb;
vec3 lMapAmbient = texture2D(lightmap, vec2(0.0,     coord1.y * sBright)).rgb;
```

这意味着**每一个像素**都在按「天空光 × 0.6」取值：正午 `coord1.y` 对应 sky=15 时，
实际读到的是 sky=9 的行 —— 晴天白昼凭空少了约 40% 的天光。这是「白天也暗」的直接原因，
而且和阴影有没有挡住这个面**无关**。

### 2.3 方块光差额

```glsl
vec3 blockLightContribution = max(vec3(0.0), lMapFull - lMapAmbient);
vec3 blockLight = blockLightContribution
    * (BLOCK_LIGHT_INTENSITY * mix(1.0, BLOCK_LIGHT_SHADOW_BOOST, shadowAmount));
```

方块光是「方块光行」与「方块光=0 行」的差额，按 `BLOCK_LIGHT_INTENSITY`（0.8）
再乘 `BLOCK_LIGHT_SHADOW_BOOST`（最多 1.25）**全额叠加**。

原版光照贴图对天空光/方块光取的是「较大者」，所以白天火把几乎看不出加成；
这里因为天光被压到 0.6，差额反而变大，火把在白天也会明显提亮 —— 这就是「方块光影响很大」。

### 2.4 太阳项

```glsl
// gbuffers_textured.fsh:461
sBright += (1.0 - lVis) * (1.0 - sBright);   // 夜晚/洞穴把太阳项关掉
skyLight += sLight * (1.0 - sBright);        // 白天权重 0.4
```

`sLight = 阴影可见性 × N·L × 2`（`gbuffers_textured.fsh:400`、`:409`），
所以受光面最多 +0.8。它本来是唯一「把受光面和暗面拉开」的项，
但天光被整体压暗后，差距在画面上并不明显。

### 2.5 数值推演（示意，天空光满值 ≈ 1.0）

| | 改前 | 改后 |
| --- | --- | --- |
| 白天受光面 | 0.49（天光）+ 0.76（太阳项）≈ **1.25** | 1.0 + 0.76 ≈ **1.76** |
| 白天阴影里 | 0.49 | 1.0 × 0.6 ≈ **0.60** |
| 亮/暗比 | ≈ 2.6 : 1 | ≈ **2.9 : 1**，且整体亮度 +40% |
| 夜晚 / 洞穴 / 下界 | 天光 = 0，方块光为主 | **不变**（天空光坐标本来就是 0，`sBright` 无论怎么变乘出来都是 0） |

> 表中 1.0 只是记法：实际亮度由 `lightmap` 的曲线决定，重点是「天光不再被全局压到 0.6」。
> 阴影比例默认 0.6，`SHADOW_BRIGHTNESS` 调小即可让阴影更黑、对比更强。

### 2.6 为什么「直接把 sBright 抬高」不行（一次失败尝试，已撤回）

先试过在白天把 `sBright` 抬到 ~0.86：

```glsl
// 已删除，不要这样写
sBright = mix(sBright, 1.0, smoothstep(0.0, 0.6, coord1.y) * 0.65);
```

问题在于 `sBright` 同时是两个东西的系数：

1. 天光的采样行（`coord1.y * sBright`）；
2. 太阳项的权重（`1.0 - sBright`）。

把 (1) 抬高，等于**亮处和暗处一起抬**；同时 (2) 被挤到 0.14，太阳项几乎消失，
于是「整体亮了一点，但明暗更糊」——正是当时反馈的「对比拉不开」。

结论：天光与太阳项必须**分开**：天光按满值取，`SHADOW_BRIGHTNESS` 只作用在「没有太阳」的那一侧。

---

## 3. 改动内容

### 3.1 `gbuffers_textured.fsh`（阴影路径，`#else` 分支内）

```glsl
// 改后（:423-424）：光照贴图按满值采样
vec3 lMapFull    = texture2D(lightmap, vec2(coord1.x, coord1.y)).rgb;
vec3 lMapAmbient = texture2D(lightmap, vec2(0.0,     coord1.y)).rgb;
```

```glsl
// 改后（:456）：受光面用满天光，阴影里才保留 SHADOW_BRIGHTNESS
// sLight = 可见性 * N·L * 2，乘 0.5 归一到 0..1
vec3 skyLight = lMapAmbient * mix(sBright, 1.0, clamp(dot(sLight, vec3(0.5)), 0.0, 1.0));
```

`skyLight += sLight * (1.0 - sBright);`（:461）**保持不变**，太阳项照旧叠加，只落在受光面。

`lMapFull` / `blockLightContribution` 的算法没有改，方块光差额随天光采样恢复满值后
自然收窄（白天火把不再压过太阳）。

### 3.2 `gbuffers_water.fsh`

水面的着色路径**不分阴影开关**（半透明实体、水面始终走这一套），
所以必须用 `#if` 把新逻辑限制在阴影开启时，否则会改到「没开阴影」的画面：

```glsl
// :263-269
#if ENABLE_SHADOWS == 1
    vec3 lMapFull    = texture2D(lightmap, vec2(coord1.x, coord1.y)).rgb;
    vec3 lMapAmbient = texture2D(lightmap, vec2(0.0,     coord1.y)).rgb;
#else
    vec3 lMapFull    = texture2D(lightmap, vec2(coord1.x, coord1.y * sBright)).rgb;
    vec3 lMapAmbient = texture2D(lightmap, vec2(0.0,     coord1.y * sBright)).rgb;
#endif
```

```glsl
// :283-287
#if ENABLE_SHADOWS == 1
    vec3 skyLight = lMapAmbient * mix(sBright, 1.0, clamp(dot(sLight, vec3(0.5)), 0.0, 1.0));
#else
    vec3 skyLight = lMapAmbient;
#endif
```

`gbuffers_textured.fsh` 不需要 `#if`：那一段本来就在 `#if ENABLE_SHADOWS == 0 ... #else` 的
阴影分支里。

---

## 4. 行为变化

| 情况 | 变化 |
| --- | --- |
| `ENABLE_SHADOWS = 0` | **完全不变**（见 5.2 的逐行验证） |
| 白天，受光面 | 变亮（天光满值 + 太阳项），约 +40% |
| 白天，阴影里 | 约 0.6 倍天光：比改前略亮，但受光面亮得更多 → 对比更强 |
| 白天，背光面（N·L≈0） | 与阴影同样按 `SHADOW_BRIGHTNESS` 取天光，没有太阳加成 → 有方向感 |
| 白天，火把/灯笼 | 加成明显收窄（天光已满，差额变小），接近原版 |
| 夜晚 / 洞穴 / 下界 | **不变** |
| 水面 | 阴影开启时与地形一致；关闭时不变 |

---

## 5. 验证

### 5.1 编译

用 glslang 把 22 个 shader 按各自声明的 `#version` 完整编译（先展开 `#include`、
按包内选项宏预处理）：

| 配置 | 结果 |
| --- | --- |
| 默认（阴影关） | 22/22 通过 |
| 全开（阴影 + 卡通 + 纹理描边 + 纸世界 + voronoi + 线性深度） | 22/22 通过 |

（附：`#version 130` 文件里 `texture()` 被同名采样器遮住的老问题已在此前的 1.16 移植中修掉，
否则这两个程序在 1.16 上会报 `Invalid program`。）

### 5.2 「没开阴影」的等价性（逐行比对）

对比对象是提交 `1fa8de3`（1.16 移植完成、未含本次光照改动）与本次改动，
把两边按 `ENABLE_SHADOWS = OFF` 预处理后逐行 `Compare-Object`：

| 文件 | 结果 |
| --- | --- |
| `gbuffers_textured.fsh` | **identical**（阴影分支整段不参与编译） |
| `gbuffers_water.fsh` | 只有 `lMapFull` / `lMapAmbient` / `skyLight` 三条语句的位置移进了 `#if/#else`，文本内容与原来一致 |

### 5.3 进游戏验证建议（F3+R 重载后）

1. 正午晴天空旷草地：应当明显亮于改前，接近原版白昼；
2. 树下/建筑旁的阴影：应当看得清边界，且比受光面暗一档；
3. 白天在屋里点火把：火把只做局部提亮，不应再压过天光；
4. 夜晚：应当与改前一致（仍是方块光为主）；
5. 关掉「阴影」：应当与改前一致。

---

## 6. 调参与回退

**阴影更黑 / 对比更强**：把 `SHADOW_BRIGHTNESS` 调小（`commonSettings.glsl:6`，默认 `0.60`），
例如 `0.45`。它现在只影响「阴影里 / 背光面」保留多少天光。

**方块光更弱**：`BLOCK_LIGHT_INTENSITY`（默认 `0.8`）；
只想弱化「暗面额外加成」就调 `BLOCK_LIGHT_SHADOW_BOOST`（默认 `1.25`，1.0 = 关闭）。

**完全回退**：把两处改回即可（`gbuffers_textured.fsh` 的 `:423-424`、`:456`，
`gbuffers_water.fsh` 的 `:263-269`、`:283-287`），即：

```glsl
vec3 lMapFull    = texture2D(lightmap, vec2(coord1.x, coord1.y * sBright)).rgb;
vec3 lMapAmbient = texture2D(lightmap, vec2(0.0,     coord1.y * sBright)).rgb;
...
vec3 skyLight = lMapAmbient;
```

---

## 7. 已知限制

- **`sLight` 混了两种信息**：阴影可见性与 `N·L` 朝向。所以 `mix` 的因子严格说是
  「太阳到达这个面的程度」，不是纯阴影可见性。后果是背光面会被和阴影面一样处理
  （都按 `SHADOW_BRIGHTNESS` 取天光）——这符合「没有直射太阳」的直觉，但如果以后
  需要「阴影只由阴影贴图决定、朝向只由 ramp 决定」，就要把两者拆开。
- **`ramp.png` / `cel_ramp.png` 的朝向没有改**：`lambertCol` 仍然由 `LAMBERT_MODE`
  的 ramp 提供方向性着色，本次未动。
- **`CEL == 1` 分支**共用 `skyLight`/`blockLight`，所以也会随之变亮；已确认可选开启后能编译，
  但观感未逐一调校。
- **`shadowDist = far` + `length(world)`**（`:340-344`）是既有实现：`length(world)` 是到世界原点的
  距离，不是到摄像机的距离。离原点很远时阴影可能整段失效。这是旧问题，本次未改。

---

## 8. 变更记录

| 日期 | 内容 |
| --- | --- |
| 2026-11-21 | 初版：天光按满值采样，`SHADOW_BRIGHTNESS` 只作用于无太阳的一面；水面加 `#if` 保护 |
| 2026-11-21 | 撤回上一版「白天抬高 `sBright`」的写法（会把亮暗一起抬、挤掉太阳项），见 2.6 |

---

## 9. 参考

- 光照贴图坐标：`gl_TextureMatrix[1] * gl_MultiTexCoord1`，X = 方块光、Y = 天空光
  （见 `gbuffers_textured.vsh:71-72`）
- 原版光照贴图的合成方式（天空光 / 方块光取较大者）：`LightTexture.updateLightTexture`
- `SHADOW_BRIGHTNESS` 选项定义：`commonSettings.glsl:6`
- 阴影路径的 `sLight` 计算：`gbuffers_textured.fsh:338-410`

---

## English summary

With shadows enabled, the shade path sampled the lightmap at `coord1.y * sBright`, i.e. it
dimmed the **sky light of every pixel** to `SHADOW_BRIGHTNESS` (0.6) instead of only the
shadowed ones. Daytime therefore lost roughly 40% of its sky light, and because the block
light is still added as the full `lMapFull - lMapAmbient` difference, torches outshone the
sun during the day and lit and shadowed surfaces ended up close in brightness.

`SHADOW_BRIGHTNESS` now applies only to the side the sun does not reach:
the lightmap is read at its full sky value, and `skyLight = lMapAmbient * mix(sBright, 1.0,
sunReach)` with `sunReach = clamp(dot(sLight, 0.5), 0, 1)` (`sLight = shadow visibility * N·L * 2`).
The existing sun term `sLight * (1 - sBright)` is unchanged, so lit faces get sky light plus
direct sun while shadowed and back-facing ones keep `SHADOW_BRIGHTNESS` of the sky light —
bright daytime, visible contrast, and nothing changes at night, in caves or in the Nether
where the sky light is zero anyway.

An earlier attempt that simply raised `sBright` during the day was reverted: it lifts lit and
shadowed pixels together and squeezes the sun term's weight, which made the image flatter.

`gbuffers_water.fsh` shares its path with the shadows-disabled look, so the new code is
wrapped in `#if ENABLE_SHADOWS == 1`; a line-by-line comparison of the preprocessed sources
confirms the shadows-disabled output is byte-identical to the previous commit.
