"""Fast workbench previews of a .blend (all visible meshes): blender -b f.blend -P preview.py -- --out DIR
[--views front,side,iso,top] [--res 900 700] [--hide name1,name2] [--ortho 1]"""
import math, os, sys
import bpy
from mathutils import Vector
A = sys.argv[sys.argv.index("--") + 1:]
def opt(k, d=None, n=1):
    if k not in A: return d
    i = A.index(k); return A[i + 1] if n == 1 else A[i + 1:i + 1 + n]
OUT = opt("--out", "/tmp/prev"); os.makedirs(OUT, exist_ok=True)
RES = [int(v) for v in opt("--res", ("900", "700"), 2)]
hide = (opt("--hide") or "").split(",")
only = opt("--only")
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = opt("--color", "SINGLE")
sc.display.shading.show_cavity = True
sc.display.shading.show_shadows = False
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.film_transparent = False
sc.display.shading.background_type = "VIEWPORT" if hasattr(sc.display.shading, "background_type") else None
sc.world = sc.world or bpy.data.worlds.new("W")
sc.world.color = (0.75, 0.75, 0.75)
sc.display.shading.light = opt("--light", "STUDIO")
for o in bpy.data.objects:
    if o.type == "MESH" and (any(h and h in o.name for h in hide) or (only and not any(t in o.name for t in only.split(",")))):
        o.hide_render = True
for lc in bpy.context.view_layer.layer_collection.children:
    lc.exclude = False
bpy.context.view_layer.update()
obs = [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render and o.visible_get()]
pts = [o.matrix_world @ Vector(c) for o in obs for c in o.bound_box]
lo = Vector([min(p[i] for p in pts) for i in range(3)]); hi = Vector([max(p[i] for p in pts) for i in range(3)])
ctr = (lo + hi) / 2; size = (hi - lo).length
cd = bpy.data.cameras.new("PV"); cam = bpy.data.objects.new("PV", cd); sc.collection.objects.link(cam); sc.camera = cam
cd.type = "ORTHO"; cd.ortho_scale = size * float(opt("--zoom", "1.0")); cd.clip_start = 0.001; cd.clip_end = 100
V = {"front": (0, -1, 0), "side": (1, 0, 0), "iso": (0.7, -0.9, 0.5), "top": (0, 0, 1), "back": (0, 1, 0), "iso2": (-0.8, -0.7, 0.35), "rear_iso": (0.6, 0.8, 0.4)}
for n in (opt("--views") or "front,side,iso").split(","):
    d = Vector(V[n]).normalized()
    tgt = Vector([float(v) for v in opt("--target").split(",")]) * 0.001 if opt("--target") else ctr
    cam.location = tgt + d * size * 2
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((0, 1, 0))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y" if up.z else "Z").to_euler()
    sc.render.filepath = os.path.join(OUT, n + ".png")
    bpy.ops.render.render(write_still=True)
print("done")
