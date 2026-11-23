# 风格化描边光影 — Better RenderDragon 移植版 (BE)

把 Java 版（Iris/OptiFine）描边光影的**纹理描边**（`ENABLE_TEXTURE_OUTLINES`）移植到
基岩版 **Better RenderDragon**，目标版本 **Minecraft Bedrock 26.50**。

- 移植原则：**不改着色器逻辑**，只做引擎层适配（顶点输入 / 纹理来源 / flag 宏写法）。
- 产物：一个可直接导入的 `OutlineShader.mcpack`。

---

## 工程结构

```
BE/
├── project.json                 # lazurite 工程配置（合并 vanilla + 编译平台）
├── RenderChunk/
│   └── shaders/
│       ├── fragment.sc          # 纹理描边逻辑（从 gbuffers_textured.fsh 移植）
│       ├── vertex.sc            # 顶点变换（vanilla RenderChunk，UV 解包/雾）
│       ├── varying.def.sc
│       └── bgfx_shader.sh
├── vanilla/
│   └── RenderChunk.material.bin # lazurite 的 merge source（原版材质，编译底版）
├── env/
│   └── shaderc.exe              # bgfx shaderc 编译器
├── include/                     # bgfx 头文件（可选）
├── build.bat                    # 一键编译 + 打包
├── package.ps1                  # 把 build/*.material.bin 打成 .mcpack
├── build/                       # 编译输出（*.material.bin）
└── OutlineShader.mcpack         # 最终产物
```

---

## 构建

需要 **Python 3.10 + lazurite**：

```bat
pip install lazurite==0.10.0
```

> 注意：lazurite 0.10.0 发布时假设 Python 3.11（`int.to_bytes` 省略 byteorder）。
> 在 Python 3.10 上需给 `lazurite/util.py` 里两处 `.to_bytes(8)` 补上 `'big'` 参数。
> 若你的环境是 Python 3.11+，则无需修改。

然后运行：

```bat
build.bat
```

它会：
1. `lazurite build` → `build/RenderChunk.material.bin`
2. `package.ps1` → `OutlineShader.mcpack`

手动编译命令：

```bat
py -3.10 -m lazurite build . --shaderc env\shaderc.exe -o build
powershell -ExecutionPolicy Bypass -File package.ps1
```

---

## 安装

1. 把 `OutlineShader.mcpack` 导入 Minecraft
2. 在 **设置 → 全局资源包** 启用
3. 用 BRD 的 `LaunchMinecraft.bat` 启动游戏，F6 确认 **Load Shaders from Resource Pack** 勾选
4. 完全重启 Minecraft

---

## 纹理描边实现说明

`fragment.sc` 里的 `getTEXTURETextureOutline()` 是 `gbuffers_textured.fsh` 的**原样移植**：
采样贴图四邻域（`texelSize = (1/res) * OUTLINE_THICKNESS * 0.3`），计算色差，
`clamp(maxDiff * 4.0, 0, 1)`，然后 `mix(color, vec3(0.05), outline * TEXTURE_OUTLINE_STRENGTH)`。

**唯一改动**：Java 的 `textureSize(texture, 0)` 在 bgfx 里没有对应函数，改成常量
`ATLAS_SIZE`（默认 256，见 `fragment.sc` 顶部）。如果你的地形图集实际是 512 或 1024，
改这个常量即可让描边粗细正确。

可调参数（`fragment.sc` 顶部）：

| 宏 | 含义 |
|---|---|
| `ENABLE_TEXTURE_OUTLINES` | 总开关（1 开 / 0 关） |
| `TEXTURE_OUTLINE_STRENGTH` | 描边强度（越大越黑） |
| `OUTLINE_THICKNESS` | 描边宽度 |
| `ATLAS_SIZE` | 地形图集分辨率（影响 texel 步长） |

---

## 为什么只做纹理描边（不做全屏深度描边）

Java 版还有一条**全屏深度描边**（`final.fsh`，读取 `depthtex0` 后处理）。经实测，
26.50 的 forward 管线**没有暴露可替换的全屏后处理材质**：

- `RenderChunk`（地形）可替换，生效 ✅
- `Blit` / `BlitColor` / `BlitHDR` / `ScreenBlit` / `displaymap` / `Upscaling` /
  `ColorPostProcessing` / `GammaScreenColorPostProcessing` / `DeferredShading` → 全部无效 ❌

因此 `final.fsh` 的全屏深度描边在当前环境无法用材质替换实现，只能做基于贴图边缘的**纹理描边**。
