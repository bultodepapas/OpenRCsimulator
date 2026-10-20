#!/usr/bin/env python3
"""Build offline, loopable engine layers from retained CC0 audio previews."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import wave

import miniaudio
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "app/assets/audio/powertrains"
SOURCES = OUTPUT / "source"
CC0_URL = "https://creativecommons.org/publicdomain/zero/1.0/"

RECORDINGS = {
    "gas_120cc": {
        "file": "gas_120cc_takeoff_hq.mp3",
        "author": "rcEyeSoar",
        "title": "1 radio control plane taking off.wav",
        "page": "https://freesound.org/people/rcEyeSoar/sounds/176968/",
        "download": "https://cdn.freesound.org/previews/176/176968_3283314-hq.mp3",
        "sha256": "9069c6e13b0a65994c575fee395c0b6504cd10983df2d0df56ae6584e346d979",
        "license": "CC0-1.0",
        "source_format": "44.1 kHz, 16-bit stereo WAV; 15.915 s",
        "source_fit": "The page describes a 120cc radio-control plane taking off from a runway. This is used only as a broad gasoline-class proxy; fuel and engine cycle are not specified on the sound page.",
    },
    "electric_quad": {
        "file": "electric_quad_takeoff_hq.mp3",
        "author": "Alcappuccino",
        "title": "Quadrocopter Take-Off And Landing",
        "page": "https://freesound.org/people/Alcappuccino/sounds/263022/",
        "download": "https://cdn.freesound.org/previews/263/263022_4536481-hq.mp3",
        "sha256": "9497991b9008714d9d03bbcc6bad44e9cb072b87effde6c4b9b68c283280abdb",
        "license": "CC0-1.0",
        "source_format": "48 kHz, 16-bit stereo WAV; 59.076 s",
        "source_fit": "A DJI Phantom 2 quadcopter recorded by a camera mounted on the aircraft. It is an electric multirotor reference, not a fixed-wing propeller recording.",
    },
    "toy_helicopter": {
        "file": "rc_toy_helicopter_hq.mp3",
        "author": "qubodup",
        "title": "Toy Engine Flying Around",
        "page": "https://freesound.org/people/qubodup/sounds/188241/",
        "download": "https://cdn.freesound.org/previews/188/188241_71257-hq.mp3",
        "sha256": "57a4ebf4c4e5457ff03911f89dc36a5a3c068c60939597236c65b0fe00d8c7ab",
        "license": "CC0-1.0",
        "source_format": "96 kHz, 24-bit stereo FLAC; 31.689 s",
        "source_fit": "A small remote-controlled toy helicopter recorded in flight with a Zoom H2. It is not identified as a .60 glow helicopter and has no separate tail-rotor track.",
    },
    "designed_jet": {
        "file": "designed_jet_engine_hq.mp3",
        "author": "minian89",
        "title": "jet_engine.wav",
        "page": "https://freesound.org/people/minian89/sounds/152509/",
        "download": "https://cdn.freesound.org/previews/152/152509_2467357-hq.mp3",
        "sha256": "84c3f0c54f31d3594620b386529ab362febecb7bf299e82ed4651b820740215f",
        "license": "CC0-1.0",
        "source_format": "44.1 kHz, 16-bit stereo WAV; 76.694 s",
        "source_fit": "The author says this jet-engine sound was created in Pure Data using methods from Andy Farnell's Designing Sound. It is an explicitly synthetic fallback, not a field recording or a measured RC turbine.",
    },
}

# Output name: (source key, source start, source window, crossfade, high-pass,
# low-pass, target RMS, peak ceiling). Source rate is retained: no upsampling.
EDITS = {
    "gasoline_low.wav": ("gas_120cc", 0.10, 1.55, 0.20, 45.0, 12000.0, 0.100, 0.398107),
    "gasoline_high.wav": ("gas_120cc", 6.20, 2.05, 0.25, 45.0, 14000.0, 0.100, 0.398107),
    "electric_quad.wav": ("electric_quad", 26.0, 9.0, 0.75, 50.0, 12000.0, 0.100, 0.398107),
    "turbine_designed.wav": ("designed_jet", 32.0, 12.0, 1.0, 55.0, 14000.0, 0.100, 0.398107),
    "rotor_low.wav": ("toy_helicopter", 14.6, 4.0, 0.50, 45.0, 12000.0, 0.100, 0.398107),
    "rotor_high.wav": ("toy_helicopter", 2.0, 4.5, 0.50, 45.0, 12000.0, 0.100, 0.398107),
}

# These acoustic estimates are references for runtime pitch mapping, not RPM
# telemetry. See docs/research/audio/AUD-15/sources.md for their derivation.
BANKS = {
    "gasoline": [
        {"file": "gasoline_low.wav", "rpm": 2800, "role": "engine", "gain": 1.0},
        {"file": "gasoline_high.wav", "rpm": 7400, "role": "engine", "gain": 1.0},
    ],
    "electric": [
        {"file": "electric_quad.wav", "rpm": 6960, "role": "prop", "gain": 1.0},
    ],
    "turbine": [
        {"file": "turbine_designed.wav", "rpm": 80000, "role": "engine", "gain": 1.0},
    ],
    "rotor": [
        {"file": "rotor_low.wav", "rpm": 2270, "role": "main_rotor", "gain": 1.0},
        {"file": "rotor_high.wav", "rpm": 2650, "role": "main_rotor", "gain": 1.0},
    ],
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def wav_bytes(samples, sample_rate):
    pcm = np.rint(np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    out = io.BytesIO()
    with wave.open(out, "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(sample_rate)
        stream.writeframes(pcm.tobytes())
    return out.getvalue(), pcm.astype(np.float64) / 32768.0


def loop_crossfade(samples, overlap):
    """Join the source tail to its head with a correlated or equal-power fade."""
    head = samples[:overlap]
    tail = samples[-overlap:]
    head_centered = head - np.mean(head)
    tail_centered = tail - np.mean(tail)
    denom = np.linalg.norm(head_centered) * np.linalg.norm(tail_centered)
    correlation = float(np.dot(head_centered, tail_centered) / denom) if denom else 0.0
    phase = (np.arange(overlap, dtype=np.float64) + 0.5) / overlap * (np.pi / 2.0)
    if correlation >= 0.5:
        # Constant-amplitude crossfade avoids a bump when the waveform repeats
        # in phase; cos² + sin² is one for correlated material.
        tail_weight = np.cos(phase) ** 2
        head_weight = np.sin(phase) ** 2
        curve = "correlated_constant_amplitude"
    else:
        # Equal-power weights retain energy when the endpoints are unrelated.
        tail_weight = np.cos(phase)
        head_weight = np.sin(phase)
        curve = "equal_power"
    blend = tail * tail_weight + head * head_weight
    return np.concatenate((samples[overlap:-overlap], blend)), correlation, curve


def shape_loop(samples, sample_rate, low_hz, high_hz):
    """Apply a gentle periodic high/low pass without inventing source detail."""
    frequency = np.fft.rfftfreq(len(samples), 1.0 / sample_rate)
    response = (1.0 - np.exp(-((frequency / low_hz) ** 4))) * np.exp(-((frequency / high_hz) ** 8))
    return np.fft.irfft(np.fft.rfft(samples) * response, n=len(samples))


def build():
    if np.__version__ != "2.4.6" or miniaudio.__version__ != "1.71":
        raise RuntimeError("Install exact tools/audio/requirements-recordings.txt versions")

    decoded = {}
    source_records = {}
    for key, record in RECORDINGS.items():
        source_path = SOURCES / record["file"]
        raw = source_path.read_bytes()
        if sha(raw) != record["sha256"]:
            raise RuntimeError(f"Source checksum mismatch: {source_path}")
        info = miniaudio.get_file_info(str(source_path))
        stream = miniaudio.decode_file(
            str(source_path),
            output_format=miniaudio.SampleFormat.FLOAT32,
            nchannels=1,
            sample_rate=info.sample_rate,
        )
        decoded[key] = (np.asarray(stream.samples, dtype=np.float64), stream.sample_rate)
        source_records[key] = dict(
            record,
            source_url=record["page"],
            license_url=CC0_URL,
            retrieved="2026-10-20",
            preview_sha256=sha(raw),
            preview_bytes=len(raw),
            preview_format="public HQ MP3 preview; lossy and lower fidelity than the original",
            decoded_sample_rate_hz=stream.sample_rate,
            decoded_channels=1,
        )

    outputs = {}
    assets = []
    for filename, edit in EDITS.items():
        source_key, start_s, duration_s, crossfade_s, low_hz, high_hz, target_rms, peak_cap = edit
        source, rate = decoded[source_key]
        first = round(start_s * rate)
        count = round(duration_s * rate)
        samples = source[first:first + count].copy()
        if len(samples) != count:
            raise RuntimeError(f"Truncated source segment for {filename}")
        samples -= np.mean(samples)
        overlap = round(crossfade_s * rate)
        if overlap <= 0 or overlap * 2 >= len(samples):
            raise RuntimeError(f"Invalid crossfade for {filename}")
        samples, correlation, curve = loop_crossfade(samples, overlap)
        samples = shape_loop(samples, rate, low_hz, high_hz)
        rms = float(np.sqrt(np.mean(samples * samples)))
        peak = float(np.max(np.abs(samples)))
        gain = min(target_rms / max(rms, 1e-12), peak_cap / max(peak, 1e-12))
        samples *= gain
        blob, pcm = wav_bytes(samples, rate)
        seam_step = abs(float(pcm[-1] - pcm[0]))
        interior_step_p99 = float(np.quantile(np.abs(np.diff(pcm)), 0.99))
        if not np.isfinite(pcm).all() or np.max(np.abs(pcm)) > peak_cap + (1.0 / 32768.0):
            raise RuntimeError(f"Invalid PCM or headroom for {filename}")
        if seam_step > max(interior_step_p99 * 1.5, 0.002):
            raise RuntimeError(f"Unacceptable loop seam for {filename}: {seam_step:.6f}")
        outputs[filename] = blob
        assets.append({
            "file": filename,
            "source": source_key,
            "sha256": sha(blob),
            "sample_rate_hz": rate,
            "channels": 1,
            "sample_count": len(pcm),
            "duration_s": len(pcm) / rate,
            "format": "signed 16-bit PCM little-endian",
            "loop": True,
            "edits": {
                "source_start_s": start_s,
                "source_window_s": duration_s,
                "crossfade_s": crossfade_s,
                "crossfade_curve": curve,
                "source_endpoint_correlation": correlation,
                "highpass_hz": low_hz,
                "lowpass_hz": high_hz,
                "target_rms": target_rms,
                "peak_cap": peak_cap,
                "applied_gain": gain,
            },
            "metrics": {
                "rms": float(np.sqrt(np.mean(pcm * pcm))),
                "peak": float(np.max(np.abs(pcm))),
                "seam_step": seam_step,
                "interior_step_p99": interior_step_p99,
            },
        })

    outputs["BANKS.json"] = (json.dumps(BANKS, indent=2) + "\n").encode()
    manifest = {
        "format": "openrc-powertrain-audio v1",
        "generator": "tools/audio/recorded_powertrains.py",
        "dependencies": {"numpy": np.__version__, "miniaudio": miniaudio.__version__},
        "sources": source_records,
        "assets": assets,
        "banks": BANKS,
        "rpm_reference_basis": {
            "gasoline": "The 2800 and 7400 RPM values are runtime mapping anchors spanning selected low/high 120cc takeoff segments. The source page gives no tachometer reading, engine cycle or fuel type; they are not measured RPM.",
            "electric": "About 232.1 Hz is the strongest line in the selected quadcopter segment. 6960 RPM assumes two blade-pass events per revolution (60 * 232.1 / 2), rounded to 10 RPM. This is an acoustic estimate, not telemetry; the recording is a multirotor surrogate.",
            "turbine": "80000 RPM is only a runtime mapping anchor for the designed jet effect. The source is synthetic and has no physical RPM measurement.",
            "rotor": "The selected toy-helicopter windows have dominant lines near 75.5 Hz and 88.2 Hz; 2270 and 2650 RPM assume two blade-pass events per revolution (60 * f / 2), rounded to 10 RPM. These are acoustic estimates, not telemetry, and the source is a toy helicopter fly-around.",
        },
        "notes": [
            "The source files are Freesound public HQ MP3 previews; previews are lossy copies, not original masters.",
            "RPM references are mapping anchors or acoustic estimates as separately stated; no source includes tachometer telemetry.",
            "The turbine layer is a CC0 synthetic design and its RPM is a runtime mapping choice, not measured or recorded.",
            "Glow 2-stroke and glow 4-stroke recordings were not found in the sourced bank; use the runtime procedural fallback until verified recordings are available.",
        ],
    }
    outputs["manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    notice = [
        "Powertrain sound sources: CC0 1.0 Universal.",
        "Loop WAVs are edits of retained public HQ MP3 previews; these preview files are lossy transcodes, not original masters.",
        "The turbine layer is an explicitly designed synthetic effect, not a field recording.",
        "",
    ]
    for record in RECORDINGS.values():
        notice.extend([f"{record['title']} by {record['author']}", record["page"], ""])
    notice.extend([f"CC0 1.0: {CC0_URL}", ""])
    outputs["LICENSE.txt"] = "\n".join(notice).encode()
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated files differ")
    args = parser.parse_args()
    outputs = build()
    if args.check:
        stale = [name for name, data in outputs.items() if not (OUTPUT / name).is_file() or (OUTPUT / name).read_bytes() != data]
        required_import_settings = {
            "compress/mode=0",
            "force/8_bit=false",
            "edit/normalize=false",
            "edit/trim=false",
        }
        for filename in EDITS:
            sidecar = OUTPUT / (filename + ".import")
            if not sidecar.is_file() or not required_import_settings.issubset(set(sidecar.read_text().splitlines())):
                stale.append(filename + ".import (PCM wrap guard requires uncompressed, unmodified import)")
        if stale:
            raise SystemExit("Stale recorded powertrain outputs: " + ", ".join(stale))
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for name, data in outputs.items():
            (OUTPUT / name).write_bytes(data)
    print(f"Recorded powertrain audio {'checked' if args.check else 'built'}: {len(EDITS)} loops, {sum(len(v) for k, v in outputs.items() if k.endswith('.wav')):,} PCM bytes")


if __name__ == "__main__":
    main()
