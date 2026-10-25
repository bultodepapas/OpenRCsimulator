"""Render the mount alone through the camera solved from the O.S. 905 product photo (52 x 25 lug-hole
rectangle on the beam tops) and save it for the photo comparison (mount/ref/amazon_mount.jpg, 800 x 902).
blender -b engine_se_bancada.blend -P mount_photo_cmp.py -- --cam /home/claude/mount/cam_amazon.json --out x.png"""
import json
import sys

import bpy
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
c = json.load(open(A[A.index("--cam") + 1]))
OUT = A[A.index("--out") + 1]
W, H = 800, 902
MM = 0.001
R = Matrix(c["R"])
t = Vector(c["t"])
# photo frame (x, y_m toward the tips, z_m down) -> engine frame: Y = 14.5 - y_m, Z = -6.7 - z_m
Mx = Matrix(((1, 0, 0), (0, -1, 0), (0, 0, -1)))
b = Vector((0.0, 14.5, -6.7))
Re = R @ Mx
te = R @ b + t
C = -(Re.transposed() @ te)
Rbl = Matrix(((1, 0, 0), (0, -1, 0), (0, 0, -1))) @ Re          # OpenCV -> Blender camera axes
keep = ("BANC_Bancada_OS905", "BANC_Letras_OS905")
for o in bpy.data.objects:
    if o.type in ("MESH", "CURVE"):
        o.hide_render = o.name not in keep
sc = bpy.context.scene
cd = bpy.data.cameras.new("CAM_Photo")
cam = bpy.data.objects.new("CAM_Photo", cd)
sc.collection.objects.link(cam)
cd.sensor_fit = "HORIZONTAL"
cd.sensor_width = 36.0
cd.lens = c["f"] * 36.0 / W
cd.shift_x = (c["cx"] - W / 2) / W
cd.shift_y = -(c["cy"] - H / 2) / W
cd.clip_start, cd.clip_end = 0.01, 50
cd.dof.use_dof = False
m = Rbl.transposed().to_4x4()
m.translation = C * MM
cam.matrix_world = m
sc.camera = cam
sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = W, H, 100
sc.render.engine = "CYCLES"
sc.cycles.samples = int(A[A.index("--samples") + 1]) if "--samples" in A else 48
sc.cycles.use_denoising = True
sc.render.film_transparent = True
sc.view_settings.view_transform = "Khronos PBR Neutral"
sc.view_settings.exposure = -1.0
for o in bpy.data.objects:   # studio set off: the product shot is on white
    if o.name == "LD_Backdrop":
        o.hide_render = True
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("@@JSON@@" + json.dumps({"ok": True, "out": OUT, "lens": cd.lens, "cam_mm": list(C)}))
