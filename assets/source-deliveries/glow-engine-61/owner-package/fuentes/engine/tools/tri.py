"""Triangulate named features from pixel observations in the solved model-frame cameras.
python3 tri.py '{"Kss": {"Ac": [393,846], "E": [1302,1273]}, ...}'"""
import json, sys
import numpy as np, cv2
from scipy.optimize import least_squares
cams = {}
def cam(vn):
    if vn not in cams:
        v = json.load(open(f"/home/claude/engine/cams/cam_{vn}.json"))
        K = np.array([[v["f"], 0, v["pp"][0]], [0, v["f"], v["pp"][1]], [0, 0, 1]])
        R = np.array(v["R"]); t = np.array(v["t"])
        cams[vn] = (K, R, t)
    return cams[vn]
def proj(vn, X):
    K, R, t = cam(vn)
    return cv2.projectPoints(np.array([X], float), cv2.Rodrigues(R)[0], t, K, None)[0].ravel()
def tri(obs):
    A = []
    for vn, (u, v) in obs.items():
        K, R, t = cam(vn); Pm = K @ np.hstack([R, t.reshape(3, 1)])
        A += [u * Pm[2] - Pm[0], v * Pm[2] - Pm[1]]
    X = np.linalg.svd(np.array(A))[2][-1]; X = X[:3] / X[3]
    X = least_squares(lambda X: np.concatenate([proj(vn, X) - np.array(o) for vn, o in obs.items()]), X).x
    return X, {vn: (proj(vn, X) - np.array(o)).round(1).tolist() for vn, o in obs.items()}
if __name__ == "__main__":
    D = json.loads(sys.argv[1])
    for n, obs in D.items():
        X, e = tri(obs)
        print(f"{n:8s} {X.round(2).tolist()}  err {e}")
