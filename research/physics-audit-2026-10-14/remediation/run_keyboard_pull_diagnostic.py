"""Run the retained AV-17 fixture without editing the selected source copy."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(app):
    paths = set(app.rglob("*.gd")) | set((app / "data/aircraft").glob("*.json"))
    return {str(p.relative_to(app)).replace("\\", "/"): digest(p) for p in sorted(paths)
            if ".godot" not in p.parts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--hz", type=int, choices=[240, 480], default=240)
    parser.add_argument("--holds", default="2")
    parser.add_argument("--test", action="store_true", help="Run the full keyboard regression instead of the diagnostic.")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    app = args.app.resolve()
    probe = Path(__file__).with_name("keyboard_pull_diagnostic.gd").resolve()
    before = identity(app)
    command = [str(args.godot.resolve()), "--headless", "--path", str(app),
               "--audio-driver", "Dummy", "--script", str(probe), "--",
               f"--out={(args.out / 'cases.json').resolve()}",
               f"--hz={args.hz}", f"--holds={args.holds}"]
    if args.test:
        command = command[:6] + ["--script", "res://tests/test_avanti_keyboard.gd"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    output = result.stdout + result.stderr
    (args.out / "probe.log").write_text(output, encoding="utf-8")
    after = identity(app)
    errors = [line for line in output.splitlines()
              if line.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL"))]
    report = {"command": command, "exit_code": result.returncode, "engine_errors": errors,
              "probe_sha256": digest(probe), "sources_before": before,
              "source_drift": sorted(p for p in before.keys() | after.keys()
                                     if before.get(p) != after.get(p))}
    report["ok"] = result.returncode == 0 and not errors and not report["source_drift"]
    (args.out / "identity.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(output)
    print(json.dumps({k: v for k, v in report.items() if k != "sources_before"}, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
