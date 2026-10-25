"""Add the solved photo cameras to a .blend with the user's photos as (packed) camera backgrounds.
blender -b in.blend -P add_photo_cams.py -- --save out.blend"""
import json
import sys

import bpy
import numpy as np
from mathutils import Matrix

a = sys.argv[sys.argv.index("--") + 1:]
out = a[a.index("--save") + 1]
names = {"Ac": "Foto lado aguja (+X)", "B2": "Foto lado palanca (-X)", "E": "Foto arriba-frente",
         "D": "Foto arriba-atras", "A": "Foto lateral +X (amplia)", "B": "Foto lateral -X (amplia)",
         "T": "Foto arriba-atras completa (mofle)"}
col = bpy.data.collections.get("Photo_Cameras") or bpy.data.collections.new("Photo_Cameras")
if col.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(col)
made = []
for vn, label in names.items():
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
    img = bpy.data.images.load(cam["image"], check_existing=True)
    img.name = f"REF_{vn}"
    img.pack()
    cd.show_background_images = True
    bg = cd.background_images.new()
    bg.image, bg.alpha, bg.display_depth, bg.frame_method = img, 0.6, "FRONT", "FIT"
    co = bpy.data.objects.new("PHOTO_" + vn, cd)
    co["label"] = label
    co["photo_size_px"] = [w, h]
    co["prop_deg"] = float(cam.get("prop_deg", 0.0))   # crank_deg that puts the prop as in this photo
    co.matrix_world = Mw
    col.objects.link(co)
    made.append(co.name)
bpy.ops.wm.save_as_mainfile(filepath=out)
print("@@JSON@@" + json.dumps({"ok": True, "cameras": made, "saved": out}))
