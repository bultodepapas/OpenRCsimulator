#!/usr/bin/env python3
"""Generate deterministic, original offline crash-audio WAVs (Python stdlib only)."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import struct
import tempfile
import wave
from pathlib import Path


RATE = 22_050
SEED = 20261011
VERSION = "1"
ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUTPUT = ROOT / "app" / "assets" / "audio" / "crash"


def _noise(count: int, rng: random.Random) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(count)]


def _lowpass(values: list[float], cutoff_hz: float) -> list[float]:
    if not values:
        return []
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / RATE)
    state = 0.0
    result: list[float] = []
    for value in values:
        state += alpha * (value - state)
        result.append(state)
    return result


def _env(t: float, attack: float, decay: float, length: float) -> float:
    if t < 0.0 or t >= length:
        return 0.0
    fade_in = min(1.0, t / max(attack, 1.0 / RATE))
    return fade_in * math.exp(-t / max(decay, 1.0 / RATE))


def _normalize(values: list[float], peak: float) -> list[float]:
    maximum = max((abs(value) for value in values), default=0.0)
    if maximum <= 1e-12:
        return values
    scale = peak / maximum
    return [value * scale for value in values]


def _write_wav(path: Path, values: list[float]) -> dict[str, object]:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = bytearray()
    peak = 0.0
    squared = 0.0
    for value in values:
        sample = max(-0.98, min(0.98, float(value)))
        peak = max(peak, abs(sample))
        squared += sample * sample
        pcm.extend(struct.pack("<h", round(sample * 32767.0)))
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(pcm)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return {
        "file": path.name,
        "sample_rate_hz": RATE,
        "channels": 1,
        "sample_format": "signed 16-bit PCM little-endian",
        "sample_count": len(values),
        "duration_s": round(len(values) / RATE, 6),
        "peak": round(peak, 6),
        "rms": round(math.sqrt(squared / max(1, len(values))), 6),
        "sha256": digest,
    }


def _crack(duration: float, seed: int, brightness: float, target_peak: float) -> list[float]:
    rng = random.Random(seed)
    count = round(duration * RATE)
    noise = _noise(count, rng)
    high = _lowpass(noise, brightness)
    low = _lowpass(noise, 900.0)
    output: list[float] = []
    modes = [(730.0, 0.075, 0.075), (1_360.0, 0.045, 0.045),
             (2_180.0, 0.027, 0.027), (3_600.0, 0.014, 0.014)]
    for i in range(count):
        t = i / RATE
        envelope = math.exp(-t / 0.022)
        resonances = sum(amplitude * math.sin(math.tau * frequency * t) * math.exp(-t / decay)
                         for frequency, amplitude, decay in modes)
        output.append(high[i] * envelope * 0.58 + low[i] * math.exp(-t / 0.012) * 0.18 + resonances)
    return _normalize(output, target_peak)


def _impact(duration: float, seed: int, surface: str, target_peak: float) -> list[float]:
    rng = random.Random(seed)
    count = round(duration * RATE)
    noise = _noise(count, rng)
    low_cut = 185.0 if surface == "grass" else (340.0 if surface == "dirt" else 700.0)
    low = _lowpass(noise, low_cut)
    mid = _lowpass(noise, 1_800.0)
    high = [noise[i] - mid[i] for i in range(count)]
    output: list[float] = []
    fundamental = 56.0 if surface == "grass" else 84.0
    for i in range(count):
        t = i / RATE
        body_env = math.exp(-t / (0.105 if surface == "grass" else 0.075))
        click_env = math.exp(-t / 0.009)
        thump = math.sin(math.tau * (fundamental - 18.0 * t) * t) * math.exp(-t / 0.16)
        output.append(low[i] * body_env * 0.75 + mid[i] * math.exp(-t / 0.032) * 0.18
                      + high[i] * click_env * (0.08 if surface == "grass" else 0.25)
                      + thump * 0.45)
    return _normalize(output, target_peak)


def _tear(duration: float, seed: int, target_peak: float) -> list[float]:
    rng = random.Random(seed)
    count = round(duration * RATE)
    noise = _noise(count, rng)
    low = _lowpass(noise, 1_250.0)
    high = [noise[i] - low[i] for i in range(count)]
    output = [0.0] * count
    # Short crackles distributed over the tear give it a rough, non-explosive edge.
    for _ in range(24):
        start = rng.randrange(max(1, count - 1))
        length = rng.randrange(round(0.002 * RATE), round(0.018 * RATE))
        amplitude = rng.uniform(0.12, 0.42)
        for j in range(min(length, count - start)):
            output[start + j] += high[start + j] * amplitude * math.exp(-j / max(1.0, length * 0.21))
    for i in range(count):
        t = i / RATE
        envelope = math.sin(math.pi * min(1.0, t / duration)) ** 0.65
        output[i] += low[i] * envelope * 0.34 + high[i] * envelope * 0.11
    return _normalize(output, target_peak)


def _scrape(duration: float, seed: int, target_peak: float) -> list[float]:
    rng = random.Random(seed)
    count = round(duration * RATE)
    noise = _noise(count, rng)
    low = _lowpass(noise, 480.0)
    band = _lowpass(noise, 4_500.0)
    output = []
    for i in range(count):
        t = i / RATE
        grit = band[i] - low[i]
        modulation = 0.72 + 0.20 * math.sin(math.tau * 19.0 * t) + 0.08 * math.sin(math.tau * 47.0 * t)
        fade = min(1.0, t / 0.025, (duration - t) / 0.11)
        output.append(grit * max(0.0, fade) * modulation * 0.36 + low[i] * max(0.0, fade) * 0.08)
    return _normalize(output, target_peak)


def _debris(duration: float, seed: int, target_peak: float) -> list[float]:
    rng = random.Random(seed)
    count = round(duration * RATE)
    noise = _noise(count, rng)
    low = _lowpass(noise, 720.0)
    high = [noise[i] - low[i] for i in range(count)]
    output = [low[i] * math.exp(-(i / RATE) / 0.55) * 0.11 for i in range(count)]
    for hit in range(19):
        start = round((0.035 + hit * (duration - 0.08) / 19.0 + rng.uniform(-0.018, 0.018)) * RATE)
        start = max(0, min(count - 1, start))
        hit_len = round(rng.uniform(0.006, 0.04) * RATE)
        amp = (0.5 * math.exp(-hit * 0.09)) * rng.uniform(0.45, 1.0)
        frequency = rng.uniform(440.0, 2_900.0)
        decay = rng.uniform(0.008, 0.02)
        for j in range(min(hit_len, count - start)):
            t = j / RATE
            envelope = math.exp(-t / decay)
            output[start + j] += amp * envelope * (0.48 * high[start + j] + 0.25 * math.sin(math.tau * frequency * t))
    return _normalize(output, target_peak)


def _secondary(duration: float, seed: int, target_peak: float) -> list[float]:
    rng = random.Random(seed)
    count = round(duration * RATE)
    noise = _noise(count, rng)
    low = _lowpass(noise, 520.0)
    high = [noise[i] - low[i] for i in range(count)]
    output = []
    for i in range(count):
        t = i / RATE
        envelope = math.exp(-t / 0.03)
        click = math.sin(math.tau * (670.0 + 150.0 * math.exp(-t * 30.0)) * t) * math.exp(-t / 0.045)
        output.append((low[i] * 0.35 + high[i] * 0.38 + click * 0.2) * envelope)
    return _normalize(output, target_peak)


def _engine_cut(duration: float, seed: int, target_peak: float) -> list[float]:
    rng = random.Random(seed)
    count = round(duration * RATE)
    noise = _noise(count, rng)
    rasp = _lowpass(noise, 1_250.0)
    output = []
    for i in range(count):
        t = i / RATE
        phase = math.tau * (112.0 * t - 39.0 * t * t / duration)
        flutter = 0.55 + 0.45 * math.sin(math.tau * (11.0 - 8.0 * t / duration) * t) ** 2
        envelope = math.exp(-t / 0.43) * max(0.0, 1.0 - t / duration)
        tone = sum(math.sin(phase * harmonic) / harmonic for harmonic in range(1, 8))
        output.append((0.38 * tone + 0.24 * rasp[i]) * envelope * flutter)
    return _normalize(output, target_peak)


def _turbine_spool(duration: float, seed: int, target_peak: float) -> list[float]:
    rng = random.Random(seed)
    count = round(duration * RATE)
    noise = _noise(count, rng)
    hiss = _lowpass(noise, 6_200.0)
    output = []
    start_hz = 1_280.0
    end_hz = 360.0
    for i in range(count):
        t = i / RATE
        fraction = t / duration
        # Linear frequency descent is an authored placeholder, not an ECU or turbine model.
        frequency = start_hz + (end_hz - start_hz) * fraction
        phase = math.tau * (start_hz * t + 0.5 * (end_hz - start_hz) * t * fraction)
        envelope = (0.22 + 0.78 * math.exp(-t / 2.4)) * max(0.0, 1.0 - fraction) ** 0.4
        tone = math.sin(phase) + 0.22 * math.sin(phase * 2.0 + 0.3) + 0.09 * math.sin(phase * 3.0 + 0.8)
        flutter = 0.91 + 0.09 * math.sin(math.tau * 7.0 * t)
        output.append((tone * 0.37 + hiss[i] * 0.095) * envelope * flutter)
    return _normalize(output, target_peak)


def _periodic_fire(duration: float, seed: int, target_peak: float) -> list[float]:
    rng = random.Random(seed)
    count = round(duration * RATE)
    noise = _noise(count, rng)
    low = _lowpass(noise, 380.0)
    band = _lowpass(noise, 4_800.0)
    output = [low[i] * 0.36 + (band[i] - low[i]) * 0.16 for i in range(count)]
    # Sparse, short crackles add detail while a symmetric edge fade makes the loop seam quiet.
    burst_count = round(duration * 5.0)
    bursts: list[tuple[int, int, float, float]] = []
    for _ in range(burst_count):
        center = rng.randrange(count)
        width = max(8, round(rng.uniform(0.0005, 0.003) * RATE))
        amplitude = rng.uniform(0.18, 0.6)
        decay = rng.uniform(0.0007, 0.002)
        bursts.append((center, width, amplitude, decay))
    for i in range(count):
        for center, width, amplitude, decay in bursts:
            delta = (i - center + count // 2) % count - count // 2
            if abs(delta) < width:
                output[i] += amplitude * math.exp(-abs(delta) / (decay * RATE)) * (1.0 if delta >= 0 else -0.65)
        edge = min(1.0, i / (0.04 * RATE), (count - 1 - i) / (0.04 * RATE))
        edge = math.sin(math.pi * max(0.0, edge) * 0.5) ** 2
        output[i] *= edge
    return _normalize(output, target_peak)


def _build_assets() -> list[dict[str, object]]:
    return [
        {"file": "crack_light.wav", "category": "airframe_crack", "role": "light and medium balsa/foam-like snap; synthetic transient", "loop": False,
         "generator": lambda: _crack(0.16, SEED + 1, 5_200.0, 0.42)},
        {"file": "crack_heavy.wav", "category": "airframe_crack", "role": "heavy composite/plywood-like snap; synthetic transient", "loop": False,
         "generator": lambda: _crack(0.26, SEED + 2, 7_200.0, 0.46)},
        {"file": "tear.wav", "category": "airframe_tear", "role": "short layered tear and splinter texture", "loop": False,
         "generator": lambda: _tear(0.62, SEED + 3, 0.38)},
        {"file": "impact_grass.wav", "category": "surface_impact", "role": "low, soft grass impact body", "loop": False,
         "generator": lambda: _impact(0.38, SEED + 4, "grass", 0.46)},
        {"file": "impact_dirt.wav", "category": "surface_impact", "role": "midrange dirt impact body", "loop": False,
         "generator": lambda: _impact(0.34, SEED + 5, "dirt", 0.46)},
        {"file": "impact_hard.wav", "category": "surface_impact", "role": "brighter hard-ground impact body", "loop": False,
         "generator": lambda: _impact(0.30, SEED + 6, "hard", 0.46)},
        {"file": "scrape.wav", "category": "surface_scrape", "role": "brief grit scrape after impact; one-shot until sustained-contact data exists", "loop": False,
         "generator": lambda: _scrape(0.82, SEED + 7, 0.40)},
        {"file": "debris.wav", "category": "debris_tail", "role": "irregular tumbling/rattle tail", "loop": False,
         "generator": lambda: _debris(1.18, SEED + 8, 0.42)},
        {"file": "secondary_hit.wav", "category": "secondary_debris_impact", "role": "short, small debris impact", "loop": False,
         "generator": lambda: _secondary(0.22, SEED + 9, 0.38)},
        {"file": "engine_cut.wav", "category": "engine_failure", "role": "short descending piston/prop engine cutoff accent", "loop": False,
         "generator": lambda: _engine_cut(0.9, SEED + 10, 0.34)},
        {"file": "turbine_spool.wav", "category": "engine_failure", "role": "stylized turbine rundown accent; not an ECU or spool model", "loop": False,
         "generator": lambda: _turbine_spool(6.0, SEED + 11, 0.34)},
        {"file": "fire_loop.wav", "category": "fire_bed", "role": "stylized fire crackle bed, only enabled by separate fuel/ignition input", "loop": True,
         "generator": lambda: _periodic_fire(4.0, SEED + 12, 0.28)},
    ]


def generate(output: Path) -> dict[str, object]:
    output.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, object]] = []
    for spec in _build_assets():
        metrics = _write_wav(output / str(spec["file"]), spec["generator"]())
        record = {key: value for key, value in spec.items() if key != "generator"}
        record.update(metrics)
        record["source"] = "Original deterministic offline synthesis; no recordings or third-party samples."
        record["seed"] = SEED + len(records) + 1
        records.append(record)
    manifest: dict[str, object] = {
        "format": "openrc-crash-audio-v1",
        "generator": "research/crash-damage/cr-02a/generate_assets.py",
        "generator_version": VERSION,
        "license": "MIT",
        "license_file": "LICENSE.txt",
        "provenance": "All included samples are original deterministic offline synthesis. No recordings, loops, or third-party source audio are included.",
        "sample_rate_hz": RATE,
        "channels": 1,
        "sample_format": "signed 16-bit PCM little-endian",
        "peak_policy": "Per-source peak <= 0.46; runtime bus uses a -1.0 dBFS hard limiter.",
        "runtime_synthesis": False,
        "assets": records,
    }
    (output / "sources.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (output / "LICENSE.txt").write_text(
        "MIT License\n\nCopyright (c) 2026 OpenRCsimulator contributors\n\n"
        "Permission is hereby granted, free of charge, to any person obtaining a copy\n"
        "of this software and associated documentation files (the \"Software\"), to deal\n"
        "in the Software without restriction, including without limitation the rights\n"
        "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n"
        "copies of the Software, and to permit persons to whom the Software is\n"
        "furnished to do so, subject to the following conditions:\n\n"
        "The above copyright notice and this permission notice shall be included in all\n"
        "copies or substantial portions of the Software.\n\n"
        "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n"
        "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n"
        "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n"
        "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n"
        "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n"
        "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n"
        "SOFTWARE.\n",
        encoding="utf-8",
    )
    return manifest


def verify(output: Path) -> bool:
    with tempfile.TemporaryDirectory(prefix="openrc-cr02a-") as temp:
        generated = generate(Path(temp))
        existing_path = output / "sources.json"
        if not existing_path.exists():
            return False
        existing = json.loads(existing_path.read_text(encoding="utf-8"))
        expected = {item["file"]: item["sha256"] for item in existing["assets"]}
        produced = {item["file"]: item["sha256"] for item in generated["assets"]}
        return expected == produced


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--verify", action="store_true", help="regenerate in a temporary directory and compare WAV hashes")
    args = parser.parse_args()
    output = args.output.resolve()
    if args.verify:
        if not verify(output):
            print("CR-02a asset hash verification failed")
            return 1
        print("CR-02a asset hashes reproduce exactly")
        return 0
    manifest = generate(output)
    total_bytes = sum((output / str(item["file"])).stat().st_size for item in manifest["assets"])
    print(f"Generated {len(manifest['assets'])} original mono WAVs ({total_bytes} bytes) at {output}")
    print(f"Manifest: {output / 'sources.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
