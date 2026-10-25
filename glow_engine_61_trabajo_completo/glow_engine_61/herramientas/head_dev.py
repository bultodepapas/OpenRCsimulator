"""Head development harness: build the cylinder + SE head only (build_engine functions) and render them through the
solved photo cameras, cropped to the head, next to the same crop of the owner's photo.
blender -b -P head_dev.py -- --out DIR [--views E,D,Ac] [--samples 48] [--save f.blend] [--old]"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
sys.argv = [sys.argv[0]]
sys.path.insert(0, "/home/claude/engine")
import build_engine as be  # noqa: E402


def opt(k, d=None):
    if k in A and (A.index(k) + 1 == len(A) or A[A.index(k) + 1].startswith("--")):
        return "1"
    return A[A.index(k) + 1] if k in A else d


OUT = opt("--out", "/home/claude/head/dev")
os.makedirs(OUT, exist_ok=True)
VIEWS = opt("--views", "E,D,Ac").split(",")
SPP = int(opt("--samples", "48"))
MM = 0.001

if opt("--blend"):   # re-render a saved build, materials rebuilt from build_engine (look-dev iterations)
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(opt("--blend")))
    sc = bpy.context.scene
    if not opt("--keepmat"):
        M = be.build_materials()
    for o in [o for o in bpy.data.objects if o.type in ("LIGHT", "CAMERA")]:
        bpy.data.objects.remove(o)
    for o in bpy.data.objects:      # studio sweep / props of the look-dev files stay out of the photo crops
        if o.name.startswith(("LD_", "BANC_", "PROP_")):
            o.hide_render = True
else:
    sc = be.reset_scene()
    be.SCREW_MESHES.clear()
    M = be.build_materials()
    V = dict(be.VARIANTS["se"])
    col = bpy.data.collections.new("HEAD_DEV")
    sc.collection.children.link(col)
    import time  # noqa: E402
    t0 = time.time()
    parts = [be.build_cylinder(col, M, V)] + be.build_head_se(col, M, V)
    print("build s", round(time.time() - t0, 1), flush=True)
    for p in parts:
        if p.type == "MESH" and p.data.users == 1:
            be.final_clean(p)
    tris = {p.name: len(p.data.polygons) for p in parts if p.type == "MESH"}
    print("@@TRIS@@" + json.dumps(tris), flush=True)
if opt("--save") and not opt("--blend"):
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(opt("--save")))

if sc.world is None or opt("--blend"):   # a plain world: the look-dev studio gradient would darken the metals
    sc.world = bpy.data.worlds.new("W_HeadDev")
sc.world.use_nodes = True
r = sc.render
r.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SPP
sc.cycles.use_denoising = True
r.film_transparent = True
sc.view_settings.view_transform = "AgX"
sc.view_settings.exposure = float(opt("--exposure", "-1.3"))


def set_camera(vn):
    cam = json.load(open(f"/home/claude/engine/cams/cam_{vn}.json"))
    R = np.array(cam["R"])
    C = np.array(cam["C"]) * MM
    Mw = Matrix(((R[0, 0], -R[1, 0], -R[2, 0], C[0]), (R[0, 1], -R[1, 1], -R[2, 1], C[1]),
                 (R[0, 2], -R[1, 2], -R[2, 2], C[2]), (0, 0, 0, 1)))
    w, h = cam["size"]
    cd = bpy.data.cameras.new("AU_" + vn)
    cd.sensor_fit, cd.sensor_width, cd.lens = "HORIZONTAL", 36.0, cam["f"] * 36.0 / w
    cd.shift_x = (w / 2 - cam["pp"][0]) / max(w, h)
    cd.shift_y = (cam["pp"][1] - h / 2) / max(w, h)
    cd.clip_start, cd.clip_end = 0.005, 20
    co = bpy.data.objects.new("AU_" + vn, cd)
    sc.collection.objects.link(co)
    co.matrix_world = Mw
    sc.camera = co
    r.resolution_x, r.resolution_y = w, h
    r.resolution_percentage = 100
    # border: the head and the top of the cylinder, projected
    Rm, t = np.array(cam["R"]), np.array(cam["t"])
    P = np.array([(23.5 * math.cos(a), 23.5 * math.sin(a), z) for a in np.linspace(0, 2 * math.pi, 48)
                  for z in (52.0, 76.5)])
    X = (Rm @ P.T).T + t
    u = cam["f"] * X[:, 0] / X[:, 2] + cam["pp"][0]
    v = cam["f"] * X[:, 1] / X[:, 2] + cam["pp"][1]
    box = [max(0, int(u.min()) - 10), max(0, int(v.min()) - 10), min(w, int(u.max()) + 10), min(h, int(v.max()) + 10)]
    r.use_border, r.use_crop_to_border = True, True
    r.border_min_x, r.border_max_x = box[0] / w, box[2] / w
    r.border_min_y, r.border_max_y = 1 - box[3] / h, 1 - box[1] / h
    return cam, C, box


def lights(C):
    for lo in [o for o in bpy.data.objects if o.type == "LIGHT"]:
        bpy.data.objects.remove(lo)
    wbg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
    wbg.inputs["Color"].default_value = (0.88, 0.84, 0.77, 1.0)
    wbg.inputs["Strength"].default_value = float(opt("--world", "1.4"))
    ld = bpy.data.lights.new("AU_Soft", "AREA")
    dist_l = 0.75 * float(np.linalg.norm(C))
    ld.shape, ld.size, ld.energy, ld.color = "DISK", 0.35, float(opt("--key", "0.45")) * 1.2 * (dist_l / 0.26) ** 2, \
        (1.0, 0.965, 0.91)
    lo = bpy.data.objects.new("AU_Soft", ld)
    sc.collection.objects.link(lo)
    lo.location = Vector(C) * 0.75 + Vector((0, 0, 0.12))
    lo.rotation_euler = (Vector((0, 0, 0.06)) - lo.location).to_track_quat("-Z", "Y").to_euler()
    top = bpy.data.lights.new("AU_Top", "AREA")
    top.shape, top.size, top.energy, top.color = "DISK", 0.6, float(opt("--top", "2.0")), (1.0, 0.96, 0.9)
    to = bpy.data.objects.new("AU_Top", top)
    sc.collection.objects.link(to)
    to.location = (0.0, 0.0, 0.55)


from PIL import Image  # noqa: E402
for vn in VIEWS:
    cam, C, box = set_camera(vn)
    lights(C)
    r.filepath = os.path.join(OUT, f"r_{vn}.png")
    bpy.ops.render.render(write_still=True)
    ph = Image.open(cam["image"]).convert("RGB").crop(box)
    rd = Image.open(r.filepath).convert("RGBA")
    bg = Image.new("RGBA", rd.size, (232, 226, 214, 255))
    bg.alpha_composite(rd)
    w, h = ph.size
    g = Image.new("RGB", (w * 2 + 6, h), (255, 255, 255))
    g.paste(ph, (0, 0))
    g.paste(bg.convert("RGB").resize(ph.size), (w + 6, 0))
    g.save(os.path.join(OUT, f"cmp_{vn}.jpg"), quality=90)
    print("view", vn, box, flush=True)
print("@@DONE@@", flush=True)
