"""Workbench close-ups of the muffler (modeling check).

blender -b engine.blend -P muf_views.py -- --out DIR [--all]   (--all keeps the engine visible)
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = a[a.index("--out") + 1] if "--out" in a else "/home/claude/engine/muf/views"
os.makedirs(out, exist_ok=True)
sc = bpy.context.scene
r = sc.render
r.engine = "BLENDER_WORKBENCH"
r.resolution_x, r.resolution_y = 1400, 900
sh = sc.display.shading
sh.light, sh.color_type = "STUDIO", "SINGLE"
sh.single_color = (0.74, 0.74, 0.75)
sh.show_cavity, sh.cavity_type = True, "BOTH"
sh.show_object_outline = False
sh.background_type, sh.background_color = "VIEWPORT", (0.95, 0.95, 0.96)
sc.view_settings.view_transform = "Standard"
keep_all = "--all" in a
for o in bpy.data.objects:
    if o.type == "MESH":
        o.hide_render = not (o.name.startswith("MUF_") or (keep_all and o.name.startswith(("ENG_", "CARB_"))))
        if o.name.startswith(("ANL_", "CUT_", "LD_", "PHOTO_")):
            o.hide_render = True
for o in bpy.data.objects:   # crisp cast edges as in the lookdev stage
    if o.type == "MESH" and o.name.startswith("MUF_") and o.data.users == 1:
        o.data.set_sharp_from_angle(angle=math.radians(30))
for m in [m for o in bpy.data.objects for m in getattr(o, "modifiers", []) if m.type == "BOOLEAN" and m.name.startswith("CUT")]:
    m.show_render = False
cd = bpy.data.cameras.new("MV_Cam")
cd.lens, cd.clip_start, cd.clip_end = 70, 0.005, 5
cam = bpy.data.objects.new("MV_Cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
ONLY = a[a.index("--only") + 1].split(",") if "--only" in a else None
SHOTS = {  # name: (target mm, azimuth deg (0 = from -Y, 90 = from +X), elevation, distance m)
    "top_rear": ((-55, 30, 50), 160, 50, 0.30),
    "side_mx": ((-70, 35, 45), -90, 12, 0.36),
    "panel": ((-62, 25, 66), -120, 55, 0.16),
    "arm_front": ((-40, 0, 38), 15, 35, 0.15),
    "arm_rear": ((-40, 10, 38), 160, 35, 0.15),
    "nipple": ((-55, 30, 62), 120, 40, 0.10),
    "tail": ((-80, 100, 50), 200, 15, 0.12),
    "below": ((-55, 10, 30), -60, -35, 0.22),
    "nipple_close": ((-56, 28, 62), 75, 35, 0.06),
    "flange_mx": ((-30, 2, 33), -90, 5, 0.12),
}
if ONLY:
    SHOTS = {k: v for k, v in SHOTS.items() if k in ONLY}
files = []
for name, (tgt, az, el, dist) in SHOTS.items():
    c = Vector(tgt) * 0.001
    A, E = math.radians(az), math.radians(el)
    d = Vector((math.sin(A) * math.cos(E), -math.cos(A) * math.cos(E), math.sin(E)))
    cam.location = c + d * dist
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    fp = os.path.join(out, f"{name}.png")
    r.filepath = fp
    bpy.ops.render.render(write_still=True)
    files.append(fp)
print("@@JSON@@" + json.dumps({"ok": True, "files": files}))
