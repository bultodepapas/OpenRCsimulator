"""Read the Movie Maker WAV from clamp_probe and print measured level per case (1 s each, 1 kHz tone)."""
import sys, wave
import numpy as np

CASES = [[2, -6], [2, -16], [2, -26], [8, -6], [8, -16], [16, -16], [32, -16], [100, -6], [100, -16], [100, -26]]
w = wave.open(sys.argv[1])
sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int32 if sw == 4 else np.int16).astype(float).reshape(-1, ch)
a /= 2**31 if sw == 4 else 2**15
ref = 16000 / 32768 / np.sqrt(2)
for i, (d, v) in enumerate(CASES):
    seg = a[int((i + 0.4) * sr):int((i + 0.9) * sr)].mean(axis=1)
    level = 20 * np.log10(np.sqrt(np.mean(seg**2)) / ref + 1e-12)
    unclamped = v + 20 * np.log10(8 / d)
    print(f"d={d:4d} m volume_db={v:4d} measured={level:6.1f} dB unclamped={unclamped:+.1f} clamped={min(unclamped, 0):+.1f}")
