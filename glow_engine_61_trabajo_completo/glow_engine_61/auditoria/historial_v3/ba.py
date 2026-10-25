"""Multi-view bundle adjustment for the reference photos of the user's engine.

Unknowns: per-view camera (rvec, tvec, log f, principal-point offset), a parametric crankcase
(symmetric screws / lug holes), head (plug height, Allen-screw circle) and free 3D points (carb).
Gauge: plug on the cylinder axis (x=y=0), upper crankcase screws at z=9.4, screw half-spacing 13 mm.
Usage: python3 ba.py obs.json out.json
"""
import json
import math
import sys

import cv2
import numpy as np
from scipy.optimize import least_squares

PARAMS0 = dict(ry=27.85, zl=-15.6, fy=-30.55, lx=25.5, lyf=-10.0, lyr=14.0, lz=0.3,
               zp=77.0, zh=71.0, ra=14.0, rb=14.0, za=72.0, phi=0.0, zu=9.4, yh=-52.0)
SX, ZU, HEAD_HALF = 13.0, 9.4, 1.43


def param_point(name, P):
    """3D point (mm) of a parametric feature, or None if it is a free point."""
    side = 1.0 if name.endswith("_px") else -1.0 if name.endswith("_nx") else 0.0
    base = name.rsplit("_", 1)[0] if side else name
    mid = base.endswith("m")  # "...m" = middle of the screw head (side views)
    b = base[:-1] if mid else base
    if b in ("rsU", "rsL", "fsU", "fsL"):
        y = P["ry"] if b[0] == "r" else P["fy"]
        if mid:
            y += -HEAD_HALF if b[0] == "r" else HEAD_HALF
        z = P["zu"] if b[2] == "U" else P["zl"]
        return np.array([side * SX, y, z])
    if b in ("lugF", "lugR"):
        return np.array([side * P["lx"], P["lyf"] if b == "lugF" else P["lyr"], P["lz"]])
    if name == "plug":
        return np.array([0.0, 0.0, P["zp"]])
    if name.startswith("rim") and P.get("_rim") is not None:
        cx, cy, cz, nx, ny, rr = P["_rim"]
        n = np.array([nx, ny, 1.0]); n /= np.linalg.norm(n)
        a = np.cross(n, [1.0, 0, 0]); a /= np.linalg.norm(a); b = np.cross(n, a)
        th = math.radians(float(name[3:]))
        return np.array([cx, cy, cz]) + rr * (math.cos(th) * a + math.sin(th) * b)
    if name == "hub":
        return np.array([0.0, P["yh"], 0.0])
    if name == "plughex":
        return np.array([0.0, 0.0, P["zh"]])
    if name.startswith("al"):
        a = float(name[2:])
        th = math.radians(a) + P["phi"]
        r = P["ra"] if a in (0.0, 180.0) else P["rb"]
        return np.array([r * math.cos(th), r * math.sin(th), P["za"]])
    return None


def main(obs_path, out_path):
    O = json.load(open(obs_path))
    views = O["views"]
    pnames = list(PARAMS0)
    free = sorted({n for v in views.values() for n in v["pts"] if param_point(n, PARAMS0) is None})
    init_free = O.get("init_free", {})

    def unpack(x):
        i = 0
        cams = {}
        for vn in views:
            cams[vn] = x[i:i + 9]
            i += 9
        P = dict(zip(pnames, x[i:i + len(pnames)]))
        i += len(pnames)
        F = {n: x[i + 3 * k:i + 3 * k + 3] for k, n in enumerate(free)}
        return cams, P, F

    def proj(cam, X, w, h):
        f = math.exp(cam[6])
        K = np.array([[f, 0, w / 2 + cam[7] * w], [0, f, h / 2 + cam[8] * h], [0, 0, 1]])
        p, _ = cv2.projectPoints(np.asarray(X, float).reshape(-1, 3), cam[:3], cam[3:6], K, None)
        return p.reshape(-1, 2)

    def residuals(x):
        cams, P, F = unpack(x)
        r = []
        for vn, v in views.items():
            w, h = v["size"]
            names = list(v["pts"])
            X = [param_point(n, P) if param_point(n, P) is not None else F[n] for n in names]
            pr = proj(cams[vn], X, w, h)
            for k, n in enumerate(names):
                uv, wt = v["pts"][n][:2], (v["pts"][n][2] if len(v["pts"][n]) > 2 else 1.0)
                r.extend(((pr[k] - uv) * wt / v.get("sigma", 2.0)).tolist())
            r.extend([cams[vn][7] / 0.12, cams[vn][8] / 0.12])
        # weak priors keep the parametric crankcase near the earlier estimate
        for k in pnames:
            s = 8.0 if k != "phi" else 0.5
            r.append((P[k] - PARAMS0[k]) / s)
        return np.array(r)

    # ---- initialisation: cameras from parametric points with PnP
    x0 = []
    cam_init = O.get("cam_init", {})
    for vn, v in views.items():
        w, h = v["size"]
        names = [n for n in v["pts"] if param_point(n, PARAMS0) is not None]
        X = np.array([param_point(n, PARAMS0) for n in names])
        U = np.array([v["pts"][n][:2] for n in names], float)
        best = None
        for f0 in np.geomspace(800, 9000, 12):
            K = np.array([[f0, 0, w / 2], [0, f0, h / 2], [0, 0, 1]])
            ok, rv, tv = cv2.solvePnP(X, U, K, None, flags=cv2.SOLVEPNP_SQPNP)
            if not ok:
                continue
            pr, _ = cv2.projectPoints(X, rv, tv, K, None)
            e = float(np.sqrt(((pr.reshape(-1, 2) - U) ** 2).sum(1).mean()))
            if best is None or e < best[0]:
                best = (e, rv.ravel(), tv.ravel(), f0)
        x0 += list(best[1]) + list(best[2]) + [math.log(best[3]), 0.0, 0.0]
        print(f"init {vn}: rms {best[0]:.1f}px f {best[3]:.0f}")
    x0 += [PARAMS0[k] for k in pnames]
    for n in free:
        x0 += list(init_free.get(n, [0.0, -36.0, 25.0]))
    x0 = np.array(x0, float)

    # triangulate free points from the initial cameras (linear DLT over all views)
    cams, P, F = unpack(x0)
    for k, n in enumerate(free):
        A = []
        for vn, v in views.items():
            if n not in v["pts"]:
                continue
            w, h = v["size"]
            c = cams[vn]
            f = math.exp(c[6])
            K = np.array([[f, 0, w / 2], [0, f, h / 2], [0, 0, 1]])
            R, _ = cv2.Rodrigues(c[:3])
            Pm = K @ np.hstack([R, c[3:6].reshape(3, 1)])
            u, vv = v["pts"][n][:2]
            A.append(u * Pm[2] - Pm[0])
            A.append(vv * Pm[2] - Pm[1])
        if len(A) >= 4:
            _, _, Vt = np.linalg.svd(np.array(A))
            Xh = Vt[-1]
            x0[9 * len(views) + len(pnames) + 3 * k:9 * len(views) + len(pnames) + 3 * k + 3] = Xh[:3] / Xh[3]

    sol = least_squares(residuals, x0, method="trf", loss="soft_l1", f_scale=3.0, max_nfev=20000)
    cams, P, F = unpack(sol.x)
    out = {"params": {k: round(float(v), 3) for k, v in P.items()},
           "free": {n: [round(float(a), 2) for a in F[n]] for n in free}, "views": {}}
    for vn, v in views.items():
        w, h = v["size"]
        names = list(v["pts"])
        X = [param_point(n, P) if param_point(n, P) is not None else F[n] for n in names]
        pr = proj(cams[vn], X, w, h)
        err = {n: [round(float(a), 1) for a in (pr[k] - v["pts"][n][:2])] for k, n in enumerate(names)}
        R, _ = cv2.Rodrigues(cams[vn][:3])
        C = (-R.T @ cams[vn][3:6]).ravel()
        f = math.exp(cams[vn][6])
        out["views"][vn] = {"size": [w, h], "f": f, "pp": [w / 2 + cams[vn][7] * w, h / 2 + cams[vn][8] * h],
                            "R": R.tolist(), "t": cams[vn][3:6].tolist(), "C": C.tolist(),
                            "dist_mm": float(np.linalg.norm(C)),
                            "az": math.degrees(math.atan2(C[0], -C[1])),
                            "el": math.degrees(math.atan2(C[2], math.hypot(C[0], C[1]))),
                            "rms": float(np.sqrt(np.mean([a * a + b * b for a, b in err.values()]))),
                            "err": err}
    json.dump(out, open(out_path, "w"), indent=1)
    print(json.dumps(out["params"]))
    for n, p in out["free"].items():
        print("free", n, p)
    for vn, v in out["views"].items():
        print(vn, "rms %.1f px  f %.0f  pp (%.0f,%.0f)  dist %.0f  az %.1f  el %.1f" %
              (v["rms"], v["f"], v["pp"][0], v["pp"][1], v["dist_mm"], v["az"], v["el"]))
        print("   ", {k: e for k, e in v["err"].items() if abs(e[0]) + abs(e[1]) > 6})


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
