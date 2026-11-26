# 阴影实现说明（Shadow）

> 本文件记录 `LSOutlineShaderNE` 阴影的**最终实现、引擎约束、关键结论与已知限制**，
> 避免以后重复踩坑。
>
> 相关文件：
> - 顶点：`addon/LSOutlineShaderNE_Res/shaders/glsl/ls_terrain_shadow_ne.vertex`
> - 片元：`addon/LSOutlineShaderNE_Res/shaders/glsl/ls_terrain_shadow_ne.fragment`
> - 材质：`addon/LSOutlineShaderNE_Res/materials/terrain.material`
>   （覆盖 `terrain_opaque` / `terrain_far`，加载于 `materials/common.json`）
> - 后处理阴影已**全部删除**（`ls_shadow_shader_ne.fragment` 已移除、
>   `postprocess.material` 里的 `ls_outline_shader_ne_shadow` 已移除、
>   `ShaderSettings.py` / `LSOutlineShaderNEClient.py` 里的 `PROCESS_SHADOW` /
>   `shadow_params` / `build_shadow_process` 已移除）。

---

## 1. 最终方案：在地形材质里做阴影

阴影不再走屏幕空间后处理，而是**改在地形方块材质（terrain shader）里做**：

- 顶点把 `COLOR`（光照）、`TEXCOORD_0`（图集 UV）传给片元；
- 片元做 `纹理 × COLOR`，再用 `COLOR` 的亮度做**二分阴影**、用 `FOG_COLOR` 做**昼夜**。

```glsl
vec3 base = tex.rgb * v_color.rgb;                 // 纹理 × 光照/色调

// 昼夜：雾色亮度（白天亮、晚上暗）
float dayNight = dot(FOG_COLOR.rgb, vec3(0.299, 0.587, 0.114));
base *= mix(NIGHT_BRIGHTNESS, 1.0, dayNight);

// 二分天空遮蔽阴影：COLOR 亮度低于阈值即压暗
float light = max(v_color.r, max(v_color.g, v_color.b));
float shadow = 1.0 - step(SHADOW_LIGHT_THRESHOLD, light);
base *= mix(1.0, SHADOW_BRIGHTNESS, shadow);
```

---

## 2. 关键结论（均已实测，别再走回头路）

| 结论 | 说明 |
|---|---|
| `COLOR` 顶点色 **就是光照** | 阴影靠它生效（含天空遮蔽 + 方块光）。曾一度误判为“白色常量”，实测阴影能出，已纠正。 |
| `FOG_COLOR` 是全局雾色 | 随昼夜变亮变暗，用它近似昼夜（`FOG_COLOR` 在头文件里已声明，**不要再重复声明**，否则编译报 `C1038 重定义`）。 |
| 地形拿不到 `EXTRA_VECTOR` | 后处理的 `SetParameter` 只作用于后处理材质，**不会共享给地形 shader**（实测“开关不起作用”）。 |
| 地形没有运行时 uniform 接口 | 网易只开放了实体 / 骨骼模型 / 实体方块 / 后处理的 uniform；**普通地形方块没有**。所以设置页“启用阴影”开关无法驱动地形 shader。 |
| `TEXCOORD_1`(uv1) → `TEXTURE_1` 光照贴图 | 实测采样为白，网易没绑；光照不在那里。 |
| 材质覆盖用**扁平格式** | `terrain.material` 顶层直接是材质名（和 `postprocess.material` 一致），不要用 `{"materials":{...}}` 包裹。 |
| 顶点布局**继承原版** | 用“最小覆盖”（只写 `vertexShader`/`fragmentShader`），不要手写 `vertexFields`，否则顶点布局会错、地形不显示。 |

---

## 3. 参数（编译期常量，在 `ls_terrain_shadow_ne.fragment` 顶部）

| 常量 | 默认 | 作用 |
|---|---|---|
| `SHADOW_ENABLED` | `1.0` | 阴影总开关（`1` 开 / `0` 关） |
| `SHADOW_LIGHT_THRESHOLD` | `0.7` | `COLOR` 亮度低于此值判定为阴影 |
| `SHADOW_BRIGHTNESS` | `0.5` | 阴影深浅（越低越黑） |
| `NIGHT_BRIGHTNESS` | `0.3` | 夜间亮度（越低越黑） |

---

## 4. 引擎事实（供参考，来自 vanilla_netease 源码）

- 深度是**透视非线性深度**：`viewZ = (f*n) / (f - z*(f-n))`，`n=0.025`，`f=FAR_CHUNKS_DISTANCE`；
- 后处理全屏 pass 里 `inverse(PROJ)` 不可靠（顶点 shader 不用 `PROJ`），但 `inverse(PROJ*WORLDVIEW)` 是官方 `scan_map` 的重建写法（矩阵可用）；
- 后处理屏幕尺寸用 UV 导数取，不要用 `TEXTURE_DIMENSIONS`；
- `EXTRA_VECTOR1/2` 由 Python `SetParameter` 写入后处理，**仅后处理有效**。

---

## 5. 已知限制

1. **开关只能编译期**：`SHADOW_ENABLED` 是常量，设置页“启用阴影”无法实时驱动地形 shader（地形无运行时 uniform 接口）。
   若日后网易开放 `SetTerrainExtraUniforms` / `SetMaterialUniform` / `ReloadMaterial` 之类接口，可把开关接回设置页。
2. **昼夜是近似**：用 `FOG_COLOR` 亮度近似，不是真实天空光照；极端天气/生物群系下可能偏。
3. 阴影是**方块级二分**（类原版天空遮蔽），边缘为整格硬边。
4. 只覆盖 `terrain_opaque` / `terrain_far`（实体方块）；树叶/水体等其它材质未覆盖。

---

## 6. 已验证但放弃的方案（避免重复踩坑）

| 方案 | 放弃原因 |
|---|---|
| 后处理深度图“屏幕向上”步进 | 压暗的是屏幕下方像素，不是世界坐标正下方方块 |
| 后处理世界空间重建 + 向上步进 | 遮挡物必须在屏幕内才可见、视角依赖；且会出“闪烁黑块” |
| 后处理 `EXTRA_VECTOR` 传开关给地形 | `EXTRA_VECTOR` 不共享，地形读到的永远是 0 |
| `fancy.json`/`sad.json` 材质切换 + `+defines` | 需“精美图像”设置，网易无 Python 接口切换它 |
| `TEXCOORD_1`(uv1) → 光照贴图 `TEXTURE_1` | 实测采样为白，网易没绑光照 |
