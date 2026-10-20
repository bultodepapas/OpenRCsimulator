"""Compare Thor elevator channels per mode (read-only). Usage: python3 -I thor_modes.py FILE..."""
import sys
import numpy as np
sys.path.insert(0, "/tmp/rc-h5py")

def load(path):
    if path.endswith(".h5"):
        import h5py
        f = h5py.File(path, "r")
        return {k: np.asarray(f[k][()], dtype=float).ravel() for k in f.keys() if isinstance(f[k], h5py.Dataset) and f[k].dtype.kind in "fiu"}
    import scipy.io as sio
    m = sio.loadmat(path, squeeze_me=True)
    return {k: np.asarray(v, dtype=float).ravel() for k, v in m.items() if not k.startswith("__") and isinstance(v, np.ndarray) and v.dtype.kind in "fiu"}

for p in sys.argv[1:]:
    d = load(p)
    print(p.split("/")[-1], "n", d["time"].size)
    air = (d["ias"] > 9) & (d["h"] > 10)
    for mo in np.unique(d["mode"]):
        s = air & (d["mode"] == mo)
        if s.sum() < 50:
            continue
        de, di = d["de"][s], d["de_in"][s]
        c = np.corrcoef(de, di)[0, 1] if de.std() > 1e-9 and di.std() > 1e-9 else float("nan")
        print(f"  mode {mo:.0f}: {s.sum()/50:.0f}s de med {np.degrees(np.median(de)):.2f} std {np.degrees(de.std()):.2f}; de_in med {np.degrees(np.median(di)):.2f} std {np.degrees(di.std()):.2f}; corr {c:.3f}; dthr med {np.median(d['dthr'][s]):.2f} dthr_in med {np.median(d['dthr_in'][s]):.2f}; ias med {np.median(d['ias'][s]):.1f}")
