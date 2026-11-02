"""Side-by-side preview: full model vs real-time export (same camera, same light).
blender -b f.blend -P rt_preview.py -- --out img.png [--rt]   (--rt shows RT_Export only, else the engine)"""
import math
import sys

import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
out = a[a.index("--out") + 1]
rt = "--rt" in a
az = float(a[a.index("--az") + 1]) if "--az" in a else 35.0
el = float(a[a.index("--el") + 1]) if "--el" in a else 25.0
sc = bpy.context.scene
for o in bpy.data.objects:
    if o.type in ("MESH", "LIGHT"):
        inrt = any(c.name == "RT_Export" for c in o.users_collection)
        o.hide_render = (not inrt) if rt else (inrt or not o.name.startswith(("ENG_", "MUF_", "CARB_")))
for c in bpy.data.collections:
    if c.name.endswith("Prop") or c.name.endswith("Analysis"):
        c.hide_render = True
    if c.name == "RT_Export":
        c.hide_render = not rt
root = bpy.data.objects.get("Glow_Engine_61_RT")
off = Vector(root.location) if (rt and root) else Vector((0, 0, 0))
r = sc.render
r.engine = "CYCLES"
sc.cycles.samples, sc.cycles.use_denoising = 24, True
r.resolution_x, r.resolution_y, r.resolution_percentage = 1000, 800, 100
r.film_transparent = False
sc.view_settings.view_transform = "AgX"
sc.view_settings.exposure = float(a[a.index("--exposure") + 1]) if "--exposure" in a else -1.6
w = sc.world or bpy.data.worlds.new("W")
sc.world = w
w.use_nodes = True
bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs["Color"].default_value = (0.85, 0.83, 0.8, 1)
bg.inputs["Strength"].default_value = 1.0
ld = bpy.data.lights.new("PV_Key", "AREA")
ld.size, ld.energy = 0.4, 60
lo = bpy.data.objects.new("PV_Key", ld)
sc.collection.objects.link(lo)
lo.location = (0.35, -0.35, 0.45)
lo.rotation_euler = (Vector((0, 0, 0.03)) - lo.location).to_track_quat("-Z", "Y").to_euler()
cd = bpy.data.cameras.new("PV_Cam")
cd.lens = 85
cam = bpy.data.objects.new("PV_Cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
A, E = math.radians(az), math.radians(el)
tgt = Vector((-0.02, 0.0, 0.03)) + off
cam.location = tgt + Vector((math.sin(A) * math.cos(E), -math.cos(A) * math.cos(E), math.sin(E))) * 0.62
cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
r.filepath = out
bpy.ops.render.render(write_still=True)
