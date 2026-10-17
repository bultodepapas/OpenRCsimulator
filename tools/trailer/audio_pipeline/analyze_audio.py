#!/usr/bin/env python3
"""Make a measured RMS envelope for the authorized trailer music sources."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def decode_mono(path: Path, ffmpeg: Path, sample_rate: int = 8000) -> np.ndarray:
    result = subprocess.run(
        [
            str(ffmpeg),
            "-v",
            "error",
            "-i",
            str(path),
            "-f",
            "f32le",
            "-ac",
            "1",
            "-ar",
            str(sample_rate),
            "pipe:1",
        ],
        check=True,
        stdout=subprocess.PIPE,
    )
    return np.frombuffer(result.stdout, dtype="<f4")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--inputs", type=Path, nargs="+", required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    sample_rate = 8000
    window_seconds = 0.1
    window_samples = int(sample_rate * window_seconds)
    report = {}

    for source in args.inputs:
        samples = decode_mono(source, args.ffmpeg, sample_rate)
        usable = samples[: len(samples) // window_samples * window_samples]
        windows = usable.reshape(-1, window_samples)
        rms = np.sqrt(np.mean(np.square(windows, dtype=np.float64), axis=1))
        peak = np.max(np.abs(windows), axis=1)
        times = (np.arange(len(rms), dtype=np.float64) + 0.5) * window_seconds
        duration = len(samples) / sample_rate

        five_second = []
        for start in np.arange(0, duration, 5.0):
            mask = (times >= start) & (times < start + 5.0)
            if np.any(mask):
                five_second.append(
                    {
                        "start_s": round(float(start), 1),
                        "rms_dbfs": round(float(20 * np.log10(max(float(np.sqrt(np.mean(rms[mask] ** 2))), 1e-8))), 2),
                        "peak_dbfs": round(float(20 * np.log10(max(float(np.max(peak[mask])), 1e-8))), 2),
                    }
                )

        one_second = []
        for start in np.arange(0, duration, 1.0):
            mask = (times >= start) & (times < start + 1.0)
            if np.any(mask):
                one_second.append(
                    {
                        "start_s": round(float(start), 1),
                        "rms_dbfs": round(float(20 * np.log10(max(float(np.sqrt(np.mean(rms[mask] ** 2))), 1e-8))), 2),
                        "peak_dbfs": round(float(20 * np.log10(max(float(np.max(peak[mask])), 1e-8))), 2),
                    }
                )

        plot_path = args.out_dir / f"{source.stem}-rms-envelope.png"
        fig, ax = plt.subplots(figsize=(15, 4))
        ax.plot(times, 20 * np.log10(np.maximum(rms, 1e-6)), linewidth=0.55)
        ax.set_title(f"Measured 100 ms RMS envelope: {source.name}")
        ax.set_xlabel("Source time (seconds)")
        ax.set_ylabel("RMS level (dBFS)")
        ax.set_ylim(-60, 0)
        ax.set_xlim(0, duration)
        ax.grid(True, alpha=0.25)
        fig.tight_layout()
        fig.savefig(plot_path, dpi=150)
        plt.close(fig)

        report[source.name] = {
            "duration_s": round(duration, 3),
            "sample_rate_hz": sample_rate,
            "window_s": window_seconds,
            "one_second_envelope": one_second,
            "five_second_envelope": five_second,
            "plot": str(plot_path),
        }

    report_path = args.out_dir / "source-envelope-analysis.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(report_path)


if __name__ == "__main__":
    main()
