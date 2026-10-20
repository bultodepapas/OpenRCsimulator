"""Print per-channel stats of UMN logs (read-only). Usage: python3 -I stats_logs.py FILE [keys...]"""
import sys
import numpy as np
import scipy.io as sio

path = sys.argv[1]
keys = sys.argv[2:]
m = sio.loadmat(path, squeeze_me=True, struct_as_record=False)
top = {k: v for k, v in m.items() if not k.startswith("__")}
# flatten one level of struct
flat = {}
for k, v in top.items():
    if hasattr(v, "_fieldnames"):
        for f in v._fieldnames:
            a = getattr(v, f)
            if hasattr(a, "_fieldnames"):
                for g in a._fieldnames:
                    flat[f"{k}.{f}.{g}"] = getattr(a, g)
            else:
                flat[f"{k}.{f}"] = a
    else:
        flat[k] = v
for k, v in flat.items():
    if keys and not any(s in k for s in keys):
        continue
    arr = np.asarray(v)
    if arr.dtype.kind in "fiu" and arr.size > 1:
        arr = arr.astype(float)
        print(f"{k:40s} n={arr.size:7d} min={np.nanmin(arr):10.4g} p5={np.nanpercentile(arr,5):10.4g} med={np.nanmedian(arr):10.4g} p95={np.nanpercentile(arr,95):10.4g} max={np.nanmax(arr):10.4g}")
    else:
        print(f"{k:40s} {arr.dtype} {str(arr)[:100]}")
