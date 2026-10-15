#!/usr/bin/env python3
"""Run the frozen app/test.sh tail after the GDScript test loop, sequentially."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


APP = Path("/home/bulto/openrc-r11-b09-r05b-20261015-07/app")
ROOT = APP.parent
GODOT = ROOT / ".tools/Godot_v4.7.2-stable_linux.x86_64"
LIVE_CHECKER = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator/app/tests/check_trimmed_flight.py")
EVIDENCE = Path(
    "/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/"
    "remediation/R11/next-candidate/materialized-20261015-07-01/diagnostic-tail-01"
)
LOGS = EVIDENCE / "logs"
PYTHON = sys.executable
GODOT_TIMEOUT = "/usr/bin/timeout"
RESULTS: list[dict] = []


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


if EVIDENCE.exists():
    raise SystemExit(f"refusing to reuse evidence directory: {EVIDENCE}")
LOGS.mkdir(parents=True)
metadata = {
    "format": "R11 frozen test.sh diagnostic tail v1",
    "started_utc": utc_now(),
    "candidate_root": str(ROOT),
    "app_path": str(APP),
    "godot_path": str(GODOT),
    "godot_sha256": sha256(GODOT),
    "test_sh_sha256": sha256(APP / "test.sh"),
    "frozen_checker_sha256": sha256(APP / "tests/check_trimmed_flight.py"),
    "live_checker_path": str(LIVE_CHECKER),
    "live_checker_sha256": sha256(LIVE_CHECKER),
    "head": subprocess.run(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip(),
    "working_tree_status": subprocess.run(
        ["git", "-C", str(ROOT), "status", "--short", "--untracked-files=normal"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout,
}
(EVIDENCE / "runner-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

BASE_ENV = os.environ.copy()
BASE_ENV["OPENRC_TEST_GODOT"] = str(GODOT)


def record(name: str, argv: list[str], *, timeout_s: int = 600, expect: str = "zero", env: dict | None = None, check_engine: bool = False) -> tuple[bool, str]:
    index = len(RESULTS) + 1
    log_path = LOGS / f"{index:03d}-{name}.log"
    started = utc_now()
    elapsed_start = time.monotonic()
    print(f"START {index:03d} {name} cap={timeout_s}s", flush=True)
    merged_env = BASE_ENV.copy()
    if env:
        merged_env.update(env)
    try:
        completed = subprocess.run(
            argv,
            cwd=APP,
            env=merged_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=timeout_s,
            check=False,
        )
        output = completed.stdout
        returncode = completed.returncode
        timed_out = False
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        output = str(partial) + f"\nRUNNER_TIMEOUT after {timeout_s}s\n"
        returncode = None
        timed_out = True
    elapsed = time.monotonic() - elapsed_start
    expected = returncode == 0 if expect == "zero" else returncode not in (None, 0)
    engine_errors = bool(check_engine and re.search(r"^(SCRIPT )?ERROR:|FAIL", output, re.MULTILINE))
    ok = expected and not timed_out and not engine_errors
    status = "PASS" if ok else ("TIMEOUT" if timed_out else "FAIL")
    log_text = (
        f"# {name}\n# started_utc={started}\n# cwd={APP}\n"
        f"# timeout_seconds={timeout_s}\n# expect={expect}\n"
        f"# command={shlex.join(argv)}\n# returncode={returncode}\n"
        f"# timed_out={timed_out}\n# engine_error_detected={engine_errors}\n\n"
        + output
    )
    log_path.write_text(log_text, encoding="utf-8", errors="replace")
    result = {
        "index": index,
        "name": name,
        "status": status,
        "returncode": returncode,
        "timed_out": timed_out,
        "elapsed_seconds": round(elapsed, 3),
        "timeout_seconds": timeout_s,
        "expect": expect,
        "engine_error_detected": engine_errors,
        "command": argv,
        "log": str(log_path),
        "started_utc": started,
        "ended_utc": utc_now(),
    }
    RESULTS.append(result)
    print(f"END   {index:03d} {name} {status} rc={returncode} wall={elapsed:.2f}s log={log_path}", flush=True)
    return ok, output


def python(name: str, relative: str, *args: str, timeout_s: int = 600, expect: str = "zero", env: dict | None = None) -> tuple[bool, str]:
    return record(name, [PYTHON, str(APP / relative), *map(str, args)], timeout_s=timeout_s, expect=expect, env=env)


def godot(name: str, *args: str, timeout_s: int = 60, expect: str = "zero", check_engine: bool = False) -> tuple[bool, str]:
    argv = [GODOT_TIMEOUT, str(timeout_s), str(GODOT), "--headless", "--path", str(APP), "--audio-driver", "Dummy", *map(str, args)]
    return record(name, argv, timeout_s=timeout_s + 15, expect=expect, check_engine=check_engine)


def assertion(name: str, passed: bool, detail: str) -> None:
    index = len(RESULTS) + 1
    log_path = LOGS / f"{index:03d}-{name}.log"
    log_path.write_text(detail + "\n", encoding="utf-8")
    RESULTS.append({
        "index": index,
        "name": name,
        "status": "PASS" if passed else "FAIL",
        "returncode": 0 if passed else 1,
        "timed_out": False,
        "elapsed_seconds": 0,
        "timeout_seconds": 0,
        "expect": "assertion",
        "engine_error_detected": False,
        "command": [],
        "log": str(log_path),
        "started_utc": utc_now(),
        "ended_utc": utc_now(),
    })
    print(f"ASSERT {index:03d} {name} {'PASS' if passed else 'FAIL'}: {detail}", flush=True)


def godot_cmd(*args: str) -> list[str]:
    return [GODOT_TIMEOUT, "60", str(GODOT), "--headless", "--path", str(APP), "--audio-driver", "Dummy", *map(str, args)]


def check_json_report(name: str, path: Path, checks) -> None:
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
        passed, detail = checks(report)
    except Exception as error:  # evidence runner must continue after a failed report
        passed, detail = False, f"{type(error).__name__}: {error}"
    assertion(name, passed, detail)


print(f"Diagnostic tail begins {utc_now()}; app/test.sh SHA-256={metadata['test_sh_sha256']}", flush=True)

# H7 through the model/asset contracts.
python("H7_math_sensitivity", "tests/check_math_sensitivity.py")
python("L5_field_failure_route", "tests/test_field_failures.py", "FieldFailureRoutes.test_headless_invalid_fields_fail_both_routes")
godot("aircraft_model_contract", "--script", "res://aircraft/verify_model.gd", check_engine=True)
godot("extra_model_contract", "--script", "res://aircraft/verify_extra.gd", check_engine=True)
python("p51_appearance_check", "../assets/aircraft/p51d-mustang-120/compile_appearance.py", "--check")
godot("p51_model_contract", "--script", "res://aircraft/verify_p51.gd", check_engine=True)
godot("p51_clearance_contract", "--script", "res://aircraft/verify_p51_clearance.gd", check_engine=True)
python("avanti_blender_source_check", "../assets/aircraft/avanti-s-a200/compile_blender.py", "--check")
godot("avanti_visual_contract", "--script", "res://aircraft/verify_avanti.gd", check_engine=True)
python("timber_manifest_check", "../research/timber/tt01/manifest.py", "--check")
godot(
    "timber_mesh_measurement_check",
    "--script", str(APP / "../research/timber/tt02/measure_mesh.gd"), "--",
    f"--out={APP / '../assets/aircraft/turbo-lumber-evolution/mesh-measurements.json'}", "--check",
)
python("timber_build_geometry_check", "../assets/aircraft/turbo-lumber-evolution/build_geometry.py", "--check")
python("timber_compile_geometry_check", "../assets/aircraft/turbo-lumber-evolution/compile_geometry.py", "--check")
python("timber_asset_check", "../research/timber/tt03/check_asset.py", "--check")
python("timber_physics_derive_check", "../research/timber/tt07/derive_physics.py", "--check")
python("timber_sensitivity_check", "../research/timber/tt07/sensitivity.py", "--check")
python("timber_derive_unit_tests", "../research/timber/tt07/test_derive.py")
godot("timber_model_contract", "--script", "res://aircraft/verify_timber.gd", check_engine=True)

# Python acceptance/CLI suites after the frozen GDScript loop.
python("trace_acceptance_frozen_checker", "tests/test_trace_acceptance.py")
godot("D8b_candidate_generator_check", "--script", str(APP / "../research/flight-robustness/d8b-r2/make_candidates.gd"), "--", "--check")
python("pullup_cli_acceptance", "tests/test_pullup_cli.py")
python("weather_cli_acceptance", "tests/test_weather_cli.py")
python("turbulence_cli_acceptance", "tests/test_turbulence_cli.py")
python("atmosphere_cli_acceptance", "tests/test_atmosphere_cli.py")
python("atmosphere_column_cli_acceptance", "tests/test_atmosphere_column_cli.py")
python("time_of_day_calendar_check", "../research/time-of-day/tod-09a/calendar_oracles.py", "--check")
python("time_of_day_cli_acceptance", "tests/test_time_of_day_cli.py")
python("shaft_cli_acceptance", "tests/test_shaft_cli.py")

# test.sh direct --trace route for all five catalog aircraft. Preserve the frozen checker's outcome,
# then run the root-approved current checker as a separate compatibility diagnostic.
trace_specs = [
    ("stik", "jensen-das-ugly-stik-60"),
    ("extra", "gp-extra-300s-60"),
    ("p51", "p51d-mustang-120"),
    ("avanti", "sebart-avanti-s-a200-p100rx"),
    ("timber", "turbo-lumber-evolution"),
]
trace_paths: dict[str, Path] = {}
for label, aircraft_id in trace_specs:
    trace_path = EVIDENCE / f"trace-{label}.csv"
    args = ["--", f"--trace={trace_path}", "--t=3"]
    if aircraft_id != "jensen-das-ugly-stik-60":
        args.insert(1, f"--aircraft={aircraft_id}")
    ok, _ = godot(f"app_trace_{label}", *args)
    trace_paths[label] = trace_path
    if trace_path.exists():
        if label in ("extra", "p51", "avanti", "timber"):
            assertion(f"app_trace_{label}_names_aircraft", aircraft_id in trace_path.read_text(encoding="utf-8", errors="replace"), f"expected aircraft ID {aircraft_id}")
        checker_args = [str(trace_path), "--duration=3"]
        if label == "timber":
            checker_args.append(f"--aircraft-input={APP / 'data/aircraft/turbo_lumber_evolution.json'}")
        python(f"frozen_trimmed_checker_{label}", "tests/check_trimmed_flight.py", *checker_args)
    else:
        assertion(f"app_trace_{label}_file_exists", False, f"Godot command ok={ok}, expected trace absent: {trace_path}")

for label, _aircraft_id in trace_specs:
    trace_path = trace_paths[label]
    if trace_path.exists():
        checker_args = [str(trace_path), "--duration=3"]
        if label == "timber":
            checker_args.append(f"--aircraft-input={APP / 'data/aircraft/turbo_lumber_evolution.json'}")
        record(f"live_trimmed_checker_{label}", [PYTHON, str(LIVE_CHECKER), *checker_args], env={"OPENRC_TEST_GODOT": str(GODOT)})

python("avanti_physics_data_check", "../research/avanti-s/av06/derive_physics.py", "--check")
for aircraft_id in ["no-such-aircraft"]:
    trace_path = EVIDENCE / "unknown-aircraft.csv"
    godot(f"unknown_aircraft_refused_{aircraft_id}", "--", f"--aircraft={aircraft_id}", f"--trace={trace_path}", "--t=1", expect="nonzero")

python("glow_packaged_smoke", "../research/glow-engines/packaged_smoke.py", "--godot", str(GODOT), "--out", str(EVIDENCE / "glow-smoke" / "results"))

# Live-input and scripted frame-time logger routes plus invalid-option negative controls.
live_frame_report = EVIDENCE / "frametimes-live.json"
godot("frametime_live_logger", "--", f"--frametimes={live_frame_report}", "--t=1.5")
def live_frame_check(report: dict) -> tuple[bool, str]:
    ms = report["frame_ms"]
    ok = (
        report["frames"] > 10 and report["seconds"] >= 1.5
        and report["format"] == "openrc-frametimes v2" and report["complete"] is True
        and report["route"] == "live-input" and report["input_enabled"] is True
        and len(report["frame_deltas_s"]) == report["frames"]
        and abs(sum(report["frame_deltas_s"]) - report["seconds"]) < 1e-8
        and all(len(values) == report["frames"] for values in report["raw_metrics"].values())
        and report["simulation"]["ticks"] > 0 and report["actual_warmup_s"] >= 1.0
        and 0 < ms["p50"] <= ms["p95"] <= ms["p99"] <= ms["max"]
        and all(key in report for key in ("adapter", "api", "godot", "os", "vsync", "physics_us_per_tick"))
    )
    return ok, f"frames={report['frames']}, ms={ms}, ticks={report['simulation']['ticks']}"
check_json_report("frametime_live_report_contract", live_frame_report, live_frame_check)

scripted_frame_report = EVIDENCE / "frametimes-scripted.json"
godot("frametime_scripted_logger", "--", f"--frametimes={scripted_frame_report}", "--warmup=0", "--t=0.1", "--scripted", "--case=logger-smoke")
def scripted_frame_check(report: dict) -> tuple[bool, str]:
    ok = (
        report["route"] == "scripted-fixed" and report["case_id"] == "logger-smoke"
        and report["input_enabled"] is False and report["simulation"]["ticks"] == 0
        and report["complete"] is True and report["seconds"] >= 0.1
        and report["seconds"] - report["frame_deltas_s"][-1] < 0.100001
        and report["warmup_s"] == 0 and bool(report["backend"]) and bool(report["preset"])
    )
    return ok, f"route={report['route']}, case={report['case_id']}, frames={report['frames']}, ticks={report['simulation']['ticks']}"
check_json_report("frametime_scripted_report_contract", scripted_frame_report, scripted_frame_check)

for bad in ["--t=0", "--t=nan", "--warmup=-1", "--capture", "--trace=/dev/null"]:
    godot(f"frametime_invalid_option_{bad.lstrip('-').replace('/', '_')}", "--", "--frametimes=/dev/null", bad, expect="nonzero")
godot("frametime_output_write_failure", "--", f"--frametimes={APP}", "--warmup=0", "--t=0.01", expect="nonzero")

# Rendering-rate invariance at 30/60/144 fps. Keep each engine run sequential.
def frame_series(prefix: str, script_args: list[str], marker: str, required: bool = True) -> None:
    hashes: list[str] = []
    for fps in (30, 60, 144):
        _ok, output = godot(f"{prefix}_{fps}fps", "--fixed-fps", str(fps), "--script", "res://tests/run_fixed_step.gd", *script_args, check_engine=True)
        matches = re.findall(rf"{re.escape(marker)}=([0-9a-f]+)", output)
        hashes.append(matches[-1] if matches else "")
    passed = bool(hashes[0]) and len(set(hashes)) == 1
    assertion(f"{prefix}_same_hash_all_fps", passed, f"{marker}={hashes}")

frame_series("fixed_step_default", [], "state_sha256")
frame_series("fixed_step_timber", ["--", "--aircraft=turbo-lumber-evolution"], "flight_sha256")

python("propwash_e0b5_frame_invariance", "../research/propwash/e0b5/check_frames.py", "--godot", str(GODOT))
python("propwash_e0b6p_frame_invariance", "../research/propwash/e0b6p/check_frames.py", "--godot", str(GODOT))
python(
    "ground_contact_e5a",
    "../research/ground-contact/e5a/verify.py",
    "--godot", str(GODOT), "--out", str(EVIDENCE / "e5a" / "results"),
    timeout_s=1800,
)
python(
    "ground_contact_e5b",
    "../research/ground-contact/e5b/verify.py",
    "--godot", str(GODOT), "--out", str(EVIDENCE / "e5b" / "results"),
    timeout_s=1800,
)

summary = {
    **metadata,
    "finished_utc": utc_now(),
    "step_count": len(RESULTS),
    "passed": sum(result["status"] == "PASS" for result in RESULTS),
    "failed": sum(result["status"] != "PASS" for result in RESULTS),
    "results": RESULTS,
}
(EVIDENCE / "results.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
with (EVIDENCE / "results.tsv").open("w", encoding="utf-8") as out:
    out.write("index\tstatus\tname\treturncode\telapsed_seconds\ttimeout_seconds\tlog\n")
    for result in RESULTS:
        out.write(
            f"{result['index']}\t{result['status']}\t{result['name']}\t{result['returncode']}\t"
            f"{result['elapsed_seconds']}\t{result['timeout_seconds']}\t{result['log']}\n"
        )
print(f"COMPLETE {summary['passed']} passed, {summary['failed']} failed, {summary['step_count']} steps", flush=True)
