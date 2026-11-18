# be —— 世界描边材质包（mcpack）

一个纯资源包：`manifest.json` + 2607 张处理过的贴图，给**方块、生物、物品**加描边。
作者：LoongLy；图标为 `pack/pack_icon.png`。

产物：[`be/dist/OutlineTextures.mcpack`](dist/OutlineTextures.mcpack)（2.6 MB）

## 打包

mcpack 就是一个 zip，唯一要求是 `manifest.json` 在压缩包**根目录**、路径用正斜杠。

```powershell
python be\tools\package.py
```

产物在 `be/dist/OutlineTextures.mcpack`，双击即可导入游戏。
手动打也行：全选 `be/pack` 里的内容（不是 pack 文件夹本身）→ 压缩成 zip → 改后缀为 `.mcpack`。

U 盘/手机上导入失败时，把 `be/pack` 整个文件夹拷到：

```
Android/data/com.mojang.minecraftpe/files/games/com.mojang/resource_packs/
```

保证 `manifest.json` 在那一层的根目录。

## 先说明它是什么

国际版基岩自 RenderDragon 起不再加载自定义着色器，`.material` / `shaders/glsl` 全部失效，
mcpack 能改的只有贴图、模型、UI 这类数据。所以这里的描边是**烤进贴图**的，不是屏幕空间的实时轮廓：

| 对象 | 做法 | 观感 |
|---|---|---|
| 方块（1207 张） | 每帧贴图四周压 1px 暗边 | 每个方块面有边框，方块之间像描了线 |
| 生物（542 张） | 不透明岛屿靠透明边界处压暗 | 头/手/腿等部位的贴图边缘变暗，像勾线 |
| 物品（858 张） | 同生物 | 物品图标/模型边缘勾线 |

它**不会**描出“物体与背景交界的那一圈”（那需要深度图，属于渲染管线）。
想要那种效果只有 material.bin，而那不是 mcpack。

## 生成

```powershell
python be\tools\gen_outline_pack.py --src "<原版 resource_pack 目录>" --only blocks,entity,items
python be\tools\build_all.py            # 或者从 GitHub 全自动拉取（网络慢，不推荐）
```

`--src` 直接指向本机网易客户端的原版包即可，例如：

```
D:\MCStudioDownload\game\MinecraftPE_Netease\3.9.0.401155\data\resource_packs\vanilla
```

调参在 `be/tools/gen_outline_pack.py` 顶部：

```python
BLOCK_BORDER = 0.35   # 方块边框压暗强度
SPRITE_EDGE  = 0.55   # 生物/物品剪影压暗强度
```

## 安装

1. 导入 `be/dist/OutlineTextures.mcpack`
2. 设置 → 全局资源包 → 激活
3. 重启游戏

## 已知限制

- 覆盖的是贴图，**不会描外轮廓**，也不会像 Java 光影那样随距离变细。
- 只覆盖原版贴图路径；玩家皮肤、自定义模型、第三方材质不受影响，也会和别的材质包互相覆盖。
- 贴图来自网易客户端 3.9.0 的原版包（1207 方块 / 542 生物 / 858 物品）。版本更老或更新的方块如果没有同名贴图，
  就不在这个包里，需要按同一脚本对相应版本的原版包再跑一次。
- 方块边框是画在每个面四周的，等于给每个面加一圈细线；如果某张贴图本身留边很少，线会显得粗一点。
