"""AUD-12: tone level before and after each burst of repeated_burst_probe (dB re the pre-burst level).

Usage: python3 -I measure_bursts.py <out.wav> [...]"""
import sys
import wave

import numpy as np


def level(x, rate, t):
    seg = x[int(t * rate):int((t + 0.2) * rate)]
    return 20 * np.log10(np.sqrt(np.mean(seg ** 2)))


for path in sys.argv[1:]:
    with wave.open(path, "rb") as w:
        rate, width = w.getframerate(), w.getsampwidth()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype={2: np.int16, 4: np.int32}[width]).astype(float)
    x = x.reshape(-1, 2)[:, 0] / float(2 ** (8 * width - 1))
    reference = level(x, rate, 1.5)
    after = [level(x, rate, t) - reference for t in (3.5, 5.5, 7.5, 9.5, 11.5, 15.5)]
    print(path, "after bursts 1-5 (+1.5 s) and at 15.5 s:", " ".join(f"{v:+.2f}" for v in after), "dB")
