#!/usr/bin/env python3
"""FT-02: run the standard flight-test battery on fixed-wing catalog aircraft and record its provenance.

Usage (repository root):
  python research/flight-test/run.py --out tmp/ft-baseline [--aircraft all|id,id] [--godot PATH] [--jobs N]
                                     [--only test,test] [--full-traces] [--app DISPOSABLE_COPY_OF_APP]

Writes <out>/<aircraft>/profile.{json,md} plus traces (flight_test.gd), <out>/run.json (card version, git commit and
dirty paths, Godot version, data-file SHA-256 and exit status per aircraft) and <out>/summary.md. Exit status 1 when a
run fails or Godot reports a script error; a test that is not valid is a result, not a run failure.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "research" / "flight-test" / "flight_test.gd"
ERROR = re.compile(r"^(SCRIPT ERROR|ERROR):", re.M)


def find_godot(explicit):
    for candidate in [explicit, os.environ.get("GODOT"), ROOT / ".tools" / "Godot_v4.7.2-stable_win64_console.exe",
                      ROOT / ".tools" / "Godot_v4.7.2-stable_linux.x86_64"]:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    sys.exit("no Godot found: pass --godot or set GODOT (pinned version: app/get-godot.sh)")


APP = ROOT / "app"


def godot(binary, args, timeout):
    command = [binary, "--headless", "--path", str(APP), "--audio-driver", "Dummy", "--script", str(SCRIPT), "--"] + args
    return subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)


def git(*args):
    try:
        # rstrip only: porcelain lines start with a status column that may be a space.
        return subprocess.run(["git", "-C", str(ROOT)] + list(args), capture_output=True, text=True, check=True).stdout.rstrip("\n")
    except (OSError, subprocess.CalledProcessError):
        return ""


def card_version():
    match = re.search(r'const VERSION := "([^"]+)"', SCRIPT.read_text(encoding="utf-8"))
    return match.group(1) if match else "unknown"


def data_paths():
    """Catalog ID -> data file, read from the catalog source (res:// paths under app/)."""
    text = (APP / "app_state" / "aircraft_catalog.gd").read_text(encoding="utf-8")
    pairs = re.findall(r'id = "([^"]+)".*?data = "res://([^"]+)"', text, re.S)
    return {aircraft: APP / path for aircraft, path in pairs}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True)
    parser.add_argument("--aircraft", default="all")
    parser.add_argument("--godot")
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    parser.add_argument("--only")
    parser.add_argument("--full-traces", action="store_true")
    parser.add_argument("--diagnostics", action="store_true", help="also write <test>.aero.csv: regime weights and oracle/local/blended coefficients")
    parser.add_argument("--timeout", type=float, default=1800.0, help="seconds per aircraft")
    parser.add_argument("--app", help="a disposable copy of app/ holding one explicit candidate change")
    args = parser.parse_args()
    global APP
    if args.app:
        APP = Path(args.app).resolve()
    binary = find_godot(args.godot)
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)

    if args.aircraft == "all":
        listing = godot(binary, ["--list"], 300)
        ids = re.findall(r"^FT-AIRCRAFT (\S+)", listing.stdout, re.M)
        if not ids:
            sys.exit("the catalog listing returned no aircraft:\n" + listing.stdout + listing.stderr)
    else:
        ids = [a for a in args.aircraft.split(",") if a]

    extra = (["--only=" + args.only] if args.only else []) + (["--full-traces"] if args.full_traces else []) + (["--diagnostics"] if args.diagnostics else [])
    paths = data_paths()

    def fly(aircraft):
        started = time.time()
        try:
            result = godot(binary, ["--aircraft=" + aircraft, "--out=" + str(out)] + extra, args.timeout)
            log = result.stdout + result.stderr
            code = result.returncode
        except subprocess.TimeoutExpired as expired:
            log = (expired.stdout or "") if isinstance(expired.stdout, str) else ""
            code = "timeout"
        log = log.replace(str(ROOT).replace("\\", "/") + "/", "").replace(str(ROOT) + os.sep, "")
        (out / aircraft).mkdir(exist_ok=True)
        (out / aircraft / "run.log").write_text("\n".join(l for l in log.splitlines() if not l.startswith("Godot Engine")) + "\n", encoding="utf-8")
        errors = len(ERROR.findall(log))
        profile = out / aircraft / "profile.json"
        valid = total = None
        if profile.is_file():
            results = json.loads(profile.read_text(encoding="utf-8"))["results"]
            total = len(results)
            valid = sum(1 for r in results.values() if r.get("valid"))
        data = paths.get(aircraft)
        return aircraft, {
            "exit": code, "script_errors": errors, "wall_s": round(time.time() - started, 1), "valid_tests": valid, "tests": total,
            "data_file": str(data.relative_to(APP)).replace("\\", "/") if data else None,
            "data_sha256": hashlib.sha256(data.read_bytes()).hexdigest() if data and data.is_file() else None,
        }

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        runs = dict(pool.map(fly, ids))

    version = subprocess.run([binary, "--version"], capture_output=True, text=True).stdout.strip()
    dirty = [line[3:] for line in git("status", "--porcelain", "--", "app", "research/flight-test").splitlines()]
    record = {"card": card_version(), "commit": git("rev-parse", "HEAD"), "dirty_paths": dirty, "godot": version,
              "app": "app" if APP == ROOT / "app" else str(APP),
              "only": args.only, "aircraft": runs}
    (out / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")

    sys.path.insert(0, str(Path(__file__).parent))
    import summarize
    finished = [a for a in ids if (out / a / "profile.json").is_file()]
    if finished:
        from io import StringIO
        buffer = StringIO()
        stdout, sys.stdout = sys.stdout, buffer
        try:
            summarize.main_with(out, finished)
        finally:
            sys.stdout = stdout
        (out / "summary.md").write_text(buffer.getvalue(), encoding="utf-8")

    failed = False
    for aircraft, run in runs.items():
        bad = run["exit"] != 0 or run["script_errors"] or run["tests"] is None
        failed = failed or bad
        print(f"{'FAIL' if bad else 'ok  '} {aircraft:32s} exit {run['exit']}, script errors {run['script_errors']}, "
              f"valid {run['valid_tests']}/{run['tests']}, {run['wall_s']} s")
    print(f"card {record['card']}, commit {record['commit'][:10]}{' (dirty)' if dirty else ''}; summary {out / 'summary.md'}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
