"""Per-zone colour of photo vs render (CIE Lab means over the zone's visible pixels, eroded to avoid edges).
python3 color_check.py AUDIT_DIR [views...] -> prints table + writes AUDIT_DIR/color.json"""
import json
import sys

import cv2
import numpy as np
from PIL import Image

D = sys.argv[1]
views = sys.argv[2:] or ["Ac", "A", "B", "B2", "D", "E", "T"]
ZN = ["head", "cyl", "case", "drive", "carb", "muf"]
out = {}
for v in views:
    cam = json.load(open(f"/home/claude/engine/cams/cam_{v}.json"))
    w, h = cam["size"]
    ids = np.asarray(Image.open(f"{D}/ids_{v}.png").convert("RGBA")).astype(int)
    zid = np.full((h, w), 255, np.uint8)
    for z in range(6):
        zid[(np.abs(ids[..., 0] - 36 * (z + 1)) <= 8) & (ids[..., 3] > 200)] = z
    ph = np.asarray(Image.open(cam["image"]).convert("RGB"))
    rn = Image.open(f"{D}/render_{v}.png").convert("RGBA").resize((w, h), Image.LANCZOS)
    rn = np.asarray(Image.alpha_composite(Image.new("RGBA", (w, h), (236, 234, 230, 255)), rn).convert("RGB"))
    lab_p = cv2.cvtColor(ph, cv2.COLOR_RGB2LAB).astype(float)
    lab_r = cv2.cvtColor(rn, cv2.COLOR_RGB2LAB).astype(float)
    res = {}
    for z, name in enumerate(ZN):
        m = cv2.erode((zid == z).astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
        if m.sum() < 2000:
            continue
        p = lab_p[m].mean(0); r = lab_r[m].mean(0)
        # OpenCV 8-bit Lab: L*255/100, a+128, b+128
        P = np.array([p[0] * 100 / 255, p[1] - 128, p[2] - 128]); Rr = np.array([r[0] * 100 / 255, r[1] - 128, r[2] - 128])
        sd_p = lab_p[m][:, 0].std() * 100 / 255; sd_r = lab_r[m][:, 0].std() * 100 / 255
        res[name] = {"photo_Lab": P.round(1).tolist(), "render_Lab": Rr.round(1).tolist(), "dE": round(float(np.linalg.norm(P - Rr)), 1),
                     "dL": round(float(Rr[0] - P[0]), 1), "texture_sd_photo": round(float(sd_p), 1), "texture_sd_render": round(float(sd_r), 1)}
    out[v] = res
json.dump(out, open(f"{D}/color.json", "w"), indent=1)
for z in ZN:
    rows = [(v, out[v][z]) for v in out if z in out[v]]
    if not rows:
        continue
    dE = np.mean([r["dE"] for _, r in rows]); dL = np.mean([r["dL"] for _, r in rows])
    pa = np.mean([r["photo_Lab"] for _, r in rows], 0); ra = np.mean([r["render_Lab"] for _, r in rows], 0)
    sp = np.mean([r["texture_sd_photo"] for _, r in rows]); sr = np.mean([r["texture_sd_render"] for _, r in rows])
    print(f"{z:6s} dE {dE:5.1f} dL {dL:+5.1f}  photo Lab {pa.round(1)}  render Lab {ra.round(1)}  texture sd photo {sp:4.1f} render {sr:4.1f}")
