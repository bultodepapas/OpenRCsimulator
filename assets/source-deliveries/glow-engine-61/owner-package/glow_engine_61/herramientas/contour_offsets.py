"""Signed contour offsets, model vs photo, per part (the measurement a modeller needs to correct a shape).

For every outline pixel of every part (object-ID pass from the solved photo camera) the photo edge is searched
ALONG THE OUTLINE NORMAL, +-3 mm: the strongest photo gradient across the outline (colour + luminance, lightly
weighted toward small offsets) gives the signed offset.  + = the photo edge lies OUTSIDE the model (model too small
there), - = inside (model too big).  The pixel's own depth turns pixels into mm; its ray gives the 3D point.

blender -b model_with_photo_cams.blend -P contour_offsets.py -- --out DIR [--views ...] [--parts ENG_Crankcase ...]
  -> DIR/offs_<V>.png (red: model too small, blue: too big, green: within 0.5 mm, grey: no clear photo edge),
     DIR/offsets.json (per view, per part: n, coverage, median signed mm, p90 |mm|, and the outline samples)
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


OUT = lst("--out", ["/tmp/claude-0/offs"])[0]
VIEWS = lst("--views", ["A", "Ac", "B", "B2", "D", "E", "T"])
ONLY = lst("--parts", [])
SEARCH_MM = float(lst("--search", ["3.0"])[0])
KEEP_SAMPLES = "--samples" in a
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


lv = [0.03 + 0.94 * k / 11 for k in range(12)]
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


def photo_gradient(path):
    rgb = np.asarray(Image.open(path).convert("RGB"))
    lab = cv2.cvtColor(cv2.GaussianBlur(rgb, (0, 0), 1.4), cv2.COLOR_RGB2LAB).astype(np.float32)
    gx = np.zeros(lab.shape[:2], np.float32)
    gy = np.zeros_like(gx)
    best = np.zeros_like(gx)
    for ch, wgt in ((0, 1.0), (1, 1.6), (2, 1.6)):     # chroma edges count (gold head on silver cylinder)
        sx = cv2.Sobel(lab[..., ch], cv2.CV_32F, 1, 0, ksize=3) * wgt
        sy = cv2.Sobel(lab[..., ch], cv2.CV_32F, 0, 1, ksize=3) * wgt
        m = sx * sx + sy * sy
        upd = m > best
        gx[upd], gy[upd], best[upd] = sx[upd], sy[upd], m[upd]
    return gx, gy


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
    cd = bpy.data.cameras.new("CO_" + vn)
    cd.sensor_fit, cd.sensor_width, cd.lens = "HORIZONTAL", 36.0, f * 36.0 / w
    cd.shift_x, cd.shift_y = (w / 2 - cx) / max(w, h), (cy - h / 2) / max(w, h)
    cd.clip_start, cd.clip_end = 0.005, 20
    co = bpy.data.objects.new("CO_" + vn, cd)
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
    gx, gy = photo_gradient(cam["image"])
    dg = bpy.context.evaluated_depsgraph_get()
    Rt = R.T
    o0 = Vector(Cm)
    present = [j for j in np.unique(oid) if j >= 0]
    canvas = (np.asarray(Image.open(cam["image"]).convert("RGB")).astype(float) * 0.5 + 60).astype(np.uint8)
    vrep = {}
    for j in present:
        name = meshes[j].name
        if ONLY and name not in ONLY:
            continue
        mk = (oid == j).astype(np.uint8)
        ys_, xs_ = np.where(mk > 0)
        if len(xs_) < 300:
            continue
        pad = 70
        x0, x1 = max(0, xs_.min() - pad), min(w, xs_.max() + pad)
        y0, y1 = max(0, ys_.min() - pad), min(h, ys_.max() + pad)
        sub = mk[y0:y1, x0:x1]
        er = cv2.erode(sub, np.ones((3, 3), np.uint8))
        bd = (sub > 0) & (er == 0)
        bd[:3, :] = bd[-3:, :] = False
        bd[:, :3] = bd[:, -3:] = False
        by, bx = np.where(bd)
        if len(bx) < 60:
            continue
        sm = cv2.GaussianBlur(sub.astype(np.float32), (0, 0), 2.0)
        ny_, nx_ = cv2.Sobel(sm, cv2.CV_32F, 0, 1, ksize=3), cv2.Sobel(sm, cv2.CV_32F, 1, 0, ksize=3)
        nx, ny = -nx_[by, bx], -ny_[by, bx]                       # outward = down the mask gradient
        nn = np.hypot(nx, ny) + 1e-9
        nx, ny = nx / nn, ny / nn
        X, Y = bx + x0, by + y0
        # neighbour across the outline: background or another part (who occludes whom)
        ox = np.clip(np.round(X + 3 * nx).astype(int), 0, w - 1)
        oy = np.clip(np.round(Y + 3 * ny).astype(int), 0, h - 1)
        other = oid[oy, ox]
        # depth per sample (every 3rd ray, nearest fill)
        depth = np.zeros(len(X))
        P3 = np.zeros((len(X), 3))
        for k in range(0, len(X), 3):
            dvec = Rt @ np.array([(X[k] + 0.5 - cx) / f, (Y[k] + 0.5 - cy) / f, 1.0])
            dvec /= np.linalg.norm(dvec)
            res = sc.ray_cast(dg, o0, Vector(dvec))
            if res[0] and res[4] is not None and res[4].name == name:
                depth[k] = (res[1] - o0).length * 1000.0
                P3[k] = np.array(res[1]) * 1000.0
        for k in range(len(X)):
            if depth[k] == 0:
                k0 = (k // 3) * 3
                depth[k], P3[k] = depth[k0], P3[k0]
        good_d = depth > 0
        if not good_d.any():
            continue
        depth[~good_d] = np.median(depth[good_d])
        mmpx = depth / f
        S = np.clip(SEARCH_MM / mmpx, 6, 60)
        steps = np.linspace(-1, 1, 49)
        offs = np.full(len(X), np.nan)
        strength = np.zeros(len(X))
        for si, s in enumerate(steps):
            px = (X + s * S * nx).astype(np.float32)
            py = (Y + s * S * ny).astype(np.float32)
            gxs = cv2.remap(gx, px.reshape(1, -1), py.reshape(1, -1), cv2.INTER_LINEAR).ravel()
            gys = cv2.remap(gy, px.reshape(1, -1), py.reshape(1, -1), cv2.INTER_LINEAR).ravel()
            g = np.abs(gxs * nx + gys * ny) * np.exp(-0.7 * s * s)
            upd = g > strength
            strength[upd] = g[upd]
            offs[upd] = s * S[upd]
        valid = strength > 60.0                        # Sobel units on Lab (a clear edge)
        off_mm = offs * mmpx
        om = off_mm[valid]
        rec = {"n": int(len(X)), "coverage_pct": round(100 * valid.mean(), 1)}
        if len(om) >= 30:
            rec.update({"median_signed_mm": round(float(np.median(om)), 2), "p90_abs_mm": round(float(np.percentile(np.abs(om), 90)), 2),
                        "within_0p5_pct": round(float((np.abs(om) <= 0.5).mean() * 100), 1),
                        "too_small_px": int((om > 0.7).sum()), "too_big_px": int((om < -0.7).sum())})
            if KEEP_SAMPLES:
                kk = np.where(valid)[0][::2]
                rec["samples"] = [[int(X[k]), int(Y[k]), round(float(off_mm[k]), 2), round(float(nx[k]), 2), round(float(ny[k]), 2),
                                   int(other[k])] + P3[k].round(2).tolist() for k in kk]
        vrep[name] = rec
        col = np.zeros((len(X), 3), np.uint8)
        col[:] = (150, 150, 150)
        v_ = valid
        col[v_ & (np.abs(off_mm) <= 0.5)] = (40, 200, 60)
        col[v_ & (off_mm > 0.5)] = (255, 150, 0)
        col[v_ & (off_mm > 1.0)] = (235, 30, 30)
        col[v_ & (off_mm < -0.5)] = (60, 170, 255)
        col[v_ & (off_mm < -1.0)] = (40, 60, 240)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                canvas[np.clip(Y + dy, 0, h - 1), np.clip(X + dx, 0, w - 1)] = col
    report[vn] = vrep
    img = Image.fromarray(canvas)
    img.save(os.path.join(OUT, f"offs_{vn}.png"))
    bpy.data.objects.remove(co)
    print(f"view {vn} done", flush=True)
json.dump({"names": [o.name for o in meshes], "views": report}, open(os.path.join(OUT, "offsets.json"), "w"), indent=1)
summ = {}
for vn, vr in report.items():
    for k, q in vr.items():
        if "median_signed_mm" in q:
            summ.setdefault(k, []).append((vn, q["median_signed_mm"], q["p90_abs_mm"], q["within_0p5_pct"], q["coverage_pct"]))
print("@@JSON@@" + json.dumps(summ))
