"""Focused R11 fixture checks in an already imported, isolated source copy."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(app):
    paths = set(app.rglob("*.gd")) | set((app / "data").rglob("*.json"))
    return {p.relative_to(app).as_posix(): digest(p) for p in sorted(paths)
            if ".godot" not in p.parts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("tests", nargs="+")
    args = parser.parse_args()
    app = args.app.resolve()
    for name in args.tests:
        if Path(name).name != name or not name.startswith("test_") or not name.endswith(".gd"):
            parser.error("tests must be test_*.gd basenames under the app/tests directory")
    args.out.mkdir(parents=True, exist_ok=False)
    before = identity(app)
    records = []
    for name in args.tests:
        command = [str(args.godot.resolve()), "--headless", "--path", str(app),
                   "--audio-driver", "Dummy", "--script", "res://tests/" + name]
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=180)
            output = result.stdout
            exit_code = result.returncode
        except subprocess.TimeoutExpired as exc:
            output = exc.stdout or b""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            exit_code = 124
        (args.out / (name + ".log")).write_text(output, encoding="utf-8")
        errors = [line for line in output.splitlines()
                  if line.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL"))]
        record = {"test": name, "command": command, "exit_code": exit_code,
                  "errors": errors, "ok": exit_code == 0 and not errors}
        records.append(record)
        print(json.dumps(record), flush=True)
    after = identity(app)
    drift = sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p))
    report = {"ok": all(r["ok"] for r in records) and not drift, "source_drift": drift,
              "commands": records, "source_before": before, "source_after": after,
              "runner_sha256": digest(Path(__file__)), "godot_sha256": digest(args.godot)}
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
