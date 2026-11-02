"""Fin placement against the owner's photos, through the solved cameras: brightness peaks of the head fin crests
along lines y = const (views D, E) and of the cylinder fins along a vertical line on the near side (views A, E), on
the photo and on a head_dev.py render of the model; reports the mean distance (mm) from each photo peak to the
nearest render peak.  python3 fin_metrics.py RUN_DIR [RUN_DIR2 ...]  (each with r_<v>.png + log.txt)"""
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image
from scipy.signal import find_peaks

sys.path.insert(0, "/home/claude/head")
from proj import cam, proj  # noqa: E402

R = 21.2


def frame(d, v):
    m = re.search(r"view %s \[(\d+), (\d+), (\d+), (\d+)\]" % v, open(os.path.join(d, "log.txt")).read())
    if not m:
        return None
    box = [int(g) for g in m.groups()]
    c = cam(v)[0]
    w, h = c["size"]
    rd = Image.open(os.path.join(d, f"r_{v}.png")).convert("RGBA")
    bg = Image.new("RGBA", rd.size, (232, 226, 214, 255))
    bg.alpha_composite(rd)
    full = Image.new("L", (w, h), 228)
    full.paste(bg.convert("L"), (box[0], box[1]))
    return np.asarray(full).astype(float)


def sample(im, uv):
    out = []
    for p, q in uv:
        i, j = int(round(q)), int(round(p))
        out.append(im[i, j] if 0 <= i < im.shape[0] and 0 <= j < im.shape[1] else np.nan)
    return np.array(out)


def peaks_line(im, v, pts, coord, ok=None, dist=45, prom=6):
    b = sample(im, proj(v, pts))
    if ok is not None:
        b[~ok] = np.nan
    bs = np.convolve(np.nan_to_num(b, nan=np.nanmean(b)), np.ones(5) / 5, "same")
    pk, _ = find_peaks(bs, distance=dist, prominence=prom)
    return [float(coord[k]) for k in pk if ok is None or ok[k]]


def head_peaks(im, v):
    xs = np.arange(-18, 18.01, 0.05)
    out = []
    for y in (-12, -9, 9, 12):
        ok = np.hypot(xs, y) < R - 0.8
        out += peaks_line(im, v, [(x, y, 70.6) for x in xs], xs, ok)
    return np.array(sorted(out))


def cyl_peaks(im, v):
    c = cam(v)[0]
    az = math.atan2(c["C"][1], c["C"][0])
    zs = np.arange(34.0, 57.5, 0.05)
    out = []
    for da in (-0.25, 0.0, 0.25):
        a = az + da
        out += peaks_line(im, v, [(20.8 * math.cos(a), 20.8 * math.sin(a), z) for z in zs], zs, None, 25, 12)
    return np.array(sorted(out))


def score(a, b):
    if not len(a) or not len(b):
        return None
    return round(float(np.mean([np.min(np.abs(b - x)) for x in a])), 3)


res = {}
for d in sys.argv[1:]:
    r = {}
    for v, fn, key in (("D", head_peaks, "head_fins_D"), ("E", head_peaks, "head_fins_E"),
                       ("A", cyl_peaks, "cyl_fins_A"), ("E", cyl_peaks, "cyl_fins_E")):
        im = frame(d, v)
        if im is None:
            continue
        ph = np.asarray(Image.open(cam(v)[0]["image"]).convert("L")).astype(float)
        r[key] = score(fn(ph, v), fn(im, v))
    res[os.path.basename(d.rstrip("/"))] = r
print(json.dumps(res, indent=1))
