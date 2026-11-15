import glob
import math
import os

from PIL import Image

FRAMES_DIR = r"D:\MC_MOD\Sobel\_video_frames"
OUT = r"D:\MC_MOD\Sobel\shaders\texture\video.png"

files = sorted(glob.glob(os.path.join(FRAMES_DIR, "f_*.png")))
N = len(files)
if N == 0:
    raise SystemExit("no frames found in " + FRAMES_DIR)

# Square-ish grid that holds every frame.
cols = math.ceil(math.sqrt(N))
rows = math.ceil(N / cols)

with Image.open(files[0]) as im:
    fw, fh = im.size

atlas_w = cols * fw
atlas_h = rows * fh
atlas = Image.new("L", (atlas_w, atlas_h), 0)

for i, fp in enumerate(files):
    gx = i % cols          # column, left -> right
    r = i // cols          # row, top -> bottom (frame 0 is at the top-left)
    with Image.open(fp) as im:
        atlas.paste(im, (gx * fw, r * fh))

atlas.save(OUT, optimize=True)

print("FRAMES=%d" % N)
print("FRAME_W=%d FRAME_H=%d" % (fw, fh))
print("GRID_X=%d GRID_Y=%d" % (cols, rows))
print("ATLAS_W=%d ATLAS_H=%d" % (atlas_w, atlas_h))
print("OUT=%s" % OUT)
print("SIZE_BYTES=%d" % os.path.getsize(OUT))
