#!/usr/bin/env python3
"""Create reproducible, stylized wildlife WAVs for the OpenRC field soundscape."""

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
except ImportError as exc:  # pragma: no cover - depends on the tool host
    raise SystemExit("tools/audio/generate_wildlife.py requires NumPy 2.4.6.") from exc

NUMPY_REQUIRED = "2.4.6"
if np.__version__ != NUMPY_REQUIRED:
    raise SystemExit(f"Requires numpy=={NUMPY_REQUIRED}; found {np.__version__}.")

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "app" / "assets" / "audio" / "soundscape" / "wildlife"
RATE = 22_050
TARGET_PEAK = 0.46
MAX_SOURCE_HZ = 9_500.0
MAX_PCM_BYTES = int(2.5 * 1024 * 1024)
FORMAT = "openrc-audio-wildlife-v1"
GENERATOR_VERSION = "1"


@dataclass(frozen=True)
class Call:
    start: float
    length: float
    low_hz: float
    high_hz: float
    level: float
    noise: float
    vibrato_hz: float = 0.0
    vibrato_depth_hz: float = 0.0


@dataclass(frozen=True)
class Asset:
    filename: str
    category: str
    duration_s: float
    seed: int
    base_hz: float
    description: str
    loop: bool
    calls: tuple[Call, ...] = ()


ASSETS = (
    Asset("dog_01.wav", "dog_bark", 1.35, 0xA05101, 112, "Two short woody, low-register barks with a rough breath edge", False, (
        Call(0.13, 0.27, 128, 91, 0.95, 0.38), Call(0.56, 0.32, 115, 84, 0.82, 0.43), Call(0.98, 0.22, 103, 78, 0.66, 0.35),
    )),
    Asset("dog_02.wav", "dog_bark", 1.55, 0xA05102, 94, "A lower double woof followed by a softer trailing bark", False, (
        Call(0.17, 0.36, 100, 74, 0.90, 0.47), Call(0.68, 0.35, 95, 70, 0.84, 0.45), Call(1.17, 0.23, 86, 72, 0.57, 0.34),
    )),
    Asset("dog_03.wav", "dog_bark", 1.70, 0xA05103, 138, "A brighter, quicker three-note raspy bark phrase", False, (
        Call(0.14, 0.23, 155, 112, 0.78, 0.45), Call(0.50, 0.28, 145, 98, 0.97, 0.50), Call(0.92, 0.34, 127, 88, 0.85, 0.43),
    )),
    Asset("crow_01.wav", "crow_caw", 1.50, 0xA05201, 650, "A pair of dry descending caws with a rasping upper edge", False, (
        Call(0.13, 0.40, 760, 510, 0.90, 0.42), Call(0.72, 0.42, 700, 455, 0.84, 0.46),
    )),
    Asset("crow_02.wav", "crow_caw", 1.65, 0xA05202, 510, "Three irregular, mid-low caws with fluttering vocal texture", False, (
        Call(0.12, 0.29, 610, 430, 0.75, 0.42), Call(0.54, 0.36, 580, 390, 0.96, 0.50), Call(1.08, 0.35, 545, 365, 0.78, 0.43),
    )),
    Asset("crow_03.wav", "crow_caw", 1.40, 0xA05203, 720, "A brisk rising-then-falling caw pair, slightly higher and thinner", False, (
        Call(0.11, 0.31, 625, 820, 0.84, 0.45), Call(0.61, 0.42, 790, 475, 0.93, 0.52),
    )),
    Asset("owl_01.wav", "owl_hoot", 1.85, 0xA05301, 385, "A soft, rounded two-hoo phrase with a faint airy undertone", False, (
        Call(0.16, 0.50, 410, 350, 0.91, 0.12, 4.1, 5.0), Call(0.96, 0.52, 385, 328, 0.72, 0.13, 3.7, 4.0),
    )),
    Asset("owl_02.wav", "owl_hoot", 2.05, 0xA05302, 470, "Three quieter hoots with varied pitch and spacing", False, (
        Call(0.13, 0.37, 470, 398, 0.75, 0.14, 3.4, 4.0), Call(0.72, 0.43, 440, 380, 0.92, 0.13, 3.1, 4.0), Call(1.40, 0.39, 420, 355, 0.69, 0.15, 3.8, 3.5),
    )),
    Asset("owl_03.wav", "owl_hoot", 2.20, 0xA05303, 342, "A lower, longer pair of soft hollow hoots", False, (
        Call(0.14, 0.66, 365, 312, 0.94, 0.15, 2.8, 3.7), Call(1.15, 0.62, 348, 301, 0.82, 0.16, 2.5, 3.0),
    )),
    Asset("bird_01.wav", "bird_trill", 1.20, 0xA05401, 3_250, "Stylized synthetic chip chatter in short rising groups; not a species call", False),
    Asset("bird_02.wav", "bird_trill", 1.40, 0xA05402, 4_050, "Stylized synthetic rapid trill bursts with dry chatter; not a species call", False),
    Asset("bird_03.wav", "bird_trill", 1.60, 0xA05403, 2_850, "Stylized synthetic broken warble and quick chirr notes; not a species call", False),
    Asset("bird_04.wav", "bird_trill", 1.75, 0xA05404, 3_650, "Stylized synthetic alternating chatter and a short high trill; not a species call", False),
    Asset("cricket_01.wav", "cricket_bed", 17.0, 0xA05501, 4_850, "Sparse asynchronous chirrup pulses from three differently filtered colonies", True),
    Asset("cricket_02.wav", "cricket_bed", 19.0, 0xA05502, 5_400, "Denser, faster pulse groups from offset colonies with a softer distant bed", True),
)


STYLE = {
    "bird_trill": {
        "formants": ((2_650, 760, 0.72), (4_650, 1_000, 0.88), (6_850, 1_100, 0.62)),
        "rolloff": 0.52,
        "noise_band": (1_350, 8_700),
        "flutter_hz": 0.0,
        "flutter_depth": 0.0,
        "attack_s": 0.004,
        "release_s": 0.012,
    },
    "dog_bark": {
        "formants": ((390, 220, 1.20), (850, 370, 1.00), (1_550, 570, 0.70), (2_750, 900, 0.30)),
        "rolloff": 0.88,
        "noise_band": (220, 7_700),
        "flutter_hz": 27.0,
        "flutter_depth": 0.14,
        "attack_s": 0.010,
        "release_s": 0.070,
    },
    "crow_caw": {
        "formants": ((730, 340, 0.80), (1_330, 470, 1.10), (2_330, 750, 0.82), (3_750, 1_100, 0.44)),
        "rolloff": 0.66,
        "noise_band": (350, 8_700),
        "flutter_hz": 19.0,
        "flutter_depth": 0.20,
        "attack_s": 0.014,
        "release_s": 0.095,
    },
    "owl_hoot": {
        "formants": ((360, 210, 1.15), (720, 330, 0.55), (1_350, 520, 0.24), (2_250, 850, 0.10)),
        "rolloff": 1.12,
        "noise_band": (130, 4_600),
        "flutter_hz": 4.0,
        "flutter_depth": 0.045,
        "attack_s": 0.085,
        "release_s": 0.145,
    },
}


def frame_count(seconds: float) -> int:
    return int(round(seconds * RATE))


def colored_noise(count: int, seed: int, low_hz: float, high_hz: float, tilt: float = 0.0) -> np.ndarray:
    """Return unit-RMS noise with a periodic DFT shape and a strict source cap."""
    rng = np.random.Generator(np.random.PCG64(seed))
    raw = rng.standard_normal(count)
    freqs = np.fft.rfftfreq(count, d=1.0 / RATE)
    safe = np.maximum(freqs, max(low_hz, 1.0))
    low = 1.0 / np.sqrt(1.0 + np.power(max(low_hz, 0.01) / np.maximum(freqs, 0.01), 8.0))
    high = 1.0 / np.sqrt(1.0 + np.power(np.maximum(freqs, 0.01) / max(high_hz, 1.0), 8.0))
    shape = low * high * np.power(safe / 1_000.0, -0.5 * tilt)
    cap_start = MAX_SOURCE_HZ - 650.0
    cap = np.ones(freqs.size, dtype=np.float64)
    cap[freqs >= MAX_SOURCE_HZ] = 0.0
    transition = (freqs > cap_start) & (freqs < MAX_SOURCE_HZ)
    cap[transition] = 0.5 * (1.0 + np.cos(np.pi * (freqs[transition] - cap_start) / (MAX_SOURCE_HZ - cap_start)))
    shape *= cap
    shape[0] = 0.0
    spectrum = np.fft.rfft(raw) * shape
    result = np.fft.irfft(spectrum, n=count)
    rms = float(np.sqrt(np.mean(np.square(result))))
    if not math.isfinite(rms) or rms <= 1e-12:
        raise ValueError("noise synthesis produced an empty or non-finite signal")
    return result / rms


def smooth_gate(count: int, attack_s: float, release_s: float) -> np.ndarray:
    envelope = np.ones(count, dtype=np.float64)
    if count < 3:
        return np.zeros(count, dtype=np.float64)
    attack = min(max(2, int(round(attack_s * RATE))), count // 3)
    release = min(max(2, int(round(release_s * RATE))), count // 3)
    x = np.arange(attack, dtype=np.float64) / (attack - 1)
    envelope[:attack] = 0.5 - 0.5 * np.cos(np.pi * x)
    x = np.arange(release, dtype=np.float64) / (release - 1)
    envelope[-release:] = 0.5 + 0.5 * np.cos(np.pi * x)
    envelope[0] = 0.0
    envelope[-1] = 0.0
    return envelope


def vocal_note(call: Call, category: str, seed: int) -> np.ndarray:
    count = frame_count(call.length)
    if count < 8:
        raise ValueError("vocal notes must contain at least eight samples")
    style = STYLE[category]
    t = np.arange(count, dtype=np.float64) / RATE
    duration = (count - 1) / RATE
    u = t / duration
    smooth = u * u * (3.0 - 2.0 * u)
    fundamental = call.low_hz + (call.high_hz - call.low_hz) * smooth
    phase_cycles = call.low_hz * t + (call.high_hz - call.low_hz) * duration * (u**3 - 0.5 * u**4)
    if call.vibrato_hz > 0.0 and call.vibrato_depth_hz > 0.0:
        phase_cycles += call.vibrato_depth_hz / (2.0 * np.pi * call.vibrato_hz) * (1.0 - np.cos(2.0 * np.pi * call.vibrato_hz * t))
        fundamental += call.vibrato_depth_hz * np.sin(2.0 * np.pi * call.vibrato_hz * t)

    max_fundamental = max(call.low_hz, call.high_hz) + call.vibrato_depth_hz
    harmonics = max(1, int((MAX_SOURCE_HZ - 800.0) // max_fundamental))
    phase_rng = np.random.Generator(np.random.PCG64(seed ^ 0x75A0))
    harmonic_sum = np.zeros(count, dtype=np.float64)
    weight_power = np.zeros(count, dtype=np.float64)
    for k in range(1, harmonics + 1):
        harmonic_hz = fundamental * k
        formant = np.full(count, 0.035, dtype=np.float64)
        for center, width, gain in style["formants"]:
            formant += gain * np.exp(-0.5 * np.square((harmonic_hz - center) / width))
        weight = formant / (k ** float(style["rolloff"]))
        harmonic_sum += weight * np.sin(2.0 * np.pi * phase_cycles * k + phase_rng.uniform(-np.pi, np.pi))
        weight_power += np.square(weight)
    harmonic_sum /= np.sqrt(np.maximum(weight_power, 1e-12))
    low_noise, high_noise = style["noise_band"]
    breath = colored_noise(count, seed + 0x1357, low_noise, min(high_noise, MAX_SOURCE_HZ - 150.0), tilt=0.22)
    envelope = smooth_gate(count, float(style["attack_s"]), float(style["release_s"]))
    flutter = 1.0 + float(style["flutter_depth"]) * np.sin(2.0 * np.pi * float(style["flutter_hz"]) * t + 0.3)
    if category == "dog_bark":
        flutter *= 1.0 + 0.055 * np.sin(2.0 * np.pi * 53.0 * t + 0.7)
    if category == "crow_caw":
        flutter *= 1.0 + 0.07 * np.sin(2.0 * np.pi * 33.0 * t + 0.2)
    return call.level * envelope * flutter * (harmonic_sum + call.noise * breath)


def add_at(output: np.ndarray, signal: np.ndarray, start_s: float) -> None:
    start = int(round(start_s * RATE))
    if start < 0 or start + signal.size > output.size:
        raise ValueError(f"call at {start_s:g}s extends outside its asset")
    output[start : start + signal.size] += signal


def endpoint_fade(samples: np.ndarray, fade_s: float = 0.055) -> np.ndarray:
    count = samples.size
    t = np.arange(count, dtype=np.float64) / RATE
    last_t = (count - 1) / RATE
    edge_distance = np.minimum(t, last_t - t)
    x = np.clip(edge_distance / fade_s, 0.0, 1.0)
    fade = np.square(np.sin(0.5 * np.pi * x))
    faded = samples * fade
    faded[0] = 0.0
    faded[-1] = 0.0
    return faded


def add_short_echo(samples: np.ndarray, delays: Iterable[tuple[float, float]]) -> np.ndarray:
    result = samples.copy()
    for delay_s, gain in delays:
        delay = int(round(delay_s * RATE))
        if 0 < delay < samples.size:
            result[delay:] += samples[:-delay] * gain
    return result


def make_vocal_phrase(asset: Asset) -> np.ndarray:
    output = np.zeros(frame_count(asset.duration_s), dtype=np.float64)
    for index, call in enumerate(asset.calls):
        add_at(output, vocal_note(call, asset.category, asset.seed + index * 7919), call.start)
    if asset.category == "dog_bark":
        output = add_short_echo(output, ((0.035, 0.12), (0.069, 0.045)))
    elif asset.category == "crow_caw":
        output = add_short_echo(output, ((0.028, 0.08), (0.055, 0.035)))
    return endpoint_fade(output)


def add_circular_pulse(
    output: np.ndarray,
    start_sample: int,
    center_hz: float,
    length_s: float,
    level: float,
    seed: int,
) -> None:
    count = frame_count(length_s)
    t = np.arange(count, dtype=np.float64) / RATE
    u = np.arange(count, dtype=np.float64) / max(count - 1, 1)
    env = np.square(np.sin(np.pi * u))
    env *= 0.78 + 0.22 * np.sin(np.pi * u)
    rng = np.random.Generator(np.random.PCG64(seed))
    phase = rng.uniform(-np.pi, np.pi)
    tone = np.sin(2.0 * np.pi * center_hz * t + phase)
    if 2.0 * center_hz < MAX_SOURCE_HZ - 400.0:
        tone += 0.22 * np.sin(4.0 * np.pi * center_hz * t + phase * 0.55 + 0.3)
    if 3.0 * center_hz < MAX_SOURCE_HZ - 400.0:
        tone += 0.075 * np.sin(6.0 * np.pi * center_hz * t + phase * 0.31 + 0.7)
    rasp = colored_noise(count, seed + 17, 1_800, MAX_SOURCE_HZ - 200.0, tilt=-0.15)
    pulse = level * env * (tone + 0.46 * rasp)
    indices = (start_sample + np.arange(count, dtype=np.int64)) % output.size
    output[indices] += pulse


def circular_gaussian_envelope(t: np.ndarray, duration: float, center: float, width: float) -> np.ndarray:
    distance = np.mod(t - center + 0.5 * duration, duration) - 0.5 * duration
    return np.exp(-0.5 * np.square(distance / width))


def make_cricket(asset: Asset) -> np.ndarray:
    count = frame_count(asset.duration_s)
    duration = count / RATE
    t = np.arange(count, dtype=np.float64) / RATE
    rng = np.random.Generator(np.random.PCG64(asset.seed))
    output = np.zeros(count, dtype=np.float64)
    # center Hz, level, pulse groups per second range, pulse count range, spacing
    if asset.filename == "cricket_01.wav":
        colonies = (
            (4_600.0, 0.78, (0.45, 0.88), (5, 8), (0.020, 0.027), 0.115),
            (5_850.0, 0.34, (0.28, 0.58), (4, 7), (0.027, 0.036), 0.096),
            (7_150.0, 0.18, (0.13, 0.31), (3, 5), (0.032, 0.044), 0.080),
        )
    else:
        colonies = (
            (4_250.0, 0.62, (0.70, 1.12), (4, 7), (0.017, 0.024), 0.108),
            (5_300.0, 0.52, (0.52, 0.88), (6, 10), (0.023, 0.030), 0.115),
            (7_400.0, 0.23, (0.19, 0.40), (3, 6), (0.030, 0.042), 0.072),
        )

    colony_notes: list[tuple[float, float, float]] = []
    for colony_index, (center_hz, colony_level, rate_range, pulse_range, spacing_range, pulse_len) in enumerate(colonies):
        colony_rng = np.random.Generator(np.random.PCG64(asset.seed + 10_003 * (colony_index + 1)))
        event_start = float(colony_rng.uniform(0.0, duration))
        event_number = 0
        while event_start < duration:
            burst_count = int(colony_rng.integers(pulse_range[0], pulse_range[1] + 1))
            spacing = float(colony_rng.uniform(*spacing_range))
            jitter = float(colony_rng.uniform(-0.006, 0.006))
            center = event_start % duration
            group_width = max(pulse_len, (burst_count - 1) * spacing + pulse_len)
            colony_notes.append((center, group_width, colony_level))
            for pulse_index in range(burst_count):
                onset = event_start + jitter + pulse_index * spacing
                frequency = center_hz * float(colony_rng.uniform(0.986, 1.014))
                length = pulse_len * float(colony_rng.uniform(0.82, 1.16))
                level = colony_level * float(colony_rng.uniform(0.68, 1.0))
                add_circular_pulse(
                    output,
                    int(round(onset * RATE)) % count,
                    frequency,
                    length,
                    level,
                    asset.seed + colony_index * 100_000 + event_number * 101 + pulse_index,
                )
            interval = float(colony_rng.uniform(1.0 / rate_range[1], 1.0 / rate_range[0]))
            event_start += max(interval, group_width + 0.08)
            event_number += 1

        bed = colored_noise(count, asset.seed + 900_000 + colony_index, center_hz - 1_050, min(center_hz + 1_250, MAX_SOURCE_HZ - 80.0), tilt=0.18)
        activity = np.full(count, 0.035, dtype=np.float64)
        for center, width, _ in colony_notes:
            activity += 0.24 * circular_gaussian_envelope(t, duration, center + width * 0.44, max(width * 0.58, 0.10))
        slow = colored_noise(count, asset.seed + 910_000 + colony_index, 0.12, 0.9, tilt=0.6)
        bed *= activity * np.clip(0.78 + 0.10 * slow, 0.48, 1.12)
        output += colony_level * 0.19 * bed
        colony_notes.clear()

    # The events are placed on a circular sample buffer and each burst envelope
    # returns smoothly to zero, so the seam is a normal adjacent sample pair.
    return output


def make_bird_chatter(asset: Asset) -> np.ndarray:
    count = frame_count(asset.duration_s)
    rng = np.random.Generator(np.random.PCG64(asset.seed))
    output = np.zeros(count, dtype=np.float64)
    # Compact note layouts differ in pulse count, speed, and register.
    layouts = {
        "bird_01.wav": ((0.11, 0.050, 5, 3_100, 3_950), (0.50, 0.043, 6, 3_500, 4_450), (0.91, 0.057, 4, 2_850, 3_650)),
        "bird_02.wav": ((0.12, 0.020, 15, 3_750, 4_950), (0.66, 0.024, 12, 4_200, 5_450), (1.04, 0.043, 5, 3_250, 4_150)),
        "bird_03.wav": ((0.12, 0.044, 5, 2_450, 3_150), (0.48, 0.030, 9, 2_950, 4_100), (1.02, 0.053, 5, 3_450, 4_700)),
        "bird_04.wav": ((0.10, 0.040, 6, 2_950, 3_750), (0.51, 0.064, 4, 2_100, 2_850), (0.91, 0.021, 14, 4_350, 5_700), (1.39, 0.043, 4, 3_300, 4_250)),
    }
    for group_index, (start, spacing, notes, low_hz, high_hz) in enumerate(layouts[asset.filename]):
        group_jitter = float(rng.uniform(-0.018, 0.018))
        for note_index in range(notes):
            length = float(rng.uniform(0.018, 0.052))
            onset = start + group_jitter + note_index * spacing + float(rng.uniform(-0.009, 0.009))
            if onset + length >= asset.duration_s - 0.09:
                continue
            # Each chip uses a fundamental plus formant-weighted partials and
            # a short breath rasp. Partial energy is bounded below 9.5 kHz.
            f0 = float(rng.uniform(low_hz, high_hz))
            f1 = f0 * float(rng.uniform(0.88, 1.15))
            call = Call(onset, length, f0, f1, float(rng.uniform(0.60, 1.0)), float(rng.uniform(0.30, 0.56)), 0.0, 0.0)
            local = vocal_note(call, "bird_trill", asset.seed + group_index * 10_007 + note_index * 67)
            add_at(output, local, onset)
    # Add a few low-level scratchy chatter clicks to separate the styles from
    # pure whistle tones without introducing any learned species recording.
    noise = colored_noise(count, asset.seed + 0x4400, 1_500, MAX_SOURCE_HZ - 200.0, tilt=0.12)
    envelope = np.zeros(count, dtype=np.float64)
    for start, spacing, notes, _low, _high in layouts[asset.filename]:
        for n in range(notes):
            center = start + n * spacing + 0.5 * spacing
            envelope += 0.025 * circular_gaussian_envelope(np.arange(count) / RATE, asset.duration_s, center % asset.duration_s, 0.018)
    output += noise * np.clip(envelope, 0.0, 0.08)
    return endpoint_fade(output, 0.045)


def build(asset: Asset) -> np.ndarray:
    if asset.category in ("dog_bark", "crow_caw", "owl_hoot"):
        result = make_vocal_phrase(asset)
    elif asset.category == "bird_trill":
        result = make_bird_chatter(asset)
    elif asset.category == "cricket_bed":
        result = make_cricket(asset)
    else:  # pragma: no cover - asset table is source-controlled
        raise ValueError(f"unknown category {asset.category}")
    if result.size != frame_count(asset.duration_s):
        raise ValueError(f"{asset.filename}: generated {result.size} samples instead of {frame_count(asset.duration_s)}")
    return limit_bandwidth(result, MAX_SOURCE_HZ)


def limit_bandwidth(samples: np.ndarray, cutoff_hz: float) -> np.ndarray:
    count = samples.size
    freqs = np.fft.rfftfreq(count, d=1.0 / RATE)
    transition = min(600.0, cutoff_hz * 0.08)
    start = cutoff_hz - transition
    gain = np.ones(freqs.size, dtype=np.float64)
    gain[freqs >= cutoff_hz] = 0.0
    band = (freqs > start) & (freqs < cutoff_hz)
    gain[band] = 0.5 * (1.0 + np.cos(np.pi * (freqs[band] - start) / transition))
    return np.fft.irfft(np.fft.rfft(samples) * gain, n=count)


def to_wav(samples: np.ndarray) -> tuple[bytes, np.ndarray]:
    peak = float(np.max(np.abs(samples)))
    if not math.isfinite(peak) or peak <= 1e-12:
        raise ValueError("generated audio is silent or non-finite")
    scaled = samples * min(TARGET_PEAK / peak, 4.0)
    peak_after = float(np.max(np.abs(scaled)))
    if peak_after > TARGET_PEAK + 1e-10:
        scaled *= TARGET_PEAK / peak_after
    pcm = np.rint(np.clip(scaled, -TARGET_PEAK, TARGET_PEAK) * 32767.0).astype("<i2")
    from io import BytesIO

    stream = BytesIO()
    with wave.open(stream, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm.tobytes())
    return stream.getvalue(), pcm


def round_metric(value: float) -> float:
    return round(float(value), 8)


def metrics(pcm: np.ndarray, asset: Asset) -> dict[str, float | int]:
    values = pcm.astype(np.float64) / 32768.0
    peak = float(np.max(np.abs(values)))
    rms = math.sqrt(float(np.mean(np.square(values))))
    result: dict[str, float | int] = {
        "duration_s": round_metric(pcm.size / RATE),
        "sample_count": int(pcm.size),
        "decoded_pcm_bytes": int(pcm.nbytes),
        "peak": round_metric(peak),
        "rms": round_metric(rms),
        "start_peak": round_metric(float(np.max(np.abs(values[: max(1, round(0.020 * RATE))])))),
        "end_peak": round_metric(float(np.max(np.abs(values[-max(1, round(0.020 * RATE)) :])))),
    }
    if asset.loop:
        steps = np.abs(np.diff(pcm.astype(np.int32))).astype(np.float64)
        seam = abs(int(pcm[0]) - int(pcm[-1]))
        interior_p99 = float(np.percentile(steps, 99.0)) if steps.size else 0.0
        curvature = np.abs(np.diff(pcm.astype(np.int32), n=2)).astype(np.float64)
        seam_curvature = abs((int(pcm[1]) - int(pcm[0])) - (int(pcm[0]) - int(pcm[-1])))
        curvature_p99 = float(np.percentile(curvature, 99.0)) if curvature.size else 0.0
        result.update({
            "seam_step": round_metric(seam / 32768.0),
            "interior_step_p99": round_metric(interior_p99 / 32768.0),
            "seam_step_to_interior_p99": round_metric(seam / interior_p99 if interior_p99 else 0.0),
            "seam_curvature": round_metric(seam_curvature / 32768.0),
            "interior_curvature_p99": round_metric(curvature_p99 / 32768.0),
            "seam_curvature_to_interior_p99": round_metric(seam_curvature / curvature_p99 if curvature_p99 else 0.0),
        })
    spectrum = np.fft.rfft(values)
    freqs = np.fft.rfftfreq(values.size, d=1.0 / RATE)
    total_power = float(np.sum(np.square(np.abs(spectrum[1:]))))
    oob_power = float(np.sum(np.square(np.abs(spectrum[freqs > MAX_SOURCE_HZ]))))
    result["quantized_out_of_band_energy_db"] = round_metric(10.0 * math.log10(max(oob_power / total_power if total_power else 0.0, 1e-15)))
    return result


def generated_assets() -> dict[str, tuple[bytes, np.ndarray]]:
    return {asset.filename: to_wav(build(asset)) for asset in ASSETS}


def make_manifest(generated: dict[str, tuple[bytes, np.ndarray]]) -> dict[str, object]:
    entries = []
    for asset in ASSETS:
        wav_data, pcm = generated[asset.filename]
        entry: dict[str, object] = {
            "file": asset.filename,
            "category": asset.category,
            "duration_s": round_metric(pcm.size / RATE),
            "sample_rate_hz": RATE,
            "channels": 1,
            "sample_format": "signed 16-bit PCM little-endian",
            "sample_count": int(pcm.size),
            "decoded_pcm_bytes": int(pcm.nbytes),
            "loop": asset.loop,
            "base_frequency_hz": round_metric(asset.base_hz),
            "frequency_note": asset.description,
            "source": "original procedural synthesis in tools/audio/generate_wildlife.py",
            "playback_pitch_factor_max": 1.1,
            "bandlimit_hz": MAX_SOURCE_HZ,
            "metrics": metrics(pcm, asset),
            "sha256": hashlib.sha256(wav_data).hexdigest(),
        }
        if asset.category in {"bird_trill", "crow_caw", "owl_hoot"}:
            entry["species"] = None
            entry["recording"] = False
            entry["stylized_synthesis"] = "Original synthetic sound; not a field recording or representation of a real species."
        entries.append(entry)
    pcm_bytes = sum(int(entry["decoded_pcm_bytes"]) for entry in entries)
    return {
        "format": FORMAT,
        "generator": "tools/audio/generate_wildlife.py",
        "generator_version": GENERATOR_VERSION,
        "toolchain": {"python": platform.python_version(), "numpy": np.__version__},
        "license": "MIT",
        "license_file": "LICENSE.txt",
        "provenance": "All fifteen sounds are original offline synthesis. No recordings, downloads, or third-party sample packs are included.",
        "sample_rate_hz": RATE,
        "channels": 1,
        "sample_format": "signed 16-bit PCM little-endian",
        "peak_target": TARGET_PEAK,
        "peak_limit": 0.48,
        "pitch_factor_max": 1.1,
        "source_bandlimit_hz": MAX_SOURCE_HZ,
        "highest_shifted_bandlimit_hz": round_metric(MAX_SOURCE_HZ * 1.1),
        "resampling_nyquist_hz": RATE / 2.0,
        "decoded_pcm_bytes": pcm_bytes,
        "decoded_pcm_budget_bytes": MAX_PCM_BYTES,
        "decoded_pcm_mib": round_metric(pcm_bytes / (1024.0 * 1024.0)),
        "loop_method": "Cricket calls and slow colony envelopes are placed on a circular sample buffer; band-limited periodic noise is generated from whole-loop DFTs. Boundary values are ordinary neighboring samples, not forced equal. One-shots use smooth attack/release and endpoint fades.",
        "runtime_loop_metadata": "Cricket files are forward-loop candidates; set AudioStreamWAV.loop_mode=LOOP_FORWARD and loop_end to sample_count in the runtime caller. Other wildlife files are one-shots.",
        "import_sidecar_contract": "Godot WAV imports use PCM with compress/mode=0; import loop metadata remains disabled because runtime callers choose loop behavior.",
        "assets": entries,
    }


def encode_manifest(manifest: dict[str, object]) -> bytes:
    return (json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def read_wav(path: Path) -> tuple[int, int, int, np.ndarray]:
    with wave.open(str(path), "rb") as wav:
        channels, width, rate, count = wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes()
        payload = wav.readframes(count)
    if width != 2:
        raise ValueError(f"expected 16-bit PCM, got {width * 8}-bit")
    pcm = np.frombuffer(payload, dtype="<i2").copy()
    return channels, rate, count, pcm


def check_import_sidecar(path: Path) -> str | None:
    sidecar = Path(str(path) + ".import")
    if not sidecar.is_file():
        return f"missing Godot import sidecar {sidecar.relative_to(ROOT)}"
    content = sidecar.read_text(encoding="utf-8")
    if "compress/mode=0" not in content.splitlines():
        return f"{sidecar.relative_to(ROOT)} must explicitly set compress/mode=0 (PCM)"
    if "edit/loop_mode=0" not in content.splitlines():
        return f"{sidecar.relative_to(ROOT)} must keep importer loop mode disabled"
    return None


def check_existing(generated: dict[str, tuple[bytes, np.ndarray]], manifest_bytes: bytes) -> None:
    failures: list[str] = []
    wav_paths = sorted(path.name for path in OUTPUT.glob("*.wav"))
    expected_names = sorted(asset.filename for asset in ASSETS)
    if wav_paths != expected_names:
        failures.append(f"expected exactly {len(expected_names)} wildlife WAVs; found {wav_paths}")
    pcm_total = 0
    for asset in ASSETS:
        path = OUTPUT / asset.filename
        expected_wav, expected_pcm = generated[asset.filename]
        pcm_total += expected_pcm.nbytes
        if not path.is_file():
            failures.append(f"missing {path.relative_to(ROOT)}")
            continue
        actual_wav = path.read_bytes()
        if actual_wav != expected_wav:
            failures.append(f"WAV bytes differ from deterministic output: {asset.filename}")
        try:
            channels, rate, count, actual_pcm = read_wav(path)
        except (OSError, wave.Error, ValueError) as exc:
            failures.append(f"invalid WAV {asset.filename}: {exc}")
            continue
        if (channels, rate, count) != (1, RATE, frame_count(asset.duration_s)):
            failures.append(f"bad WAV header in {asset.filename}: {channels}ch {rate}Hz {count} frames")
        if not np.array_equal(actual_pcm, expected_pcm):
            failures.append(f"decoded PCM differs from fixed-seed synthesis: {asset.filename}")
        report = metrics(actual_pcm, asset)
        if report["peak"] > 0.48:
            failures.append(f"peak exceeds 0.48 in {asset.filename}: {report['peak']}")
        if report["quantized_out_of_band_energy_db"] > -60.0:
            failures.append(f"too much quantized energy above {MAX_SOURCE_HZ:g} Hz in {asset.filename}: {report['quantized_out_of_band_energy_db']} dB")
        if asset.loop:
            if report["seam_step_to_interior_p99"] > 3.5:
                failures.append(f"loop seam step is an outlier in {asset.filename}: {report['seam_step_to_interior_p99']}")
            if report["seam_curvature_to_interior_p99"] > 4.0:
                failures.append(f"loop seam slope change is an outlier in {asset.filename}: {report['seam_curvature_to_interior_p99']}")
        elif report["start_peak"] > 0.002 or report["end_peak"] > 0.002:
            failures.append(f"one-shot endpoint fade is too loud in {asset.filename}: start={report['start_peak']} end={report['end_peak']}")
        sidecar_failure = check_import_sidecar(path)
        if sidecar_failure:
            failures.append(sidecar_failure)

    if pcm_total > MAX_PCM_BYTES:
        failures.append(f"decoded PCM exceeds 2.5 MiB budget: {pcm_total} bytes")
    manifest_path = OUTPUT / "manifest.json"
    if not manifest_path.is_file():
        failures.append(f"missing {manifest_path.relative_to(ROOT)}")
    elif manifest_path.read_bytes() != manifest_bytes:
        failures.append("manifest.json differs from deterministic metadata and WAV hashes")
    license_source = ROOT / "LICENSE"
    license_copy = OUTPUT / "LICENSE.txt"
    if not license_copy.is_file():
        failures.append(f"missing {license_copy.relative_to(ROOT)}")
    elif license_copy.read_bytes() != license_source.read_bytes():
        failures.append("wildlife LICENSE.txt differs from repository MIT LICENSE")

    if failures:
        raise SystemExit("Wildlife asset check failed:\n- " + "\n- ".join(failures))
    print(f"Checked {len(ASSETS)} original mono 16-bit/22,050 Hz WAVs; decoded PCM {pcm_total} bytes ({pcm_total / (1024 * 1024):.3f} MiB).")
    for asset in ASSETS:
        wav_data, pcm = generated[asset.filename]
        report = metrics(pcm, asset)
        loop_text = (
            f" seam/p99={report['seam_step_to_interior_p99']:.3f} curvature/p99={report['seam_curvature_to_interior_p99']:.3f}"
            if asset.loop else f" fades={report['start_peak']:.5f}/{report['end_peak']:.5f}"
        )
        print(
            f"  {asset.filename}: {report['duration_s']:.3f}s peak={report['peak']:.4f} rms={report['rms']:.4f}"
            f"{loop_text} OOB={report['quantized_out_of_band_energy_db']:.1f}dB sha256={hashlib.sha256(wav_data).hexdigest()}"
        )


def write_all(generated: dict[str, tuple[bytes, np.ndarray]], manifest_bytes: bytes) -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for asset in ASSETS:
        (OUTPUT / asset.filename).write_bytes(generated[asset.filename][0])
    (OUTPUT / "manifest.json").write_bytes(manifest_bytes)
    (OUTPUT / "LICENSE.txt").write_bytes((ROOT / "LICENSE").read_bytes())
    total = sum(pcm.nbytes for _wav, pcm in generated.values())
    if total > MAX_PCM_BYTES:
        raise SystemExit(f"Generated decoded PCM exceeds 2.5 MiB: {total} bytes")
    print(f"Wrote {len(ASSETS)} wildlife WAVs and manifest ({total} decoded PCM bytes) to {OUTPUT.relative_to(ROOT)}.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="regenerate in memory and check WAVs, levels, seams, license and PCM imports")
    args = parser.parse_args()
    generated = generated_assets()
    manifest_bytes = encode_manifest(make_manifest(generated))
    if args.check:
        check_existing(generated, manifest_bytes)
    else:
        write_all(generated, manifest_bytes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
