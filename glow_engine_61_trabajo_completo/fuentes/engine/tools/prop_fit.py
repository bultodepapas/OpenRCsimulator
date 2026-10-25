"""Per-photo prop clock angle: the owner turned the crank between photos, so the blade angle differs per view.
Renders the visible-blade mask (flat ID pass, occlusion by the engine included) for a sweep of crank angles and
keeps the one with the best IoU against the photo's black-blade pixels; writes "prop_deg" into cams/cam_V.json.

blender -b f.blend -P prop_fit.py -- --views T B [--range -90 90 --step 3] [--pct 25]"""
import json
import os
import sys

import bpy
import cv2
import numpy as np
from mathutils import Matrix
from PIL import Image

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def lst(k, d):
    if k not in a:
        return d
    i = a.index(k) + 1
    out = []
    while i < len(a) and not a[i].startswith("--"):
        out.append(a[i])
        i += 1
    return out


VIEWS = lst("--views", ["T", "B"])
RNG = [float(x) for x in lst("--range", ["-90", "90"])]
STEP = float(lst("--step", ["3"])[0])
PCT = int(lst("--pct", ["25"])[0])
sc = bpy.context.scene
r = sc.render
for c in bpy.data.collections:
    if c.name.endswith("Prop") or c.name.endswith("Muffler"):
        c.hide_render = False
    if c.name.endswith("Analysis"):
        c.hide_render = True
for o in bpy.data.objects:
    if o.name.startswith(("LD_", "PHOTO_", "ANL_", "CUT_", "CMP_", "FIT_", "MO_", "PV_", "MV_")):
        o.hide_render = True
    if o.type == "MESH":
        o.color = (1, 0, 0, 1) if o.name == "ENG_Prop_Blades" else (1, 1, 1, 1)
r.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light, sh.color_type = "FLAT", "OBJECT"
sh.show_cavity = sh.show_shadows = sh.show_object_outline = False
sc.display.render_aa = "OFF"
r.film_transparent = True
r.resolution_percentage = PCT
sc.view_settings.view_transform = "Standard"
root = bpy.data.objects["Glow_Engine_61"]
tmp = "/tmp/claude-0/prop_fit.png"
res = {}
for vn in VIEWS:
    fp = f"/home/claude/engine/cams/cam_{vn}.json"
    cam = json.load(open(fp))
    R = np.array(cam["R"]); C = np.array(cam["C"]) * 0.001
    w, h = cam["size"]
    cd = bpy.data.cameras.new("PF_" + vn)
    cd.sensor_fit, cd.sensor_width, cd.lens = "HORIZONTAL", 36.0, cam["f"] * 36.0 / w
    cd.shift_x = (w / 2 - cam["pp"][0]) / max(w, h)
    cd.shift_y = (cam["pp"][1] - h / 2) / max(w, h)
    cd.clip_start, cd.clip_end = 0.005, 20
    co = bpy.data.objects.new("PF_" + vn, cd)
    sc.collection.objects.link(co)
    co.matrix_world = Matrix(((R[0, 0], -R[1, 0], -R[2, 0], C[0]), (R[0, 1], -R[1, 1], -R[2, 1], C[1]),
                              (R[0, 2], -R[1, 2], -R[2, 2], C[2]), (0, 0, 0, 1)))
    sc.camera = co
    r.resolution_x, r.resolution_y = w, h
    ww, hh = w * PCT // 100, h * PCT // 100
    ph = np.asarray(Image.open(cam["image"]).convert("RGB").resize((ww, hh), Image.LANCZOS)).astype(int)
    hsv = cv2.cvtColor(ph.astype(np.uint8), cv2.COLOR_RGB2HSV)
    dark = (hsv[..., 2] < int(lst("--v", ["95"])[0])) & (hsv[..., 1] < 110)
    dark = cv2.morphologyEx(dark.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8)) > 0
    best = None
    sweep = []
    deg = RNG[0]
    while deg <= RNG[1] + 1e-6:
        root["crank_deg"] = float(deg)
        root.update_tag()
        bpy.context.view_layer.update()
        r.filepath = tmp
        bpy.ops.render.render(write_still=True)
        im = np.asarray(Image.open(tmp).convert("RGBA")).astype(int)
        blade = (im[..., 0] > 200) & (im[..., 1] < 60) & (im[..., 3] > 200)
        eng = (im[..., 3] > 200) & ~blade
        # only score where the photo can show a blade: outside the rest of the engine silhouette
        d = dark & ~eng
        iou = float((blade & d).sum()) / max(1.0, float((blade | d).sum()))
        sweep.append((deg, round(iou, 4)))
        if "--debug" in a and abs(deg - float(lst("--debug", ["0"])[0])) < 1e-6:
            dbg = np.zeros((hh, ww, 3), np.uint8)
            dbg[..., 0] = blade * 255
            dbg[..., 1] = d * 255
            dbg[..., 2] = eng * 120
            Image.fromarray(dbg).save(f"/tmp/claude-0/prop_dbg_{vn}.png")
        if best is None or iou > best[1]:
            best = (deg, iou)
        deg += STEP
    cam["prop_deg"] = best[0]
    json.dump(cam, open(fp, "w"), indent=1)
    res[vn] = {"prop_deg": best[0], "iou": round(best[1], 3), "sweep": sweep}
root["crank_deg"] = 0.0
print("@@JSON@@" + json.dumps(res))
