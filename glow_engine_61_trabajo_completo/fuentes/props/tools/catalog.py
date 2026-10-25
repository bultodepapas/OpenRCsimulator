"""Catalogue shot of the whole library on the engine renders' studio sweep: nine props lying on their hub's
rear face (front face up), the four spinners standing, labels on the floor.
blender -b props_library.blend -P catalog.py -- --studio engine_se_bancada.blend --check check_props.json
        --out DIR [--res 1800 1250] [--samples 96] [--save catalog.blend] [--views catalogo,detalle_raices]"""
import json
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


OUT = opt("--out", "/tmp/catalog")
RES = tuple(int(v) for v in opt("--res", ("1800", "1250"), 2))
SPP = int(opt("--samples", "96"))
MM = 0.001
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
chk = json.load(open(opt("--check"))) if opt("--check") else {"props": {}}

# studio: the engine renders' sweep, key / fill / rim lights and world
with bpy.data.libraries.load(opt("--studio"), link=False) as (src, dst):
    dst.objects = [n for n in src.objects if n in ("LD_Backdrop", "LD_Key", "LD_Fill", "LD_Rim")]
    dst.worlds = [n for n in src.worlds][:1]
stc = bpy.data.collections.new("ESTUDIO")
sc.collection.children.link(stc)
for o in dst.objects:
    stc.objects.link(o)
    o.parent = None
if dst.worlds:
    sc.world = dst.worlds[0]
FLOOR = -0.0586
bd = bpy.data.objects["LD_Backdrop"]
bd.scale = (1.0, 1.0, 1.0)
# unparented from the engine rig's pivot the sweep sits square: flat floor at z -0.059 up to y ~ +0.5,
# wall rising behind (+Y)

ORDER = [["APC_11x7", "APC_11x8", "APC_12x6"], ["APC_12x7", "APC_12.5x6", "MA_GF_11x7"],
         ["MA_Scimitar_11x7", "MA_3B_11x7", "MA_3B_12x6"]]
SPINS = ["TT_Std_2-1_2", "TT_Ult_2-1_4", "DB_2-1_2", "DB_3B_2-3_4"]
up = Matrix.Rotation(math.radians(-90), 4, "X")         # thrust (-Y) up: front face up, hub rear face on the floor
lab_mat = bpy.data.materials.new("M_Etiqueta")
lab_mat.use_nodes = True
b = lab_mat.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.035, 0.035, 0.035, 1)
b.inputs["Roughness"].default_value = 0.6


def label(text, x, y, size=0.016):
    cu = bpy.data.curves.new("TXT", "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    cu.extrude = 0.0002
    fp = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    if os.path.exists(fp):
        cu.font = bpy.data.fonts.load(fp, check_existing=True)
    ob = bpy.data.objects.new("ETQ_" + text[:20], cu)
    ob.location = (x, y, FLOOR + 0.0003)
    cu.materials.append(lab_mat)
    stc.objects.link(ob)
    return ob


DX, DY = 0.335, 0.215
for j, row in enumerate(ORDER):
    for i, k in enumerate(row):
        root = bpy.data.objects.get(f"ROOT_{k}")
        if not root:
            continue
        x = (i - 1) * DX
        y = [0.25, 0.035, -0.195][j]
        rz = 0.0 if "3B" not in k else -90.0     # one blade toward the camera, the label below its tip
        root.matrix_world = Matrix.Translation((x, y, FLOOR)) @ Matrix.Rotation(math.radians(rz), 4, "Z") @ up
        p = chk["props"].get(k, {})
        lbl = p.get("label", k).replace("Master Airscrew", "MA")
        label(f"{lbl}  -  {p.get('mass_g', '')} g", x, y - (0.168 if "3B" in k else 0.088))
for i, t in enumerate(SPINS):
    root = bpy.data.objects.get(f"ROOT_SPIN_{t}")
    if not root:
        continue
    x = (i - 1.5) * 0.15
    y = -0.56
    root.matrix_world = Matrix.Translation((x, y, FLOOR)) @ Matrix.Rotation(math.radians(90), 4, "Z") @ up
    cone = next(o for o in root.children if o.name.endswith("_Cono"))
    lbl = {"TT_Std_2-1_2": "Tru-Turn Std 2-1/2\"", "TT_Ult_2-1_4": "Tru-Turn Ultimate 2-1/4\"",
           "DB_2-1_2": "Dubro 2-1/2\"", "DB_3B_2-3_4": "Dubro 2-3/4\" 3 palas"}[t]
    label(lbl, x, y - 0.062, 0.0135)
for o in bpy.data.objects:            # hardware stays in the drawer
    if o.name.startswith("ROOT_HW_"):
        for c in o.children:
            c.hide_render = True
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SPP
sc.cycles.use_denoising = True
sc.cycles.use_adaptive_sampling = True
sc.cycles.adaptive_threshold = 0.02
sc.render.resolution_x, sc.render.resolution_y = RES
sc.view_settings.view_transform = "Khronos PBR Neutral"
sc.view_settings.exposure = float(opt("--exposure", "-1.6"))
cd = bpy.data.cameras.new("CAM_Catalogo")
cam = bpy.data.objects.new("CAM_Catalogo", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.clip_start, cd.clip_end = 0.01, 30
cd.dof.use_dof = True
cd.dof.aperture_fstop = 18.0
# catalogue lighting: the engine rig was aimed at one engine; here one big overhead softbox + a low front fill
for n in ("LD_Key", "LD_Fill", "LD_Rim"):
    bpy.data.objects[n].hide_render = True
CY = -0.16


def area(name, size, energy, loc, tgt):
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape = "RECTANGLE"
    ld.size, ld.size_y = size
    ld.energy = energy
    ob = bpy.data.objects.new(name, ld)
    stc.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return ob


E = float(opt("--energy", "210"))
area("CAT_Softbox", (1.6, 1.2), E, (0.0, CY - 0.15, 1.45), (0.0, CY, FLOOR))
area("CAT_Fill", (1.2, 0.5), E * 0.35, (-0.9, CY - 1.3, 0.55), (0.0, CY, FLOOR))
area("CAT_Rim", (1.4, 0.4), E * 0.30, (0.4, CY + 1.2, 0.7), (0.0, CY, FLOOR))
VIEWS = {   # name: target, az, el, dist, lens
    "catalogo": ((0.0, -0.155, FLOOR), 0.0, 60.0, 1.95, 50.0),
    "detalle_raices": ((0.0, 0.26, FLOOR + 0.01), 18.0, 40.0, 0.62, 85.0),
    "spinners": ((0.0, -0.575, FLOOR + 0.025), 0.0, 22.0, 0.92, 55.0),
}
for n in (opt("--views") or "catalogo").split(","):
    tgt, az, el, dist, lens = VIEWS[n]
    t = Vector(tgt)
    a, e = math.radians(az), math.radians(el)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = t + d * dist
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    cd.lens = lens
    cd.dof.focus_distance = dist
    sc.render.filepath = os.path.join(OUT, f"{n}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", n, flush=True)
if opt("--save"):
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(opt("--save")))
print("@@JSON@@done", flush=True)
