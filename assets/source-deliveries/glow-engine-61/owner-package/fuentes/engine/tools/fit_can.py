"""Fit the muffler can (axis + size) to silhouette points picked in photos B, A and T (solved cameras).

python3 fit_can.py  -> prints fitted MUF parameters (mm, model frame)
"""
import json
import math
import sys

import cv2
import numpy as np
from scipy.optimize import least_squares

sys.path.insert(0, "/home/claude/engine")
CAM = {}


def cam(vn):
    if vn not in CAM:
        v = json.load(open(f"/home/claude/engine/cams/cam_{vn}.json"))
        K = np.array([[v["f"], 0, v["pp"][0]], [0, v["f"], v["pp"][1]], [0, 0, 1]])
        CAM[vn] = (K, cv2.Rodrigues(np.array(v["R"]))[0], np.array(v["t"], float))
    return CAM[vn]


def project(vn, P):
    K, rv, t = cam(vn)
    return cv2.projectPoints(P.reshape(-1, 1, 3).astype(float), rv, t, K, None)[0].reshape(-1, 2)


# ---- observations (original pixel coordinates)
SIL = json.load(open("/home/claude/engine/muf/sil.json"))
OBS = {"B": [], "A": [], "T": [], "E": []}
OBS["E"] = [("right", r, x) for r, x in ((10, 179), (25, 179), (40, 181), (55, 184), (70, 185), (85, 185), (100, 184),
            (115, 182), (130, 178), (145, 176), (160, 173), (175, 171), (190, 169), (205, 171), (235, 169), (250, 157),
            (265, 154), (280, 151), (295, 148), (310, 147))]
for kind, c, v in SIL["B"]:
    if kind == "bot" and c > 590:
        continue
    OBS["B"].append((kind, c, v))
for kind, c, v in SIL["A"]:
    if kind == "bot":
        continue                      # auto bottom hits the soft shadow: use the manual picks below
    OBS["A"].append((kind, c, v))
OBS["A"] += [("bot", u, v) for u, v in ((1050, 292), (1100, 288), (1150, 281), (1200, 272), (1250, 262), (1300, 250),
                                        (1350, 233), (1400, 213), (1450, 210))]
for kind, c, v in SIL["T"]:
    if kind == "right" and 590 <= c <= 700:
        continue                      # propeller blade behind the can
    OBS["T"].append((kind, c, v))
P0 = dict(tip=(-53.4, -37.0, 53.1), end=(-78.2, 112.2, 50.7), R=17.6, dome=13.0, seam=79.5,
          taper=((80.0, 17.6), (85.5, 17.45), (90.9, 17.1), (96.5, 16.6), (102.3, 15.9), (108.0, 15.0), (113.7, 13.8),
                 (119.5, 12.2), (125.0, 10.3), (129.5, 8.5), (133.5, 7.0), (137.0, 6.0)),
          out_r=5.6, out_len=13.0)


def profile(p, L):
    """(s, r) of the can: elliptic front cap, cylinder to the seam, cone with 3 free radii, outlet tube."""
    R, dome, fseam, c1, c2, c3, out_r = p[6], p[7], p[8], p[9], p[10], p[11], p[12]
    so = L - P0["out_len"]
    sseam = fseam * so
    s_list, r_list = [], []
    for i in range(1, 25):
        t = math.pi / 2 * i / 24
        s_list.append(dome * (1 - math.cos(t)))
        r_list.append(R * math.sin(t))
    s_list.append(sseam); r_list.append(R)
    for f_, c_ in ((0.25, c1), (0.5, c2), (0.75, c3)):
        s_list.append(sseam + f_ * (so - sseam)); r_list.append(out_r + c_ * (R - out_r))
    s_list += [so, so + 0.6, L - 0.3]
    r_list += [out_r + 0.4, out_r, out_r]
    return np.array(s_list), np.array(r_list)


def surface(p):
    F, O = np.array(p[0:3]), np.array(p[3:6])
    d = O - F
    L = np.linalg.norm(d)
    ax = d / L
    s, r = profile(p, L)
    ss = np.linspace(0, L - 0.3, 300)
    rr = np.interp(ss, s, r)
    a = np.cross(ax, [0, 0, 1.0]); a /= np.linalg.norm(a)
    b = np.cross(ax, a)
    th = np.linspace(0, 2 * np.pi, 160, endpoint=False)
    kx = p[13] if len(p) > 13 else 1.0      # horizontal / vertical semi-axis ratio of the cross-section
    P = (F[None, None, :] + ss[:, None, None] * ax[None, None, :]
         + rr[:, None, None] * (kx * np.cos(th)[None, :, None] * a[None, None, :] + np.sin(th)[None, :, None] * b[None, None, :]))
    return P.reshape(-1, 3)


# outlet end faces (tube ends): B from the left, A from the right
OBS["B"] += [("left", r, x) for r, x in ((550, 76), (560, 73), (570, 70), (580, 69), (590, 69), (600, 68), (610, 68),
                                         (620, 69), (630, 70), (640, 72))]
OBS["A"] += [("right", r, x) for r, x in ((168, 1474), (176, 1476), (184, 1478), (192, 1477), (200, 1477), (208, 1475),
                                          (216, 1472))]
if "-Tup" in sys.argv:   # can +X edge just above / beside the manifold arm (read off the T close-up)
    OBS["T"] += [("left", r, 1196) for r in range(580, 770, 30)]
USE = [v for v in ("B", "A", "T", "E") if "-no" + v not in sys.argv]


def residuals(p, verbose=False, views=None):
    P = surface(p)
    res = []
    for vn, obs in OBS.items():
        if vn not in (views or USE):
            continue
        uv = project(vn, P)
        for kind, c, val in obs:
            if kind in ("top", "bot"):
                m = np.abs(uv[:, 0] - c) < 2.0
                if not m.any():
                    res.append(50.0); continue
                pred = uv[m, 1].min() if kind == "top" else uv[m, 1].max()
            else:
                m = np.abs(uv[:, 1] - c) < 2.0
                if not m.any():
                    res.append(50.0); continue
                pred = uv[m, 0].min() if kind == "left" else uv[m, 0].max()
            res.append(pred - val)
            if verbose:
                print(f"  {vn} {kind:5s} @{c:5.0f}: pred {pred:7.1f} obs {val:6.0f} d {pred - val:6.1f}")
    return np.array(res)


# start: current model (seam 79.5 of a 138.3 body, cone radii read off the old taper table)
p0 = np.array([-60.0, -37.0, 50.0, -79.0, 113.0, 50.0, 17.6, 13.0, 79.5 / 138.3, 0.84, 0.55, 0.22, 5.6, 1.0])
lo = [-90, -50, 35, -100, 95, 35, 14, 6, 0.4, 0.4, 0.2, 0.0, 4.5, 0.8]
hi = [-40, -25, 65, -60, 130, 65, 21, 22, 0.75, 1.1, 0.9, 0.6, 7.0, 1.25]
r0 = residuals(p0)
print("start rms", np.sqrt(np.mean(r0 ** 2)).round(2), "n obs", len(r0))
if "-kx1" in sys.argv:
    lo[13], hi[13], p0[13] = 0.999, 1.001, 1.0
if "-dome" in sys.argv:
    dv = float(sys.argv[sys.argv.index("-dome") + 1]); lo[7], hi[7], p0[7] = dv - 0.01, dv + 0.01, dv
fit = least_squares(residuals, p0, bounds=(lo, hi), diff_step=1e-3, loss="soft_l1", f_scale=4.0)
for vn in ("B", "A", "T", "E"):
    rr = residuals(fit.x, views=[vn])
    print(f"  {vn}: n {len(rr)} rms {np.sqrt(np.mean(rr**2)):.2f} mean {rr.mean():.2f}")
print("fit rms", np.sqrt(np.mean(fit.fun ** 2)).round(2))
if "-v" in sys.argv:
    residuals(fit.x, verbose=True, views=["B", "A", "T", "E"])
x = fit.x
for vn in OBS:
    rr = residuals(x)  # noqa
L = float(np.linalg.norm(x[3:6] - x[0:3]))
res = {"tip": x[0:3].round(2).tolist(), "end": x[3:6].round(2).tolist(), "R": round(x[6], 2), "dome": round(x[7], 2),
       "seam": round(x[8] * (L - P0["out_len"]), 2), "cone": [round(v, 3) for v in x[9:12]], "out_r": round(x[12], 2), "kx": round(x[13], 3),
       "length": round(L, 2)}
print(json.dumps(res))
outp = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else "/home/claude/engine/muf/can_fit.json"
json.dump(res, open(outp, "w"))
