"""Workbench close-ups of individual internal parts (modeling check against reference photos).

blender -b engine.blend -P part_views.py -- --out DIR
"""
import math
import os
import sys

import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = a[a.index("--out") + 1] if "--out" in a else "/home/claude/engine/parts"
os.makedirs(out, exist_ok=True)
sc = bpy.context.scene
root = bpy.data.objects["Glow_Engine_61"]
r = sc.render
r.engine = "BLENDER_WORKBENCH"
r.resolution_x, r.resolution_y = 1000, 800
sh = sc.display.shading
sh.light, sh.color_type = "STUDIO", "SINGLE"
sh.single_color = (0.72, 0.73, 0.74)
sh.show_cavity, sh.cavity_type = True, "BOTH"
sh.show_object_outline = True
sh.background_type, sh.background_color = "VIEWPORT", (0.93, 0.85, 0.86)
sc.view_settings.view_transform = "Standard"
cd = bpy.data.cameras.new("PV_Cam")
cd.lens, cd.clip_start, cd.clip_end = 85, 0.005, 5
cam = bpy.data.objects.new("PV_Cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
SHOTS = {
    "crankshaft": (["ENG_Crankshaft", "ENG_Crank_Counterweight", "ENG_Bearing_Rear_Inner", "ENG_Bearing_Rear_Outer",
                    "ENG_Bearing_Rear_Balls", "ENG_Bearing_Rear_Cage", "ENG_Crankshaft_Thread", "ENG_Woodruff_Key"],
                   0.0, (70, 35), 0.20, 272.5),
    "piston_rod": (["ENG_Piston", "ENG_Piston_Ring", "ENG_Wrist_Pin", "ENG_Circlip_1", "ENG_Circlip_2", "ENG_Rod",
                    "ENG_Rod_Bush_Small", "ENG_Rod_Bush_Big"], 0.0, (35, 15), 0.19, 90.0),
    "piston_boost_side": (["ENG_Piston", "ENG_Piston_Ring", "ENG_Wrist_Pin", "ENG_Circlip_1", "ENG_Circlip_2", "ENG_Rod",
                           "ENG_Rod_Bush_Small", "ENG_Rod_Bush_Big"], 0.0, (95, 10), 0.13, 0.0),
    "liner": (["ENG_Liner"], 0.0, (240, 25), 0.13, 0.0),
    "crank_window": (["ENG_Crankshaft", "ENG_Bearing_Rear_Inner", "ENG_Bearing_Rear_Outer", "ENG_Bearing_Rear_Balls",
                      "ENG_Bearing_Rear_Cage"], 0.0, (60, 40), 0.075, 272.5),
    "liner_boost": (["ENG_Liner"], 0.0, (75, 15), 0.13, 0.0),
    "hub_front": (["ENG_Drive_Hub", "ENG_Woodruff_Key", "ENG_Crankshaft_Thread", "ENG_Crankshaft"], 0.0, (0, 20), 0.15, 0.0),
}
files = []
for name, (objs, _, (az, el), dist, crank) in SHOTS.items():
    root["crank_deg"] = crank
    root.update_tag()
    bpy.context.view_layer.update()
    vis = set(objs)
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o.name not in vis
    pts = [o.matrix_world @ Vector(c) for n in objs if n in bpy.data.objects for o in [bpy.data.objects[n]] for c in o.bound_box]
    if name == "crank_window":
        pts = [Vector((0.0, -0.0376, bpy.data.objects["ENG_Crankshaft"].matrix_world.translation.z))]   # on the crank axis
    if name == "hub_front":
        pts = [bpy.data.objects["ENG_Drive_Hub"].matrix_world @ Vector(c) for c in bpy.data.objects["ENG_Drive_Hub"].bound_box]
    c = sum(pts, Vector()) / len(pts)
    A, E = math.radians(az), math.radians(el)
    d = Vector((math.sin(A) * math.cos(E), -math.cos(A) * math.cos(E), math.sin(E)))
    cam.location = c + d * dist
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    fp = os.path.join(out, f"{name}.png")
    r.filepath = fp
    bpy.ops.render.render(write_still=True)
    files.append(fp)
root["crank_deg"] = 0.0
print("@@JSON@@" + __import__("json").dumps({"ok": True, "files": files}))
