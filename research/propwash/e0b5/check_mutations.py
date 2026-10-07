#!/usr/bin/env python3
"""E0b5 fault detection in disposable project copies; never mutate the shared tree."""
import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MUTATIONS = [
    ("double transport speed", "physics/wash_transport.gd", "* values[1] / distance", "* 2.0 * values[1] / distance", "test_wash_transport.gd"),
    ("ignore transported load speed", "physics/slipstream.gd", "transported_dv[piece_index]", "dv", "test_wash_transport.gd"),
    ("freeze coupled load state", "sim/simulation.gd", "continuous_loads.call(combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), stage_t)", "continuous_loads.call(combined.slice(0, RB.SIZE), continuous, stage_t)", "test_continuous_state.gd"),
    ("freeze derivative body state", "sim/simulation.gd", "continuous_derivative.call(s.slice(0, RB.SIZE), s.slice(RB.SIZE), stage_t)", "continuous_derivative.call(state, s.slice(RB.SIZE), stage_t)", "test_continuous_state.gd"),
    ("corrupt checkpoint transport", "sim/simulation.gd", "snapshot.continuous = continuous.duplicate()", "snapshot.continuous = continuous.duplicate()\n\t\tsnapshot.continuous[0] += 1.0", "test_continuous_state.gd"),
]


def run(godot: str, project: Path, test: str) -> subprocess.CompletedProcess:
    return subprocess.run([godot, "--headless", "--path", str(project), "--script", "res://tests/" + test],
                          capture_output=True, text=True, timeout=90)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="openrc-e0b5-mutations-") as tmp:
        project = Path(tmp) / "app"
        shutil.copytree(ROOT / "app", project, ignore=shutil.ignore_patterns(".godot", "captures"))
        for test in sorted({m[4] for m in MUTATIONS}):
            result = run(args.godot, project, test)
            assert result.returncode == 0 and "ERROR:" not in result.stdout + result.stderr, result.stdout + result.stderr
            print("baseline passes:", test)
        for label, path, old, new, test in MUTATIONS:
            file = project / path
            original = file.read_text()
            assert old in original, (label, "mutation anchor absent")
            try:
                file.write_text(original.replace(old, new))
                result = run(args.godot, project, test)
                # A parse/runtime error is not a detected physics mutation.
                output = result.stdout + result.stderr
                assert result.returncode == 1 and "FAIL" in output and "ERROR:" not in output, (label, output)
                print("rejected:", label)
            finally:
                file.write_text(original)
    print("5 physics/state mutations rejected by assertions; shared tree unchanged")


if __name__ == "__main__":
    main()
