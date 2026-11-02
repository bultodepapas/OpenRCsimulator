"""Stills of the prop + spinner combos on the engine and its mount (Cycles, the engine file's studio rig).
blender -b motor_bancada_helices.blend -P render_props.py -- --out DIR [--views a_hero,b_hero,...]
        [--res 1600 1100] [--samples 80]
az 0 = from the front (-Y), 90 = needle side (+X); targets in mm (engine frame)."""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(k, d=None, n=1):
    if k not in A:
        return d
    i = A.index(k)
    return A[i + 1] if n == 1 else A[i + 1:i + 1 + n]


OUT = opt("--out", "/tmp/props_renders")
RES = tuple(int(v) for v in opt("--res", ("1600", "1100"), 2))
SPP = int(opt("--samples", "80"))
MM = 0.001
NAMES = {"A": "COMBO_A_APC12x6_TruTurn2-5", "B": "COMBO_B_MA3B11x7_Dubro2-75", "C": "COMBO_C_APC11x7_Dubro2-5",
         "D": "COMBO_D_MAScimitar11x7_TTUltimate2-25"}
#        name          combo  az     el     target (mm)          dist   lens  floor drop (m)
VIEWS = {
    "a_hero":     ("A", 36.0, 16.0, (0.0, -32.0, 0.0), 700.0, 50.0, 0.0),
    "a_frente":   ("A", 0.0, 4.0, (0.0, -60.0, -4.0), 820.0, 50.0, 0.0),
    "b_hero":     ("B", -34.0, 14.0, (0.0, -32.0, 0.0), 700.0, 50.0, 0.025),
    "c_detalle":  ("C", 28.0, 8.0, (0.0, -82.0, -6.0), 420.0, 70.0, 0.0),
    "d_detalle":  ("D", -26.0, 10.0, (0.0, -82.0, -6.0), 420.0, 70.0, 0.0),
    "a_lado":     ("A", 90.0, 3.0, (0.0, -10.0, -4.0), 760.0, 50.0, 0.0),
}
names = (opt("--views") or ",".join(VIEWS)).split(",")
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SPP
sc.cycles.use_denoising = True
sc.cycles.use_adaptive_sampling = True
sc.cycles.adaptive_threshold = 0.02
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.resolution_percentage = 100
sc.render.film_transparent = False
sc.view_settings.view_transform = "Khronos PBR Neutral"
sc.view_settings.exposure = float(opt("--exposure", "-1.6"))
os.makedirs(OUT, exist_ok=True)


def lc_find(lc, name):
    if lc.collection.name == name:
        return lc
    for c in lc.children:
        r = lc_find(c, name)
        if r:
            return r
    return None


def set_visible(cname, vis):
    c = bpy.data.collections.get(cname)
    if c is None:
        return
    c.hide_render = not vis
    lc = lc_find(bpy.context.view_layer.layer_collection, cname)
    if lc:
        lc.exclude = not vis
        if vis:          # nested collections (prop / spinner / hardware) come in excluded when appended
            stack = list(lc.children)
            while stack:
                x = stack.pop()
                x.exclude = False
                stack += list(x.children)


cd = bpy.data.cameras.new("CAM_Helices")
cam = bpy.data.objects.new("CAM_Helices", cd)
sc.collection.objects.link(cam)
cd.clip_start, cd.clip_end = 0.01, 20.0
cd.dof.use_dof = True
cd.dof.aperture_fstop = 14.0
sc.camera = cam
rig = [o for o in bpy.data.objects if o.name in ("LD_Backdrop", "LD_Key", "LD_Fill", "LD_Rim")]
base = {o.name: o.matrix_world.copy() for o in rig}
ldc = bpy.data.objects.get("LD_Cam")
c0 = ldc.matrix_world.translation if ldc else Vector((0, -1, 0))
AZ0 = math.degrees(math.atan2(c0.x, -c0.y))
for o in rig:
    o.parent = None
bd = bpy.data.objects.get("LD_Backdrop")
done = []
for n in names:
    ck, az, el, tgt, dist, lens, drop = VIEWS[n]
    for k, cname in NAMES.items():
        set_visible(cname, k == ck)
    Rz = Matrix.Rotation(math.radians(az - AZ0), 4, "Z")
    for o in rig:     # the sweep's floor drops for the 3-blade (a blade below the fuselage line)
        o.matrix_world = Rz @ (Matrix.Translation((0, 0, -drop)) if o.name == "LD_Backdrop" else Matrix()) @ base[o.name]
    t = Vector(tgt) * MM
    a, e = math.radians(az), math.radians(el)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = t + d * dist * MM
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    cd.lens = lens
    cd.dof.focus_distance = dist * MM
    sc.render.filepath = os.path.join(OUT, f"{n}.png")
    bpy.ops.render.render(write_still=True)
    done.append(sc.render.filepath)
    print("rendered", n, flush=True)
for k, cname in NAMES.items():
    set_visible(cname, k == "A")
print("@@JSON@@" + str(done), flush=True)
