"""Similarity-align the BA frame to the model frame using body features; export model-frame cameras
and carb points. Usage: python3 ba_to_model.py ba.json out.json"""
import json, sys, math
import numpy as np
sys.path.insert(0, "/home/claude/engine/tools")
from ba import param_point
B = json.load(open(sys.argv[1])); P = B["params"]
names = ["rsU_px", "rsU_nx", "rsL_px", "rsL_nx", "fsU_nx", "fsL_nx", "lugF_px", "lugR_px", "lugF_nx", "lugR_nx", "plug"]
def mdl(n):
    side = 1 if n.endswith("_px") else -1
    b = n.rsplit("_", 1)[0] if n.endswith(("_px", "_nx")) else n
    if b in ("rsU", "rsL"): return (side * 13, 27.85, 9.4 if b == "rsU" else -15.6)
    if b in ("fsU", "fsL"): return (side * 13, -30.55, 9.4 if b == "fsU" else -15.6)
    if b == "lugF": return (side * 25.5, -10, 0.3)
    if b == "lugR": return (side * 25.5, 14, 0.3)
    if n == "plug": return (0, 0, 76.84)
X = np.array([param_point(n, P) for n in names]); Y = np.array([mdl(n) for n in names], float)
mx, my = X.mean(0), Y.mean(0); Xc, Yc = X - mx, Y - my
U, S, Vt = np.linalg.svd(Yc.T @ Xc); D = np.eye(3); D[2, 2] = np.sign(np.linalg.det(U @ Vt))
R = U @ D @ Vt; s = (S * np.diag(D)).sum() / (Xc ** 2).sum(); t = my - s * R @ mx
tf = lambda p: s * R @ np.asarray(p, float) + t
out = {"scale": s, "R": R.tolist(), "t": t.tolist(), "free": {n: tf(p).round(2).tolist() for n, p in B["free"].items()},
       "body_resid": {n: (tf(param_point(n, P)) - np.array(mdl(n))).round(2).tolist() for n in names}, "views": {}}
for vn, v in B["views"].items():
    Rc = np.array(v["R"]); C = np.array(v["C"])
    Cm = tf(C); Rm = Rc @ R.T
    out["views"][vn] = {"size": v["size"], "f": v["f"], "pp": v["pp"], "R": Rm.tolist(), "C": Cm.tolist(),
                        "t": (-Rm @ Cm).tolist()}
json.dump(out, open(sys.argv[2], "w"), indent=1)
print("scale", round(s, 4))
for n, p in out["free"].items(): print("carb", n, p)
