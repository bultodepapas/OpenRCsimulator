"""AUD-12: limiter transfer from limiter_transfer_probe captures.

Usage: python3 -I measure_transfer.py <out.wav> [<out.wav> ...]
For 20 ms windows of the 1 kHz ramp it reports input level (known from time), output peak (dBFS) and
distortion (residual RMS after removing the fitted 1 kHz sinusoid, dB re fundamental); then the
-20 dBFS hold level against its expected value (recovery after the overload)."""
import sys
import wave

import numpy as np

RAMP_S, HOLD_S, F0 = 6.0, 4.0, 1000.0
LEVELS = [-12.0, -6.0, -4.0, -3.0, -2.5, -2.1, -1.9, -1.5, -1.0, 0.0, 3.0, 6.0]


def read(path):
    with wave.open(path, "rb") as w:
        rate, width, channels = w.getframerate(), w.getsampwidth(), w.getnchannels()
        raw = w.readframes(w.getnframes())
    data = np.frombuffer(raw, dtype={2: np.int16, 4: np.int32}[width]).astype(np.float64)
    return rate, data.reshape(-1, channels)[:, 0] / float(2 ** (8 * width - 1))


def onset(x, rate):
    # The tone starts at -12 dBFS; the first sample above -40 dBFS marks t = 0.
    return int(np.argmax(np.abs(x) > 0.01))


def window_stats(x, rate):
    t = np.arange(x.size) / rate
    basis = np.stack([np.sin(2 * np.pi * F0 * t), np.cos(2 * np.pi * F0 * t)], axis=1)
    coef, *_ = np.linalg.lstsq(basis, x, rcond=None)
    residual = x - basis @ coef
    fundamental = np.hypot(*coef) / np.sqrt(2)
    return 20 * np.log10(np.abs(x).max()), 20 * np.log10(max(np.sqrt(np.mean(residual ** 2)), 1e-12) / fundamental)


def main():
    for path in sys.argv[1:]:
        rate, x = read(path)
        start = onset(x, rate)
        win = int(0.02 * rate)
        print(path)
        for level in LEVELS:
            centre = start + int((level + 12.0) / 18.0 * RAMP_S * rate)
            peak, distortion = window_stats(x[centre - win // 2:centre + win // 2], rate)
            print(f"  in {level:+5.1f} dBFS -> peak {peak:+6.2f} dBFS, distortion {distortion:6.1f} dB")
        for after in (0.5, 1.0, 2.0, 3.5):
            centre = start + int((RAMP_S + after) * rate)
            peak, distortion = window_stats(x[centre - win // 2:centre + win // 2], rate)
            print(f"  hold +{after:.1f} s (expect -20.00) -> peak {peak:+6.2f} dBFS")


main()
