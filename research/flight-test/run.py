#!/usr/bin/env python3
"""FT-02: run the standard flight-test battery on fixed-wing catalog aircraft and record its provenance.

Usage (repository root):
  python research/flight-test/run.py --out tmp/ft-baseline [--aircraft all|id,id] [--godot PATH] [--jobs N]
                                     [--only test,test] [--full-traces] [--app DISPOSABLE_COPY_OF_APP] [--data GENERATED_JSON]

Writes <out>/<aircraft>/profile.{json,md} plus traces (flight_test.gd), <out>/run.json (card version, git commit and
dirty paths, Godot version, data-file SHA-256 and exit status per aircraft) and <out>/summary.md. Exit status 1 when a
run fails or Godot reports a script error; a test that is not valid is a result, not a run failure.
"""
import argparse
import concurrent.futures
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from profile_io import read_profile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "research" / "flight-test" / "flight_test.gd"
ERROR = re.compile(r"^(SCRIPT ERROR|ERROR):", re.M)
AIRCRAFT_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*\Z")


def find_godot(explicit):
    for candidate in [explicit, os.environ.get("GODOT"),
                      ROOT / ".tools" / ("Godot_v4.8-beta2_win64_console.exe" if os.name == "nt" else "Godot_v4.8-beta2_linux.x86_64")]:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    sys.exit("no Godot found: pass --godot or set GODOT (pinned version: app/get-godot.sh)")


APP = ROOT / "app"


def godot(binary, args, timeout):
    command = [binary, "--headless", "--path", str(APP), "--audio-driver", "Dummy", "--script", str(SCRIPT), "--"] + args
    return subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)


def output_text(value):
    """TimeoutExpired captures bytes even with text=True; no output may be None."""
    return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else (value or "")


def child_log(stdout, stderr):
    # These streams were captured separately; their original interleaving is unknown.
    return ("--- stdout (captured separately) ---\n" + output_text(stdout)
            + "\n--- stderr (captured separately) ---\n" + output_text(stderr))


def git(*args):
    try:
        # rstrip only: porcelain lines start with a status column that may be a space.
        return subprocess.run(["git", "-C", str(ROOT)] + list(args), capture_output=True, text=True, check=True).stdout.rstrip("\n")
    except (OSError, subprocess.CalledProcessError):
        return ""


def card_version():
    match = re.search(r'const VERSION := "([^"]+)"', SCRIPT.read_text(encoding="utf-8"))
    return match.group(1) if match else "unknown"


def card_test_names():
    """Read the card's single literal registry, shared by its validator and dispatcher."""
    registry = re.search(r'^func _card\(\) -> Dictionary:\n(.*?)(?=^\S|\Z)',
                         SCRIPT.read_text(encoding="utf-8"), re.M | re.S)
    names = re.findall(r'^\s*"([^"\n]+)":', registry[1], re.M) if registry else []
    if not names or len(names) != len(set(names)):
        raise ValueError("the flight card must declare a nonempty, unique test roster")
    return names


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
    parser.add_argument("--only", help="comma-separated card test names; unknown, empty and duplicate names are refused")
    parser.add_argument("--full-traces", action="store_true")
    parser.add_argument("--diagnostics", action="store_true", help="also write <test>.aero.csv: regime weights and oracle/local/blended coefficients")
    parser.add_argument("--timeout", type=float, default=3600.0, help="seconds per aircraft")
    parser.add_argument("--app", help="a disposable copy of app/ holding one explicit candidate change")
    parser.add_argument("--data", help="generated candidate JSON for one explicitly selected aircraft; data id must match")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be positive and finite")
    if args.jobs <= 0:
        parser.error("--jobs must be positive")
    selected_ids = [a.strip() for a in args.aircraft.split(",")]
    if not all(selected_ids) or ("all" in selected_ids and selected_ids != ["all"]):
        parser.error("--aircraft must name all or a nonempty list of distinct aircraft IDs")
    if any(not AIRCRAFT_ID.fullmatch(aircraft) for aircraft in selected_ids):
        parser.error("--aircraft IDs must be plain catalog names, never file paths")
    if len(selected_ids) != len(set(selected_ids)):
        parser.error("--aircraft must not contain duplicate IDs")
    try:
        supported_tests = card_test_names()
    except ValueError as error:
        parser.error(str(error))
    expected_tests = supported_tests
    if args.only is not None:
        selected_tests = [name.strip() for name in args.only.split(",")]
        if not all(selected_tests) or len(selected_tests) != len(set(selected_tests)):
            parser.error("--only must be a nonempty list of distinct test names")
        unknown_tests = sorted(set(selected_tests) - set(supported_tests))
        if unknown_tests:
            parser.error("unknown --only tests: " + ", ".join(unknown_tests) + "; available: " + ", ".join(supported_tests))
        expected_tests = [name for name in supported_tests if name in selected_tests]
        args.only = ",".join(selected_tests)
    args.aircraft = ",".join(selected_ids)
    global APP
    if args.app:
        APP = Path(args.app).resolve()
    paths = data_paths()
    if selected_ids != ["all"]:
        unknown_ids = sorted(set(selected_ids) - set(paths))
        if unknown_ids:
            parser.error("unknown --aircraft IDs: " + ", ".join(unknown_ids))
    data_override = Path(args.data).resolve() if args.data else None
    if data_override and (args.aircraft == "all" or len([a for a in args.aircraft.split(",") if a]) != 1):
        parser.error("--data requires exactly one explicit --aircraft")
    if data_override and not data_override.is_file():
        parser.error("--data must name an existing generated aircraft JSON file")
    binary = find_godot(args.godot)
    out = Path(args.out).resolve()
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error("--out must be a new or empty directory; existing evidence is preserved")
    out.mkdir(parents=True, exist_ok=True)

    if args.aircraft == "all":
        def fail_listing(reason, stdout, stderr, child_exit, complete):
            log = child_log(stdout, stderr) + "\nERROR: " + reason + "\n"
            (out / "run.log").write_text(log, encoding="utf-8")
            record = {"phase": "catalog_discovery", "exit": "catalog_failed", "child_exit": child_exit,
                      "capture_complete": complete, "error": reason, "aircraft": {},
                      "card": card_version(), "commit": git("rev-parse", "HEAD"), "expected_tests": expected_tests}
            (out / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
            print(f"FAIL catalog discovery: {reason}; evidence {out}", file=sys.stderr)
            sys.exit(1)

        try:
            listing = godot(binary, ["--list"], 300)
        except subprocess.TimeoutExpired as expired:
            fail_listing("catalog listing timed out", expired.stdout, expired.stderr, "timeout", False)
        except OSError as error:
            fail_listing(f"cannot launch catalog listing: {error}", None, None, "launch_error", False)
        if listing.returncode != 0 or ERROR.search(listing.stdout + listing.stderr):
            fail_listing("catalog listing failed", listing.stdout, listing.stderr, listing.returncode, True)
        ids = re.findall(r"^FT-AIRCRAFT (\S+)", listing.stdout, re.M)
        if (not ids or len(ids) != len(set(ids))
                or any(not AIRCRAFT_ID.fullmatch(aircraft) or aircraft not in paths for aircraft in ids)):
            fail_listing("catalog listing returned an empty, duplicate or unknown aircraft roster",
                         listing.stdout, listing.stderr, listing.returncode, True)
    else:
        ids = selected_ids

    extra = (["--only=" + args.only] if args.only else []) + (["--full-traces"] if args.full_traces else []) + (["--diagnostics"] if args.diagnostics else [])
    if data_override:
        extra.append("--data=" + str(data_override))
    if data_override:
        if ids[0] not in paths:
            parser.error("--data requires a known catalog aircraft")
        paths[ids[0]] = data_override

    def fly(aircraft):
        started = time.monotonic()
        job_dir = out / aircraft
        capture_complete = True
        launch_error = None
        try:
            result = godot(binary, ["--aircraft=" + aircraft, "--out=" + str(out)] + extra, args.timeout)
            log = child_log(result.stdout, result.stderr)
            code = result.returncode
        except subprocess.TimeoutExpired as expired:
            log = child_log(expired.stdout, expired.stderr)
            code = "timeout"
            capture_complete = False
        except OSError as error:
            launch_error = f"{type(error).__name__}: {error}"
            log = "ERROR: cannot launch flight-test child: " + launch_error + "\n"
            code = "launch_error"
            capture_complete = False
        child_exit = code
        log = log.replace(str(ROOT).replace("\\", "/") + "/", "").replace(str(ROOT) + os.sep, "")
        # Retain the child evidence even if reading or validating its profile fails.
        job_dir.mkdir(exist_ok=True)
        log_path = job_dir / "run.log"
        log_path.write_text(log, encoding="utf-8")
        errors = len(ERROR.findall(log))
        profile = job_dir / "profile.json"
        valid = total = None
        loaded_hash = None
        actual_tests = []
        profile_error = None
        try:
            report = read_profile(profile, summary_metadata=True)
            loaded_hash = report.get("aircraft_input_sha256")
            results = report["results"]
            actual_tests = list(results)
            total = len(results)
            valid = sum(1 for r in results.values() if r.get("valid"))
        except (OSError, UnicodeError, ValueError) as error:
            profile_error = f"{type(error).__name__}: {error}"
            log += "\nERROR: unusable flight-test profile: " + profile_error + "\n"
            errors += 1
            if code == 0:
                code = "profile_invalid"
        missing_tests = sorted(set(expected_tests) - set(actual_tests))
        unexpected_tests = sorted(set(actual_tests) - set(expected_tests))
        test_roster_matches = bool(actual_tests) and not missing_tests and not unexpected_tests
        data = paths.get(aircraft)
        data_error = None
        try:
            disk_hash = hashlib.sha256(data.read_bytes()).hexdigest() if data else None
        except OSError as error:
            disk_hash = None
            data_error = f"{type(error).__name__}: {error}"
        identity_matches = isinstance(loaded_hash, str) and len(loaded_hash) == 64 and loaded_hash == disk_hash
        if code == 0 and not identity_matches:
            code = "data_identity_mismatch"
            errors += 1
            log += "\nERROR: flight-test loaded input identity does not match the reported data file\n"
        if code == 0 and not test_roster_matches:
            code = "test_roster_mismatch"
            errors += 1
            log += ("\nERROR: flight-test results do not match the requested test roster; "
                    f"missing={missing_tests}, unexpected={unexpected_tests}\n")
        log_path.write_text(log.rstrip("\n") + "\n", encoding="utf-8")
        receipt = {
            "exit": code, "child_exit": child_exit, "script_errors": errors,
            "capture_complete": capture_complete, "launch_error": launch_error,
            "profile_error": profile_error, "data_error": data_error,
            "wall_s": round(time.monotonic() - started, 1), "valid_tests": valid, "tests": total,
            "data_file": (str(data.relative_to(APP)) if data.is_relative_to(APP) else str(data)).replace("\\", "/") if data else None,
            "data_sha256": loaded_hash, "data_file_sha256_after": disk_hash, "data_identity_matches": identity_matches,
            "test_roster_matches": test_roster_matches,
            "missing_tests": missing_tests, "unexpected_tests": unexpected_tests,
        }
        (job_dir / "run.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        return aircraft, receipt

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        runs = dict(pool.map(fly, ids))

    try:
        version_result = subprocess.run([binary, "--version"], capture_output=True, text=True,
                                        encoding="utf-8", errors="replace", timeout=30)
        version = version_result.stdout.strip()
        version_error = None if getattr(version_result, "returncode", 0) == 0 else "engine version command failed"
    except (OSError, subprocess.TimeoutExpired) as error:
        version, version_error = "", f"{type(error).__name__}: {error}"
    dirty = [line[3:] for line in git("status", "--porcelain", "--", "app", "research/flight-test").splitlines()]
    record = {"card": card_version(), "commit": git("rev-parse", "HEAD"), "dirty_paths": dirty, "godot": version,
              "godot_version_error": version_error,
              "app": "app" if APP == ROOT / "app" else str(APP),
              "data_override": str(data_override) if data_override else None,
              "only": args.only, "expected_tests": expected_tests, "aircraft": runs}
    (out / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")

    import summarize
    finished = [a for a in ids if runs[a]["exit"] == 0 and not runs[a]["script_errors"]
                and runs[a]["test_roster_matches"] and (out / a / "profile.json").is_file()]
    summary_error = None
    if finished:
        from io import StringIO
        buffer = StringIO()
        stdout, sys.stdout = sys.stdout, buffer
        try:
            summarize.main_with(out, finished)
        except (OSError, UnicodeError, ValueError, KeyError, TypeError) as error:
            summary_error = f"{type(error).__name__}: {error}"
        finally:
            sys.stdout = stdout
        if summary_error is None:
            (out / "summary.md").write_text(buffer.getvalue(), encoding="utf-8")
    record["summary_error"] = summary_error
    (out / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")

    failed = bool(summary_error or version_error)
    for aircraft, run in runs.items():
        bad = run["exit"] != 0 or run["script_errors"] or run["tests"] is None
        failed = failed or bad
        print(f"{'FAIL' if bad else 'ok  '} {aircraft:32s} exit {run['exit']}, script errors {run['script_errors']}, "
              f"valid {run['valid_tests']}/{run['tests']}, {run['wall_s']} s")
    summary_status = (f"summary unavailable ({summary_error})" if summary_error else
                      f"summary {out / 'summary.md'}" if finished else "summary unavailable (no complete runs)")
    if version_error:
        print("engine provenance unavailable: " + version_error)
    print(f"card {record['card']}, commit {record['commit'][:10]}{' (dirty)' if dirty else ''}; {summary_status}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
