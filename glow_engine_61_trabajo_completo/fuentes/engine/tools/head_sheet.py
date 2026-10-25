"""Photo | before | after sheets of the head region, from two head_dev.py runs (same solved cameras, same crop).
python3 head_sheet.py BEFORE_DIR AFTER_DIR OUT_DIR V1,V2,...   (each dir holds r_<v>.png + the run's log.txt)"""
import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

bd, ad, od, views = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(",")
os.makedirs(od, exist_ok=True)
try:
    FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
except OSError:
    FONT = ImageFont.load_default()
NAMES = {"E": "E (arriba-frente)", "Ac": "Ac (lado +X)", "B2": "B2 (lado -X, bajo)", "D": "D (arriba-atras)",
         "A": "A (lateral +X)", "T": "T (arriba)"}


def box_of(d, v):
    m = re.search(r"view %s \[(\d+), (\d+), (\d+), (\d+)\]" % v, open(os.path.join(d, "log.txt")).read())
    return [int(g) for g in m.groups()]


def flat(p, size):
    im = Image.open(p).convert("RGBA")
    bg = Image.new("RGBA", im.size, (232, 226, 214, 255))
    bg.alpha_composite(im)
    return bg.convert("RGB").resize(size, Image.LANCZOS)


for v in views:
    box = box_of(ad, v)
    cam = json.load(open(f"/home/claude/engine/cams/cam_{v}.json"))
    ph = Image.open(cam["image"]).convert("RGB").crop(box)
    w, h = ph.size
    tiles = [("Foto " + NAMES.get(v, v), ph), ("Antes", flat(os.path.join(bd, f"r_{v}.png"), (w, h))),
             ("Despues", flat(os.path.join(ad, f"r_{v}.png"), (w, h)))]
    g = Image.new("RGB", (3 * w + 24, h + 46), (255, 255, 255))
    dr = ImageDraw.Draw(g)
    for k, (t, im) in enumerate(tiles):
        x = k * (w + 12)
        g.paste(im, (x, 46))
        dr.text((x + 6, 8), t, fill=(20, 20, 20), font=FONT)
    g.save(os.path.join(od, f"culata_{v}_antes_despues.jpg"), quality=90)
    print("sheet", v, g.size)
