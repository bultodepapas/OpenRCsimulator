"""Solve the top-rear photo (86b5c288) camera from engine landmarks (model frame, mm); writes cams/cam_T.json."""
import json
import numpy as np, cv2
from scipy.optimize import least_squares
IMG = "/root/.claude/uploads/5aad6050-4747-5d68-bd16-c5cdce93a416/86b5c288-image.png"
obs = [((8, -13.86, 66.6), (805, 505)),
       ((-8, -13.86, 66.6), (930, 510)), ((8, 13.86, 66.6), (815, 652)), ((-8, 13.86, 66.6), (935, 655)),
       ((0, 0, 75.4), (876, 534)), ((13, 28.3, 9.4), (740, 982)), ((-13, 28.3, 9.4), (930, 990)),
       ((13, 28.3, -15.6), (720, 1107)), ((-13, 28.3, -15.6), (907, 1110)),
       ((25.5, -10, 0.3), (664, 826)), ((25.5, 14, 0.3), (664, 936)), ((-25.5, -10, 0.3), (990, 844)), ((-25.5, 14, 0.3), (992, 950))]
X = np.array([o[0] for o in obs], float); U = np.array([o[1] for o in obs], float)
W = H = 1600
def resid(p):
    f, rv, t = p[0], p[1:4], p[4:7]
    K = np.array([[f, 0, W / 2], [0, f, H / 2], [0, 0, 1]])
    return (cv2.projectPoints(X, rv, t, K, None)[0].reshape(-1, 2) - U).ravel()
best = None
for f0 in (1500, 2500, 3500, 5000):
    K = np.array([[f0, 0, W / 2], [0, f0, H / 2], [0, 0, 1]])
    ok, rv, t = cv2.solvePnP(X, U, K, None, flags=cv2.SOLVEPNP_SQPNP)
    r = least_squares(resid, np.concatenate([[f0], rv.ravel(), t.ravel()]))
    e = np.sqrt(np.mean(r.fun ** 2))
    if best is None or e < best[0]:
        best = (e, r.x)
e, p = best
R = cv2.Rodrigues(p[1:4])[0]; t = p[4:7]; C = -R.T @ t
res = resid(p).reshape(-1, 2)
print("rms px", round(e, 2), "f", round(p[0], 1), "C", C.round(1), "max", np.abs(res).max().round(1))
for (x, u), rr in zip(obs, res):
    print(x, u, rr.round(1))
json.dump({"size": [W, H], "f": float(p[0]), "pp": [W / 2, H / 2], "R": R.tolist(), "C": C.tolist(), "t": t.tolist(),
           "image": IMG}, open("/home/claude/engine/cams/cam_T.json", "w"))
