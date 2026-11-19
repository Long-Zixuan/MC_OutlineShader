# oldLighting 与 ENABLE_SHADOWS

> 记录一次修复：`shaders.properties` 里的 `oldLighting=true` 会干扰 `ENABLE_SHADOWS = 1` 的观感，
> 而该属性无法按选项条件关闭，因此在 shader 里做了等效还原。
>
> 涉及文件：`shaders/commonSettings.glsl`、`shaders/gbuffers_textured.fsh`、
> `shaders/gbuffers_water.vsh`、`shaders/gbuffers_water.fsh`

---

## 1. 现象

打开「阴影」( `ENABLE_SHADOWS = 1` ) 后，画面比预期偏暗：

- 东西（W/E）面明显更暗，南北（N/S）面稍暗，顶面正常；
- `SHADOW_BRIGHTNESS`、`BLOCK_LIGHT_INTENSITY`、`BLOCK_LIGHT_SHADOW_BOOST` 怎么调都不对，
  因为多出来的那层暗度和这些参数无关；
- 关掉阴影（`ENABLE_SHADOWS = 0`）反而正常。

原因是 vanilla 的**面向亮度（face shade）被乘了两次**：一次被 `oldLighting=true` 烘进了
顶点色 `gl_Color`，一次由阴影路径自己的 `N·L` / ramp 计算得出。

---

## 2. 原理

### 2.1 `oldLighting` 到底做了什么

`oldLighting` 是 `shaders.properties` 的**包级属性**（不是选项）：

```
oldLighting=true
```

开启后，Iris / OptiFine 会把 vanilla「按方块朝向决定的固定亮度」乘进顶点色，也就是
shader 里的 `gl_Color`（本包用 `varying vec4 color` 接收）。这个系数来自
`BlockAndTintGetter.getShade(Direction, boolean)`：

| 面 | 亮度 |
| --- | --- |
| DOWN（下） | 0.5 |
| UP（上） | 1.0 |
| NORTH / SOUTH（南 / 北） | 0.8 |
| WEST / EAST（西 / 东） | 0.6 |

而 vanilla 的最终像素是：

```
texture × gl_Color × lightmap
```

本包设了 `separateAo=false`，所以

```
gl_Color.rgb = 面向系数 × AO × 生物群系染色
```

### 2.2 为什么不能"只在 ENABLE_SHADOWS = 1 时关掉"

- **它是包级静态属性**：光影包加载时解析一次，作用在所有 program 上，不参与选项系统；
- **解析时不看选项宏**：OptiFine 文档明确列出
  `version / oldLighting / separateAo / sliders / profiles / screen` 是**不使用选项宏解析**的
  （见 [Preprocessor directives](https://optifine.readthedocs.io/shaders_dev/preprocessor.html)），
  Iris 行为一致。所以 `#if ENABLE_SHADOWS`、`program.xxx.enabled` 之类都影响不到它；
- **它不是 uniform**：shader 里读不到当前状态，没有 `if (oldLighting)` 这种写法；
- 改它必须改文件 + 重载光影（F3+R），并且会同时影响所有分支。

还有两个坑：

1. OptiFine 的「视频设置 > 光影 > 经典光效」优先级**高于** `shaders.properties`，
   玩家可以覆盖包里的设置；
2. OptiFine 会注入 `MC_OLD_LIGHTING` 宏，但 **Iris 不定义这个宏**
   （Iris 的 `StandardMacros` 里没有，见参考链接），所以没法跨平台可靠判断"现在到底开没开"。

结论：**属性本身关不掉，只能在 shader 里把它的影响抵消掉。**

### 2.3 两个分支的需求正好冲突

| 分支 | 需要 `gl_Color` 带面向系数吗 | 原因 |
| --- | --- | --- |
| `ENABLE_SHADOWS = 0`（vanilla 复刻） | **需要** | 这条路径不再算 `N·L`，直接用 vanilla 已经算好的面向亮度，才能和原版一致 |
| `ENABLE_SHADOWS = 1`（风格化） | **不需要** | 这条路径用 `N·L` + ramp 自己决定明暗，再乘一次就是重复 |

所以 `oldLighting=true` 必须保留（否则关阴影时所有面一样亮），冲突只能在开阴影的分支里解决。

### 2.4 等效还原的数学

设 `S` = 面向系数，`A` = AO，`T` = 生物群系染色，则

```
C = gl_Color.rgb = S · A · T
```

`oldLighting=false` 时 shader 拿到的是 `A · T`，因此

```
C / S = A · T
```

即：**用面法线求出 S，再把 `gl_Color` 除回去**，等价于「只在这个分支里 oldLighting=false」。

修正前后的阴影路径：

```
修正前：texture · (S · A · T) · shad      // 比预期暗 S 倍（0.5 / 0.6 / 0.8）
修正后：texture · (A · T)     · shad      // 期望值
```

因为 `S ≤ 1`，还原后的 albedo 仍 ≤ 1，不会过曝。

**前提**：`S` 只对「vanilla 真的会做面向着色」的面成立。模型可以在 json 里写
`"shade": false` 拒绝面向着色，此时 `getShade(...)` 直接返回 1.0，`gl_Color` 里根本没有
这个系数。草、花、作物用的 `block/cross` 就是 `"shade": false`（同时 `ambientocclusion: false`），
而且它们的几何体旋转了 45°。**这一步很关键**：如果不区分，草会被多除掉 0.8，并且
45° 法线的 x/z 分量几乎相等，判定会在 0.6 / 0.8 之间逐像素翻转 —— 表现为草闪烁。
详见 3.1。

---

## 3. 改动内容

### 3.1 `commonSettings.glsl`：从法线求回面向系数

```glsl
float vanillaFaceShade(vec3 worldNormal) {
    vec3 n = normalize(worldNormal); // zero or NaN normals fall through to 1.0 below
    vec3 a = abs(n);
    float axis = max(a.x, max(a.y, a.z));
    if (!(axis >= 0.85)) return 1.0; // diagonal normal: "shade": false geometry
    if (a.y >= a.x && a.y >= a.z) return (n.y < 0.0) ? 0.5 : 1.0;
    return (a.x > a.z) ? 0.6 : 0.8;
}
```

三件事：

1. **轴向判定（`axis >= 0.85`）**：0.85 约等于偏离最近轴 32°。草、花、作物的 `block/cross`
   旋转了 45°（分量 0.707），因此被判为「没有面向系数」并返回 1.0 —— 于是 `col / 1.0`，
   草回到改动前的样子。22.5° 的斜向模型（如龙蛋）仍在阈值内，按最近的轴处理。
2. **为什么必须这么做（闪烁的直接原因）**：`"shade": false` 的面 vanilla 给的是 1.0，
   除 0.8 会让草亮 25%；更糟的是 45° 法线的 `a.x` 与 `a.z` 只差最后几个二进制位，
   逐顶点/逐像素的浮点差异会让判定在 `0.6` 和 `0.8` 之间来回跳，而十字模型的两个面片
   在交叉线上互相 z-fighting —— 于是交叉处出现明暗斑块，镜头一动就像草在闪。
3. **归一化 + 反向判定**：`normalize` 让轴向判定与法线长度无关；`!(axis >= 0.85)` 用反向写法，
   这样零长度/NaN 法线（退化面片、没有法线的几何）也会落到 1.0 分支，而不是被判成 0.8。

对轴向面，取轴的顺序照抄 vanilla 的 `Direction.getNearest()`：按 DOWN、UP、NORTH、SOUTH、
WEST、EAST 取第一个最大值，即**平局面按 Y 优先于 X/Z、Z 优先于 X** 处理。

### 3.2 `gbuffers_textured.fsh`：阴影路径除回去

在 `col.rgb *= color.rgb;` 之后：

```glsl
#if ENABLE_SHADOWS == 1
    if (terrainFlag >= 0.5) {
        vec3 nWorld = mat3(gbufferModelViewInverse) * N.xyz;
        col.rgb /= vanillaFaceShade(nWorld);
    }
#endif
```

两个要点：

- **只在地形上做**（`terrainFlag >= 0.5`）。地形是全包唯一同时带 `mc_Entity.y` 与
  `at_midBlock` 的几何体，也只有它被 `oldLighting` 乘了面向系数；实体、方块实体、粒子、文字
  带的是 vanilla 的 `minecraft_mix_light()`，不能除。
- **只改 `col`，不改 `color`**。`color` 之后还要用于 colortex4（`originalTexture * color.rgb`）
  和 alpha，保持原样更安全。

### 3.3 `gbuffers_water.vsh / .fsh`：水与半透明方块同样处理

`gbuffers_water` 也是风格化光照（没有 `ENABLE_SHADOWS == 0` 分支），所以同样要还原。
但该 program 还会画半透明的**实体**几何（实体下面的阴影 blob、史莱姆/恶魂的半透明部件），
因此需要 `terrainFlag` 来区分：

- `gbuffers_water.vsh`：新增 `attribute vec4 at_midBlock;` 与 `varying float terrainFlag`，
  用和 `gbuffers_textured.vsh` 完全相同的判定；
- `gbuffers_water.fsh`：新增同名 varying，在 `col.rgb *= color.rgb;` 之后做同样的除法，
  但包在 `#if ENABLE_SHADOWS == 1` 里，保证「关阴影时的水面」观感不变。

### 3.4 顺带修掉的 bug：`N` 从来没被写过

`gbuffers_water.vsh` 一直声明了 `varying vec4 N;` 却从未赋值，而
`gbuffers_water.fsh` 的阴影 bias 里用 `normalize(N.xyz)` 算 `N·L`
（`float ndotl = max(dot(normalize(N.xyz), ...), 0.1)`）。
也就是说那段 bias 一直在用未定义值。本次补上：

```glsl
vec3 nView = gl_NormalMatrix * gl_Normal;
float nLen = length(nView);
N.xyz = (nLen > 1e-5) ? nView / nLen : vec3(0.0, 1.0, 0.0);
N.a = isWater;
```

（零长度保护，避免文本/退化面片算出 NaN。顺带也让 `vanillaFaceShade` 拿到的是真实面朝向。）

---

## 4. 行为变化与验证

| 情况 | 变化 |
| --- | --- |
| `ENABLE_SHADOWS = 0` | **完全不变**（改动都在 `#if ENABLE_SHADOWS == 1` 里） |
| `ENABLE_SHADOWS = 1`，地形顶面 | 不变（S = 1.0） |
| `ENABLE_SHADOWS = 1`，地形侧/底面 | 变亮到「该有的亮度」（除以 0.6 / 0.8 / 0.5），不再受 vanilla 明暗支配 |
| `ENABLE_SHADOWS = 1`，草 / 花 / 作物（`block/cross`） | **完全不变**，且不再闪烁（`"shade": false` → 返回 1.0） |
| `ENABLE_SHADOWS = 1`，实体 / 方块实体 / 粒子 / 文字 | 不变（被 `terrainFlag` 排除） |
| `ENABLE_SHADOWS = 1`，水面 / 半透明方块 | 侧面同样变亮到该有的亮度；海带/海草等 45° 十字几何同样不受影响 |
| 水面阴影 bias | 由未定义值改为真实法线，可能出现轻微的偏移（这是修复，不是回归） |

进游戏验证建议（F3+R 重载后）：

1. 白墙 / 雪地的东西面：应当不再比顶面暗 40%；
2. 草地、花、作物：应当**和改动前完全一致**，交叉处不再有明暗斑块或闪烁；
3. 箱子、告示牌、床等方块实体：亮度应当和改动前一致；
4. 水面与染色玻璃：侧面亮度正常，阴影没有明显的漏光 / 黑边。

---

## 5. 调参与回退

**想要弱一点的效果**（保留一部分 vanilla 面向明暗）：

```glsl
col.rgb /= mix(1.0, vanillaFaceShade(nWorld), 0.5);   // 半强度
```

**完全回退**：删掉 `gbuffers_textured.fsh` 和 `gbuffers_water.fsh` 里两处
`#if ENABLE_SHADOWS == 1 ... #endif` 块即可；`vanillaFaceShade()` 留着不用也无害。

**做成可切换选项**（选项名同步加进 `shaders.properties` 的 `sliders` / `screen.Shadow`，
以及 `shaders/lang/*.lang` 四个语言文件）：

```glsl
// commonSettings.glsl
#define SHADOW_CANCEL_OLD_LIGHTING ON // Cancel the vanilla face shade in the shadow path [OFF ON]
```

```glsl
// gbuffers_textured.fsh / gbuffers_water.fsh
#if ENABLE_SHADOWS == 1 && SHADOW_CANCEL_OLD_LIGHTING == 1
```

**重要限制**：如果以后把 `shaders.properties` 里的 `oldLighting` 改成 `false`，
必须同时删掉这两处除法，否则在 Iris 上会过曝（那里没有 `MC_OLD_LIGHTING` 可判断，
代码默认按 `oldLighting=true` 处理）。

### 已知限制 / 后续

- **`"shade": false` 但法线是轴向的模型**：目前用「法线是否贴着坐标轴」来近似「vanilla 有没有
  做面向着色」。如果某个模型写明了 `"shade": false` 却仍是轴向面片，它会被多除一次（偏亮一档）。
  原版资源里这类模型很少（十字模型都是 45° 的，正好被排除掉）；真遇到了就按方块单独排除。
- **植物自阴影（acne）**：3.1 的修改只解决「系数取错 / 取跳」导致的闪烁。如果某个方块仍在闪，
  且闪的是会随镜头移动的条纹或斑块，那是阴影贴图的 acne（十字模型非常容易自阴影），
  需要另外调 `SHADOW_BRIGHTNESS` 附近的 bias（`sBias` / `finalBias`），或让 cutout 几何
  不投射阴影，与本文件讨论的 oldLighting 无关。
- **阈值 0.85**：等于「偏离最近轴不超过约 32°」。如果以后遇到 30° 左右的自定义模型资源包，
  可以按需要调低（例如 0.7 会把 45° 十字也算进来，不建议）。

---

## 7. 变更记录

| 日期 | 内容 |
| --- | --- |
| 2026-11-20 | 初版：`vanillaFaceShade()` + `gbuffers_textured` / `gbuffers_water` 的 oldLighting 还原 |
| 2026-11-20 | 修复草闪烁：`vanillaFaceShade()` 增加轴向判定，45° 十字模型（`"shade": false`）返回 1.0 |

---

## 6. 参考

- OptiFine 预处理指令与 `oldLighting` 语义（含"不使用选项宏解析"与 `MC_OLD_LIGHTING`）：
  <https://optifine.readthedocs.io/shaders_dev/preprocessor.html>
- `oldLighting` 指令说明：<https://shaders.properties/current/reference/shadersproperties/features/>
- Iris 标准宏（确认没有 `MC_OLD_LIGHTING`）：
  <https://github.com/IrisShaders/Iris/blob/multiloader-new/common/src/main/java/net/irisshaders/iris/gl/shader/StandardMacros.java>
- vanilla 面向亮度：`BlockAndTintGetter.getShade(Direction, boolean)`、`ModelBlockRenderer.putQuadData`

---

## English summary

`oldLighting` is a pack-global property parsed once when the pack loads. OptiFine/Iris parse it
**without option macros** (only `version`, `oldLighting`, `separateAo`, `sliders`, `profiles` and
`screen` are handled that way), it is not a uniform, and OptiFine's video setting overrides it while
Iris defines no `MC_OLD_LIGHTING` macro. It therefore cannot be switched off per option.

`oldLighting=true` is still required by the `ENABLE_SHADOWS == 0` path, which wants vanilla's
per-face brightness in `gl_Color`. The shadow path instead builds its own `N·L` term, so it now
divides the baked factor `S ∈ {0.5, 0.6, 0.8, 1.0}` back out of `col.rgb` on terrain
(`vanillaFaceShade()` + `terrainFlag` gate), which is the per-fragment equivalent of
`oldLighting=false` for that branch. AO and the biome tint stay, and the `ENABLE_SHADOWS == 0`
path is untouched.

Only clearly axis-aligned normals are compensated. The 45° cross models that vanilla renders with
`"shade": false` (grass, flowers, crops) carry no factor at all, and on their diagonal normals the
axis test would flip between 0.6 and 0.8 from pixel to pixel - which showed up as flicker where the
two quads of a cross model overlap. They now return 1.0, i.e. they are left exactly as before.
