"""Tone level before and after the limiter probe's burst at 2.0 s (run from the repo root)."""
import pathlib, sys
import numpy as np
sys.path.insert(0, "tools/audio")
import bench_analyze as bench

audio, rate = bench.read_wav(pathlib.Path(sys.argv[1]))
tone = audio[:, 0]
before = 20 * np.log10(np.sqrt(np.mean(tone[rate:int(1.9 * rate)] ** 2)))
for t0 in (2.3, 3.0, 5.0, 10.0, 20.0):
    seg = tone[int(t0 * rate):int((t0 + 0.5) * rate)]
    print(f"{t0:4.1f} s: {20 * np.log10(np.sqrt(np.mean(seg ** 2))) - before:+.2f} dB against the pre-burst tone")
print(f"burst peak {20 * np.log10(np.abs(tone[2 * rate:int(2.2 * rate)]).max()):.2f} dBFS")
