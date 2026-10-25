"""Robust single-view camera solve: pose + focal + principal point (with priors) from 2D-3D landmarks.

landmarks json: {"size":[w,h], "points":[{"name","uv":[u,v],"xyz":[x,y,z],"w":1}, ...],
                 "pp_sigma":0.08, "f_range":[400,8000]}
3D in mm (engine frame: X = needle side, -Y = front/prop, Z = up). Output json with K, R, t, C, residuals.
"""
import json
import math
import sys

import cv2
import numpy as np
from scipy.optimize import least_squares


def project(params, X, w, h):
    rv, tv, lf, dcx, dcy = params[:3], params[3:6], params[6], params[7], params[8]
    f = math.exp(lf)
    K = np.array([[f, 0, w / 2 + dcx * w], [0, f, h / 2 + dcy * h], [0, 0, 1]])
    p, _ = cv2.projectPoints(X, rv, tv, K, None)
    return p.reshape(-1, 2), K


def solve(L):
    w, h = L["size"]
    X = np.array([p["xyz"] for p in L["points"]], float)
    U = np.array([p["uv"] for p in L["points"]], float)
    W = np.array([p.get("w", 1.0) for p in L["points"]], float)
    ps = L.get("pp_sigma", 0.08)
    sig = L.get("px_sigma", 2.0)
    best = None
    for f0 in np.geomspace(*L.get("f_range", [500, 8000]), 14):
        K0 = np.array([[f0, 0, w / 2], [0, f0, h / 2], [0, 0, 1]])
        ok, rv, tv = cv2.solvePnP(X, U, K0, None, flags=cv2.SOLVEPNP_SQPNP)
        if not ok:
            continue
        x0 = np.r_[rv.ravel(), tv.ravel(), math.log(f0), 0.0, 0.0]

        def res(x):
            pr, _ = project(x, X, w, h)
            r = ((pr - U) * W[:, None] / sig).ravel()
            return np.r_[r, x[7] / ps, x[8] / ps]
        try:
            sol = least_squares(res, x0, method="lm", max_nfev=4000)
        except Exception:
            continue
        pr, K = project(sol.x, X, w, h)
        R, _ = cv2.Rodrigues(sol.x[:3])
        C = (-R.T @ sol.x[3:6]).ravel()
        depth = (R @ X.T + sol.x[3:6, None])[2]
        if (depth <= 0).any():
            continue
        e = np.linalg.norm(pr - U, axis=1)
        rms = float(np.sqrt((e ** 2).mean()))
        cost = float(sol.cost)
        if best is None or cost < best["cost"]:
            best = dict(cost=cost, rms=rms, K=K.tolist(), R=R.tolist(), t=sol.x[3:6].tolist(), C=C.tolist(),
                        f=float(K[0, 0]), pp=[float(K[0, 2]), float(K[1, 2])],
                        per_point={p["name"]: [round(float(a), 1) for a in (pr[i] - U[i])]
                                   for i, p in enumerate(L["points"])})
    b = best
    C = np.array(b["C"])
    b["size"] = [w, h]
    b["distance_mm"] = float(np.linalg.norm(C))
    b["az_deg"] = math.degrees(math.atan2(C[0], -C[1]))
    b["el_deg"] = math.degrees(math.atan2(C[2], math.hypot(C[0], C[1])))
    b["lens_mm_36"] = b["f"] * 36.0 / w
    return b


if __name__ == "__main__":
    L = json.load(open(sys.argv[1]))
    b = solve(L)
    json.dump(b, open(sys.argv[2], "w"), indent=1)
    print(json.dumps({k: (round(v, 2) if isinstance(v, float) else v) for k, v in b.items()
                      if k in ("rms", "f", "pp", "distance_mm", "az_deg", "el_deg", "lens_mm_36", "per_point")}))
