"""Solve a photo's camera (pose + focal length) from 2D landmarks <-> 3D model points (mm).

Silhouette landmarks on vertical cylinders (head walls) are re-derived from the current camera centre
every iteration (tangent points), so they stay geometrically correct.
Usage: python3 solve_cam.py landmarks.json out.json
landmarks.json: {"image": path, "size": [w, h], "points": [{"name", "uv": [u, v], "xyz": [x, y, z]} |
                 {"name", "uv", "cyl": {"r": r, "z": z, "side": "left"|"right", "cx": 0, "cy": 0}}]}
"""
import json
import math
import sys

import cv2
import numpy as np


def tangent_points(C, r, cx=0.0, cy=0.0):
    dx, dy = C[0] - cx, C[1] - cy
    d = math.hypot(dx, dy)
    th = math.atan2(dy, dx)
    a = math.acos(min(1.0, r / d))
    return [(cx + r * math.cos(th + s * a), cy + r * math.sin(th + s * a)) for s in (1, -1)]


def build(points, C, K, R, t):
    obj, img = [], []
    for p in points:
        if "xyz" in p:
            X = p["xyz"]
        else:
            c = p["cyl"]
            cands = [(x, y, c["z"]) for x, y in tangent_points(C, c["r"], c.get("cx", 0), c.get("cy", 0))]
            if R is None:  # first pass: pick by world Y (front = -Y = image left for these photos)
                X = min(cands, key=lambda q: q[1]) if c["side"] == "left" else max(cands, key=lambda q: q[1])
            else:
                us = [cv2.projectPoints(np.array([q], float), R, t, K, None)[0][0][0][0] for q in cands]
                X = cands[int(np.argmin(us))] if c["side"] == "left" else cands[int(np.argmax(us))]
        obj.append(X)
        img.append(p["uv"])
    return np.array(obj, float), np.array(img, float)


def solve(L, f_range=(300, 20000)):
    w, h = L["size"]
    pts = L["points"]
    best = None
    for f in np.geomspace(*f_range, 160):
        K = np.array([[f, 0, w / 2], [0, f, h / 2], [0, 0, 1]], float)
        C, R, t = (1000.0, -200.0, 50.0), None, None
        ok = True
        for _ in range(6):
            obj, img = build(pts, C, K, R, t)
            if R is None:
                ok, R, t = cv2.solvePnP(obj, img, K, None, flags=cv2.SOLVEPNP_SQPNP)
            else:
                ok, R, t = cv2.solvePnP(obj, img, K, None, R, t, useExtrinsicGuess=True,
                                        flags=cv2.SOLVEPNP_ITERATIVE)
            if not ok:
                break
            Rm, _ = cv2.Rodrigues(R)
            C = tuple((-Rm.T @ t).ravel())
        if not ok:
            continue
        obj, img = build(pts, C, K, R, t)
        proj = cv2.projectPoints(obj, R, t, K, None)[0].reshape(-1, 2)
        err = np.sqrt(((proj - img) ** 2).sum(1))
        rms = float(np.sqrt((err ** 2).mean()))
        Rm, _ = cv2.Rodrigues(R)
        if C[0] < 0 and L.get("expect_positive_x", True) is True:
            continue
        if best is None or rms < best["rms"]:
            best = dict(f=float(f), rms=rms, R=Rm.tolist(), t=t.ravel().tolist(), C=list(C),
                        per_point={p["name"]: round(float(e), 2) for p, e in zip(pts, err)},
                        obj=obj.tolist())
    # refine f around the best with a finer sweep
    return best


if __name__ == "__main__":
    L = json.load(open(sys.argv[1]))
    b = solve(L)
    f0 = b["f"]
    b2 = solve(L, (f0 / 1.15, f0 * 1.15))
    b = b2 if b2 and b2["rms"] <= b["rms"] else b
    w, h = L["size"]
    C = np.array(b["C"])
    b["distance_mm"] = float(np.linalg.norm(C))
    b["lens_mm_36"] = b["f"] * 36.0 / w
    b["az_deg"] = math.degrees(math.atan2(C[0], -C[1]))  # 0 = front (-Y), 90 = +X side
    b["el_deg"] = math.degrees(math.atan2(C[2], math.hypot(C[0], C[1])))
    b["size"] = [w, h]
    json.dump(b, open(sys.argv[2], "w"), indent=1)
    print(json.dumps({k: (round(v, 2) if isinstance(v, float) else v) for k, v in b.items()
                      if k in ("f", "rms", "distance_mm", "lens_mm_36", "az_deg", "el_deg", "per_point", "C")}))
