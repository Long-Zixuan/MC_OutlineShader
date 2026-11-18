"""拉取原版贴图并生成描边资源包（全自动）。

  1. GitHub tree API 取文件清单
  2. jsDelivr 并发下载 textures/blocks、textures/entity（可加 items）
  3. 逐张烤描边，写到 be/pack
  4. 打 be/dist/OutlineTextures.mcpack

    python be/tools/build_all.py [--with-items] [--limit N]
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_outline_pack as g  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "_src")
PACK = os.path.join(ROOT, "pack")
DIST = os.path.join(ROOT, "dist")
TREE = "https://api.github.com/repos/Mojang/bedrock-samples/git/trees/main?recursive=1"
CDN = "https://cdn.jsdelivr.net/gh/Mojang/bedrock-samples@main/"


def list_textures(with_items):
    cache = os.path.join(ROOT, "_tree.json")
    if os.path.exists(cache):
        data = json.load(open(cache, "r", encoding="utf-8"))
    else:
        req = urllib.request.Request(TREE, headers={"User-Agent": "outline-builder"})
        data = json.loads(urllib.request.urlopen(req, timeout=180).read())
        with open(cache, "w", encoding="utf-8") as f:
            json.dump(data, f)
    prefix = ["resource_pack/textures/blocks/", "resource_pack/textures/entity/"]
    if with_items:
        prefix.append("resource_pack/textures/items/")
    paths = []
    for item in data.get("tree", []):
        p = item["path"]
        if p.endswith(".png") and p.startswith(tuple(prefix)):
            paths.append(p)
    return paths


def download(path):
    dst = os.path.join(SRC, path.replace("resource_pack/", ""))
    if os.path.exists(dst) and os.path.getsize(dst) > 0:
        return dst
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    url = CDN + urllib.parse.quote(path)
    raw = "https://raw.githubusercontent.com/Mojang/bedrock-samples/main/" + urllib.parse.quote(path)
    last = None
    for i in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "outline-builder"})
            d = urllib.request.urlopen(req, timeout=25).read()
            with open(dst, "wb") as f:
                f.write(d)
            return dst
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(0.6 * (i + 1))
    try:
        req = urllib.request.Request(raw, headers={"User-Agent": "outline-builder"})
        d = urllib.request.urlopen(req, timeout=60).read()
        with open(dst, "wb") as f:
            f.write(d)
        return dst
    except Exception as e:  # noqa: BLE001
        last = e
    print("  fail", path, last, flush=True)
    return None


def process_one(path):
    src = os.path.join(SRC, path.replace("resource_pack/", ""))
    if not os.path.exists(src):
        return 0
    from PIL import Image

    rel = path.replace("resource_pack/", "")
    dst = os.path.join(PACK, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    try:
        with Image.open(src) as im:
            if "/textures/blocks/" in path:
                out = g.outline_block(im)
            else:
                out = g.outline_sprite(im)
            out.save(dst)
        return 1
    except Exception as e:  # noqa: BLE001
        print("  proc fail", rel, e)
        return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--with-items", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=24)
    args = ap.parse_args()

    print("取文件清单...")
    paths = list_textures(args.with_items)
    if args.limit:
        paths = paths[: args.limit]
    print(f"共 {len(paths)} 张")

    os.makedirs(SRC, exist_ok=True)
    ok = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for i, r in enumerate(ex.map(download, paths), 1):
            if r:
                ok += 1
            if i % 100 == 0:
                print(f"  下载 {i}/{len(paths)} (成功 {ok})", flush=True)
    print(f"下载完成 {ok}/{len(paths)}")

    os.makedirs(PACK, exist_ok=True)
    g.write_manifest(PACK)
    done = 0
    for i, p in enumerate(paths, 1):
        done += process_one(p)
        if i % 100 == 0:
            print(f"  处理 {i}/{len(paths)} (出图 {done})", flush=True)
    print(f"处理完成 {done} 张")

    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, "OutlineTextures.mcpack")
    n = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(PACK):
            for name in files:
                full = os.path.join(base, name)
                z.write(full, os.path.relpath(full, PACK).replace("\\", "/"))
                n += 1
    print(f"{out}  ({n} 个文件)")


if __name__ == "__main__":
    main()
