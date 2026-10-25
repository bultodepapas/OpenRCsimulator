"""Workbench close-ups of chosen details (modeling check). blender -b f.blend -P detail_views.py -- --out DIR [--prop]"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = a[a.index("--out") + 1]
os.makedirs(out, exist_ok=True)
sc = bpy.context.scene
r = sc.render
r.engine = "BLENDER_WORKBENCH"
r.resolution_x, r.resolution_y = 1000, 700
sh = sc.display.shading
sh.light, sh.color_type = "STUDIO", "MATERIAL"
sh.show_cavity, sh.cavity_type = True, "BOTH"
sh.background_type, sh.background_color = "VIEWPORT", (0.95, 0.95, 0.96)
sc.view_settings.view_transform = "Standard"
for c in bpy.data.collections:
    if c.name == "E61_Prop":
        c.hide_render = "--prop" not in a
    if c.name in ("E61_Analysis", "LD_Lookdev"):
        c.hide_render = True
for o in bpy.data.objects:
    if o.name.startswith(("ANL_", "LD_", "PHOTO_", "CUT_")):
        o.hide_render = True
    if o.type == "MESH" and o.data.users == 1:
        o.data.set_sharp_from_angle(angle=math.radians(35))
cd = bpy.data.cameras.new("DV")
cd.lens, cd.clip_start, cd.clip_end = 70, 0.005, 10
cam = bpy.data.objects.new("DV", cd)
sc.collection.objects.link(cam)
sc.camera = cam
SHOTS = {
    "plaque_se": ((29.5, 1, -3), 90, 5, 0.09),
    "boss_61": ((-17.3, 0, 19), -90, 5, 0.06),
    "arm_744": ((-26, 1, 43), 30, 70, 0.07),
    "fins_front": ((0, -20, 45), 10, 10, 0.12),
    "head_top": ((0, 0, 70), 0, 70, 0.16),
    "backplate": ((0, 26, -2), 180, 20, 0.14),
    "carb_throat": ((0, -37.6, 34), 0, 65, 0.09),
    "front_wide": ((0, -40, 20), 25, 15, 0.45),
}
if "--prop" in a:
    SHOTS = {"prop_front": ((0, -80, 0), 15, 15, 0.7), "prop_side": ((0, -70, 10), 80, 10, 0.5),
             "spinner": ((0, -80, 0), 40, 20, 0.25)}
files = []
for name, (tgt, az, el, dist) in SHOTS.items():
    c = Vector(tgt) * 0.001
    A, E = math.radians(az), math.radians(el)
    d = Vector((math.sin(A) * math.cos(E), -math.cos(A) * math.cos(E), math.sin(E)))
    cam.location = c + d * dist
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    r.filepath = os.path.join(out, f"{name}.png")
    bpy.ops.render.render(write_still=True)
    files.append(r.filepath)
print("@@JSON@@" + json.dumps({"ok": True, "files": files}))
