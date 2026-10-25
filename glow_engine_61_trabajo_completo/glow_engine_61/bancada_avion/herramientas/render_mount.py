"""Stills of the engine on its mount: cameras by azimuth / elevation around a target (mm, engine frame:
az 0 = from the front (-Y), 90 = needle side (+X), -90 = exhaust side (-X), 180 = from behind).
blender -b engine_se_bancada.blend -P render_mount.py -- --out DIR [--res 1400 1050] [--samples 96]
       [--views hero,lado,...] [--save cams.blend]"""
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


OUT = opt("--out", "/tmp/mount_renders")
RES = tuple(int(v) for v in opt("--res", ("1400", "1050"), 2))
SPP = int(opt("--samples", "96"))
MM = 0.001
#        name           az     el    target (mm)          dist  lens  hide
VIEWS = {
    "hero":        (38.0, 20.0, (0.0, 18.0, 6.0), 620.0, 70.0, ()),
    "frente_izq": (-40.0, 24.0, (0.0, 18.0, 6.0), 620.0, 70.0, ()),
    "lado":        (90.0, 4.0, (0.0, 30.0, -4.0), 640.0, 75.0, ()),
    "detalle":     (30.0, 3.0, (0.0, 12.0, -10.0), 300.0, 70.0, ("E61_Prop",)),
    "atras":       (-148.0, 30.0, (0.0, 40.0, -4.0), 470.0, 60.0, ("BANC_Fuselaje",)),
    "bancada_sola": (36.0, 26.0, (0.0, 22.0, -6.0), 300.0, 70.0, ("E61_Body", "E61_Carburetor", "E61_Drive",
                                                                  "E61_Fasteners", "E61_Muffler", "E61_Prop",
                                                                  "E61_Lettering", "E61_Analysis", "E61_Internals",
                                                                  "BANC_Fuselaje", "BANC_Lineas", "Engine_61")),
    "arriba":      (60.0, 62.0, (0.0, 20.0, 10.0), 640.0, 70.0, ()),
}
names = (opt("--views") or ",".join(VIEWS)).split(",")
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SPP
sc.cycles.use_denoising = True
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


def set_hidden(names_, hidden):
    for n in names_:
        c = bpy.data.collections.get(n)
        if c is None:
            continue
        c.hide_render = hidden
        lc = lc_find(bpy.context.view_layer.layer_collection, n)
        if lc:
            lc.exclude = False


cd = bpy.data.cameras.new("CAM_Bancada")
cam = bpy.data.objects.new("CAM_Bancada", cd)
sc.collection.objects.link(cam)
cd.clip_start, cd.clip_end = 0.01, 20.0
cd.dof.use_dof = True
cd.dof.aperture_fstop = 16.0
sc.camera = cam
rig = [o for o in bpy.data.objects if o.name in ("LD_Backdrop", "LD_Key", "LD_Fill", "LD_Rim")]
base = {o.name: o.matrix_world.copy() for o in rig}
ldc = bpy.data.objects.get("LD_Cam")
c0 = ldc.matrix_world.translation if ldc else Vector((0, -1, 0))
AZ0 = math.degrees(math.atan2(c0.x, -c0.y))   # the studio set was built facing LD_Cam (turntable frame)
for o in rig:   # keep the studio set facing the camera: sweep behind, key / fill / rim around it
    o.parent = None
done = []
for n in names:
    az, el, tgt, dist, lens, hide = VIEWS[n]
    set_hidden(hide, True)
    Rz = Matrix.Rotation(math.radians(az - AZ0), 4, "Z")
    for o in rig:
        o.matrix_world = Rz @ base[o.name]
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
    set_hidden(hide, False)
if opt("--save"):
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(opt("--save")))
print("@@JSON@@" + str(done), flush=True)
