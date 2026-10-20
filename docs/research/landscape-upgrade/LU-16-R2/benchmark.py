"""Reproduce LU-16-R2 alternating native R1/R2 captures on Windows."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "tmp/mountains-r2-repeat")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--frames", type=int, default=360)
    parser.add_argument("--cases", default="pilot_north,mountain_detail,mountain_oblique,twilight_aircraft")
    args = parser.parse_args()
    if args.repeats < 1 or args.frames < 1:
        parser.error("repeats and frames must be positive")
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=True)
    shader = output / "reference.gdshader"
    profile = output / "reference-profile.json"
    reference = output / "reference.gd"
    capture = output / "capture.gd"
    shutil.copyfile(HERE / "reference-shader.gdshader.txt", shader)
    shutil.copyfile(HERE / "reference-profile.json", profile)
    reference.write_text((HERE / "reference-ridges.gd.txt").read_text()
                         .replace("%REFERENCE_SHADER%", shader.as_posix())
                         .replace("%REFERENCE_PROFILE%", profile.as_posix()))
    shutil.copyfile(HERE / "capture.gd.txt", capture)
    for repeat in range(1, args.repeats + 1):
        for variant in ("reference", "final"):
            label = f"{variant}-{repeat}"
            command = [
                sys.executable, str(ROOT / "tools/godot/run_checked.py"),
                "--out-dir", str(output / "checks"), "--label", label, "--timeout", "120", "--",
                str(ROOT / ".tools/Godot_v4.7.2-stable_win64_console.exe"),
                "--path", str(ROOT / "app"), "--audio-driver", "Dummy",
                "--resolution", "1280x720", "--script", str(capture), "--",
                f"--out={output / label}", f"--cases={args.cases}", f"--frames={args.frames}",
            ]
            if variant == "reference":
                command.append(f"--ridge-reference-geometry={reference}")
            subprocess.run(command, cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
