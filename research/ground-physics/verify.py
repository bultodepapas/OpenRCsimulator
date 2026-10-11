"""GP-05 native Godot runner; timeouts and engine errors fail even with exit code zero.

Uses a disposable app for development. --full parses every script and runs all
test_*.gd files, equivalent to the GDScript part of app/test.sh on Windows.
It does not claim to run the shell suite's Python/export/render checks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
import subprocess
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--tests", nargs="*", default=[])
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    app, godot = args.app.resolve(), args.godot.resolve()
    version = subprocess.check_output([str(godot), "--version"], text=True).strip()
    rows = []

    def run(label: str, extra: list[str], timeout: int = 120) -> bool:
        command = [str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy", *extra]
        started = time.monotonic()
        try:
            result = subprocess.run(command, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=timeout)
            output, code = result.stdout + result.stderr, result.returncode
        except subprocess.TimeoutExpired as exc:
            output = str(exc.stdout or "") + str(exc.stderr or "") + "\nTIMEOUT\n"
            code = -1
        ok = code == 0 and re.search(r"^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL\b)", output, re.MULTILINE) is None
        name = re.sub(r"[^a-zA-Z0-9_.-]", "_", label)
        (args.out / f"{name}.log").write_text(output, encoding="utf-8")
        rows.append(dict(label=label, ok=ok, exit_code=code, seconds=time.monotonic() - started, command=command))
        print(f"{'PASS' if ok else 'FAIL'} {label}", flush=True)
        return ok

    run("import", ["--import"], 240)
    if args.full:
        for path in sorted(app.rglob("*.gd")):
            if ".godot" not in path.parts:
                run("parse-" + path.relative_to(app).as_posix(), ["--check-only", "--script", "res://" + path.relative_to(app).as_posix()])
    tests = args.tests or ([path.name for path in sorted((app / "tests").glob("test_*.gd"))] if args.full else ["test_ground_physics.gd"])
    for name in tests:
        run(name, ["--script", "res://tests/" + name])
    sources = {path.relative_to(app).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
               for directory in ("physics", "sim", "data/ground") for path in (app / directory).rglob("*") if path.is_file()}
    report = dict(engine=version, host=platform.platform(), app=str(app), results=rows, sources=sources, ok=all(row["ok"] for row in rows))
    (args.out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{sum(row['ok'] for row in rows)}/{len(rows)} passed", flush=True)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
