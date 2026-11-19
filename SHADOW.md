# 阴影实现说明（Shadow）

> 本文件记录 `LSOutlineShaderNE` 阴影 pass 的**实现原理、引擎约束、本次更改**，
> 以及已经验证过、但最终放弃的替代方案，避免以后重复踩坑。
>
> 相关文件：
> - 着色器：`addon/LSOutlineShaderNE_Res/shaders/glsl/ls_shadow_shader_ne.fragment`
> - 参数表：`addon/LSOutlineShaderNE_Beh/LSOutlineShaderScript/ShaderSettings.py`
> - 材质：`addon/LSOutlineShaderNE_Res/materials/postprocess.material`（`ls_outline_shader_ne_shadow`）
> - 驱动：`LSOutlineShaderNEClient.py` 的 `Apply()` / `build_shadow_process()`

---

## 1. 引擎约束：为什么只能做近似

网易《我的世界》中国版（**非渲染龙**，即旧 OpenGL 后处理管线）给自定义后处理
pass 的数据只有三张图：

| 纹理 | 内容 |
|---|---|
| `TEXTURE_0` | 上一 pass 的颜色（场景颜色） |
| `TEXTURE_1` | 未处理的原始场景颜色 |
| `TEXTURE_2` | **透视非线性深度**（仅 `.r` 通道有效） |

**拿不到**：shadow map、lightmap（天空光照 / 方块光照）、G-Buffer 法线。

原 Java 光影（OptiFine/Iris）的阴影依赖 `shadowtex0/shadowtex1/shadowcolor0`、
`shadowProjection`、PCF 等延迟管线数据，这些在网易旧后处理里**一律不存在**。
因此本模组的"阴影"只能是**屏幕空间近似**，不能冒充真实投影阴影。

---

## 2. 引擎事实（已对照 vanilla_netease 源码核实）

以下结论都来自引擎自带着色器，而不是猜测：

### 2.1 深度是"透视非线性深度"

官方 `vanilla_netease/shaders/glsl/depth_sample.fragment` 里的换算：

```glsl
float DepthToViewZ(float z, float n, float f) {
    return (f*n) / (f - z*(f-n));          // n = 0.025（近平面）, f = FAR_CHUNKS_DISTANCE
}
```

即：`TEXTURE_2.r` ∈ `[0,1]`（近=0、远=1），近平面 **0.025**，远平面
**`FAR_CHUNKS_DISTANCE`**。本实现用等价的：

```glsl
float depthToViewDist(float d) {
    float f = max(FAR_CHUNKS_DISTANCE, 16.0);
    return (f * NEAR_PLANE) / max(f - d * (f - NEAR_PLANE), 1e-4);  // NEAR_PLANE = 0.025
}
```

### 2.2 后处理全屏 pass 里 `inverse(PROJ)` 不可靠

`uv_fullscreen.vertex` 的顶点着色器是：

```glsl
void main() {
    gl_Position = vec4(POSITION.xy, 0.0, 1.0);
    uv = TEXCOORD_0;
}
```

**它根本不用 `PROJ`**。所以后处理里的 `PROJ` 不是"当前场景相机投影矩阵"，
用 `inverse(PROJ)` 重建视空间深度会得到错误结果。这正是原描边
「线性深度」开关会异常的原因（见 `PORTING.md` 排错表）。

> 结论：阴影**不要**依赖 `inverse(PROJ)`；用 2.1 的解析式即可。

（注：`scan_map.fragment` 用 `inverse(PROJ*WORLDVIEW)` 重建世界坐标是官方写法，
说明矩阵本身可用；真正不可靠的是把 `PROJ` 当成相机投影去做**逐像素深度反算**。）

### 2.3 屏幕尺寸要用 UV 导数取

官方后处理 shader（`daul_blur_down_sample.fragment`、`vignette.fragment`）取屏幕
尺寸用的是 `EXTRA_VECTOR4`（screen info），**不是 `TEXTURE_DIMENSIONS`**。
`TEXTURE_DIMENSIONS` 在 post pass 里的含义没有保证，所以本实现直接：

```glsl
vec2 screenSize = vec2(1.0/max(abs(dFdx(uv.x)),1e-6),
                       1.0/max(abs(dFdy(uv.y)),1e-6));
```

### 2.4 参数注入

`EXTRA_VECTOR1/2` 由 Python 的 `SetParameter` 写入，片元着色器里声明成普通
`uniform vec4` 即可（与现有 `ls_outline_shader_ne.fragment` 的用法一致）。

---

## 3. 最终算法：局部遮蔽（Ambient Occlusion）

**目标**：在没有 shadow map / lightmap 的前提下，做出最干净的"遮蔽光"——
只在**真有近处遮挡**的地方压暗，平地/受光面完全不动。

### 3.1 流程

对每个像素：

1. 用 2.1 的解析式把深度换成**视空间距离** `center`；
2. 若 `center >= FAR_CHUNKS_DISTANCE * 0.995`（天空/远平面）→ 直接跳过，不压暗；
3. 以 `center` 为基准，在屏幕空间用**黄金角螺旋**采样一个圆盘（半径 40~56 像素，
   软阴影更大）；
4. 对每个邻居，算 `depthDiff = center - neighbour`：
   - `> 0` 表示邻居更近（存在遮挡物）；
   - 用 `smoothstep(0, penumbra, depthDiff)` 累积，`penumbra` 随距离增大；
5. 平均后做一次 `smoothstep(0, 0.45, ...)` 拉对比，得到 `occlusion ∈ [0,1]`；
6. `SHADOW_DISTANCE > 0` 时按距离衰减；
7. 最终只把**被遮挡的像素**向 `SHADOW_TINT`（偏冷蓝）混合，力度由
   `SHADOW_BRIGHTNESS` 控制。

### 3.2 关键设计（为什么这样能"干净"）

| 设计 | 作用 |
|---|---|
| **黄金角螺旋采样** | 均匀、无轴向条带 |
| **判定门槛 `penumbra ≥ 1.3 格`** | 草叶/树叶这类薄片（厚度远小于 1 格）被忽略 → **不会在草地上产生"鬼影/暗斑"** |
| **只对有遮挡的像素调色** | `occlusion == 0` 的像素保持原样 → **画面整体不会变暗** |
| **不算法线、不计算 N·L、不做太阳步进** | 没有摩尔纹、没有 z-fight 感、**不随太阳变化** |
| **不做整幅对比度/饱和度调色** | 不会被误当成"阴影"的全局压暗 |

### 3.3 只覆盖哪些地方

- ✅ 台阶缝、方块底角、方块与地面的交界、树干根部、树冠下方、洞穴凹处；
- ✅ 这些位置会产生明显的柔和暗部；
- ❌ **平地上不会有树冠投下的影子**——那需要 lightmap / shadow map，旧后处理没有。

---

## 4. 参数映射

`EXTRA_VECTOR1 = (ENABLE_SHADOWS, SHADOW_BRIGHTNESS, SHADOW_DISTANCE, SOFT_SHADOWS)`
`EXTRA_VECTOR2 = (shadowMapResolution, BLOCK_LIGHT_INTENSITY, BLOCK_LIGHT_SHADOW_BOOST, Shininess)`

| 参数 | 作用 | 备注 |
|---|---|---|
| `ENABLE_SHADOWS` | 阴影 pass 总开关 | 默认关；关闭时不产生开销 |
| `SHADOW_BRIGHTNESS` | 阴影里保留的亮度，**越低越暗** | 本次范围改为 **0.7 ~ 1.0**（步长 0.05），默认 **0.85** |
| `SHADOW_DISTANCE` | 遮蔽衰减距离；`-1` = AUTO | 语义为"屏幕空间遮蔽作用距离" |
| `SOFT_SHADOWS` | 采样半径更大、更柔 | |
| `shadowMapResolution` | 仅影响采样数（512→8192） | 没有真正的阴影贴图，仅作质量档位 |
| `BLOCK_LIGHT_INTENSITY` | 亮像素（近似火把）乘该强度 | |
| `BLOCK_LIGHT_SHADOW_BOOST` | 遮蔽越强，亮像素额外乘得越多 | |
| `Shininess` | 亮部 `pow(luma,16)` 高光 | 无水面法线，做近似 |

---

## 5. 本次更改记录

### 5.1 着色器

`ls_shadow_shader_ne.fragment` 经过多轮迭代，最终定为**纯局部 AO**（本文第 3 节）：

- 移除 `inverse(PROJ)` 深度反算 → 改用引擎解析式（第 2.1 节）；
- 移除屏幕空间太阳步进（SSS）与朝上步进（天空遮挡近似）——它们会产生随机色块；
- 移除整幅对比度/饱和度调色——它会把画面整体压暗；
- 采样半径放大、判定门槛抬高 → 消除草地鬼影与随机暗斑。

### 5.2 参数表 `ShaderSettings.py`

按需求只改两处：

- **第 68 行**：`SHADOW_BRIGHTNESS_OPTIONS` 由 `0.0..1.0`(21 档)
  改为 **`0.7..1.0`(7 档)**：
  ```python
  SHADOW_BRIGHTNESS_OPTIONS = [round(0.7 + i * 0.05, 2) for i in range(7)]
  ```
- **第 159 行**：`"default"` 由 `12` 改为 **`3`**（对应 0.85）：
  ```python
  {"kind": "slider", "key": "SHADOW_BRIGHTNESS", "label": u"阴影亮度",
   "options": SHADOW_BRIGHTNESS_OPTIONS, "default": 3},
  ```

> 注意：该值按**索引**存入全局配置。旧范围（21 档）存下的索引在新范围（7 档）里
> 会越界并被夹到上限。更新后请进游戏把「阴影亮度」重新点一次（或清一次全局配置），
> 新默认 0.85 只对全新配置生效。

### 5.3 离线自检

`tools/validate_port.py` 里与阴影相关的检查已同步为：
阴影 pass 能收到全部参数、用 `FAR_CHUNKS_DISTANCE` 重建深度而不依赖投影逆矩阵。
（其中"0..1 共 21 档"的旧断言在 5.2 改动后已不适用。）

---

## 6. 已验证但放弃的方案（避免重复踩坑）

| 方案 | 放弃原因 |
|---|---|
| **N·L 方向光照**（深度导数求法线） | 大平面上法线随深度精度抖动 → **摩尔纹 / z-fight 感**；且随太阳变化，与"只和上方遮蔽有关"矛盾 |
| **朝太阳方向屏幕空间步进（SSS）** | 树叶/重叠物上产生**随机暗块/鬼影**；俯视角下步进很快出屏幕 |
| **朝正上方步进（天空遮挡近似）** | 出现**莫名其妙色块**，随视角/屏幕位置不稳定 |
| **整幅对比度 + 饱和度调色** | 把**画面整体压暗**，且本质上不是阴影 |

这些方案都试过，均因上述原因回退。最终回到"局部遮蔽 AO + 只压暗被遮挡处"。

---

## 7. 已知限制

1. **平地无树冠阴影**：树冠投在地面的影子需要 lightmap/shadow map，屏幕空间深度
   只记录"视线遮挡"，不记录"光照遮挡"，俯视角下**根本算不出来**。
2. **屏幕外遮挡物测不到**。
3. **薄物体被忽略**：为保证干净，判定门槛 ≥1.3 格，极细的遮挡会漏。
4. 仅适用于**非渲染龙**的 GLSL 后处理管线。要真实阴影需走渲染龙 ShaderSDK（另一套接口）。

---

## 8. 推荐设置

| 参数 | 推荐 |
|---|---|
| 启用阴影 | 开 |
| 软阴影 | 开 |
| 阴影距离 | 自动 |
| **阴影亮度** | **0.7 ~ 0.85** |
| 方块光强度 / 增强 | 1.0 / 1.0 |
