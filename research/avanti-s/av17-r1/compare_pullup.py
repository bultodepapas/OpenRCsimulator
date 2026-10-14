"""Summarize the retained AV-17-R1 flight records and render the comparison figure."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "docs/research/avanti-realism/AV-17-R1"


def read(name: str, count: int) -> dict:
    record = json.loads((OUT / name).read_text(encoding="utf-8"))
    assert len(record["cases"]) == count
    assert all(c["completed"] and not c["fault"] for c in record["cases"])
    return {(c["speed_mps"], c["hold_s"]): c for c in record["cases"]}


def metrics(case: dict) -> dict:
    return {k: v for k, v in case.items() if k != "samples"}


def main() -> None:
    baseline = read("baseline-240.json", 18)
    current = read("candidate-240.json", 21)
    refined = read("candidate-480.json", 21)
    old_pulses = read("legacy-pulses-240.json", 3)
    assert current.keys() == refined.keys()
    assert baseline.keys() | old_pulses.keys() == current.keys()
    refinement = {}
    for field in ["peak_alpha_deg", "peak_g", "peak_stall_weight", "first_stall_s", "recovered_s"]:
        # Negative event times mean that the event never occurred in the four-second run.
        assert all((current[k][field] < 0) == (refined[k][field] < 0) for k in current)
        differences = [(abs(current[k][field] - refined[k][field]), k) for k in current
                       if current[k][field] >= 0]
        delta, key = max(differences)
        refinement[field] = {"max_abs_delta": delta, "speed_mps": key[0], "hold_s": key[1]}
    summary = {
        "format": "openrc-avanti-pullup-comparison v1",
        "scenario": "500 m AGL, -45 deg path, clean gear-up, trimmed turbine demand; four seconds",
        "pulse_policy": "0.45 s up / 0.15 s release until path gamma first reaches zero; then release",
        "stall_event": "first time any wing strip reaches separation blend weight >= 0.5",
        "body_normal_g": "-accepted body-Z nongravitational force / (model mass * gravity)",
        "records": {name: hashlib.sha256((OUT / name).read_bytes()).hexdigest() for name in
                    ["baseline-240.json", "candidate-240.json", "candidate-480.json", "legacy-pulses-240.json"]},
        "completed_cases": {"original_baseline_240": 18, "legacy_pulses_240": 3,
                            "candidate_240": 21, "candidate_480": 21},
        "half_second_pull": [{"before": metrics(baseline[(v, 0.5)]),
                              "after": metrics(current[(v, 0.5)])} for v in [29, 45, 60]],
        "pulsed_recovery": [{"before": metrics(old_pulses[(v, -1)]),
                             "after": metrics(current[(v, -1)])} for v in [29, 45, 60]],
        "held_overpull_45_mps": metrics(current[(45, 2)]),
        "240_to_480_hz": refinement,
        "refinement_scope": "Observed differences, not a predeclared physical-validation tolerance.",
    }
    (OUT / "comparison.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    fig, axes = plt.subplots(2, 3, figsize=(13, 7), constrained_layout=True)
    colors = ["#a74432", "#126b91"]
    for ax, column, label in zip(axes[0], [2, 4, 7],
                                 ["Angle of attack (deg)", "Body normal load (g)", "Maximum strip separation"]):
        for cases, name, color in [(baseline, "Before: 0.25 s press", colors[0]),
                                    (current, "After: 1.00 s press", colors[1])]:
            rows = cases[(45, 0.5)]["samples"]
            ax.plot([r[0] for r in rows], [r[column] for r in rows], label=name, color=color, lw=1.8)
        ax.axvspan(0, 0.5, color="#a0a0a0", alpha=0.16)
        ax.set(xlim=(0, 2), ylabel=label, xlabel="Time (s)", title="45 m/s · 0.50 s pull then release")
    axes[0, 0].legend(fontsize=8)
    for ax, speed in zip(axes[1], [29, 45, 60]):
        for cases, color in [(old_pulses, colors[0]), (current, colors[1])]:
            rows = cases[(speed, -1)]["samples"]
            ax.plot([r[0] for r in rows], [r[3] for r in rows], color=color, lw=1.8)
        ax.axhline(0, color="#555555", linestyle="--", lw=0.8)
        ax.set(xlim=(0, 4), ylabel="Flight-path angle (deg)", xlabel="Time (s)",
               title=f"{speed} m/s · repeated 0.45 / 0.15 s taps")
    for ax in axes.flat:
        ax.grid(alpha=0.22)
    fig.suptitle("AV-17-R1 · Keyboard dive recovery at 240 Hz\n"
                 "Same aircraft physics; faster path rotation alone does not imply attached flight", fontsize=13)
    fig.savefig(OUT / "pullup-comparison.png", dpi=160)
    plt.close(fig)
    print(json.dumps({"completed": summary["completed_cases"], "refinement": refinement}, indent=2))


if __name__ == "__main__":
    main()
