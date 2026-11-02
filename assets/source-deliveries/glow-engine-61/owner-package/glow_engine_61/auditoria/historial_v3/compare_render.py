"""Cycles renders through the solved photo cameras + side-by-side comparison sheets.

blender -b engine.blend -P compare_render.py -- --out DIR [--views Ac B2 E D] [--samples 48] [--crop carb|engine]
"""
import json
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix
from PIL import Image, ImageDraw

a = sys.argv[sys.argv.index("--") + 1:]


def arg(k, d=None):
    return a[a.index(k) + 1] if k in a else d


out = arg("--out", "/home/claude/engine/compare")
os.makedirs(out, exist_ok=True)
views = ["Ac", "B2", "E", "D"]
if "--views" in a:
    views = []
    for t in a[a.index("--views") + 1:]:
        if t.startswith("--"):
            break
        views.append(t)
CROPS = {"carb": {"Ac": (150, 300, 850, 1180), "B2": (900, 280, 1440, 1080), "E": (420, 860, 1600, 1600),
                  "D": (180, 0, 1260, 760)},
         "engine": {"Ac": (0, 0, 1600, 1600), "B2": (0, 0, 1600, 1600), "E": (0, 0, 1600, 1600),
                    "D": (0, 0, 1600, 1600), "A": (300, 30, 1536, 1050), "B": (0, 330, 1600, 1250)},
         "head": {"Ac": (600, 0, 1340, 520), "E": (430, 0, 1280, 720), "D": (620, 150, 1480, 1050),
                  "B2": (240, 0, 960, 420)}}
crop_kind = arg("--crop", "carb")
labels = {"Ac": "+X side (needle side)", "B2": "-X side (throttle arm)", "E": "top / front", "D": "top / rear",
          "A": "+X side, wide", "B": "-X side, wide"}
sc = bpy.context.scene
SHOWMUF = "--muffler" in a
for o in bpy.data.objects:
    if o.name.startswith("LD_Backdrop") or (o.name.startswith("MUF_") and not SHOWMUF):
        o.hide_render = True
    elif o.name.startswith("MUF_"):
        o.hide_render = False
for c in bpy.data.collections:
    if c.name.endswith("Muffler"):
        c.hide_render = not SHOWMUF
r = sc.render
r.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = int(arg("--samples", 48))
sc.cycles.use_denoising = True
r.film_transparent = True
sc.view_settings.exposure = float(arg("--exposure", -0.9))
sheets = []
for vn in views:
    cam = json.load(open(f"/home/claude/engine/cams/cam_{vn}.json"))
    R = np.array(cam["R"]); C = np.array(cam["C"]) * 0.001
    Mw = Matrix(((R[0, 0], -R[1, 0], -R[2, 0], C[0]), (R[0, 1], -R[1, 1], -R[2, 1], C[1]),
                 (R[0, 2], -R[1, 2], -R[2, 2], C[2]), (0, 0, 0, 1)))
    w, h = cam["size"]
    cd = bpy.data.cameras.new("PHOTO_" + vn)
    cd.sensor_fit, cd.sensor_width, cd.lens = "HORIZONTAL", 36.0, cam["f"] * 36.0 / w
    cd.shift_x = (w / 2 - cam["pp"][0]) / max(w, h)
    cd.shift_y = (cam["pp"][1] - h / 2) / max(w, h)
    cd.clip_start, cd.clip_end = 0.005, 20
    co = bpy.data.objects.new("PHOTO_" + vn, cd)
    sc.collection.objects.link(co)
    co.matrix_world = Mw
    sc.camera = co
    # photo-like soft light: big area light just above the camera, LD rig lights off, brighter world
    for lo in [o for o in bpy.data.objects if o.type == "LIGHT"]:
        lo.hide_render = True
    ld = bpy.data.lights.get("CMP_Soft") or bpy.data.lights.new("CMP_Soft", "AREA")
    dist_l = 0.75 * float(np.linalg.norm(C))
    ld.shape, ld.size, ld.energy = "DISK", 0.35, float(arg("--key", 1.2)) * (dist_l / 0.26) ** 2
    lo_ = bpy.data.objects.get("CMP_Soft") or bpy.data.objects.new("CMP_Soft", ld)
    if lo_.name not in sc.collection.objects:
        sc.collection.objects.link(lo_)
    lo_.hide_render = False
    from mathutils import Vector
    cpos = Vector(C)
    up = Vector((0, 0, 1))
    lo_.location = cpos * 0.75 + up * 0.12
    lo_.rotation_euler = (Vector((0, 0, 0.02)) - lo_.location).to_track_quat("-Z", "Y").to_euler()
    wbg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
    for l_ in list(wbg.inputs["Color"].links):  # light-tent look of the photos: uniform bright surround
        sc.world.node_tree.links.remove(l_)
    wbg.inputs["Color"].default_value = (0.8, 0.8, 0.8, 1.0)
    wbg.inputs["Strength"].default_value = float(arg("--world", 0.55))
    r.resolution_x, r.resolution_y, r.resolution_percentage = w, h, 100
    x0, y0, x1, y1 = CROPS[crop_kind][vn]
    r.use_border, r.use_crop_to_border = True, False
    r.border_min_x, r.border_max_x = x0 / w, x1 / w
    r.border_min_y, r.border_max_y = 1 - y1 / h, 1 - y0 / h
    fp = os.path.join(out, f"render_{vn}_{crop_kind}.png")
    r.filepath = fp
    r.image_settings.media_type = "IMAGE"
    r.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    ph = Image.open(cam["image"]).convert("RGB").crop((x0, y0, x1, y1))
    rn = Image.open(fp).convert("RGBA").crop((x0, y0, x1, y1))
    bg = Image.new("RGBA", rn.size, (236, 234, 230, 255))
    rn = Image.alpha_composite(bg, rn).convert("RGB")
    H = 640
    s = H / ph.height
    W = round(ph.width * s)
    row = Image.new("RGB", (W * 2 + 12, H + 34), (255, 255, 255))
    row.paste(ph.resize((W, H), Image.LANCZOS), (0, 34))
    row.paste(rn.resize((W, H), Image.LANCZOS), (W + 12, 34))
    d = ImageDraw.Draw(row)
    d.text((6, 10), f"Foto ({labels.get(vn, vn)})", fill=(30, 30, 30))
    d.text((W + 18, 10), "Blender, misma camara resuelta desde la foto", fill=(30, 30, 30))
    row.save(os.path.join(out, f"compare_{vn}_{crop_kind}.png"))
    sheets.append(os.path.join(out, f"compare_{vn}_{crop_kind}.png"))
print("@@JSON@@" + json.dumps({"ok": True, "sheets": sheets}))
