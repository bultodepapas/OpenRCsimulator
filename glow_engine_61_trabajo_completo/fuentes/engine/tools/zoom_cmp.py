"""Zoomed comparison of one region: photo | model render | model outlines on the photo (same solved camera).
python3 zoom_cmp.py AUDIT_DIR VIEW x0 y0 x1 y1 OUT.png [--scale 1.0] [--grid 50]
(coordinates in photo pixels; AUDIT_DIR holds render_V.png and ids_V.png from audit_views.py)"""
import json
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

D, V = sys.argv[1], sys.argv[2]
x0, y0, x1, y1 = map(int, sys.argv[3:7])
OUT = sys.argv[7]
a = sys.argv[8:]
SCALE = float(a[a.index("--scale") + 1]) if "--scale" in a else 1.0
GRID = int(a[a.index("--grid") + 1]) if "--grid" in a else 50
cam = json.load(open(f"/home/claude/engine/cams/cam_{V}.json"))
w, h = cam["size"]
ph = Image.open(cam["image"]).convert("RGB")
rn = Image.open(f"{D}/render_{V}.png").convert("RGBA").resize((w, h), Image.LANCZOS)
rn = Image.alpha_composite(Image.new("RGBA", (w, h), (236, 234, 230, 255)), rn).convert("RGB")
ids = np.asarray(Image.open(f"{D}/ids_{V}.png").convert("RGBA")).astype(int)
code = ids[..., 0] * (ids[..., 3] > 200)
pad = np.pad(code, 1, constant_values=-1)
bd = np.zeros((h, w), bool)
for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
    bd |= pad[dy:dy + h, dx:dx + w] != code
ov = np.asarray(ph).copy()
ov[cv2.dilate(bd.astype(np.uint8), np.ones((2, 2), np.uint8)) > 0] = (255, 0, 200)
box = (x0, y0, x1, y1)
tiles = [ph.crop(box), rn.crop(box), Image.fromarray(ov).crop(box)]
tw, th = int((x1 - x0) * SCALE), int((y1 - y0) * SCALE)
sheet = Image.new("RGB", (tw * 3 + 20, th + 30), "white")
try:
    F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
except Exception:
    F = ImageFont.load_default()
for k, t in enumerate(tiles):
    t = t.resize((tw, th), Image.LANCZOS)
    dr = ImageDraw.Draw(t)
    for gx in range((x0 // GRID + 1) * GRID, x1, GRID):
        X = int((gx - x0) * SCALE)
        dr.line((X, 0, X, th), fill=(0, 220, 255), width=1)
        dr.text((X + 2, 2), str(gx), fill=(0, 120, 200), font=F)
    for gy in range((y0 // GRID + 1) * GRID, y1, GRID):
        Y = int((gy - y0) * SCALE)
        dr.line((0, Y, tw, Y), fill=(0, 220, 255), width=1)
        dr.text((2, Y + 2), str(gy), fill=(0, 120, 200), font=F)
    sheet.paste(t, (k * (tw + 10), 30))
ImageDraw.Draw(sheet).text((4, 6), f"{V}  foto | modelo | contornos  ({x0},{y0})-({x1},{y1})", fill=(0, 0, 0), font=F)
sheet.save(OUT)
