"""把描边烤进贴图，生成一个纯资源包（.mcpack）。

为什么是贴图而不是 shader：
国际版基岩从 RenderDragon 起就不支持自定义着色器，资源包能改的只有贴图/模型/UI。
所以“给方块和生物加描边”唯一能落地的做法，就是把暗边直接画进原版贴图里。
这不是实时轮廓，但它是 mcpack 能做到的全部。

两种处理：
  方块贴图  -> 每一帧四周压一圈 1px 暗边（每个方块面因此有边框）
  生物/物品 -> 不透明像素靠近透明边界处压暗（描出剪影），可选内部细边

用法：
  python be/tools/gen_outline_pack.py --src <解压后的 resource_pack>
"""
import argparse
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "pack")
UUID = "5c2f8a10-3d4b-4e7a-9f61-8b2c4d6e7a01"

# 描边参数（对应 Java 版的 OUTLINE_COL 与 TEXTURE_OUTLINE_STRENGTH）
BLOCK_BORDER = 0.35   # 方块边框压暗强度 0..1
SPRITE_EDGE = 0.55    # 生物剪影压暗强度
SPRITE_ALPHA = 0.5    # 剪影在 alpha 上的阈值


def darken(c, f):
    return (int(c[0] * (1 - f)), int(c[1] * (1 - f)), int(c[2] * (1 - f)), c[3])


def outline_block(img):
    """每帧四周 1px 暗边。动画贴图是竖排帧，按 16px 或宽度分帧。"""
    img = img.convert("RGBA")
    w, h = img.size
    frame = w if h > w and h % w == 0 else h
    out = img.copy()
    px = out.load()
    src = img.load()
    for top in range(0, h, frame):
        bottom = min(top + frame, h) - 1
        for x in range(w):
            px[x, top] = darken(src[x, top], BLOCK_BORDER)
            px[x, bottom] = darken(src[x, bottom], BLOCK_BORDER)
        for y in range(top, min(top + frame, h)):
            px[0, y] = darken(src[0, y], BLOCK_BORDER)
            px[w - 1, y] = darken(src[w - 1, y], BLOCK_BORDER)
    return out


def outline_sprite(img):
    """剪影描边：不透明像素若四邻域有透明，则压暗。"""
    img = img.convert("RGBA")
    w, h = img.size
    out = img.copy()
    src = img.load()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            if a < 8:
                continue
            border = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= w or ny >= h:
                    continue
                if src[nx, ny][3] < 8:
                    border = True
                    break
            if border:
                dst[x, y] = darken((r, g, b, a), SPRITE_EDGE)
    return out


def process(src_root, out_root, sub, fn, exts=(".png",)):
    src_dir = os.path.join(src_root, sub)
    if not os.path.isdir(src_dir):
        print(f"  跳过 {sub}（不存在）")
        return 0
    n = 0
    for base, _, files in os.walk(src_dir):
        for name in files:
            if not name.lower().endswith(exts):
                continue
            src = os.path.join(base, name)
            rel = os.path.relpath(src, src_root)
            dst = os.path.join(out_root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            try:
                with Image.open(src) as im:
                    fn(im).save(dst)
                n += 1
            except Exception as e:  # noqa: BLE001
                print(f"  失败 {rel}: {e}")
    print(f"  {sub}: {n} 张")
    return n


def write_manifest(out_root):
    manifest = {
        "format_version": 2,
        "header": {
            "name": "Outline Textures",
            "description": "Baked outline for blocks and mobs",
            "uuid": UUID,
            "version": [1, 0, 0],
            "min_engine_version": [1, 20, 0],
        },
        "modules": [{"type": "resources", "uuid": "5c2f8a10-3d4b-4e7a-9f61-111122223333", "version": [1, 0, 0]}],
    }
    with open(os.path.join(out_root, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="解压后的原版 resource_pack 目录")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--only", default="blocks,entity,items")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    write_manifest(args.out)

    kinds = [k.strip() for k in args.only.split(",") if k.strip()]
    total = 0
    for kind in kinds:
        if kind == "blocks":
            total += process(args.src, args.out, "textures/blocks", outline_block)
        elif kind == "entity":
            total += process(args.src, args.out, "textures/entity", outline_sprite)
        elif kind == "items":
            total += process(args.src, args.out, "textures/items", outline_sprite)
        else:
            print(f"未知类别 {kind}")
    print(f"完成：{total} 张贴图 -> {args.out}")


if __name__ == "__main__":
    main()
