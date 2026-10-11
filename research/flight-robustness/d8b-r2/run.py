"""D8b-R2: run the real Godot session probe and check evidence completeness."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "docs/research/flight-robustness/D8b-R2"
TESTS = ("test_spin.gd", "test_damping_regimes.gd", "test_gyro.gd", "test_handling.gd")


def hashes():
    paths = [*ROOT.joinpath("app/physics").glob("*.gd"),
             *ROOT.joinpath("app/sim").glob("*.gd"),
             *ROOT.joinpath("app/input").glob("*.gd"),
             ROOT / "app/data/aircraft/jensen_ugly_stik_60.json",
             ROOT / "app/project.godot", Path(__file__), Path(__file__).with_name("probe.gd")]
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}


def run(godot, script, log):
    completed = subprocess.run([str(godot), "--headless", "--path", str(ROOT / "app"),
                                "--script", str(script)], cwd=ROOT, text=True,
                               encoding="utf-8", errors="replace", capture_output=True, timeout=60)
    output = completed.stdout + completed.stderr
    (OUT / log).write_text(output, encoding="utf-8")
    if completed.returncode or re.search(r"(?m)^(?:SCRIPT |SHADER )?ERROR:|^FAIL", output):
        raise RuntimeError(f"Godot failure: {log}")
    return output


def finite(value):
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError("Nonfinite evidence")
    if isinstance(value, dict):
        for item in value.values():
            finite(item)
    elif isinstance(value, list):
        for item in value:
            finite(item)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    godot = args.godot.resolve()
    OUT.mkdir(parents=True, exist_ok=True)
    before = hashes()
    output_path = OUT / "results.json"
    if output_path.exists():
        output_path.unlink()  # Only this explicitly named generated evidence file.
    run(godot, Path(__file__).with_name("probe.gd"), "run.log")
    results = json.loads(output_path.read_text(encoding="utf-8"))
    finite(results)
    assert len(results) == 29
    trials = [row for row in results if row["variant"] != "static_sweep"]
    assert len(trials) == 28
    for trial in trials:
        assert not trial.get("error") and not trial["fault"]
        assert trial["tick"] == 4 * trial["hz"]
        assert len(trial["rows"]) == 81 and trial["rows"][-1]["t"] == 4.0
        assert all(abs(row["t"] - i * 0.05) < 1e-12 for i, row in enumerate(trial["rows"]))
    checks = {}
    for name in TESTS:
        output = run(godot, f"res://tests/{name}", f"{name}.log")
        match = re.search(r"(\d+) checks, 0 failed", output)
        assert match, name
        checks[name] = int(match[1])
    assert hashes() == before, "Source changed during the investigation run"
    manifest = {"format": "openrc-pullup-investigation v1", "date": "2026-10-11",
                "base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "engine_version": subprocess.check_output([str(godot), "--version"], text=True).strip(),
                "engine_sha256": hashlib.sha256(godot.read_bytes()).hexdigest(),
                "source_sha256": before, "trials": len(trials), "checks": checks,
                "results_sha256": hashlib.sha256(output_path.read_bytes()).hexdigest(),
                "scope": "Calm-air synthetic reproduction, sampled state every 0.05 s; maxima computed every tick. No physical acceptance."}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(trials)} complete 4-second trials, static sweep, {sum(checks.values())} existing checks; source unchanged.")


if __name__ == "__main__":
    main()
