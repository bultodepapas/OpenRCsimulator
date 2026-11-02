"""Rebuild the carb with parameters and overlay it on every photo through the solved cameras.

blender -b engine.blend -P carb_iter.py -- --params p.json --out sheet.png [--views Ac B2 D E] [--mode random|material]
"""
import importlib
import json
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, "/home/claude/engine")
import build_engine as H  # noqa: E402
import carb_v4  # noqa: E402

importlib.reload(carb_v4)
a = sys.argv[sys.argv.index("--") + 1:]


def arg(k, d=None):
    return a[a.index(k) + 1] if k in a else d


params = json.load(open(arg("--params"))) if arg("--params") else {}
out = arg("--out", "/home/claude/engine/carbfit/sheet.png")
views = ["Ac", "B2", "D", "E"]
if "--views" in a:
    views = []
    for t in a[a.index("--views") + 1:]:
        if t.startswith("--"):
            break
        views.append(t)
mode = arg("--mode", "random")
BOX = arg("--box")  # "Ac:x0,y0,x1,y1;E:..." overrides the crop boxes
CROPS = {"Ac": (170, 300, 830, 1160), "B2": (920, 300, 1420, 1060), "D": (200, 0, 1250, 720),
         "E": (420, 860, 1600, 1600), "B": (1200, 640, 1520, 1000), "A": (440, 340, 820, 680)}

if BOX:
    for item in BOX.split(";"):
        k, v = item.split(":")
        CROPS[k] = tuple(int(float(t)) for t in v.split(","))
sc = bpy.context.scene
KEEP = "--keep" in a
for o in [o for o in bpy.data.objects if o.name.startswith("CARB_") and not KEEP]:
    bpy.data.objects.remove(o)
M = {}
for k, n in (("cast", "M_Alu_Cast"), ("polished", "M_Alu_Polished"), ("steel", "M_Steel"), ("black", "M_Black_Oxide"),
             ("plastic_black", "M_Plastic_Black"), ("nickel", "M_Nickel"), ("brass", "M_Brass")):
    M[k] = bpy.data.materials[n]
for k, n, c in (("brass_dull", "M_Brass_Olive", (0.42, 0.40, 0.26)), ("rust", "M_Rust", (0.18, 0.08, 0.04))):
    m = bpy.data.materials.get(n) or bpy.data.materials.new(n)
    m.diffuse_color = (*c, 1)
    M[k] = m
col = bpy.data.collections.get("E61_Carburetor")
if KEEP:
    parts = [o for o in bpy.data.objects if o.name.startswith("CARB_")]
else:
    parts = carb_v4.build(col, M, H, params)
    root = bpy.data.objects.get("Glow_Engine_61")
    for p in parts:
        p.parent = root
SHOWMUF = "--muffler" in a
for o in bpy.data.objects:
    if o.name.startswith("LD_") or (o.name.startswith("MUF_") and not SHOWMUF):
        o.hide_render = True
    elif o.name.startswith("MUF_"):
        o.hide_render = False
for c in bpy.data.collections:
    if c.name.startswith("LD_") or (c.name.endswith("Muffler") and not SHOWMUF):
        c.hide_render = True
    elif c.name.endswith("Muffler"):
        c.hide_render = False
bpy.context.view_layer.update()

r = sc.render
r.engine = "BLENDER_WORKBENCH"
r.film_transparent = True
sh = sc.display.shading
sh.light, sh.show_cavity = "STUDIO", True
sh.color_type = "RANDOM" if mode == "random" else "MATERIAL"
sh.show_object_outline = True
rows = []
for vn in views:
    cam = json.load(open(f"/home/claude/engine/cams/cam_{vn}.json"))
    R = np.array(cam["R"]); C = np.array(cam["C"]) * 0.001
    Mw = Matrix(((R[0, 0], -R[1, 0], -R[2, 0], C[0]), (R[0, 1], -R[1, 1], -R[2, 1], C[1]),
                 (R[0, 2], -R[1, 2], -R[2, 2], C[2]), (0, 0, 0, 1)))
    cd = bpy.data.cameras.get("FIT_" + vn) or bpy.data.cameras.new("FIT_" + vn)
    w, h = cam["size"]
    cd.sensor_fit, cd.sensor_width, cd.lens = "HORIZONTAL", 36.0, cam["f"] * 36.0 / w
    cd.shift_x = (w / 2 - cam["pp"][0]) / max(w, h)
    cd.shift_y = (cam["pp"][1] - h / 2) / max(w, h)
    cd.clip_start, cd.clip_end = 0.005, 20
    co = bpy.data.objects.get("FIT_" + vn) or bpy.data.objects.new("FIT_" + vn, cd)
    if co.name not in sc.collection.objects:
        sc.collection.objects.link(co)
    co.matrix_world = Mw
    sc.camera = co
    r.resolution_x, r.resolution_y, r.resolution_percentage = w, h, 100
    x0, y0, x1, y1 = CROPS[vn]
    r.use_border, r.use_crop_to_border = True, False
    r.border_min_x, r.border_max_x = x0 / w, x1 / w
    r.border_min_y, r.border_max_y = 1 - y1 / h, 1 - y0 / h
    fp = f"/home/claude/engine/carbfit/r_{vn}.png"
    r.filepath = fp
    bpy.ops.render.render(write_still=True)
    ph = Image.open(cam["image"]).convert("RGB").crop((x0, y0, x1, y1))
    rn = Image.open(fp).convert("RGBA").crop((x0, y0, x1, y1))
    white = Image.new("RGBA", rn.size, (255, 255, 255, 255))
    blend = Image.blend(ph, Image.alpha_composite(white, rn).convert("RGB"), 0.5)
    alpha = rn.split()[3].point(lambda v: 255 if v > 20 else 0)
    edge = alpha.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(3))
    outl = ph.copy()
    outl.paste(Image.new("RGB", rn.size, (255, 0, 0)), (0, 0), edge)
    s = 520 / rn.height
    row = Image.new("RGB", (round(rn.width * s) * 2 + 8, 520), (255, 255, 255))
    row.paste(outl.resize((round(rn.width * s), 520)), (0, 0))
    row.paste(blend.resize((round(rn.width * s), 520)), (round(rn.width * s) + 8, 0))
    ImageDraw.Draw(row).text((6, 6), vn, fill=(0, 0, 255))
    rows.append(row)
W = max(rr.width for rr in rows)
sheet = Image.new("RGB", (W, sum(rr.height + 8 for rr in rows)), (255, 255, 255))
yy = 0
for rr in rows:
    sheet.paste(rr, (0, yy)); yy += rr.height + 8
sheet.save(out)
if arg("--save"):
    bpy.ops.wm.save_as_mainfile(filepath=arg("--save"))
print("@@JSON@@" + json.dumps({"ok": True, "sheet": out, "parts": len(parts)}))
