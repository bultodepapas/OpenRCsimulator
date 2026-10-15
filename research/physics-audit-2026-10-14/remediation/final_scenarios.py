"""Retain R11 source, old goldens, and same-tape experiments without erasing evidence.

The changed wake state cannot migrate an arbitrary checkpoint. compare_scenario.gd
defines an explicit fresh-reset experiment; each new recording must then replay
exactly under its own solver. No result here establishes physical validation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "app"
EVIDENCE = ROOT / "docs/research/physics-audit-2026-10-14/remediation"


def sources(app):
    paths = sorted(p for directory in ("physics", "sim", "failures")
                   for p in (app / directory).rglob("*.gd"))
    return {"app/" + p.relative_to(app).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--refresh-goldens", action="store_true")
    parser.add_argument("--app", type=Path, default=APP, help="isolated application snapshot recommended")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    godot = str(args.godot.resolve())
    app = args.app.resolve()
    before = sources(app)
    (args.out / "sources-before.json").write_text(json.dumps(before, indent=2) + "\n")
    with tarfile.open(args.out / "solver-source.tar.gz", "w:gz") as archive:
        for relative in before:
            archive.add(app / Path(relative).relative_to("app"), arcname=relative, recursive=False)
    commands = []

    def run(label, command):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
        output = result.stdout + result.stderr
        (args.out / f"{label}.log").write_text(output, encoding="utf-8")
        commands.append({"label": label, "command": command, "exit_code": result.returncode})
        if result.returncode or any(line.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL")) for line in output.splitlines()):
            raise RuntimeError(f"{label} failed; see retained log")

    error = ""
    try:
        if args.refresh_goldens:
            old = args.out / "previous-goldens"
            old.mkdir()
            for path in sorted((app / "tests/golden").glob("*.json")):
                (old / path.name).write_bytes(path.read_bytes())
            run("record-goldens", [godot, "--headless", "--path", str(app), "--audio-driver", "Dummy",
                                   "--script", "res://tests/record_golden.gd"])
            run("test-goldens", [godot, "--headless", "--path", str(app), "--audio-driver", "Dummy",
                                 "--script", "res://tests/test_golden.gd"])
            changes = {}
            for path in sorted(old.glob("*.json")):
                previous = json.loads(path.read_text())
                current = json.loads((app / "tests/golden" / path.name).read_text())
                changes[path.name] = {"previous_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "current_sha256": hashlib.sha256((app / "tests/golden" / path.name).read_bytes()).hexdigest(),
                    "input_tape_identical": previous["inputs"] == current["inputs"],
                    "ticks": current["ticks"],
                    "reason": "R02 section-plane forces, source-weighted induced flow and bounded dimensional wake; auxiliary wake unit changes from CL to m/s."}
            (args.out / "golden-changes.json").write_text(json.dumps(changes, indent=2) + "\n")
        for name in ("stik", "jet"):
            baseline = EVIDENCE / "R00/session" / f"{name}-normal-yaw.orfl"
            scenario = args.out / name
            run(f"{name}-scenario", [godot, "--headless", "--path", str(app), "--audio-driver", "Dummy",
                 "--script", str(Path(__file__).with_name("compare_scenario.gd")), "--",
                 f"--baseline={baseline}", f"--out={scenario.resolve()}"])
            exact = scenario / "exact"
            exact.mkdir()
            run(f"{name}-exact", [godot, "--headless", "--path", str(app), "--audio-driver", "Dummy",
                 "--script", "res://tools/flight_log_cli.gd", "--", f"--log={(scenario / 'candidate.orfl').resolve()}",
                 f"--csv={(exact / 'flight.csv').resolve()}", f"--report={(exact / 'replay.json').resolve()}", "--replay"])
            run(f"{name}-compare", [sys.executable, "tools/flight_log/flight_log.py", "compare",
                 str(EVIDENCE / "R00/session" / f"{name}-exact/flight.csv"),
                 str(scenario / "exact/flight.csv"), "--out", str(scenario / "comparison.json")])
        run("catalog-session-pulses", [godot, "--headless", "--path", str(app), "--audio-driver", "Dummy",
             "--script", str(ROOT / "research/physics-audit-2026-10-14/session_probe.gd"), "--",
             f"--out={(args.out / 'catalog-pulses').resolve()}"])
    except (RuntimeError, subprocess.TimeoutExpired) as failure:
        error = str(failure)
    after = sources(app)
    drift = [path for path in before.keys() | after.keys() if before.get(path) != after.get(path)]
    report = {"ok": not error and not drift, "error": error, "source_drift": sorted(drift),
              "purpose": "software scenarios and exact replay; not physical validation", "commands": commands}
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.out / "sources-after.json").write_text(json.dumps(after, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "commands"}, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
