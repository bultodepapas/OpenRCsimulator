"""Inspect UMN Baldr/Thor MATLAB logs (read-only). Usage: python3 -I inspect_logs.py FILE..."""
import sys
import numpy as np
import scipy.io as sio

for path in sys.argv[1:]:
    print("=" * 80)
    print(path)
    try:
        m = sio.loadmat(path, squeeze_me=True, struct_as_record=False)
    except NotImplementedError as e:
        print("  v7.3 (HDF5) mat:", e)
        continue
    for k, v in m.items():
        if k.startswith("__"):
            continue
        print(" key", k, type(v).__name__, getattr(v, "shape", None))
        if hasattr(v, "_fieldnames"):
            for f in v._fieldnames:
                a = getattr(v, f)
                if hasattr(a, "_fieldnames"):
                    print("   ", f, "struct", a._fieldnames[:40])
                else:
                    arr = np.asarray(a)
                    s = arr.shape
                    if arr.dtype.kind in "fiu" and arr.size > 0:
                        print("   ", f, s, arr.dtype, "min %.4g max %.4g" % (np.nanmin(arr), np.nanmax(arr)))
                    else:
                        print("   ", f, s, arr.dtype, str(arr)[:80])
