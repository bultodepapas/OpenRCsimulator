#!/usr/bin/env python3
"""Compare full-session event ticks from isolated EL2a-P2 baseline/candidate app snapshots."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PROBE = HERE / "event_probe.gd"
IGNORED_DIRS = {".godot", "captures"}
PINNED_VERSION = re.compile(r"4\.7\.2\.stable\.official\.[0-9a-f]{9}")
BASELINE_REVISION = "5f85109ada405071864ee1c3c5c2a97ecaa4bc84"
ENGINE_ERROR = re.compile(r"(?mi)^\s*(?:SCRIPT ERROR|SHADER ERROR|ERROR|Parse Error|Compile Error):")
DEFAULT_TIMEOUT_S = 1800

BODY_ABS_TOL = 1e-8
WASH_ABS_TOL = 1e-8
RPM_ABS_TOL = 1e-5
CHARGE_ABS_TOL_C = 1e-8
ENERGY_ABS_TOL_J = 1e-6
HEAT_ABS_TOL_J = 1e-6

FULL_CASE_CONTRACT = {
    "battery-powered-4s": {"mode": "battery", "required_events": ["battery_exhausted"],
                            "max_ticks": 3 * 240, "engine_running": True, "initial_throttle": 1.0,
                            "initial_charge_c": 4.0, "cut_after_ticks": -1},
    "battery-coast-4s": {"mode": "battery", "required_events": ["battery_exhausted"],
                          "max_ticks": 3 * 240, "engine_running": False, "initial_throttle": 0.0,
                          "initial_charge_c": 0.25, "cut_after_ticks": -1},
    "battery-powered-6s": {"mode": "battery", "required_events": ["battery_exhausted"],
                            "max_ticks": 3 * 240, "engine_running": True, "initial_throttle": 1.0,
                            "initial_charge_c": 2.4, "cut_after_ticks": -1},
    "battery-coast-6s": {"mode": "battery", "required_events": ["battery_exhausted"],
                          "max_ticks": 3 * 240, "engine_running": False, "initial_throttle": 0.0,
                          "initial_charge_c": 0.25, "cut_after_ticks": -1},
    "fixed-voltage-rotor-stop": {"mode": "fixed_voltage", "required_events": ["rotor_stop"],
                                  "max_ticks": 20 * 240, "engine_running": True, "initial_throttle": 1.0,
                                  "initial_charge_c": -1.0, "cut_after_ticks": 120},
    "battery-no-event-4s": {"mode": "no_event", "required_events": [], "max_ticks": 240,
                             "engine_running": True, "initial_throttle": 0.5,
                             "initial_charge_c": 10944.0, "cut_after_ticks": -1},
}
SMOKE_CASE_CONTRACT = {
    "battery-powered-smoke-4s": {"mode": "battery", "required_events": ["battery_exhausted"],
                                 "max_ticks": round(0.05 * 240), "engine_running": True,
                                 "initial_throttle": 1.0, "initial_charge_c": 0.2, "cut_after_ticks": -1},
}
FULL_CASES = set(FULL_CASE_CONTRACT)
SMOKE_CASES = set(SMOKE_CASE_CONTRACT)


class CompareError(RuntimeError):
    pass


def require(ok: bool, message: str) -> None:
    if not ok:
        raise CompareError(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_hashes(root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for directory, dirs, files in os.walk(root):
        dirs[:] = sorted(name for name in dirs if name.casefold() not in IGNORED_DIRS)
        for name in sorted(files):
            path = Path(directory) / name
            require(not path.is_symlink(), f"refusing symlink in app snapshot: {path}")
            result[path.relative_to(root).as_posix()] = sha256_file(path)
    return result


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda token: (_ for _ in ()).throw(
            CompareError(f"non-finite JSON token {token}")))
    except (OSError, json.JSONDecodeError) as exc:
        raise CompareError(f"cannot read JSON at {path}: {exc}") from exc
    require(isinstance(value, dict), f"expected JSON object at {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")


def git_revision(app: Path) -> str | None:
    try:
        result = subprocess.run(["git", "-C", str(app), "rev-parse", "HEAD"], capture_output=True,
                                text=True, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def run_command(command: list[str], timeout: int, log_path: Path,
                xdg_root: Path | None = None, allowed_codes: tuple[int, ...] = (0,)) -> str:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    if xdg_root is not None:
        xdg_names = ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME")
        xdg_paths = {name: xdg_root / name.removeprefix("XDG_").lower() for name in xdg_names}
        for path in xdg_paths.values():
            path.mkdir(parents=True, exist_ok=True)
        environment.update({name: str(path) for name, path in xdg_paths.items()})
    header = "$ " + subprocess.list2cmdline(command) + f"\n# timeout_s={timeout}\n\n"
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                errors="replace", check=False, timeout=timeout, env=environment)
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        log_path.write_text(header + output + f"\nTIMEOUT after {timeout}s\n", encoding="utf-8")
        raise CompareError(f"command timed out; log preserved at {log_path}") from exc
    output = result.stdout or ""
    log_path.write_text(header + output, encoding="utf-8")
    require(result.returncode in allowed_codes,
            f"command exited {result.returncode}; see {log_path}: {output[-2000:]}")
    require(ENGINE_ERROR.search(output) is None, f"engine error output; see {log_path}: {output[-2000:]}")
    return output


def validate_probe(report: dict[str, Any], smoke: bool) -> dict[str, dict[str, Any]]:
    expected = SMOKE_CASES if smoke else FULL_CASES
    require(report.get("format") == "el2a-p2-whole-session-event-probe-v1", "wrong event probe report format")
    require(report.get("tick_hz") == 240 and report.get("smoke") is smoke, "wrong tick or smoke mode")
    rows = report.get("rows")
    require(isinstance(rows, list) and report.get("failures") == [], "probe reports failures or missing rows")
    decoded: dict[str, dict[str, Any]] = {}
    for row in rows:
        require(isinstance(row, dict) and row.get("ok") is True and row.get("all_finite") is True,
                "probe case failed or contains nonfinite state")
        case_id = row.get("id")
        require(case_id in expected and case_id not in decoded, f"unexpected or duplicate case {case_id}")
        require(row.get("tick_hz") == 240 and row.get("ticks", 0) > 0
                and math.isclose(float(row.get("end_time_s", math.nan)), row["ticks"] / 240,
                                 rel_tol=1e-12, abs_tol=1e-15),
                f"{case_id}: incomplete tick report")
        require(isinstance(row.get("event_types"), list) and row.get("event_types") == [
            event.get("type") for event in row.get("events", [])], f"{case_id}: event list mismatch")
        require(isinstance(row.get("events"), list), f"{case_id}: malformed event list")
        last_tick = 0
        for event in row["events"]:
            require(isinstance(event, dict) and event.get("type") in {"battery_exhausted", "rotor_stop"},
                    f"{case_id}: invalid event type")
            require(isinstance(event.get("tick"), int) and event["tick"] >= last_tick,
                    f"{case_id}: events are not in chronological tick order")
            require(math.isclose(float(event.get("containing_tick_time_s", math.nan)), event["tick"] / 240,
                                 rel_tol=1e-12, abs_tol=1e-15),
                    f"{case_id}: event is not at its containing full-step endpoint")
            require(isinstance(event.get("event_tick_wall_usec"), int)
                    and event["event_tick_wall_usec"] > 0, f"{case_id}: missing event-tick timing")
            require(event.get("rotor_rpm", -1) >= 0, f"{case_id}: accepted rotor RPM is negative")
            require(isinstance(event.get("body_state"), list) and len(event["body_state"]) == 13,
                    f"{case_id}: malformed rigid-body event state")
            require(isinstance(event.get("continuous_state"), list), f"{case_id}: missing continuous event state")
            require(all(isinstance(x, (int, float)) and math.isfinite(float(x)) for x in
                        event["body_state"] + event["continuous_state"]), f"{case_id}: nonfinite event state")
            if event["type"] == "battery_exhausted":
                require(event.get("remaining_charge_c") == 0.0, f"{case_id}: accepted charge is not exactly zero")
            last_tick = event["tick"]
        if row.get("mode") == "no_event":
            require(row["events"] == [] and row.get("final_charge_c") > 0,
                    f"{case_id}: no-event control crossed a boundary")
        require(row.get("seed_checkpoint_file") and row.get("endpoint_checkpoint_file"),
                f"{case_id}: missing full native checkpoints")
        decoded[case_id] = row
    require(decoded.keys() == expected, "probe is missing expected event cases")
    return decoded


def safe_checkpoint(run_dir: Path, row: dict[str, Any], key: str) -> bytes:
    name = row.get(key)
    require(isinstance(name, str) and Path(name).name == name, f"unsafe checkpoint filename for {row.get('id')}")
    path = run_dir / name
    require(path.is_file(), f"missing native checkpoint file: {path}")
    data = path.read_bytes()
    expected_size = row.get("seed_checkpoint_bytes" if key.startswith("seed") else "endpoint_checkpoint_bytes")
    require(expected_size == len(data), f"native checkpoint byte count mismatch: {path}")
    return data


def event_replay_fingerprint(event: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in event.items() if key != "event_tick_wall_usec"}


def _max_abs(left: list[Any], right: list[Any], label: str, tolerance: float) -> float:
    require(len(left) == len(right), f"{label}: state layouts differ")
    maximum = max((abs(float(a) - float(b)) for a, b in zip(left, right)), default=0.0)
    require(maximum <= tolerance, f"{label}: maximum absolute difference {maximum:.9g} exceeds {tolerance:.9g}")
    return maximum


def compare_event_state(old: dict[str, Any], new: dict[str, Any], label: str) -> dict[str, float]:
    require(old.get("type") == new.get("type") and old.get("tick") == new.get("tick"),
            f"{label}: event type or containing tick differs")
    require(old.get("rotor_index") == new.get("rotor_index")
            and old.get("charge_index") == new.get("charge_index"), f"{label}: state layouts differ")
    body = _max_abs(old["body_state"], new["body_state"], label + " rigid body", BODY_ABS_TOL)
    rotor_index = int(old["rotor_index"])
    charge_index = int(old["charge_index"])
    continuous_old = old["continuous_state"]
    continuous_new = new["continuous_state"]
    expected_length = charge_index + 3 if charge_index >= 0 else rotor_index + 1
    require(len(continuous_old) == len(continuous_new) == expected_length,
            f"{label}: continuous-state layout differs from wash/RPM/electrical schema")
    require(rotor_index >= 0 and charge_index in (-1, rotor_index + 1), f"{label}: invalid state indexes")
    wash = _max_abs(continuous_old[:rotor_index], continuous_new[:rotor_index], label + " wash state", WASH_ABS_TOL)
    rpm = abs(float(old["rotor_rpm"]) - float(new["rotor_rpm"]))
    require(rpm <= RPM_ABS_TOL, f"{label}: rotor difference {rpm:.9g} exceeds {RPM_ABS_TOL:.9g} rpm")
    maxima = {"body_state_max_abs": body, "wash_state_max_abs_m_s": wash, "rotor_rpm_abs": rpm}
    if charge_index >= 0:
        charge = abs(float(old["remaining_charge_c"]) - float(new["remaining_charge_c"]))
        energy = abs(float(old["terminal_energy_j"]) - float(new["terminal_energy_j"]))
        heat = abs(float(old["pack_heat_j"]) - float(new["pack_heat_j"]))
        require(charge <= CHARGE_ABS_TOL_C, f"{label}: charge difference {charge:.9g} exceeds tolerance")
        require(energy <= ENERGY_ABS_TOL_J, f"{label}: terminal-energy difference {energy:.9g} exceeds tolerance")
        require(heat <= HEAT_ABS_TOL_J, f"{label}: pack-heat difference {heat:.9g} exceeds tolerance")
        maxima.update({"charge_abs_c": charge, "terminal_energy_abs_j": energy, "pack_heat_abs_j": heat})
    return maxima


def _copy_app(source: Path, destination: Path) -> None:
    def ignore(directory: str, names: list[str]) -> set[str]:
        return {name for name in names if name.casefold() in IGNORED_DIRS
                and (Path(directory) / name).is_dir()}
    destination.parent.mkdir(parents=True, exist_ok=False)
    shutil.copytree(source, destination, ignore=ignore, symlinks=False)
    require(tree_hashes(destination) == tree_hashes(source), f"isolated app copy differs from source: {source}")


def _event_time_samples(reports: list[dict[str, Any]], case_id: str) -> list[float]:
    return [float(event["event_tick_wall_usec"])
            for report in reports for event in report[case_id]["events"]]


def compare_runs(reports: dict[str, list[dict[str, Any]]], run_dirs: dict[str, list[Path]], smoke: bool) -> dict[str, Any]:
    failures: list[str] = []
    cases: list[dict[str, Any]] = []
    expected = SMOKE_CASES if smoke else FULL_CASES
    for case_id in sorted(expected):
        base_rows = [report[case_id] for report in reports["baseline"]]
        candidate_rows = [report[case_id] for report in reports["candidate"]]
        run_rows = [("baseline", base_rows, run_dirs["baseline"]), ("candidate", candidate_rows, run_dirs["candidate"])]
        checkpoint_bytes: dict[tuple[str, str], list[bytes]] = {}
        for label, rows, paths in run_rows:
            for field, key in (("seed", "seed_checkpoint_file"), ("endpoint", "endpoint_checkpoint_file")):
                checkpoint_bytes[(label, field)] = [safe_checkpoint(path, row, key) for path, row in zip(paths, rows)]
            require(len(set(checkpoint_bytes[(label, "seed")])) == 1,
                    f"{case_id}: {label} seed checkpoint replay differs")
            require(len(set(checkpoint_bytes[(label, "endpoint")])) == 1,
                    f"{case_id}: {label} endpoint checkpoint replay differs")
            fingerprints = [[event_replay_fingerprint(event) for event in row["events"]] for row in rows]
            require(all(value == fingerprints[0] for value in fingerprints[1:]),
                    f"{case_id}: {label} accepted event-state replay differs")
        seed_equal = checkpoint_bytes[("baseline", "seed")][0] == checkpoint_bytes[("candidate", "seed")][0]
        if not seed_equal:
            failures.append(f"{case_id}: baseline/candidate native seed checkpoint bytes differ")
        b0, c0 = base_rows[0], candidate_rows[0]
        require(b0["event_types"] == c0["event_types"], f"{case_id}: observed event ordering differs")
        require(b0["initial_charge_c"] == c0["initial_charge_c"]
                and b0["engine_running"] == c0["engine_running"]
                and b0["initial_throttle"] == c0["initial_throttle"], f"{case_id}: replay inputs differ")
        if case_id == "battery-no-event-4s":
            same_seed = checkpoint_bytes[("baseline", "seed")][0] == checkpoint_bytes[("candidate", "seed")][0]
            same_endpoint = checkpoint_bytes[("baseline", "endpoint")][0] == checkpoint_bytes[("candidate", "endpoint")][0]
            if not same_seed or not same_endpoint:
                failures.append("battery-no-event-4s: full native checkpoint bytes changed")
            state_differences: list[dict[str, float]] = []
        else:
            state_differences = []
            for event_index, (old_event, new_event) in enumerate(zip(b0["events"], c0["events"])):
                state_differences.append(compare_event_state(old_event, new_event,
                                                              f"{case_id} event {event_index + 1}"))
        base_samples = _event_time_samples(reports["baseline"], case_id)
        candidate_samples = _event_time_samples(reports["candidate"], case_id)
        case_record: dict[str, Any] = {
            "id": case_id,
            "event_types": b0["event_types"],
            "event_ticks": [event["tick"] for event in b0["events"]],
            "baseline_event_tick_wall_usec": base_samples,
            "candidate_event_tick_wall_usec": candidate_samples,
            "baseline_median_event_tick_wall_usec": statistics.median(base_samples) if base_samples else None,
            "candidate_median_event_tick_wall_usec": statistics.median(candidate_samples) if candidate_samples else None,
            "native_seed_bytes_identical_across_implementations": seed_equal,
            "baseline_replay_checkpoint_bytes_identical": len(set(checkpoint_bytes[("baseline", "endpoint")])) == 1,
            "candidate_replay_checkpoint_bytes_identical": len(set(checkpoint_bytes[("candidate", "endpoint")])) == 1,
            "event_state_maxima": state_differences,
        }
        if case_id == "battery-no-event-4s":
            case_record["native_no_event_seed_bytes_identical"] = seed_equal
            case_record["native_no_event_endpoint_bytes_identical"] = checkpoint_bytes[("baseline", "endpoint")][0] == checkpoint_bytes[("candidate", "endpoint")][0]
        cases.append(case_record)
    return {"status": "passed" if not failures else "failed", "case_count": len(cases),
            "timing_scope": "only the wall time of the simulation tick in which an accepted event was observed",
            "root_bits_compared": False,
            "absolute_tolerances": {"body_state": BODY_ABS_TOL, "wash_state_m_s": WASH_ABS_TOL,
                                    "rotor_rpm": RPM_ABS_TOL, "remaining_charge_c": CHARGE_ABS_TOL_C,
                                    "terminal_energy_j": ENERGY_ABS_TOL_J, "pack_heat_j": HEAT_ABS_TOL_J},
            "cases": cases, "failures": failures}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-app", type=Path, required=True)
    parser.add_argument("--candidate-app", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", required=True, help="fresh absolute durable evidence directory")
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--timeout-sec", type=int, default=DEFAULT_TIMEOUT_S)
    parser.add_argument("--expected-baseline-revision", default=BASELINE_REVISION)
    parser.add_argument("--smoke", action="store_true", help="one short battery event case, one round")
    args = parser.parse_args()
    try:
        baseline = args.baseline_app.expanduser().resolve(strict=True)
        candidate = args.candidate_app.expanduser().resolve(strict=True)
        godot = args.godot.expanduser().resolve(strict=True)
        output = Path(args.out).expanduser()
        require(output.is_absolute() and not output.exists(), "--out must be a fresh absolute path")
        require(baseline.is_dir() and (baseline / "project.godot").is_file(), "baseline app is invalid")
        require(candidate.is_dir() and (candidate / "project.godot").is_file(), "candidate app is invalid")
        require(godot.is_file(), "pinned Godot executable is missing")
        require(PROBE.is_file(), f"event probe is missing: {PROBE}")
        require(args.timeout_sec >= 1, "--timeout-sec must be positive")
        rounds = 1 if args.smoke else args.rounds
        require(rounds == 1 if args.smoke else rounds >= 3, "use --smoke or at least three alternating rounds")
        for app in (baseline, candidate):
            require(not output.resolve().is_relative_to(app) and not app.is_relative_to(output.resolve()),
                    "output and source app paths must not contain one another")
        baseline_revision = git_revision(baseline)
        if baseline_revision is not None and args.expected_baseline_revision:
            require(baseline_revision.startswith(args.expected_baseline_revision),
                    f"baseline revision {baseline_revision} differs from expected {args.expected_baseline_revision}")
    except (OSError, CompareError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 2

    output.mkdir(parents=True, exist_ok=False)
    report_path = output / "comparison.json"
    run_record: dict[str, Any] = {
        "format": "el2a-p2-event-comparison-v1",
        "status": "running",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "smoke": args.smoke,
        "round_count": rounds,
        "arguments": {"baseline_app": str(baseline), "candidate_app": str(candidate),
                      "godot": str(godot), "expected_baseline_revision": args.expected_baseline_revision,
                      "observed_baseline_revision": baseline_revision, "timeout_sec": args.timeout_sec},
        "machine": {"os": platform.platform(), "architecture": platform.machine(),
                    "processor": platform.processor(), "logical_cpu_count": os.cpu_count()},
    }
    write_json(report_path, run_record)
    try:
        version_output = run_command([str(godot), "--version"], 30, output / "godot-version.log",
                                     xdg_root=output / "runtime" / "version", allowed_codes=(0, 1))
        version_lines = [line.strip() for line in version_output.splitlines() if line.strip()]
        require(len(version_lines) == 1 and PINNED_VERSION.fullmatch(version_lines[0]) is not None,
                "Godot must be the pinned official 4.7.2 build")
        engine = {"path": str(godot), "version": version_lines[0], "sha256": sha256_file(godot),
                  "bytes": godot.stat().st_size}
        source_hashes = {"baseline": tree_hashes(baseline), "candidate": tree_hashes(candidate)}
        app_copies: dict[str, Path] = {}
        for label, source in (("baseline", baseline), ("candidate", candidate)):
            app_copy = output / "snapshots" / label / "app"
            _copy_app(source, app_copy)
            app_copies[label] = app_copy
        changed_paths = []
        for relative in sorted(source_hashes["baseline"].keys() | source_hashes["candidate"].keys()):
            b_hash, c_hash = source_hashes["baseline"].get(relative), source_hashes["candidate"].get(relative)
            if b_hash != c_hash:
                changed_paths.append({"path": relative, "baseline_sha256": b_hash, "candidate_sha256": c_hash,
                                      "change": "added" if b_hash is None else "removed" if c_hash is None else "modified"})
        write_json(output / "source-manifest.json", {
            "excluded_directories": sorted(IGNORED_DIRS),
            "baseline": {"source_app": str(baseline), "file_count": len(source_hashes["baseline"]),
                         "files_sha256": source_hashes["baseline"]},
            "candidate": {"source_app": str(candidate), "file_count": len(source_hashes["candidate"]),
                          "files_sha256": source_hashes["candidate"]},
            "changed_app_paths": changed_paths,
            "event_probe_sha256": sha256_file(PROBE), "comparison_tool_sha256": sha256_file(Path(__file__).resolve()),
        })
        run_record.update({"engine": engine, "changed_app_paths": changed_paths,
                           "changed_app_path_count": len(changed_paths), "source_manifest": "source-manifest.json"})
        reports: dict[str, list[dict[str, Any]]] = {"baseline": [], "candidate": []}
        run_dirs: dict[str, list[Path]] = {"baseline": [], "candidate": []}
        order: list[dict[str, Any]] = []
        for round_index in range(rounds):
            sequence = ("baseline", "candidate") if round_index % 2 == 0 else ("candidate", "baseline")
            for label in sequence:
                run_dir = output / "runs" / f"round-{round_index + 1:02d}" / label
                run_dir.mkdir(parents=True, exist_ok=False)
                report_file = run_dir / "probe.json"
                log_file = run_dir / "probe.log"
                command = [str(godot), "--headless", "--path", str(app_copies[label]),
                           "--script", str(PROBE), "--", f"--out={run_dir}"]
                if args.smoke:
                    command.append("--smoke")
                run_command(command, args.timeout_sec, log_file,
                            xdg_root=output / "runtime" / f"round-{round_index + 1:02d}" / label)
                report = read_json(report_file)
                validated = validate_probe(report, args.smoke)
                reports[label].append(validated)
                run_dirs[label].append(run_dir)
                order.append({"round": round_index + 1, "snapshot": label,
                              "probe": report_file.relative_to(output).as_posix(),
                              "log": log_file.relative_to(output).as_posix()})
                run_record["run_order"] = order.copy()
                write_json(report_path, run_record)
        comparison = compare_runs(reports, run_dirs, args.smoke)
        run_record.update({"run_order": order, "comparison": comparison,
                           "status": comparison["status"], "completed_utc": datetime.now(timezone.utc).isoformat()})
        write_json(report_path, run_record)
        print(f"{run_record['status'].upper()}: {comparison['case_count']} cases; evidence: {output}")
        return 0 if comparison["status"] == "passed" else 1
    except Exception as exc:
        run_record.update({"status": "failed", "failure": f"{type(exc).__name__}: {exc}",
                           "completed_utc": datetime.now(timezone.utc).isoformat()})
        write_json(report_path, run_record)
        print(f"FAIL: {run_record['failure']}; evidence preserved at {output}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
