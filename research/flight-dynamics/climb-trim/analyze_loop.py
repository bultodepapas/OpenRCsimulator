"""Summarize a captured observer session; no simulation or coefficient changes."""
import argparse
import csv
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recording", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    rows, raw, hashes = {}, {}, {}
    for path in sorted(args.recording.glob("flight-*.csv")):
        data = path.read_bytes()
        hashes[path.name] = hashlib.sha256(data).hexdigest()
        for row in csv.DictReader(line for line in data.decode().splitlines() if not line.startswith("#")):
            rows[int(row["tick"])] = {key: float(value) for key, value in row.items()}
    for path in sorted(args.recording.glob("input-*.csv")):
        data = path.read_bytes()
        hashes[path.name] = hashlib.sha256(data).hexdigest()
        for row in csv.DictReader(data.decode().splitlines()):
            raw[int(row["tick"])] = row
    ordered = [rows[tick] for tick in sorted(rows)]
    keys = ["alt_m", "tas_mps", "cmd_throttle", "cmd_pitch", "srv_pitch", "q_radps"]
    summary = {
        "source": str(args.recording), "trace_sha256": hashes,
        "first_tick": min(rows), "last_tick": max(rows), "rows": len(rows),
        "ranges": {key: [min(row[key] for row in ordered), max(row[key] for row in ordered)] for key in keys},
        "raw_pitch_range": [min(float(row["raw_pitch"]) for row in raw.values()), max(float(row["raw_pitch"]) for row in raw.values())],
        "trim_pitch_range": [min(float(row["trim_pitch"]) for row in raw.values()), max(float(row["trim_pitch"]) for row in raw.values())],
        "first_inverted_s": next((row["t_s"] for row in ordered if 1 - 2 * (row["qx"]**2 + row["qy"]**2) < 0), None),
        "first_full_throttle_s": next((row["t_s"] for row in ordered if row["cmd_throttle"] > 0.999999), None),
        "limits": "An observed simulator flight, not physical-aircraft validation. Quaternion body-down dot world-down defines inverted. Euler pitch alone does not count loops.",
    }
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "ugly-observed.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    time = np.array([row["t_s"] for row in ordered])
    inverted = np.array([1 - 2 * (row["qx"]**2 + row["qy"]**2) < 0 for row in ordered])
    fig, axes = plt.subplots(4, 1, figsize=(11, 9), sharex=True, layout="constrained")
    axes[0].plot(time, [100 * row["cmd_throttle"] for row in ordered], color="#b86216", label="Throttle")
    axes[0].set_ylabel("Throttle (%)")
    axes[1].plot(time, [20 * row["srv_pitch"] for row in ordered], label="Actual elevator (TE up)", color="#794eac")
    axes[1].plot([float(row["time_s"]) for row in raw.values()], [20 * float(row["raw_pitch"]) for row in raw.values()], label="Keyboard pitch × max throw", color="#2a7983")
    axes[1].set_ylabel("Elevator (degrees)")
    axes[2].plot(time, [row["alt_m"] for row in ordered], label="Height", color="#2a7983")
    axes[2].plot(time, [row["tas_mps"] for row in ordered], label="Airspeed", color="#b86216", linestyle="--")
    axes[2].set_ylabel("Height (m) / TAS (m/s)")
    axes[3].plot(time, [np.degrees(row["q_radps"]) for row in ordered], label="Body pitch rate", color="#794eac")
    axes[3].set_ylabel("Pitch rate (deg/s)")
    axes[3].set_xlabel("Simulation time (s)")
    for ax in axes:
        ax.fill_between(time, 0, 1, where=inverted, color="#d04444", alpha=.12, transform=ax.get_xaxis_transform(), label="Inverted" if ax is axes[0] else None)
        ax.grid(alpha=.2)
        ax.legend(loc="upper right", fontsize=8)
    fig.suptitle("Ugly Stik — recorded flight, neutral keyboard elevator\nRed shading: inverted attitude; no inference from Euler-angle wrapping", fontsize=12)
    fig.savefig(args.output / "ugly-observed.png", dpi=150)
    print(json.dumps({key: value for key, value in summary.items() if key != "trace_sha256"}, indent=2))


if __name__ == "__main__":
    main()
