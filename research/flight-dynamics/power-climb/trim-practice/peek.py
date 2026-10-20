"""Print 1 Hz samples of key channels for a time window (read-only). Usage: peek.py FILE kind t0 t1"""
import sys
import numpy as np
sys.path.insert(0, ".")
import trim_curve as tc
p, kind, t0, t1 = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
d = tc.load_baldr(p) if kind == "b" else tc.load_thor(p, int(kind))
t = d["t"]; fs = 1 / np.median(np.diff(t)); n1 = int(round(fs))
sm = {k: tc.movavg(d[k], n1) for k in d if isinstance(d[k], np.ndarray) and d[k].shape == t.shape}
print("   t     V   h     phi   theta  climb   de    thr   q(dps)  nz   flap")
for tt in np.arange(t0, t1, 1.0):
    i = np.searchsorted(t, tt)
    if i >= len(t):
        break
    print(f"{tt:6.0f} {sm['ias'][i]:5.1f} {d['h'][i]:5.0f} {sm['phi'][i]:6.1f} {sm['theta'][i]:6.1f} {sm['climb'][i]:5.1f} {sm['de'][i]:6.2f} {sm['thr'][i]:5.2f} {np.degrees(sm['q'][i]):6.1f} {-sm['az'][i]/9.80665:5.2f} {sm['flap'][i]:5.1f}")
