"""Click score per loop_probe case: seam second difference against the case's median (run from the repo root)."""
import pathlib, sys
import numpy as np
sys.path.insert(0, "tools/audio")
import bench_analyze as bench

audio, rate = bench.read_wav(pathlib.Path(sys.argv[1]))
mono = audio.mean(axis=1)
d2 = np.abs(np.diff(mono, 2))
for k, (name, period) in enumerate([("A no guard, pitch 1.0", 1.0), ("B no guard, pitch 0.87", 1 / 0.87),
                                    ("C guard, pitch 1.0", 1.0), ("D guard, pitch 0.87", 1 / 0.87)]):
    t0 = 4 * k
    seams = [d2[int((t0 + w) * rate) - 480:int((t0 + w) * rate) + 480].max() for w in (period, 2 * period)]
    median = np.median(d2[int((t0 + 0.2) * rate):int((t0 + 0.9) * rate)])
    clicks = bench.clicks(mono[int(t0 * rate):int((t0 + 4) * rate)], rate)
    print(f"{name:24s} seam d2 {np.round(seams, 4)} median {median:.5f} clicks {clicks}")
