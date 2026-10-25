"""Close-up stills of the SE head (fins, crescents, screws, glow plug) in the look-dev studio of engine_se.blend.
Cameras are set in the ENGINE frame (front = -Y, up = +Z) and follow the turntable pivot, so the same views
can be rendered on two builds (before / after) for a fair comparison.
blender -b engine_se.blend -P head_renders.py -- --out DIR [--views a,b] [--res 1400 1050] [--samples 96]
       [--prefix name_] [--no-muffler]"""
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(k, d=None, n=1):
    if k not in A:
        return d
    i = A.index(k)
    if n == 0:
        return True
    return A[i + 1] if n == 1 else A[i + 1:i + 1 + n]


OUT = opt("--out", "/tmp/head_renders")
os.makedirs(OUT, exist_ok=True)
RES = tuple(int(v) for v in opt("--res", ("1400", "1050"), 2))
SPP = int(opt("--samples", "96"))
PRE = opt("--prefix", "")
MM = 0.001
# name: (azimuth from the front (-Y) toward +X, elevation, distance m, lens mm, target in engine mm, fstop)
VIEWS = {
    "culata_34": (35.0, 42.0, 0.235, 105.0, (0.0, 0.0, 64.0), 22.0),
    "culata_arriba": (0.0, 86.0, 0.26, 105.0, (0.0, 0.0, 66.0), 22.0),
    "culata_lado": (90.0, 20.0, 0.235, 105.0, (0.0, 0.0, 63.0), 22.0),
    "culata_atras": (200.0, 34.0, 0.235, 105.0, (0.0, 0.0, 63.0), 22.0),
    "bujia": (25.0, 38.0, 0.115, 105.0, (0.0, 0.0, 68.5), 16.0),
}
sc = bpy.context.scene
sc.frame_set(16)
head = bpy.data.objects["ENG_Head"]
root = head.parent if head.parent is not None else None     # the engine root empty = the engine (model) frame
Tw = root.matrix_world.copy() if root is not None else __import__("mathutils").Matrix.Identity(4)
Rw = Tw.to_3x3().normalized()


def eng(p_mm):   # engine-frame mm -> world
    return Tw @ (Vector(p_mm) * MM)


if opt("--no-muffler", n=0):
    for c in bpy.data.collections:
        if c.name.endswith("Muffler"):
            c.hide_render = True
for o in bpy.data.objects:     # props / mount stay out of the head close-ups
    if o.name.startswith(("BANC_", "PROP_", "ROOT_")):
        o.hide_render = True
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SPP
sc.cycles.use_denoising = True
sc.cycles.use_adaptive_sampling = True
sc.cycles.adaptive_threshold = 0.02
sc.cycles.max_bounces, sc.cycles.glossy_bounces, sc.cycles.diffuse_bounces = 8, 4, 3
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.resolution_percentage = 100
sc.render.use_border = False
cd = bpy.data.cameras.new("CAM_HeadDetail")
cam = bpy.data.objects.new("CAM_HeadDetail", cd)
sc.collection.objects.link(cam)
cd.clip_start, cd.clip_end = 0.005, 30
cd.dof.use_dof = True
for n in (opt("--views") or ",".join(VIEWS)).split(","):
    az, el, dist, lens, tgt, fs = VIEWS[n]
    a, e = math.radians(az), math.radians(el)
    d_eng = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    t = eng(tgt)
    d = (Rw @ d_eng).normalized()
    cam.location = t + d * dist
    up = Rw @ Vector((0, 0, 1))
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    if el > 80:   # top view: keep the engine's front at the bottom of the frame
        cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.rotation_mode = "QUATERNION"
        fwd = (t - cam.location).normalized()
        yv = (Rw @ Vector((0, 1, 0))).normalized()
        yv = (yv - fwd * yv.dot(fwd)).normalized()
        xv = yv.cross(-fwd)
        from mathutils import Matrix
        m = Matrix((xv, yv, -fwd)).transposed()
        cam.rotation_quaternion = m.to_quaternion()
    else:
        cam.rotation_mode = "XYZ"
    cd.lens = lens
    cd.dof.focus_distance = dist
    cd.dof.aperture_fstop = fs
    sc.camera = cam
    sc.render.filepath = os.path.join(OUT, f"{PRE}{n}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", n, flush=True)
print("@@DONE@@", flush=True)
