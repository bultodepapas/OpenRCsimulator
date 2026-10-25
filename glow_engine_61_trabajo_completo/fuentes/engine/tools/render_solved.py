"""Render the model through a solved photo camera (workbench, transparent) at N x the photo size."""
import bpy, json, sys, math
import numpy as np
from mathutils import Matrix, Vector
a = sys.argv[sys.argv.index("--") + 1:]
cam = json.load(open(a[a.index("--cam") + 1]))
out = a[a.index("--out") + 1]
k = int(a[a.index("--scale") + 1]) if "--scale" in a else 3
show_muf = "--muffler" in a
sc = bpy.context.scene
for c in bpy.data.collections:
    if c.name.startswith("LD_") or (c.name.endswith("Muffler") and not show_muf):
        c.hide_render = True
    elif c.name.endswith("Muffler"):
        c.hide_render = False
for o in bpy.data.objects:
    if o.name.startswith("LD_") or (o.name.startswith("MUF_") and not show_muf):
        o.hide_render = True
R = np.array(cam["R"]); C = np.array(cam["C"]) * 0.001
xc, yc, zc = R[0], R[1], R[2]           # rows of R = camera axes in world (OpenCV)
M = Matrix(((xc[0], -yc[0], -zc[0], C[0]), (xc[1], -yc[1], -zc[1], C[1]),
            (xc[2], -yc[2], -zc[2], C[2]), (0, 0, 0, 1)))
cd = bpy.data.cameras.new("SOLVED"); cd.sensor_fit = "HORIZONTAL"; cd.sensor_width = 36.0
w, h = cam["size"]; cd.lens = cam["f"] * 36.0 / w
if "pp" in cam:  # principal point offset -> lens shift (fractions of the larger image dimension)
    cd.shift_x = (w / 2 - cam["pp"][0]) / max(w, h)
    cd.shift_y = (cam["pp"][1] - h / 2) / max(w, h)
cd.clip_start, cd.clip_end = 0.005, 20
co = bpy.data.objects.new("SOLVED", cd); sc.collection.objects.link(co); co.matrix_world = M
sc.camera = co
sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = w * k, h * k, 100
sc.render.pixel_aspect_x = sc.render.pixel_aspect_y = 1
eng = a[a.index("--engine") + 1] if "--engine" in a else "BLENDER_WORKBENCH"
sc.render.engine = eng
sc.render.film_transparent = True
if eng == "BLENDER_WORKBENCH":
    sh = sc.display.shading
    sh.light, sh.color_type, sh.show_cavity = "STUDIO", "MATERIAL", True
from bpy_extras.object_utils import world_to_camera_view
bpy.context.view_layer.update()
chk = {}
for n, p in (("plug", (0, 0, 76.84)), ("rsU_nx", (-13, 27.85, 9.4))):
    q = world_to_camera_view(sc, co, Vector(p) * 0.001)
    chk[n] = [round(q.x * w, 1), round((1 - q.y) * h, 1)]
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("@@JSON@@" + json.dumps({"ok": True, "out": out, "lens": cd.lens, "check_px": chk}))
