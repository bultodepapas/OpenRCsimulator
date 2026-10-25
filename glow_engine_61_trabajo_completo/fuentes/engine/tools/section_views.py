"""Quick Workbench section views through the cutaway modes (modeling check, not beauty renders).

blender -b engine.blend -P section_views.py -- --out DIR [--angles 0 90 180] [--modes 1 2] [--muffler]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

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


out = arg("--out", "/home/claude/engine/sections")
os.makedirs(out, exist_ok=True)
angles = [float(v) for v in arglist("--angles", ["0", "90", "180"])]
modes = [int(v) for v in arglist("--modes", ["1", "2"])]
sc = bpy.context.scene
root = bpy.data.objects["Glow_Engine_61"]
for o in bpy.data.objects:
    if o.name.startswith(("LD_", "PHOTO_", "FIT_", "CMP_")):
        o.hide_render = True
    if o.name.startswith("MUF_") and "--muffler" not in a:
        o.hide_render = True
for c in bpy.data.collections:
    if c.name.startswith("LD_") or c.name == "E61_Analysis":
        c.hide_render = True
r = sc.render
r.engine = "BLENDER_WORKBENCH"
r.resolution_x, r.resolution_y = int(arg("--w", 1400)), int(arg("--h", 1100))
r.film_transparent = False
sh = sc.display.shading
sh.light, sh.color_type = "STUDIO", "MATERIAL"
sh.show_cavity, sh.cavity_type = True, "BOTH"
sh.show_object_outline, sh.object_outline_color = True, (0.05, 0.05, 0.05)
sh.background_type = "VIEWPORT"
sh.background_color = (0.93, 0.93, 0.92)
sc.view_settings.view_transform = "Standard"
VIEWS = {1: (Vector((1, 0, 0)), Vector((0, 0, 1))), 2: (Vector((0, 1, 0)), Vector((0, 0, 1)))}
cd = bpy.data.cameras.get("SEC_Cam") or bpy.data.cameras.new("SEC_Cam")
cd.type, cd.ortho_scale = "ORTHO", float(arg("--scale", 0.17))
cam = bpy.data.objects.get("SEC_Cam") or bpy.data.objects.new("SEC_Cam", cd)
if cam.name not in sc.collection.objects:
    sc.collection.objects.link(cam)
sc.camera = cam
files = []
for m in modes:
    d, up = VIEWS[m]
    cen = Vector((0.0, -0.012, 0.022)) if m == 1 else Vector((0.0, 0.0, 0.022))
    cam.location = cen + d * 0.5
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cd.clip_start, cd.clip_end = 0.01, 2.0
    root["cutaway"] = m
    for th in angles:
        root["crank_deg"] = th
        root.update_tag()
        bpy.context.view_layer.update()
        fp = os.path.join(out, f"section_m{m}_{int(th):03d}.png")
        r.filepath = fp
        bpy.ops.render.render(write_still=True)
        files.append(fp)
root["cutaway"] = 0
root["crank_deg"] = 0.0
print("@@JSON@@" + __import__("json").dumps({"ok": True, "files": files}))
