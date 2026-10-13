#!/usr/bin/env python3
"""Generate the original, loop-ready OpenRC soundscape WAV assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

try:
    import numpy as np
except ImportError as exc:  # pragma: no cover - exercised on unsupported tool hosts
    raise SystemExit("tools/audio/generate.py requires NumPy; use the recorded versions in manifest.json for exact checks.") from exc

NUMPY_REQUIRED = "2.4.6"
if np.__version__ != NUMPY_REQUIRED:
    raise SystemExit(f"tools/audio/generate.py requires numpy=={NUMPY_REQUIRED}; found {np.__version__}.")


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "app" / "assets" / "audio" / "soundscape"
RATE = 22_050
TARGET_PEAK = 0.48
# Pitch-shifted content lands in the mix at band limit x pitch. It must stay below the output Nyquist
# (22,050 Hz on the slowest supported 44.1 kHz device), not the source Nyquist; 20 kHz keeps a margin.
# The source Nyquist (11,025 Hz) only caps the band limit itself (audio realism plan, F1/F6).
SHIFTED_LIMIT_HZ = 20_000
MANIFEST_NAME = "manifest.json"
FORMAT_NAME = "openrc-audio-soundscape-v1"
GENERATOR_VERSION = "2"


@dataclass(frozen=True)
class AssetSpec:
    filename: str
    seconds: float
    seed: int
    kind: str
    base_hz: float | None
    frequency_note: str
    bird_phrase: int | None = None
    playback_pitch_factor: float = 1.0
    bandlimit_hz: float | None = None


ASSETS = (
    AssetSpec("wind_low.wav", 29, 0xA00201, "ambient", None, "Broad low wind, source-limited to 10,000 Hz", None, 1.06, 10_000),
    AssetSpec("wind_high.wav", 31, 0xA00202, "ambient", None, "Airy wind, source-limited to 10,000 Hz", None, 1.06, 10_000),
    AssetSpec("foliage.wav", 23, 0xA00203, "ambient", None, "Modulated leafy rustle, source-limited to 10,000 Hz", None, 1.06, 10_000),
    AssetSpec("airframe.wav", 7, 0xA00204, "aircraft", None, "Buffet and airflow noise, source-limited to 4,300 Hz", None, 2.325, 4_300),
    AssetSpec("motor_combustion.wav", 1, 0xA00205, "motor", 100, "100 Hz firing cycle with harmonic body and mild cycle-rate wobble", None, 4.0, 2_400),
    AssetSpec("motor_propeller.wav", 1, 0xA00206, "motor", 200, "200 Hz blade-pass tone with harmonic airflow texture", None, 4.0, 2_400),
    AssetSpec("motor_electric.wav", 1, 0xA00207, "motor", 600, "600 Hz electrical whine with harmonics and switching hiss", None, 4.0, 2_400),
    # AUD-10: turbine layers. Whine reference 82,320 rpm (shaft order 1,372 Hz); runtime pitch N/82,320 spans 0.53-1.87.
    AssetSpec("turbine_whine.wav", 8, 0xA00209, "motor", 1_372, "Shaft-order whine: harmonics 1-7 of 1,372 Hz (82,320 rpm) with compressor hiss, source-limited to 10,000 Hz", None, 1.88, 10_000),
    # Roar reference: spectral peak near 1.5 kHz; runtime pitch follows jet velocity (Strouhal scaling), at most 1.40.
    AssetSpec("turbine_roar.wav", 10, 0xA0020A, "motor", None, "Jet mixing noise peaking near 1.5 kHz with turbulent modulation and low rumble, source-limited to 10,000 Hz", None, 1.40, 10_000),
    AssetSpec("birds_01.wav", 2.4, 0xA00211, "bird_phrase", None, "Stylized synthetic whistles; not species-specific", 1, 1.06, 10_000),
    AssetSpec("birds_02.wav", 1.9, 0xA00212, "bird_phrase", None, "Stylized synthetic whistles; not species-specific", 2, 1.06, 10_000),
    AssetSpec("birds_03.wav", 2.76, 0xA00213, "bird_phrase", None, "Stylized synthetic whistles; not species-specific", 3, 1.06, 10_000),
    AssetSpec("birds_04.wav", 2.3, 0xA00214, "bird_phrase", None, "Stylized synthetic whistles; not species-specific", 4, 1.06, 10_000),
    AssetSpec("birds_05.wav", 2.56, 0xA00215, "bird_phrase", None, "Stylized synthetic whistles; not species-specific", 5, 1.06, 10_000),
    AssetSpec("birds_06.wav", 1.72, 0xA00216, "bird_phrase", None, "Stylized synthetic whistles; not species-specific", 6, 1.06, 10_000),
)


def sample_count(seconds: float) -> int:
    count = round(seconds * RATE)
    if not math.isclose(count / RATE, seconds, rel_tol=0.0, abs_tol=1e-10):
        raise ValueError(f"duration must be an exact sample count: {seconds}s")
    return count


def timebase(seconds: float) -> np.ndarray:
    return np.arange(sample_count(seconds), dtype=np.float64) / RATE


def band_noise(
    seconds: float,
    seed: int,
    low_hz: float,
    high_hz: float,
    *,
    tilt: float = 0.0,
    resonances: Iterable[tuple[float, float, float]] = (),
) -> np.ndarray:
    """Make circular, shaped noise from an integer-bin Fourier spectrum.

    Every positive-frequency component contains an integer number of cycles in
    the requested duration. The periodic spectrum therefore joins at the loop
    point with the same value and analytic slope; no crossfade is needed.
    """
    count = sample_count(seconds)
    freqs = np.fft.rfftfreq(count, d=1.0 / RATE)
    safe_freqs = np.maximum(freqs, max(low_hz, 1.0))
    highpass = 1.0 / np.sqrt(1.0 + np.power(max(low_hz, 0.01) / np.maximum(freqs, 0.01), 8.0))
    lowpass = 1.0 / np.sqrt(1.0 + np.power(np.maximum(freqs, 0.01) / high_hz, 8.0))
    spectrum_shape = highpass * lowpass * np.power(safe_freqs / 1_000.0, -0.5 * tilt)
    for center_hz, width_hz, boost in resonances:
        spectrum_shape *= 1.0 + boost * np.exp(-0.5 * np.square((freqs - center_hz) / width_hz))

    rng = np.random.Generator(np.random.PCG64(seed))
    real = rng.standard_normal(freqs.size)
    imag = rng.standard_normal(freqs.size)
    spectrum = (real + 1j * imag) * (spectrum_shape / math.sqrt(2.0))
    spectrum[0] = 0.0
    if count % 2 == 0:
        spectrum[-1] = spectrum[-1].real

    samples = np.fft.irfft(spectrum, n=count)
    samples -= samples.mean()
    rms = math.sqrt(float(np.mean(np.square(samples))))
    if rms == 0.0:
        raise ValueError("noise filter produced silence")
    return samples / rms


def slow_envelope(seconds: float, seed: int, *, depth: float, low_hz: float, high_hz: float) -> np.ndarray:
    movement = band_noise(seconds, seed, low_hz, high_hz, tilt=0.8)
    return np.clip(1.0 + depth * movement, 0.22, 1.72)


def circular_bursts(seconds: float, seed: int, count: int) -> np.ndarray:
    """Build irregular, smooth rustle swells while preserving circularity."""
    t = timebase(seconds)
    rng = np.random.Generator(np.random.PCG64(seed))
    centers = rng.uniform(0.0, seconds, count)
    widths = rng.uniform(0.045, 0.29, count)
    levels = rng.uniform(0.45, 1.25, count)
    envelope = np.full(t.size, 0.16, dtype=np.float64)
    for center, width, level in zip(centers, widths, levels):
        distance = t - center
        pulse = np.zeros(t.size, dtype=np.float64)
        for cycle in (-1, 0, 1):
            pulse += np.exp(-0.5 * np.square((distance + cycle * seconds) / width))
        envelope += level * pulse
    envelope /= max(float(np.percentile(envelope, 92)), 1e-12)
    return np.clip(envelope, 0.08, 1.5)


def make_wind_low(spec: AssetSpec) -> np.ndarray:
    seconds = spec.seconds
    t = timebase(seconds)
    low = band_noise(seconds, spec.seed, 18, 560, tilt=1.05)
    body = band_noise(seconds, spec.seed + 100, 110, 1_700, tilt=0.55)
    gusts = slow_envelope(seconds, spec.seed + 200, depth=0.24, low_hz=0.08, high_hz=0.8)
    distant = 0.025 * np.sin(2.0 * np.pi * 44.0 * t + 0.6)
    return (0.72 * low + 0.28 * body) * gusts + distant


def make_wind_high(spec: AssetSpec) -> np.ndarray:
    seconds = spec.seconds
    t = timebase(seconds)
    air = band_noise(seconds, spec.seed, 350, 9_500, tilt=-0.12)
    fine = band_noise(seconds, spec.seed + 100, 1_700, 10_300, tilt=0.22)
    gusts = slow_envelope(seconds, spec.seed + 200, depth=0.14, low_hz=0.11, high_hz=1.3)
    thin_whistle = 0.035 * np.sin(2.0 * np.pi * 1_180.0 * t + 0.09 * np.sin(2.0 * np.pi * (22.0 / seconds) * t))
    return (0.68 * air + 0.32 * fine) * gusts + thin_whistle


def make_foliage(spec: AssetSpec) -> np.ndarray:
    seconds = spec.seconds
    t = timebase(seconds)
    rustle = circular_bursts(seconds, spec.seed + 100, 86)
    leaf_mid = band_noise(seconds, spec.seed, 240, 4_200, tilt=0.28)
    leaf_top = band_noise(seconds, spec.seed + 200, 1_100, 10_200, tilt=-0.14)
    flutter = 0.04 * np.sin(2.0 * np.pi * (170.0 / seconds) * t + 0.25 * np.sin(2.0 * np.pi * (9.0 / seconds) * t))
    return rustle * (0.40 * leaf_mid + 0.60 * leaf_top) + flutter


def make_airframe(spec: AssetSpec) -> np.ndarray:
    seconds = spec.seconds
    t = timebase(seconds)
    buffet = band_noise(seconds, spec.seed, 35, 520, tilt=0.78, resonances=((92, 33, 1.8),))
    airflow = band_noise(seconds, spec.seed + 100, 180, 3_200, tilt=0.15, resonances=((1_450, 310, 0.65),))
    edge = band_noise(seconds, spec.seed + 200, 1_900, 9_000, tilt=-0.12)
    flutter = 1.0 + 0.13 * np.sin(2.0 * np.pi * (88.0 / seconds) * t + 0.035 * np.sin(2.0 * np.pi * (6.0 / seconds) * t))
    return (0.31 * buffet + 0.51 * airflow + 0.18 * edge) * flutter


def make_combustion(spec: AssetSpec) -> np.ndarray:
    seconds = spec.seconds
    t = timebase(seconds)
    phase_wander = 0.012 * band_noise(seconds, spec.seed + 100, 1.0, 24.0, tilt=-0.2)
    phase = 2.0 * np.pi * (spec.base_hz * t + phase_wander)
    harmonics = (1.0, 0.56, 0.39, 0.27, 0.19, 0.13, 0.095, 0.068, 0.046, 0.031)
    tone = np.zeros(t.size, dtype=np.float64)
    for harmonic, weight in enumerate(harmonics, start=1):
        tone += weight * np.sin(harmonic * phase + 0.13 * (harmonic - 1))
    exhaust = band_noise(seconds, spec.seed + 200, 260, 5_900, tilt=0.28)
    firing_pulse = np.clip(0.5 + 0.5 * np.sin(phase + 0.1), 0.0, 1.0) ** 3.5
    amplitude = 1.0 + 0.055 * band_noise(seconds, spec.seed + 300, 0.6, 7.0, tilt=0.5)
    return amplitude * tone + (0.07 + 0.11 * firing_pulse) * exhaust


def make_propeller(spec: AssetSpec) -> np.ndarray:
    seconds = spec.seconds
    t = timebase(seconds)
    phase_wander = 0.0018 * band_noise(seconds, spec.seed + 100, 0.6, 15.0, tilt=0.1)
    phase = 2.0 * np.pi * (spec.base_hz * t + phase_wander)
    blade = (
        1.0 * np.sin(phase)
        + 0.34 * np.sin(2.0 * phase + 0.34)
        + 0.18 * np.sin(3.0 * phase + 0.75)
        + 0.09 * np.sin(4.0 * phase + 1.10)
    )
    shaft = 0.14 * np.sin(2.0 * np.pi * 100.0 * t + 0.2)
    airflow = band_noise(seconds, spec.seed + 200, 190, 5_600, tilt=0.12)
    slow = 1.0 + 0.08 * np.sin(2.0 * np.pi * 1.0 * t + 0.7)
    return slow * blade + shaft + 0.055 * airflow * (0.65 + 0.35 * np.sin(phase) ** 2)


def make_electric(spec: AssetSpec) -> np.ndarray:
    seconds = spec.seconds
    t = timebase(seconds)
    phase_wander = 0.0022 * band_noise(seconds, spec.seed + 100, 1.0, 18.0, tilt=0.0)
    phase = 2.0 * np.pi * (spec.base_hz * t + phase_wander)
    whine = (
        1.0 * np.sin(phase)
        + 0.47 * np.sin(2.0 * phase + 0.24)
        + 0.29 * np.sin(3.0 * phase + 0.62)
        + 0.17 * np.sin(4.0 * phase + 0.91)
        + 0.10 * np.sin(5.0 * phase + 1.15)
    )
    rotor = 0.13 * np.sin(2.0 * np.pi * 200.0 * t + 0.35)
    switching = band_noise(seconds, spec.seed + 200, 2_400, 10_200, tilt=-0.18)
    modulation = 1.0 + 0.025 * np.sin(2.0 * np.pi * 3.0 * t + 0.3)
    return modulation * whine + rotor + 0.055 * switching


def make_turbine_whine(spec: AssetSpec) -> np.ndarray:
    """Compressor/shaft whine. Every component completes whole cycles in the loop (1,372 Hz x 8 s)."""
    seconds = spec.seconds
    t = timebase(seconds)
    wander = 0.0035 * band_noise(seconds, spec.seed + 100, 0.2, 6.0, tilt=0.3)
    phase = 2.0 * np.pi * (spec.base_hz * t + wander)
    weights = (1.0, 0.45, 0.30, 0.22, 0.15, 0.10, 0.07)
    tone = np.zeros(t.size, dtype=np.float64)
    for harmonic, weight in enumerate(weights, start=1):
        tone += weight * np.sin(harmonic * phase + 0.21 * (harmonic - 1))
    level = slow_envelope(seconds, spec.seed + 200, depth=0.06, low_hz=0.15, high_hz=1.5)
    hiss = band_noise(seconds, spec.seed, 1_800, 9_600, tilt=-0.2, resonances=((4_200, 900, 0.6),))
    return level * tone + 0.35 * hiss


def make_turbine_roar(spec: AssetSpec) -> np.ndarray:
    """Jet mixing noise: one broad peak (Strouhal-scaled at runtime), turbulent amplitude modulation, rumble."""
    seconds = spec.seconds
    roar = band_noise(seconds, spec.seed, 80, 9_400, tilt=0.8, resonances=((1_500, 1_100, 1.5),))
    turbulence = band_noise(seconds, spec.seed + 100, 4.0, 40.0, tilt=0.4)
    rumble = band_noise(seconds, spec.seed + 200, 40, 400, tilt=0.6)
    return roar * (1.0 + 0.18 * turbulence) + 0.10 * rumble


BIRD_PHRASES: dict[int, tuple[tuple[float, float, float, float, float, float, float], ...]] = {
    # start, length, start Hz, end Hz, vibrato Hz, vibrato depth Hz, level
    1: ((0.24, 0.17, 1_820, 2_360, 6.0, 10, 0.82), (0.49, 0.16, 1_960, 2_480, 7.2, 11, 0.72), (0.91, 0.23, 2_340, 1_980, 5.2, 12, 0.86), (1.35, 0.18, 1_740, 2_190, 6.4, 9, 0.72), (1.67, 0.34, 2_060, 2_740, 7.0, 13, 0.88)),
    2: ((0.18, 0.36, 2_940, 2_080, 5.2, 12, 0.90), (0.72, 0.22, 2_640, 2_030, 5.8, 8, 0.75), (1.14, 0.38, 2_280, 1_760, 4.6, 11, 0.83), (1.57, 0.13, 2_020, 2_260, 6.8, 8, 0.66)),
    3: ((0.18, 0.12, 2_080, 2_820, 8.8, 8, 0.72), (0.36, 0.12, 2_330, 3_080, 9.2, 8, 0.68), (0.55, 0.13, 2_640, 3_260, 9.6, 9, 0.74), (0.95, 0.34, 2_850, 2_420, 6.0, 12, 0.90), (1.55, 0.13, 1_820, 2_520, 8.0, 8, 0.69), (1.75, 0.13, 2_040, 2_740, 8.2, 8, 0.67), (2.02, 0.39, 2_460, 1_900, 5.4, 10, 0.86)),
    4: ((0.27, 0.32, 1_560, 1_980, 4.8, 9, 0.84), (0.75, 0.19, 2_310, 2_970, 8.5, 8, 0.72), (1.02, 0.39, 2_720, 2_060, 5.8, 11, 0.90), (1.58, 0.18, 1_840, 2_350, 7.2, 8, 0.74), (1.88, 0.18, 2_020, 2_640, 7.0, 9, 0.77)),
    5: ((0.20, 0.37, 2_720, 2_140, 5.1, 12, 0.85), (0.67, 0.43, 2_180, 2_760, 6.1, 10, 0.90), (1.27, 0.38, 2_520, 3_180, 7.6, 12, 0.87), (1.85, 0.28, 3_040, 2_140, 5.0, 12, 0.84), (2.20, 0.15, 1_910, 2_400, 8.0, 8, 0.70)),
    6: ((0.20, 0.18, 2_120, 2_930, 9.0, 9, 0.75), (0.48, 0.18, 2_420, 3_180, 9.2, 10, 0.76), (0.86, 0.39, 2_850, 2_150, 5.2, 12, 0.92), (1.39, 0.20, 1_860, 2_570, 8.0, 8, 0.73)),
}


def make_bird(spec: AssetSpec) -> np.ndarray:
    assert spec.bird_phrase is not None
    seconds = spec.seconds
    t = timebase(seconds)
    out = np.zeros(t.size, dtype=np.float64)
    breath = band_noise(seconds, spec.seed + 100, 650, 8_800, tilt=0.25)
    for start, length, start_hz, end_hz, vibrato_hz, vibrato_depth, level in BIRD_PHRASES[spec.bird_phrase]:
        tau = t - start
        active = (tau >= 0.0) & (tau <= length)
        progress = np.clip(tau / length, 0.0, 1.0)
        note_envelope = np.sin(np.pi * progress) ** 1.45
        sweep_cycles = start_hz * tau + 0.5 * (end_hz - start_hz) * np.square(tau) / length
        if vibrato_hz > 0.0:
            sweep_cycles += vibrato_depth / (2.0 * np.pi * vibrato_hz) * (1.0 - np.cos(2.0 * np.pi * vibrato_hz * tau))
        phase = 2.0 * np.pi * sweep_cycles
        note = np.sin(phase) + 0.24 * np.sin(2.0 * phase + 0.19) + 0.065 * np.sin(3.0 * phase + 0.38)
        note += 0.022 * breath
        out += np.where(active, level * note_envelope * note, 0.0)

    fade_seconds = 0.072
    edge = np.minimum(np.minimum(t / fade_seconds, (seconds - t) / fade_seconds), 1.0)
    edge_envelope = np.square(np.sin(0.5 * np.pi * np.clip(edge, 0.0, 1.0)))
    out *= edge_envelope
    return out


GENERATORS = {
    "ambient": {"wind_low.wav": make_wind_low, "wind_high.wav": make_wind_high, "foliage.wav": make_foliage},
    "aircraft": {"airframe.wav": make_airframe},
    "motor": {
        "motor_combustion.wav": make_combustion,
        "motor_propeller.wav": make_propeller,
        "motor_electric.wav": make_electric,
        "turbine_whine.wav": make_turbine_whine,
        "turbine_roar.wav": make_turbine_roar,
    },
    "bird_phrase": {f"birds_{i:02d}.wav": make_bird for i in range(1, 7)},
}


def pcm_bytes(samples: np.ndarray) -> tuple[bytes, np.ndarray]:
    peak = float(np.max(np.abs(samples)))
    if not np.isfinite(peak) or peak <= 0.0:
        raise ValueError("asset is silent or contains a non-finite value")
    normalized = samples * (TARGET_PEAK / peak)
    pcm = np.rint(np.clip(normalized, -0.6, 0.6) * 32767.0).astype("<i2")
    return pcm.tobytes(), pcm


def wav_bytes(samples: np.ndarray) -> tuple[bytes, np.ndarray]:
    payload, pcm = pcm_bytes(samples)
    from io import BytesIO

    stream = BytesIO()
    with wave.open(stream, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(payload)
    return stream.getvalue(), pcm


def limit_bandwidth(samples: np.ndarray, cutoff_hz: float) -> np.ndarray:
    """Apply a smooth circular low-pass so pitch-scaled sources stay below Nyquist."""
    count = samples.size
    freqs = np.fft.rfftfreq(count, d=1.0 / RATE)
    transition_hz = min(600.0, cutoff_hz * 0.12)
    transition_start = cutoff_hz - transition_hz
    gain = np.ones(freqs.size, dtype=np.float64)
    gain[freqs >= cutoff_hz] = 0.0
    transition = (freqs > transition_start) & (freqs < cutoff_hz)
    progress = (freqs[transition] - transition_start) / transition_hz
    gain[transition] = 0.5 * (1.0 + np.cos(np.pi * progress))
    filtered = np.fft.irfft(np.fft.rfft(samples) * gain, n=count)
    return filtered


def round_metric(value: float) -> float:
    return round(float(value), 8)


def metrics(
    pcm: np.ndarray,
    seconds: float,
    *,
    bandlimit_hz: float | None = None,
) -> dict[str, float | int]:
    samples = pcm.astype(np.float64) / 32768.0
    steps = np.abs(np.diff(pcm.astype(np.int32))).astype(np.float64) / 32768.0
    seam_step = abs(int(pcm[0]) - int(pcm[-1])) / 32768.0
    step_p99 = float(np.percentile(steps, 99.0)) if steps.size else 0.0
    report: dict[str, float | int] = {
        "duration_s": round_metric(seconds),
        "sample_count": int(pcm.size),
        "peak": round_metric(float(np.max(np.abs(samples)))),
        "rms": round_metric(math.sqrt(float(np.mean(np.square(samples))))),
        "seam_step": round_metric(seam_step),
        "interior_step_p99": round_metric(step_p99),
        "seam_step_to_interior_p99": round_metric(seam_step / step_p99 if step_p99 else 0.0),
    }
    if bandlimit_hz is not None:
        spectrum = np.fft.rfft(samples)
        freqs = np.fft.rfftfreq(samples.size, d=1.0 / RATE)
        total_power = float(np.sum(np.square(np.abs(spectrum[1:]))))
        out_of_band_power = float(np.sum(np.square(np.abs(spectrum[freqs > bandlimit_hz]))))
        ratio = out_of_band_power / total_power if total_power else 0.0
        report["quantized_out_of_band_energy_db"] = round_metric(10.0 * math.log10(max(ratio, 1e-15)))
    return report


def generate(spec: AssetSpec) -> tuple[bytes, np.ndarray]:
    generator = GENERATORS[spec.kind][spec.filename]
    samples = generator(spec)
    if samples.size != sample_count(spec.seconds):
        raise ValueError(f"{spec.filename}: got {samples.size} samples for {spec.seconds}s")
    if spec.bandlimit_hz is not None:
        samples = limit_bandwidth(samples, spec.bandlimit_hz)
    return wav_bytes(samples)


def manifest_entry(spec: AssetSpec, wav_data: bytes, pcm: np.ndarray) -> dict[str, object]:
    entry: dict[str, object] = {
        "file": spec.filename,
        "category": spec.kind,
        "duration_s": round_metric(spec.seconds),
        "sample_rate_hz": RATE,
        "channels": 1,
        "sample_format": "signed 16-bit PCM little-endian",
        "loop": True,
        "base_frequency_hz": spec.base_hz,
        "frequency_note": spec.frequency_note,
        "source": "original procedural synthesis in tools/audio/generate.py",
        "playback_pitch_factor": spec.playback_pitch_factor,
        "bandlimit_hz": spec.bandlimit_hz,
        "highest_pitch_shifted_hz": round_metric(spec.bandlimit_hz * spec.playback_pitch_factor) if spec.bandlimit_hz is not None else None,
        "metrics": metrics(pcm, spec.seconds, bandlimit_hz=spec.bandlimit_hz),
        "sha256": hashlib.sha256(wav_data).hexdigest(),
    }
    if spec.bird_phrase is not None:
        entry["species"] = None
        entry["bird_label"] = "stylized synthetic phrase; not a real species or field recording"
    return entry


def manifest_for(generated: dict[str, tuple[bytes, np.ndarray]]) -> dict[str, object]:
    return {
        "format": FORMAT_NAME,
        "generator": "tools/audio/generate.py",
        "generator_version": GENERATOR_VERSION,
        "toolchain": {"python": platform.python_version(), "numpy": np.__version__},
        "license": "MIT",
        "license_file": "LICENSE.txt",
        "provenance": "All sounds are original offline synthesis. No recordings or third-party sample packs are included.",
        "sample_rate_hz": RATE,
        "channels": 1,
        "sample_format": "signed 16-bit PCM little-endian",
        "peak_target": TARGET_PEAK,
        "resampling_nyquist_hz": RATE / 2.0,
        "loop_construction": "Periodic integer-bin Fourier components; analytic waveform and slope repeat at the loop point. Bird phrases use zero-value, zero-slope endpoint fades. The circular cosine-tapered source low-pass has exact zero above its declared cap; PCM quantization leaves only a low-level out-of-band floor.",
        "runtime_loop_metadata": "Set AudioStreamWAV.loop_mode to LOOP_FORWARD and loop_end to sample_count when loading.",
        "assets": [manifest_entry(spec, *generated[spec.filename]) for spec in ASSETS],
    }


def encode_manifest(manifest: dict[str, object]) -> bytes:
    return (json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def read_wav(path: Path) -> tuple[int, int, int, np.ndarray]:
    with wave.open(str(path), "rb") as wav:
        channels = wav.getnchannels()
        width = wav.getsampwidth()
        rate = wav.getframerate()
        count = wav.getnframes()
        payload = wav.readframes(count)
    if width != 2:
        raise ValueError(f"{path.name}: expected 16-bit PCM, got {width * 8}-bit")
    samples = np.frombuffer(payload, dtype="<i2").copy()
    return channels, rate, count, samples


def check_existing(expected: dict[str, tuple[bytes, np.ndarray]], expected_manifest: bytes) -> None:
    failures: list[str] = []
    for spec in ASSETS:
        path = OUTPUT / spec.filename
        if not path.is_file():
            failures.append(f"missing {path.relative_to(ROOT)}")
            continue
        actual = path.read_bytes()
        expected_bytes, expected_pcm = expected[spec.filename]
        if actual != expected_bytes:
            failures.append(f"content differs from deterministic output: {spec.filename}")
        try:
            channels, rate, count, actual_pcm = read_wav(path)
        except (OSError, wave.Error, ValueError) as exc:
            failures.append(f"invalid WAV {spec.filename}: {exc}")
            continue
        if (channels, rate, count) != (1, RATE, sample_count(spec.seconds)):
            failures.append(f"wrong WAV header in {spec.filename}: {channels}ch {rate}Hz {count} frames")
        if not np.array_equal(actual_pcm, expected_pcm):
            failures.append(f"decoded PCM differs from generator: {spec.filename}")
        report = metrics(actual_pcm, spec.seconds, bandlimit_hz=spec.bandlimit_hz)
        if report["peak"] > 0.6:
            failures.append(f"peak exceeds 0.6 in {spec.filename}: {report['peak']}")
        if report["seam_step_to_interior_p99"] > 3.5:
            failures.append(f"unusually large loop-boundary sample step in {spec.filename}: {report['seam_step_to_interior_p99']}")
        if spec.bandlimit_hz is not None:
            highest_shifted = spec.bandlimit_hz * spec.playback_pitch_factor
            if highest_shifted >= SHIFTED_LIMIT_HZ:
                failures.append(f"{spec.filename}: shifted band limit reaches the output Nyquist margin ({highest_shifted:.1f} Hz)")
            if report["quantized_out_of_band_energy_db"] > -65.0:
                failures.append(f"{spec.filename}: too much quantized energy above {spec.bandlimit_hz:g} Hz ({report['quantized_out_of_band_energy_db']} dB)")

    manifest_path = OUTPUT / MANIFEST_NAME
    if not manifest_path.is_file():
        failures.append(f"missing {manifest_path.relative_to(ROOT)}")
    elif manifest_path.read_bytes() != expected_manifest:
        failures.append("manifest.json does not match the generated asset hashes or metrics")

    license_source = ROOT / "LICENSE"
    license_copy = OUTPUT / "LICENSE.txt"
    if not license_copy.is_file():
        failures.append("missing app/assets/audio/soundscape/LICENSE.txt")
    elif license_copy.read_bytes() != license_source.read_bytes():
        failures.append("soundscape LICENSE.txt differs from repository LICENSE")
    requirements = ROOT / "tools" / "audio" / "requirements.txt"
    if not requirements.is_file() or requirements.read_text(encoding="utf-8").strip() != f"numpy=={NUMPY_REQUIRED}":
        failures.append("tools/audio/requirements.txt must pin the checked NumPy version")

    if failures:
        raise SystemExit("Audio asset check failed:\n- " + "\n- ".join(failures))

    print(f"Checked {len(ASSETS)} WAVs at {RATE} Hz, mono, 16-bit; all match deterministic output.")
    for spec in ASSETS:
        wav_data, pcm = expected[spec.filename]
        report = metrics(pcm, spec.seconds, bandlimit_hz=spec.bandlimit_hz)
        digest = hashlib.sha256(wav_data).hexdigest()
        pitch_note = (
            f" cap<={spec.bandlimit_hz:.0f}Hz ×{spec.playback_pitch_factor:g}"
            f"(<{spec.bandlimit_hz * spec.playback_pitch_factor:.0f}Hz; oob={report['quantized_out_of_band_energy_db']:.1f}dB)"
            if spec.bandlimit_hz is not None
            else ""
        )
        print(
            f"  {spec.filename}: {report['duration_s']:>4}s peak={report['peak']:.4f} "
            f"rms={report['rms']:.4f} seam/p99={report['seam_step_to_interior_p99']:.3f}"
            f"{pitch_note} sha256={digest}"
        )


def write_all(generated: dict[str, tuple[bytes, np.ndarray]], manifest: bytes) -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for spec in ASSETS:
        (OUTPUT / spec.filename).write_bytes(generated[spec.filename][0])
    (OUTPUT / MANIFEST_NAME).write_bytes(manifest)
    (OUTPUT / "LICENSE.txt").write_bytes((ROOT / "LICENSE").read_bytes())
    print(f"Wrote {len(ASSETS)} original WAV loops and {MANIFEST_NAME} to {OUTPUT.relative_to(ROOT)}.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="regenerate in memory and verify WAV bytes, headers, metrics and manifest")
    args = parser.parse_args()

    generated: dict[str, tuple[bytes, np.ndarray]] = {}
    for spec in ASSETS:
        generated[spec.filename] = generate(spec)
    manifest = encode_manifest(manifest_for(generated))

    if args.check:
        check_existing(generated, manifest)
    else:
        write_all(generated, manifest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
