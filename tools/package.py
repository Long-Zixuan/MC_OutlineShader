"""把 be/pack 打成 .mcpack（本质就是 zip，manifest.json 在根目录）。

    python be/tools/package.py

产物：be/dist/OutlineTextures.mcpack
"""
import os
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, "pack")
OUT = os.path.join(ROOT, "dist", "OutlineTextures.mcpack")


def main():
    if not os.path.isfile(os.path.join(PACK, "manifest.json")):
        raise SystemExit("be/pack/manifest.json 不存在，先生成贴图")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    n = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(PACK):
            for name in files:
                full = os.path.join(base, name)
                rel = os.path.relpath(full, PACK).replace("\\", "/")
                z.write(full, rel)  # 正斜杠，manifest 在根
                n += 1
    print(f"{OUT}  ({n} 个文件, {os.path.getsize(OUT) / 1048576:.1f} MB)")


if __name__ == "__main__":
    main()
