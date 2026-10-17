"""AUD-11b: measure Godot bus-filter responses from the filter_probe Movie Maker capture.

Usage: python3 measure_filters.py <out.wav> <probe log with the PROBE_SEGMENTS line>
Reports, per noise segment, the level relative to the bypass segment at fixed frequencies
(Welch PSD ratio), the -3 dB point, and, for the tone sweeps, the largest 1 ms second-difference
peak relative to the bypass tone (a click detector)."""
import json
import sys
import wave

import numpy as np

FREQS = [250, 500, 1000, 2000, 4000, 8000, 12000, 16000]


def read(path):
    with wave.open(path, "rb") as w:
        rate, width, channels, frames = w.getframerate(), w.getsampwidth(), w.getnchannels(), w.getnframes()
        raw = w.readframes(frames)
    dtype = {2: np.int16, 4: np.int32}[width]
    data = np.frombuffer(raw, dtype=dtype).astype(np.float64) / float(np.iinfo(dtype).max)
    return rate, data.reshape(-1, channels).mean(axis=1)


def psd(x, n=8192):
    window = np.hanning(n)
    hops = range(0, len(x) - n, n // 2)
    return np.mean([np.abs(np.fft.rfft(window * x[i:i + n])) ** 2 for i in hops], axis=0)


def main():
    rate, mono = read(sys.argv[1])
    line = next(l for l in open(sys.argv[2]) if l.startswith("PROBE_SEGMENTS "))
    spec = json.loads(line.split(" ", 1)[1])
    seg = int(rate * spec["frames_per_segment"] / spec["fps"])
    skip = int(0.25 * rate)  # settle after each parameter change
    parts = {s["name"]: mono[i * seg + skip:(i + 1) * seg] for i, s in enumerate(spec["segments"])}
    freqs = np.fft.rfftfreq(8192, 1.0 / rate)
    ref = psd(parts["bypass"])
    result = {}
    for s in spec["segments"]:
        if s.get("tone") or s["name"] == "bypass" or s["name"].startswith("3d_ref"):
            continue
        reference = ref
        if "spatial" in s:  # the same distance with the 3D filter off
            reference = psd(parts["3d_ref_%dm" % int(s["spatial"])])
        ratio = 10 * np.log10(psd(parts[s["name"]]) / reference)
        smooth = np.convolve(ratio, np.ones(9) / 9, mode="same")
        at = {f: round(float(np.interp(f, freqs, smooth)), 2) for f in FREQS}
        band = (freqs > 100) & (freqs < 20000)
        below = np.where(band & (smooth < -3.0))[0]
        result[s["name"]] = {"db": at, "minus3_hz": round(float(freqs[below[0]]), 0) if below.size else None}
        print(f"{s['name']:22s} -3 dB at {result[s['name']]['minus3_hz']}  " + "  ".join(f"{f}:{v:+.2f}" for f, v in at.items()))
    for distance in (30, 200):
        level = 10 * np.log10(np.mean(parts["3d_ref_%dm" % distance] ** 2) / np.mean(parts["bypass"] ** 2))
        result["3d_ref_%dm_level_db" % distance] = round(float(level), 2)
        print(f"3d_ref_{distance}m level relative to the bypass bus: {level:+.2f} dB")
    ms = int(rate / 1000)
    def click(x):
        # 1 ms second-difference peaks over the median of the surrounding 21 ms: insensitive to slow level changes.
        d2 = np.abs(np.diff(x, 2))
        peaks = np.array([d2[i:i + ms].max() for i in range(0, len(d2) - ms, ms)])
        local = np.array([np.median(peaks[max(0, k - 10):k + 11]) for k in range(len(peaks))])
        return float((peaks / local).max())
    base = click(parts["tone_bypass"])
    tones = [s["name"] for s in spec["segments"] if s.get("tone")]
    for k, name in enumerate(tones):
        index = next(i for i, s in enumerate(spec["segments"]) if s["name"] == name)
        settled = click(parts[name])
        # Onset: the 40 ms either side of the boundary, where the previous tone segment continues into this one.
        onset = click(mono[index * seg - int(0.04 * rate):index * seg + int(0.04 * rate)]) if k > 0 else None
        result[name] = {"click_ratio": round(settled, 3), "onset_ratio": None if onset is None else round(onset, 3)}
        print(f"{name:22s} 1 ms second-difference peak / local median: settled {settled:.3f}, boundary "
              + ("n/a" if onset is None else f"{onset:.3f}") + f" (bypass tone {base:.3f})")
    json.dump(result, open(sys.argv[1] + ".json", "w"), indent=1)


main()
