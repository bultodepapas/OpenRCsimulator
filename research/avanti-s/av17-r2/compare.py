"""Compare AV-17-R2 complete gamepad traces and draw the reproduced departures."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    out = args.evidence
    names = ["baseline-240.json", "candidate-240.json", "candidate-480.json"]
    runs = [json.loads((out / name).read_text(encoding="utf-8")) for name in names]
    for run in runs:
        assert run["completed"] and len(run["cases"]) == 18
        assert all(row["completed"] and row["finite"] and len(row["samples"]) == 120 for row in run["cases"])
        assert all(row["unwanted_command_max"] == 0 for row in run["cases"])
    old, new, fine = runs
    metrics = ["alpha_max", "roll_rate_max", "pull_roll_rate_max", "speed_min", "normal_g_max", "stall_max"]
    for group in zip(*(run["cases"] for run in runs)):
        assert len({(row["speed"], row["pitch"], row["hold_s"]) for row in group}) == 1
    errors = {key: max(abs(a[key] - b[key]) for a, b in zip(new["cases"], fine["cases"])) for key in metrics}
    assert errors["alpha_max"] < 0.01 and errors["roll_rate_max"] < 0.05 and errors["speed_min"] < 0.02
    summary = {
        "case_count": 54, "all_complete_finite": True, "sample_hz": 20,
        "protocol": "500 m initial altitude; trimmed level at initial speed; standard Mode2 gamepad; pure pitch from 0.5 to 2.5 s; release until 6 s; trim throttle held, no roll/yaw inputs; sea-level-density model",
        "metric_note": "body p measures axial roll; Euler bank can flip by 180 degrees during a pitch loop and is deliberately excluded. Separation is max strip model weight, not measured stalled wing area.",
        "max_240_480_absolute_difference": errors,
        "runs": {name: hashlib.sha256((out / name).read_bytes()).hexdigest() for name in names},
        "cases": [{"speed": a["speed"], "pitch": a["pitch"],
                   "baseline": {k: a[k] for k in metrics}, "candidate": {k: b[k] for k in metrics},
                   "candidate_first_half_separated_s": b["stall_first"]} for a, b in zip(old["cases"], new["cases"])],
    }
    (out / "comparison.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    figure, axes = plt.subplots(3, 2, figsize=(10, 7.5), sharex=True, constrained_layout=True)
    for column, (speed, pitch) in enumerate([(29, 0.5), (45, 0.75)]):
        for run, label, color in [(old, "Before R2", "#c84b39"), (new, "R2 integrated", "#167995")]:
            case = next(row for row in run["cases"] if row["speed"] == speed and row["pitch"] == pitch)
            samples = case["samples"]
            for row, (index, unit) in enumerate([(4, "Body roll rate (deg/s)"), (2, "Angle of attack (deg)"), (1, "Airspeed (m/s)")]):
                ax = axes[row, column]
                ax.plot([x[0] for x in samples], [x[index] for x in samples], label=label, color=color)
                ax.axvspan(0.5, 2.5, color="#4d6075", alpha=0.08)
                ax.set_ylabel(unit)
                ax.grid(alpha=0.2)
        axes[0, column].set_title(f"Start {speed} m/s; raw pitch {pitch:.0%}")
        axes[0, column].legend()
        axes[2, column].set_xlabel("Time (s); shaded interval = held pitch")
    figure.suptitle("Pure gamepad pitch, no roll/yaw command — simulated, not flight measurements")
    figure.savefig(out / "gamepad-comparison.png", dpi=160)
    print(json.dumps({"complete_cases": 54, "max_240_480_difference": errors}, indent=2))


if __name__ == "__main__":
    main()
