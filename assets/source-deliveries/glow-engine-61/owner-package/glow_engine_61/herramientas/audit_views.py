"""Final audit: render the finished model through every solved photo camera and measure how well it sits on the photo.

blender -b engine_se.blend -P audit_views.py -- --out DIR [--views A Ac B B2 D E T] [--samples 20] [--pct 50] [--no-cycles]

Per view: render_<v>.png (Cycles, final materials), ids_<v>.png (flat zone colours, full res), sheet_<v>.png
(photo | render | zone outlines on the photo) and metrics.json (outline-to-photo-edge distance per zone, px and mm).
"""
import json
import os
import sys

import bpy
import cv2
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image, ImageDraw, ImageFont

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(k, d=None):
    return a[a.index(k) + 1] if k in a else d


def arglist(k, d):
    if k not in a:
        return d
    out_ = []
    for t in a[a.index(k) + 1:]:
        if t.startswith("--"):
            break
        out_.append(t)
    return out_


OUT = arg("--out", "/home/claude/engine/audit")
os.makedirs(OUT, exist_ok=True)
VIEWS = arglist("--views", ["A", "Ac", "B", "B2", "D", "E", "T"])
CYCLES = "--no-cycles" not in a
LABEL = {"A": "lateral +X amplia", "Ac": "primer plano +X", "B": "lateral -X amplia", "B2": "frente -X bajo",
         "D": "arriba-atras cercana", "E": "arriba-frente", "T": "arriba-atras completa"}
ZONES = [  # (key, label, colour on the sheet, name prefixes)
    ("head", "culata", (255, 190, 0), ("ENG_Head", "ENG_GlowPlug", "ENG_Gasket_Head")),
    ("cyl", "cilindro", (0, 200, 255), ("ENG_Cylinder_Fins", "ENG_Liner")),
    ("case", "carter", (60, 120, 255), ("ENG_Crankcase", "ENG_Front_Housing", "ENG_Backplate", "ENG_Gasket", "ENG_Screw",
                                       "ENG_Letter")),
    ("drive", "eje / hub", (200, 0, 200), ("ENG_Drive_Hub", "ENG_Prop_Washer", "ENG_Prop_Nut", "ENG_Crankshaft_Thread", "ENG_Thrust", "ENG_Woodruff",
                                          "ENG_Crankshaft", "ENG_Bearing_Front")),
    ("carb", "carburador", (0, 200, 60), ("CARB_",)),
    ("muf", "mofle", (255, 40, 40), ("MUF_",)),
]


def zone_of(name):
    for i, (_, _, _, pre) in enumerate(ZONES):
        if name.startswith(pre):
            return i
    return None


sc = bpy.context.scene
for o in bpy.data.objects:
    if o.name.startswith(("LD_Backdrop", "PHOTO_", "ANL_", "CUT_", "CMP_", "FIT_", "MO_", "PV_", "MV_")):
        o.hide_render = True
for c in bpy.data.collections:
    if c.name.endswith("Muffler"):
        c.hide_render = False
    if c.name.endswith("Prop"):          # the owner's engine is photographed with prop + spinner mounted
        c.hide_render = "--no-prop" in a
    if c.name == "E61_Analysis":
        c.hide_render = True
for o in bpy.data.objects:
    if o.name.startswith("MUF_"):
        o.hide_render = False
root = bpy.data.objects.get("Glow_Engine_61")
if root is not None:
    root["crank_deg"] = 0.0
    if "cutaway" in root.keys():
        root["cutaway"] = 0
    root.update_tag()
bpy.context.view_layer.update()
meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render]
r = sc.render


def set_camera(vn):
    cam = json.load(open(f"/home/claude/engine/cams/cam_{vn}.json"))
    R = np.array(cam["R"]); C = np.array(cam["C"]) * 0.001
    Mw = Matrix(((R[0, 0], -R[1, 0], -R[2, 0], C[0]), (R[0, 1], -R[1, 1], -R[2, 1], C[1]),
                 (R[0, 2], -R[1, 2], -R[2, 2], C[2]), (0, 0, 0, 1)))
    w, h = cam["size"]
    cd = bpy.data.cameras.get("AU_" + vn) or bpy.data.cameras.new("AU_" + vn)
    cd.sensor_fit, cd.sensor_width, cd.lens = "HORIZONTAL", 36.0, cam["f"] * 36.0 / w
    cd.shift_x = (w / 2 - cam["pp"][0]) / max(w, h)
    cd.shift_y = (cam["pp"][1] - h / 2) / max(w, h)
    cd.clip_start, cd.clip_end = 0.005, 20
    co = bpy.data.objects.get("AU_" + vn) or bpy.data.objects.new("AU_" + vn, cd)
    if co.name not in sc.collection.objects:
        sc.collection.objects.link(co)
    co.matrix_world = Mw
    sc.camera = co
    r.resolution_x, r.resolution_y = w, h
    if root is not None:     # prop clock angle of this photo (tools/prop_fit.py); internals are hidden anyway
        root["crank_deg"] = float(cam.get("prop_deg", 0.0))
        root.update_tag()
        bpy.context.view_layer.update()
    return cam, co, C


def render_ids(vn, w, h):
    """Flat zone colours, no AA: decode a zone index per pixel (255 = background)."""
    keep = (r.engine, sc.display.shading.light, sc.display.shading.color_type, sc.display.render_aa, r.film_transparent,
            r.resolution_percentage)
    r.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type = "FLAT", "OBJECT"
    sh.show_cavity = sh.show_shadows = sh.show_object_outline = False
    sc.display.render_aa = "OFF"
    r.film_transparent = True
    r.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    keep_vs = (sc.view_settings.exposure, sc.view_settings.gamma, sc.view_settings.look, r.dither_intensity)
    sc.view_settings.exposure, sc.view_settings.gamma, sc.view_settings.look = 0.0, 1.0, "None"
    r.dither_intensity = 0.0   # no dither noise in the id pass

    def lin(v):   # the PNG is sRGB-encoded: pick linear colours that encode to well separated levels
        v = v / 255.0
        return ((v + 0.055) / 1.055) ** 2.4
    for o in meshes:
        z = zone_of(o.name)
        # accessories (prop, spinner): drawn and occluding, but in no scored zone (decodes to 255)
        o.color = (lin((z + 1) * 36), 0.0, 0.0, 1.0) if z is not None else (lin(250), 0.0, 0.0, 1.0)
    r.filepath = os.path.join(OUT, f"ids_{vn}.png")
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    bpy.ops.render.render(write_still=True)
    im = np.asarray(Image.open(r.filepath).convert("RGBA")).astype(int)
    ids = np.full(im.shape[:2], 255, np.uint8)
    for z in range(len(ZONES)):
        m = (np.abs(im[..., 0] - 36 * (z + 1)) <= 8) & (im[..., 3] > 200)   # exposure 0, Standard, no dither
        ids[m] = z
    (r.engine, sh.light, sh.color_type, sc.display.render_aa, r.film_transparent, r.resolution_percentage) = keep
    (sc.view_settings.exposure, sc.view_settings.gamma, sc.view_settings.look, r.dither_intensity) = keep_vs
    return ids


def render_cycles(vn, C):
    r.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = int(arg("--samples", 20))
    sc.cycles.use_denoising = True
    r.film_transparent = True
    r.resolution_percentage = int(arg("--pct", 50))
    sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in
                                                        sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    sc.view_settings.exposure = float(arg("--exposure", -1.3))
    for lo in [o for o in bpy.data.objects if o.type == "LIGHT"]:
        lo.hide_render = True
    ld = bpy.data.lights.get("AU_Soft") or bpy.data.lights.new("AU_Soft", "AREA")
    dist_l = 0.75 * float(np.linalg.norm(C))
    ld.shape, ld.size, ld.energy = "DISK", 0.35, float(arg("--key", 0.45)) * 1.2 * (dist_l / 0.26) ** 2
    lo_ = bpy.data.objects.get("AU_Soft") or bpy.data.objects.new("AU_Soft", ld)
    if lo_.name not in sc.collection.objects:
        sc.collection.objects.link(lo_)
    lo_.hide_render = False
    lo_.location = Vector(C) * 0.75 + Vector((0, 0, 0.12))
    lo_.rotation_euler = (Vector((0, 0, 0.02)) - lo_.location).to_track_quat("-Z", "Y").to_euler()
    wbg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
    for l_ in list(wbg.inputs["Color"].links):
        sc.world.node_tree.links.remove(l_)
    tent = arg("--light", "tent") == "tent"
    # light tent like the photos: warm-white surround + a soft key from the camera side, a top softbox
    wbg.inputs["Color"].default_value = (0.88, 0.84, 0.77, 1.0) if tent else (0.8, 0.8, 0.8, 1.0)
    wbg.inputs["Strength"].default_value = float(arg("--world", 1.4))
    ld.color = (1.0, 0.965, 0.91) if tent else (1.0, 1.0, 1.0)
    top = bpy.data.lights.get("AU_Top") or bpy.data.lights.new("AU_Top", "AREA")
    top.shape, top.size, top.energy, top.color = "DISK", 0.6, (float(arg("--top", 2.0)) if tent else 0.0), (1.0, 0.96, 0.9)
    to_ = bpy.data.objects.get("AU_Top") or bpy.data.objects.new("AU_Top", top)
    if to_.name not in sc.collection.objects:
        sc.collection.objects.link(to_)
    to_.hide_render = not tent
    to_.location = (0.0, 0.0, 0.55)
    to_.rotation_euler = (0.0, 0.0, 0.0)
    r.filepath = os.path.join(OUT, f"render_{vn}.png")
    r.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    return r.filepath


try:
    FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    FONT_S = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 17)
except Exception:
    FONT = FONT_S = ImageFont.load_default()
metrics = {}
for vn in VIEWS:
    cam, co, C = set_camera(vn)
    w, h = cam["size"]
    ids = render_ids(vn, w, h)
    rpath = os.path.join(OUT, f"render_{vn}.png")
    if "--reuse" in a and os.path.exists(rpath):
        pass
    else:
        rpath = render_cycles(vn, C) if CYCLES else None
    photo = Image.open(cam["image"]).convert("RGB")
    g = cv2.cvtColor(np.asarray(photo), cv2.COLOR_RGB2GRAY)
    g = cv2.GaussianBlur(g, (5, 5), 1.2)
    edges = cv2.Canny(g, 30, 80)
    dist = cv2.distanceTransform((edges == 0).astype(np.uint8), cv2.DIST_L2, 5)
    # zone outlines: pixels whose 4-neighbourhood holds another zone or the background
    pad = np.pad(ids, 1, constant_values=255)
    border = np.zeros_like(ids, bool)
    for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
        border |= pad[dy:dy + h, dx:dx + w] != ids
    fg = ids != 255
    ys, xs = np.where(fg)
    x0, x1 = max(0, xs.min() - 40), min(w, xs.max() + 40)
    y0, y1 = max(0, ys.min() - 40), min(h, ys.max() + 40)
    vm = {}
    for z, (key, lab, col, pre) in enumerate(ZONES):
        m = border & (ids == z)
        m[:6, :] = m[-6:, :] = False
        m[:, :6] = m[:, -6:] = False
        n = int(m.sum())
        if n < 150:
            continue
        d = dist[m]
        obs = [o for o in meshes if zone_of(o.name) == z]
        cen = sum((o.matrix_world @ Vector(c) for o in obs for c in o.bound_box), Vector()) / (8 * len(obs))
        depth = (cen - co.matrix_world.translation).length * 1000.0
        mm_px = depth / cam["f"]
        vm[key] = {"outline_px": n, "median_px": round(float(np.median(d)), 2), "p90_px": round(float(np.percentile(d, 90)), 2),
                   "median_mm": round(float(np.median(d)) * mm_px, 2), "p90_mm": round(float(np.percentile(d, 90)) * mm_px, 2),
                   "within_1mm_pct": round(float((d * mm_px <= 1.0).mean() * 100), 1), "mm_per_px": round(mm_px, 4)}
    metrics[vn] = vm
    # sheet: photo | render | outlines
    box = (x0, y0, x1, y1)
    pc = photo.crop(box)
    if rpath:
        rn = Image.open(rpath).convert("RGBA").resize((w, h), Image.LANCZOS).crop(box)
        rn = Image.alpha_composite(Image.new("RGBA", rn.size, (236, 234, 230, 255)), rn).convert("RGB")
    else:
        rn = Image.new("RGB", pc.size, (236, 234, 230))
    ov = pc.copy()
    arr = np.asarray(ov).copy()
    bc = border[y0:y1, x0:x1]
    ic = ids[y0:y1, x0:x1]
    bc = cv2.dilate(bc.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)
    for z, (key, lab, col, pre) in enumerate(ZONES):
        zm = bc & (cv2.dilate((ic == z).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0)
        arr[zm] = col
    ov = Image.fromarray(arr)
    H = 620
    s = H / pc.height
    W = round(pc.width * s)
    sheet = Image.new("RGB", (W * 3 + 24, H + 76), (255, 255, 255))
    for k, im in enumerate((pc, rn, ov)):
        sheet.paste(im.resize((W, H), Image.LANCZOS), (k * (W + 12), 44))
    dr = ImageDraw.Draw(sheet)
    dr.text((8, 10), f"Foto {vn} ({LABEL.get(vn, vn)})", fill=(20, 20, 20), font=FONT)
    dr.text((W + 20, 10), "Modelo, misma camara", fill=(20, 20, 20), font=FONT)
    dr.text((2 * W + 32, 10), "Contornos del modelo sobre la foto", fill=(20, 20, 20), font=FONT)
    xx = 8
    for key, lab, col, pre in ZONES:
        if key in vm:
            txt = f"{lab} {vm[key]['median_mm']:.1f} mm"
            dr.rectangle((xx, H + 52, xx + 14, H + 66), fill=col)
            dr.text((xx + 20, H + 50), txt, fill=(30, 30, 30), font=FONT_S)
            xx += 30 + int(dr.textlength(txt, font=FONT_S))
    sheet.save(os.path.join(OUT, f"sheet_{vn}.png"))
    json.dump(metrics, open(os.path.join(OUT, "metrics.json"), "w"), indent=1)
    print(f"view {vn} done", flush=True)
print("@@JSON@@" + json.dumps({"ok": True, "metrics": metrics}))
