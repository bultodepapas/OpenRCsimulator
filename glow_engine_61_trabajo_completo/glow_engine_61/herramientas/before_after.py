"""Photo | model before | model after, same solved camera, one region (photo pixels).
python3 before_after.py VIEW DIR_BEFORE DIR_AFTER x0 y0 x1 y1 OUT.png [--scale 1.0] [--title '...']"""
import json
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

V, DB, DA = sys.argv[1:4]
x0, y0, x1, y1 = map(int, sys.argv[4:8])
OUT = sys.argv[8]
a = sys.argv[9:]
S = float(a[a.index("--scale") + 1]) if "--scale" in a else 1.0
TITLE = a[a.index("--title") + 1] if "--title" in a else V
cam = json.load(open(f"/home/claude/engine/cams/cam_{V}.json"))
w, h = cam["size"]
ph = Image.open(cam["image"]).convert("RGB")


def model(D):
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
    return rn, Image.fromarray(ov)


rb, ob = model(DB)
ra, oa = model(DA)
box = (x0, y0, x1, y1)
tiles = [("foto", ph), ("antes", rb), ("despues", ra), ("contornos antes", ob), ("contornos despues", oa)]
tw, th = int((x1 - x0) * S), int((y1 - y0) * S)
try:
    F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
except Exception:
    F = ImageFont.load_default()
sheet = Image.new("RGB", (tw * len(tiles) + 8 * (len(tiles) - 1), th + 58), "white")
dr = ImageDraw.Draw(sheet)
dr.text((6, 6), TITLE, fill=(0, 0, 0), font=F)
for k, (lab, im) in enumerate(tiles):
    sheet.paste(im.crop(box).resize((tw, th), Image.LANCZOS), (k * (tw + 8), 50))
    dr.text((k * (tw + 8) + 4, 30), lab, fill=(60, 60, 60), font=F)
sheet.save(OUT)
