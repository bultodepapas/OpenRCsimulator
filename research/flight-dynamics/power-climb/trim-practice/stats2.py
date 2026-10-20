"""Print nested air structs of a UMN Baldr log (read-only)."""
import sys
import numpy as np
import scipy.io as sio
m = sio.loadmat(sys.argv[1], squeeze_me=True, struct_as_record=False)
d = m["dtc"]
def walk(obj, pre):
    for f in obj._fieldnames:
        a = getattr(obj, f)
        if hasattr(a, "_fieldnames"):
            walk(a, pre + f + ".")
        else:
            arr = np.asarray(a)
            if arr.dtype.kind in "fiu" and arr.size > 1:
                arr = arr.astype(float)
                print(f"{pre+f:36s} n={arr.size:7d} p5={np.nanpercentile(arr,5):9.4g} med={np.nanmedian(arr):9.4g} p95={np.nanpercentile(arr,95):9.4g}")
            else:
                print(f"{pre+f:36s} {str(arr)[:150]}")
walk(d.air, "air.")
print([f for f in d._fieldnames])
for f in ["pgm"]:
    pass
p = m["pgm"]
print({f: str(getattr(p, f))[:200] for f in p._fieldnames})
