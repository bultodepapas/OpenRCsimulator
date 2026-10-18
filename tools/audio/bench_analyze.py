"""AUD-06: analyze bench captures (Movie Maker WAV + per-frame telemetry JSON).

Usage: python3 tools/audio/bench_analyze.py <prefix> [<prefix> ...] [--out=summary.json]
Each <prefix> names <prefix>.wav and <prefix>.json written by tools/audio/bench.sh.

Metrics are mixer diagnostics, not calibrated acoustics:
- level: BS.1770 K-weighted RMS per segment (LKFS-like, ungated), dBFS sample peak, 4x-oversampled
  true peak (dBTP) and the count of full-scale samples (clipping in the integer capture);
- spectrum: centroid and 95 % energy bandwidth;
- pitch: strongest spectral peak 40-4000 Hz (the motor's dominant line);
- periodicity: autocorrelation of the 10 ms RMS envelope, lags 0.15-3 s (repeating loop texture);
- clicks: 1 ms blocks whose second-difference peak exceeds 8x the median of the surrounding 200 ms;
- doppler: per-frame jumps from the soundscape telemetry.
"""
from __future__ import annotations

import json
import math
import sys
import wave
from pathlib import Path

import numpy as np

STEADY_SECONDS = 3.0  # analyze the last seconds of each steady stage


def read_wav(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path)) as w:
        rate, channels, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dtype = {2: np.int16, 4: np.int32}[width]
    data = np.frombuffer(raw, dtype=dtype).astype(np.float64).reshape(-1, channels)
    return data / float(2 ** (8 * width - 1)), rate


def biquad(x: np.ndarray, b: tuple[float, ...], a: tuple[float, ...]) -> np.ndarray:
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    _, a1, a2 = a
    for i, xi in enumerate(x):
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def k_weight(x: np.ndarray, rate: int) -> np.ndarray:
    if rate != 48000:
        raise SystemExit(f"K-weighting coefficients are for 48 kHz; got {rate}")
    # ITU-R BS.1770-4 stage 1 (high shelf) and stage 2 (RLB high-pass) at 48 kHz.
    x = biquad(x, (1.53512485958697, -2.69169618940638, 1.19839281085285), (1.0, -1.69065929318241, 0.73248077421585))
    return biquad(x, (1.0, -2.0, 1.0), (1.0, -1.99004745483398, 0.99007225036621))


def db(value: float) -> float:
    return 20.0 * math.log10(max(value, 1e-12))


def spectrum_stats(x: np.ndarray, rate: int) -> dict:
    n = 8192
    if x.size < n:
        return {}
    frames = np.lib.stride_tricks.sliding_window_view(x, n)[:: n // 2]
    power = np.mean(np.abs(np.fft.rfft(frames * np.hanning(n), axis=1)) ** 2, axis=0)
    freqs = np.fft.rfftfreq(n, 1.0 / rate)
    if power.sum() <= 1e-30:
        return {"silent": True}
    cumulative = np.cumsum(power) / max(power.sum(), 1e-30)
    band = (freqs >= 40) & (freqs <= 4000)
    return {
        "centroid_hz": round(float(np.sum(freqs * power) / max(power.sum(), 1e-30)), 1),
        "bandwidth95_hz": round(float(freqs[np.searchsorted(cumulative, 0.95)]), 1),
        "dominant_hz": round(float(freqs[band][np.argmax(power[band])]), 1),
    }


def periodicity(x: np.ndarray, rate: int) -> dict:
    hop = rate // 100
    count = x.size // hop
    if count < 200:
        return {}
    env = np.sqrt(np.mean(x[: count * hop].reshape(count, hop) ** 2, axis=1))
    env = env - np.convolve(env, np.ones(50) / 50, mode="same")  # remove slow level drift (0.5 s)
    env = env[25:-25]
    ac = np.correlate(env, env, mode="full")[env.size - 1 :]
    ac /= max(ac[0], 1e-30)
    lo, hi = 15, min(300, env.size // 2)
    lag = int(np.argmax(ac[lo:hi])) + lo
    return {"envelope_autocorr_peak": round(float(ac[lag]), 3), "period_s": round(lag / 100.0, 2)}


def clicks(x: np.ndarray, rate: int) -> list[float]:
    d2 = np.abs(np.diff(x, 2))
    block = rate // 1000
    count = d2.size // block
    peaks = d2[: count * block].reshape(count, block).max(axis=1)
    local = np.array([np.median(peaks[max(0, i - 100) : i + 100]) for i in range(0, count)])
    hits = np.nonzero(peaks > 8.0 * np.maximum(local, 1e-6))[0]
    times: list[float] = []
    for i in hits:
        t = round(i / 1000.0, 3)
        if not times or t - times[-1] > 0.05:
            times.append(t)
    return times


def true_peak(audio: np.ndarray) -> float:
    """BS.1770-4 Annex 2 style: 4x oversampling with a 48-tap-per-phase windowed-sinc FIR, then |peak|."""
    factor, taps = 4, 48
    n = np.arange(factor * taps) - (factor * taps - 1) / 2.0
    kernel = np.sinc(n / factor) * np.blackman(n.size)
    kernel *= factor / kernel.sum()
    peak = 0.0
    for channel in audio.T:
        stuffed = np.zeros(channel.size * factor)
        stuffed[::factor] = channel
        size = stuffed.size + kernel.size - 1
        fft = 1 << (size - 1).bit_length()
        up = np.fft.irfft(np.fft.rfft(stuffed, fft) * np.fft.rfft(kernel, fft), fft)[:size]
        peak = max(peak, float(np.abs(up).max()))
    return peak


def analyze(prefix: Path) -> dict:
    audio, rate = read_wav(prefix.with_suffix(".wav"))
    report = json.loads(prefix.with_suffix(".json").read_text())
    cols = {name: i for i, name in enumerate(report["columns"])}
    rows = report["rows"]
    fps = report["fps"]
    mono = audio.mean(axis=1)
    weighted = k_weight(mono, rate)
    per_frame = rate // fps
    events = report["events"] + [{"frame": report["frames"], "stage": "end"}]
    segments = []
    for start, stop in zip(events, events[1:]):
        f1 = stop["frame"]
        f0 = max(start["frame"], f1 - int(STEADY_SECONDS * fps))
        if f1 - f0 < fps // 2:
            continue
        s0, s1 = f0 * per_frame, min(f1 * per_frame, mono.size)
        tel = rows[f0:f1]
        mean = lambda key: round(float(np.mean([r[cols[key]] for r in tel])), 4)
        seg = {
            "stage": start["stage"], "t0": round(f0 / fps, 2), "t1": round(f1 / fps, 2),
            "rpm": mean("rpm"), "distance_m": mean("distance_m"), "motor_pitch_scale": mean("motor_pitch_scale"),
            "motor_volume_db": mean("motor_volume_db"),
            "k_level_db": round(db(float(np.sqrt(np.mean(weighted[s0:s1] ** 2)))), 2),
            "peak_dbfs": round(db(float(np.abs(audio[s0:s1]).max())), 2),
        }
        seg.update(spectrum_stats(mono[s0:s1], rate))
        seg.update(periodicity(mono[s0:s1], rate))
        seg["motor_loop_period_s"] = round(1.0 / max(seg["motor_pitch_scale"], 1e-6), 2)  # 1 s source loop
        segments.append(seg)
    doppler = np.array([r[cols["doppler"]] for r in rows])
    jumps = np.abs(np.diff(doppler))
    frame_jumps = [round(float(rows[i + 1][cols["t"]]), 3) for i in np.nonzero(jumps > 0.03)[0]]
    return {
        "capture": prefix.name, "scenario": report["scenario"], "aircraft": report["aircraft"],
        "duration_s": round(mono.size / rate, 3), "telemetry_frames": report["frames"],
        "audio_frames_per_video_frame": per_frame, "focus_resumes": report.get("focus_resumes", 0),
        "peak_dbfs": round(db(float(np.abs(audio).max())), 2),
        "true_peak_dbtp": round(db(true_peak(audio)), 2),
        # Movie Maker writes integer PCM, so a mix above 0 dBFS lands as full-scale samples.
        "full_scale_samples": int(np.count_nonzero(np.abs(audio) >= 1.0 - 2.0 ** -23)),
        "segments": segments,
        "doppler_min": round(float(doppler.min()), 4), "doppler_max": round(float(doppler.max()), 4),
        "doppler_jump_times_s": frame_jumps,
        "click_times_s": clicks(mono, rate),
    }


def main() -> int:
    out = None
    prefixes = []
    for arg in sys.argv[1:]:
        if arg.startswith("--out="):
            out = Path(arg[6:])
        else:
            prefixes.append(Path(arg))
    results = [analyze(p) for p in prefixes]
    for r in results:
        print(f"\n{r['capture']} ({r['aircraft']}, {r['scenario']}) peak {r['peak_dbfs']} dBFS, "
              f"true peak {r['true_peak_dbtp']} dBTP, full-scale samples {r['full_scale_samples']}, "
              f"doppler {r['doppler_min']}..{r['doppler_max']}, jumps {r['doppler_jump_times_s'][:8]}, clicks {r['click_times_s'][:8]}")
        print(f"{'stage':12s} {'t':>11s} {'rpm':>8s} {'dist':>6s} {'pitch':>6s} {'vol_dB':>7s} {'K_dB':>7s} {'cent':>6s} {'bw95':>6s} {'dom':>7s} {'ac':>5s} {'per':>5s} {'loop':>5s}")
        for s in r["segments"]:
            print(f"{s['stage']:12s} {s['t0']:5.1f}-{s['t1']:5.1f} {s['rpm']:8.0f} {s['distance_m']:6.1f} {s['motor_pitch_scale']:6.2f} "
                  f"{s['motor_volume_db']:7.1f} {s['k_level_db']:7.1f} {s.get('centroid_hz', 0):6.0f} {s.get('bandwidth95_hz', 0):6.0f} "
                  f"{s.get('dominant_hz', 0):7.1f} {s.get('envelope_autocorr_peak', 0):5.2f} {s.get('period_s', 0):5.2f} {s['motor_loop_period_s']:5.2f}")
    if out:
        out.write_text(json.dumps(results, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
