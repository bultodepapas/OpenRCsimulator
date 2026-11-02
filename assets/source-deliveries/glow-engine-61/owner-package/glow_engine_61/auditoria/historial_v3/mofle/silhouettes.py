"""Auto-extract muffler silhouette points (photo B, A, T) against the light background; writes muf/sil.json
and debug overlays muf/sil_{view}.png."""
import json

import numpy as np
from PIL import Image, ImageDraw

U = "/root/.claude/uploads/5aad6050-4747-5d68-bd16-c5cdce93a416/"
IMG = {"B": U + "da708d98-image.png", "A": U + "874a7277-image.png", "T": U + "86b5c288-image.png"}


def gray(vn):
    return np.asarray(Image.open(IMG[vn]).convert("RGB")).astype(float).mean(axis=2)


def first_drop(prof, start, step, drop=24.0, run=4):
    """index of the first sample (walking from start by step) darker than the local background by `drop`
    for `run` consecutive samples; background = median of the first 12 samples."""
    n = len(prof)
    idx = list(range(start, n if step > 0 else -1, step))
    bg = np.median(prof[idx[:12]])
    cnt = 0
    for k, i in enumerate(idx[12:]):
        bg = 0.97 * bg + 0.03 * prof[i] if prof[i] > bg - drop else bg
        if prof[i] < bg - drop:
            cnt += 1
            if cnt >= run:
                return i - step * (run - 1)
        else:
            cnt = 0
    return None


SPEC = {  # view: list of (kind, scan coordinate range, scan window)
    "B": [("top", range(80, 815, 12), (360, 700)), ("top", range(1290, 1405, 10), (360, 640)),
          ("bot", range(80, 600, 12), (900, 560)), ("right", range(470, 740, 15), (1490, 1250))],
    "A": [("top", range(1010, 1470, 12), (20, 260)), ("bot", range(1060, 1470, 12), (420, 150)),
          ("left", range(150, 300, 12), (520, 700))],
    "T": [("right", list(range(500, 585, 12)) + list(range(670, 1330, 12)), (1599, 1330)),
          ("left", range(800, 1300, 12), (1150, 1420)), ("top", range(1230, 1360, 12), (430, 560))],
}
out = {}
for vn, specs in SPEC.items():
    g = gray(vn)
    pts = []
    for kind, rng, (a, b) in specs:
        for c in rng:
            if kind in ("top", "bot"):
                prof = g[:, c]
                i = first_drop(prof, a, 1 if b > a else -1)
                if i is not None and min(a, b) <= i <= max(a, b):
                    pts.append((kind, c, int(i)))
            else:
                prof = g[c, :]
                i = first_drop(prof, a, 1 if b > a else -1)
                if i is not None and min(a, b) <= i <= max(a, b):
                    pts.append((kind, c, int(i)))
    out[vn] = pts
    im = Image.open(IMG[vn]).convert("RGB")
    d = ImageDraw.Draw(im)
    for kind, c, v in pts:
        x, y = (c, v) if kind in ("top", "bot") else (v, c)
        d.ellipse((x - 4, y - 4, x + 4, y + 4), outline=(255, 0, 0), width=2)
    im.save(f"/home/claude/engine/muf/sil_{vn}.png")
    print(vn, len(pts))
json.dump(out, open("/home/claude/engine/muf/sil.json", "w"))
