#!/usr/bin/env python3
"""E0b6 fault detection in disposable project copies; never mutate the shared tree."""
import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MUTATIONS = [
    ("omit distributed correction", "physics/slipstream.gd", "result[component] += correction[component]", "result[component] += 0.0 * correction[component]", "test_swirl_accuracy.gd"),
    ("reverse swirl direction", "physics/swirl_loads.gd", "var swirl_scale: float = swirl_strength /", "var swirl_scale: float = -swirl_strength /", "test_swirl_accuracy.gd"),
    ("retain axial load in correction", "physics/swirl_loads.gd", " - axial_", " + 0.0 * axial_", "test_swirl_accuracy.gd"),
    ("wrong torque strength", "physics/slipstream.gd", "ss.swirl_factor * 0.5 * k_w * torque", "ss.swirl_factor * 0.75 * k_w * torque", "test_swirl_torque.gd"),
]


def run(godot: str, project: Path, test: str) -> subprocess.CompletedProcess:
    return subprocess.run([godot, "--headless", "--path", str(project), "--script", "res://tests/" + test],
                          capture_output=True, text=True, timeout=90)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="openrc-e0b6-mutations-") as tmp:
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
    print("4 swirl mutations rejected by assertions; shared tree unchanged")


if __name__ == "__main__":
    main()
