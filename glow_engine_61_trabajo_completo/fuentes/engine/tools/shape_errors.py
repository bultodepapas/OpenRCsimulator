"""Where is the shape wrong?  Per photo view: every outline pixel of every part (object-ID pass from the solved camera)
is measured to the nearest photo edge, converted to mm with that pixel's own depth, and attributed to the part.
The rays of the off pixels give the 3D place of each error on the model.

blender -b model_with_photo_cams.blend -P shape_errors.py -- --out DIR [--views A Ac ...] [--tol 1.0]
writes DIR/heat_<V>.png (green <= 0.5 mm, yellow <= tol, red > tol, top parts labelled) and DIR/shape_errors.json
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


def lst(k, d):
    if k not in a:
        return d
    i, out = a.index(k) + 1, []
    while i < len(a) and not a[i].startswith("--"):
        out.append(a[i])
        i += 1
    return out


OUT = lst("--out", ["/tmp/claude-0/shape"])[0]
VIEWS = lst("--views", ["A", "Ac", "B", "B2", "D", "E", "T"])
TOL = float(lst("--tol", ["1.0"])[0])
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
r = sc.render
ACCESSORY = ("ENG_Spinner", "ENG_Prop_Blades")
for c in bpy.data.collections:
    if c.name.endswith("Muffler") or c.name.endswith("Prop"):
        c.hide_render = False
    if c.name.endswith("Analysis"):
        c.hide_render = True
for o in bpy.data.objects:
    if o.name.startswith(("LD_", "PHOTO_", "ANL_", "CUT_", "CMP_", "FIT_", "MO_", "PV_", "MV_", "AU_")):
        o.hide_render = True
root = bpy.data.objects.get("Glow_Engine_61")
if root is not None and "cutaway" in root.keys():
    root["cutaway"] = 0
bpy.context.view_layer.update()
meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render
          and all(not c.hide_render for c in o.users_collection)]


def srgb(v):
    return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


lv = [0.03 + 0.94 * k / 11 for k in range(12)]                       # 12 well separated sRGB levels per channel
for i, o in enumerate(meshes):
    o.color = (lv[i % 12] ** 2.2, lv[(i // 12) % 12] ** 2.2, lv[i // 144] ** 2.2, 1.0)
codes = np.array([[round(255 * srgb(c)) for c in o.color[:3]] for o in meshes])
r.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light, sh.color_type = "FLAT", "OBJECT"
sh.show_cavity = sh.show_shadows = sh.show_object_outline = False
sc.display.render_aa = "OFF"
r.film_transparent = True
r.resolution_percentage = 100
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.view_settings.exposure, sc.view_settings.gamma = 0.0, 1.0
r.dither_intensity = 0.0
try:
    FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
except Exception:
    FONT = ImageFont.load_default()
report = {}
for vn in VIEWS:
    cam = json.load(open(f"/home/claude/engine/cams/cam_{vn}.json"))
    R = np.array(cam["R"]); C = np.array(cam["C"])
    w, h = cam["size"]
    f, (cx, cy) = cam["f"], cam["pp"]
    if root is not None:
        root["crank_deg"] = float(cam.get("prop_deg", 0.0))
        root.update_tag()
        bpy.context.view_layer.update()
    cd = bpy.data.cameras.new("SE_" + vn)
    cd.sensor_fit, cd.sensor_width, cd.lens = "HORIZONTAL", 36.0, f * 36.0 / w
    cd.shift_x, cd.shift_y = (w / 2 - cx) / max(w, h), (cy - h / 2) / max(w, h)
    cd.clip_start, cd.clip_end = 0.005, 20
    co = bpy.data.objects.new("SE_" + vn, cd)
    sc.collection.objects.link(co)
    Cm = C * 0.001
    co.matrix_world = Matrix(((R[0, 0], -R[1, 0], -R[2, 0], Cm[0]), (R[0, 1], -R[1, 1], -R[2, 1], Cm[1]),
                              (R[0, 2], -R[1, 2], -R[2, 2], Cm[2]), (0, 0, 0, 1)))
    sc.camera = co
    r.resolution_x, r.resolution_y = w, h
    r.filepath = os.path.join(OUT, f"_id_{vn}.png")
    bpy.ops.render.render(write_still=True)
    im = np.asarray(Image.open(r.filepath).convert("RGBA")).astype(int)
    os.remove(r.filepath)
    oid = np.full((h, w), -1, int)
    fg = im[..., 3] > 200
    cols, inv = np.unique(im[..., :3][fg], axis=0, return_inverse=True)
    lut = np.full(len(cols), -1)
    for k, cval in enumerate(cols):
        dd = np.abs(codes - cval).max(1)
        j = int(dd.argmin())
        lut[k] = j if dd[j] <= 2 else -1
    oid[fg] = lut[inv.ravel()]
    # photo edges and distance field (same settings as audit_views)
    g = cv2.GaussianBlur(cv2.cvtColor(np.asarray(Image.open(cam["image"]).convert("RGB")), cv2.COLOR_RGB2GRAY), (5, 5), 1.2)
    dist = cv2.distanceTransform((cv2.Canny(g, 30, 80) == 0).astype(np.uint8), cv2.DIST_L2, 5)
    pad = np.pad(oid, 1, constant_values=-1)
    border = np.zeros((h, w), bool)
    for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
        border |= pad[dy:dy + h, dx:dx + w] != oid
    border &= oid >= 0
    border[:6, :] = border[-6:, :] = False
    border[:, :6] = border[:, -6:] = False
    ys, xs = np.where(border)
    # per-pixel depth by ray cast (every 2nd pixel, nearest-neighbour fill for the rest)
    dg = bpy.context.evaluated_depsgraph_get()
    Rt = R.T
    depth = np.zeros(len(xs))
    hit = np.zeros((len(xs), 3))
    o0 = Vector(Cm)
    for k in range(0, len(xs), 2):
        dvec = Rt @ np.array([(xs[k] + 0.5 - cx) / f, (ys[k] + 0.5 - cy) / f, 1.0])
        dvec /= np.linalg.norm(dvec)
        res = sc.ray_cast(dg, o0, Vector(dvec))
        if res[0]:
            depth[k] = (res[1] - o0).length * 1000.0
            hit[k] = np.array(res[1]) * 1000.0
    for k in range(1, len(xs), 2):
        depth[k], hit[k] = depth[k - 1], hit[k - 1]
    dmm = dist[ys, xs] * np.where(depth > 0, depth, np.median(depth[depth > 0])) / f
    parts = {}
    for k in range(len(xs)):
        parts.setdefault(int(oid[ys[k], xs[k]]), []).append(k)
    rows = []
    for j, ks in parts.items():
        ks = np.array(ks)
        d = dmm[ks]
        bad = ks[d > TOL]
        name = meshes[j].name
        rows.append({"part": name, "outline_px": int(len(ks)), "median_mm": round(float(np.median(d)), 2),
                     "p90_mm": round(float(np.percentile(d, 90)), 2), "over_tol_px": int(len(bad)),
                     "over_tol_pct": round(100 * len(bad) / len(ks), 1),
                     "excess_mm_px": round(float(np.clip(d - TOL, 0, None).sum()), 1),
                     "bad_center_px": [int(xs[bad].mean()), int(ys[bad].mean())] if len(bad) else None,
                     "bad_center_mm": hit[bad][depth[bad] > 0].mean(0).round(1).tolist() if (depth[bad] > 0).any() else None,
                     "accessory": name.startswith(ACCESSORY)})
    rows.sort(key=lambda q: -q["excess_mm_px"])
    report[vn] = rows
    # heat map: photo, outlines coloured by error
    ph = np.asarray(Image.open(cam["image"]).convert("RGB")).astype(float) * 0.55 + 255 * 0.45 * 0.35
    ph = ph.astype(np.uint8)
    col = np.zeros((len(xs), 3), np.uint8)
    col[:] = (40, 190, 60)
    col[dmm > 0.5] = (240, 200, 0)
    col[dmm > TOL] = (230, 30, 30)
    canvas = ph.copy()
    for k in range(len(xs)):
        canvas[max(0, ys[k] - 1):ys[k] + 2, max(0, xs[k] - 1):xs[k] + 2] = col[k]
    img = Image.fromarray(canvas)
    dr = ImageDraw.Draw(img)
    n = 0
    for q in rows:
        if q["accessory"] or not q["bad_center_px"] or q["over_tol_px"] < 40:
            continue
        x_, y_ = q["bad_center_px"]
        dr.ellipse((x_ - 6, y_ - 6, x_ + 6, y_ + 6), outline=(255, 255, 255), width=3)
        lab = f"{q['part'].replace('ENG_', '').replace('MUF_', 'M:').replace('CARB_', 'C:')} p90 {q['p90_mm']}"
        dr.text((x_ + 10, y_ - 10), lab, fill=(255, 255, 255), font=FONT, stroke_width=3, stroke_fill=(0, 0, 0))
        n += 1
        if n >= 8:
            break
    img.save(os.path.join(OUT, f"heat_{vn}.png"))
    bpy.data.objects.remove(co)
    print(f"view {vn} done", flush=True)
json.dump(report, open(os.path.join(OUT, "shape_errors.json"), "w"), indent=1)
# ranking over all views: summed excess (mm * px) per part, accessories apart
tot = {}
for vn, rows in report.items():
    for q in rows:
        t = tot.setdefault(q["part"], {"excess": 0.0, "views": []})
        t["excess"] += q["excess_mm_px"]
        if q["over_tol_pct"] >= 10 and q["over_tol_px"] >= 40:
            t["views"].append(f"{vn}:{q['p90_mm']}")
rank = sorted(((k, round(v["excess"], 1), v["views"]) for k, v in tot.items() if not k.startswith(ACCESSORY)), key=lambda t: -t[1])
json.dump({"rank": rank}, open(os.path.join(OUT, "rank.json"), "w"), indent=1)
print("@@JSON@@" + json.dumps({"rank": rank[:25]}))
