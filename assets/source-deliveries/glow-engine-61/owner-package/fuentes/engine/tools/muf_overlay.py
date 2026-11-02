"""Overlay the muffler (and the rest of the engine, faint) on the owner's photos through the solved cameras.

blender -b engine.blend -P muf_overlay.py -- --out sheet.png [--views A B D E Ac B2] [--params p.json]
                                              [--prefix MUF_] [--margin 60]
Left: photo with the red outline of the muffler silhouette (blue: rest of the engine). Right: 50 % blend.
"""
import json
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector
from PIL import Image, ImageDraw, ImageFilter

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(k, d=None):
    return a[a.index(k) + 1] if k in a else d


def arglist(k, d):
    if k not in a:
        return d
    out = []
    for t in a[a.index(k) + 1:]:
        if t.startswith("--"):
            break
        out.append(t)
    return out


out = arg("--out", "/home/claude/engine/muf/sheet.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
views = arglist("--views", ["A", "B", "D", "E", "Ac", "B2"])
prefix = arg("--prefix", "MUF_")
margin = int(arg("--margin", 60))
H_ROW = int(arg("--row", 520))
sc = bpy.context.scene
for o in bpy.data.objects:
    if o.name.startswith(("LD_", "PHOTO_", "FIT_", "CMP_", "ANL_", "CUT_")):
        o.hide_render = True
for c in bpy.data.collections:
    if c.name.startswith("LD_") or c.name == "E61_Analysis":
        c.hide_render = True
    if c.name.endswith("Muffler"):
        c.hide_render = False
r = sc.render
r.engine = "BLENDER_WORKBENCH"
r.film_transparent = True
sh = sc.display.shading
sh.light, sh.color_type = "STUDIO", "SINGLE"
sh.single_color = (0.8, 0.8, 0.8)
sh.show_cavity = True
sh.show_object_outline = False
r.image_settings.file_format = "PNG"
muf = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(prefix)]
rest = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(("ENG_", "CARB_")) and not o.hide_render]
tmpdir = os.path.join(os.path.dirname(out), "_tmp")
os.makedirs(tmpdir, exist_ok=True)
rows = []
for vn in views:
    cam = json.load(open(f"/home/claude/engine/cams/cam_{vn}.json"))
    R = np.array(cam["R"]); C = np.array(cam["C"]) * 0.001
    Mw = Matrix(((R[0, 0], -R[1, 0], -R[2, 0], C[0]), (R[0, 1], -R[1, 1], -R[2, 1], C[1]),
                 (R[0, 2], -R[1, 2], -R[2, 2], C[2]), (0, 0, 0, 1)))
    w, h = cam["size"]
    cd = bpy.data.cameras.get("MO_" + vn) or bpy.data.cameras.new("MO_" + vn)
    cd.sensor_fit, cd.sensor_width, cd.lens = "HORIZONTAL", 36.0, cam["f"] * 36.0 / w
    cd.shift_x = (w / 2 - cam["pp"][0]) / max(w, h)
    cd.shift_y = (cam["pp"][1] - h / 2) / max(w, h)
    cd.clip_start, cd.clip_end = 0.005, 20
    co = bpy.data.objects.get("MO_" + vn) or bpy.data.objects.new("MO_" + vn, cd)
    if co.name not in sc.collection.objects:
        sc.collection.objects.link(co)
    co.matrix_world = Mw
    sc.camera = co
    r.resolution_x, r.resolution_y, r.resolution_percentage = w, h, 100
    bpy.context.view_layer.update()
    # crop: projected muffler bounding box
    xs, ys = [], []
    dg = bpy.context.evaluated_depsgraph_get()
    for o in muf:
        for v in list(o.evaluated_get(dg).data.vertices)[::7]:
            p = world_to_camera_view(sc, co, o.matrix_world @ v.co)
            xs.append(p.x * w); ys.append((1 - p.y) * h)
    x0, x1 = max(0, int(min(xs)) - margin), min(w, int(max(xs)) + margin)
    y0, y1 = max(0, int(min(ys)) - margin), min(h, int(max(ys)) + margin)
    if arg(f"--box{vn}"):
        x0, y0, x1, y1 = (int(t) for t in arg(f"--box{vn}").split(","))
    masks = {}
    for tag, show in (("muf", set(muf)), ("all", set(muf) | set(rest))):
        for o in muf + rest:
            o.hide_render = o not in show
        r.filepath = os.path.join(tmpdir, f"{vn}_{tag}.png")
        bpy.ops.render.render(write_still=True)
        masks[tag] = Image.open(r.filepath).convert("RGBA")
    for o in muf + rest:
        o.hide_render = False
    ph = Image.open(cam["image"]).convert("RGB")
    box = (x0, y0, x1, y1)
    phc = ph.crop(box)
    mm = masks["muf"].crop(box)
    al = masks["all"].crop(box)
    a_m = mm.split()[3].point(lambda v: 255 if v > 30 else 0)
    a_a = al.split()[3].point(lambda v: 255 if v > 30 else 0)
    e_m = a_m.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(3))
    e_a = a_a.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(3))
    outl = phc.copy()
    outl.paste(Image.new("RGB", phc.size, (40, 90, 255)), (0, 0), e_a)
    outl.paste(Image.new("RGB", phc.size, (255, 0, 0)), (0, 0), e_m)
    white = Image.new("RGBA", phc.size, (255, 255, 255, 255))
    blend = Image.blend(phc, Image.alpha_composite(white, mm).convert("RGB"), 0.5)
    s = H_ROW / phc.height
    W = max(1, round(phc.width * s))
    row = Image.new("RGB", (W * 2 + 8, H_ROW), (255, 255, 255))
    row.paste(outl.resize((W, H_ROW)), (0, 0))
    row.paste(blend.resize((W, H_ROW)), (W + 8, 0))
    ImageDraw.Draw(row).text((6, 6), f"{vn} box {box}", fill=(0, 0, 255))
    rows.append(row)
    row.save(os.path.join(os.path.dirname(out), f"muf_{vn}.png"))
Wm = max(rr.width for rr in rows)
sheet = Image.new("RGB", (Wm, sum(rr.height + 8 for rr in rows)), (255, 255, 255))
yy = 0
for rr in rows:
    sheet.paste(rr, (0, yy))
    yy += rr.height + 8
sheet.save(out)
print("@@JSON@@" + json.dumps({"ok": True, "sheet": out, "views": views}))
