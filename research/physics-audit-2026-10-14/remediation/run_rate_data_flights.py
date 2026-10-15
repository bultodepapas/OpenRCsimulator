"""Record 28 controlled catalog pulses, exact-replay each, and compare data candidates."""
from __future__ import annotations

import argparse
import hashlib
import json
import queue
from pathlib import Path
import subprocess
import sys
import threading
import time

from run_fixture_checks import identity


ROOT = Path(__file__).resolve().parents[3]
PROBE = ROOT / "research/physics-audit-2026-10-14/remediation/record_catalog_pulses.gd"
OLD_PROBE = ROOT / "research/physics-audit-2026-10-14/session_probe.gd"
OLD_RUNNER = ROOT / "research/physics-audit-2026-10-14/remediation/run_catalog_flights.py"
IDENTITY_HELPER = ROOT / "research/physics-audit-2026-10-14/remediation/run_fixture_checks.py"
COMPARER = ROOT / "tools/flight_log/flight_log.py"
BASELINE_STIK_SHA256 = "5fe8ece91b7ebe92f304f764f0d50edc936ae5c4ab1d1c801cf20827ec1ee9b6"
CURRENT_STIK_SHA256 = "bdcf4d64c45676a112d837513ee1eef7ed017c39fa8b39b21236cd801950f723"
CURRENT_JET_SHA256 = "68d3fd42b28e30bf1dc210b838d945d517f062506749af14f995a5a5f39a83b6"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def external_hashes(paths: dict[str, Path]) -> dict[str, str]:
    return {name: sha256(path) for name, path in paths.items()}


def run_process(label: str, command: list[str], log_path: Path, timeout_s: int,
                command_log: list[dict]) -> None:
    """Run one bounded process, stream case progress, and retain all merged output."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    record = {"label": label, "command": command, "timeout_s": timeout_s,
              "log": str(log_path), "exit_code": None, "timeout": False, "errors": []}
    command_log.append(record)
    print(json.dumps({"event": "start", "label": label, "timeout_s": timeout_s}), flush=True)
    lines: queue.Queue[str | None] = queue.Queue()
    with log_path.open("w", encoding="utf-8", newline="") as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, encoding="utf-8", errors="replace", bufsize=1)
        assert process.stdout is not None

        def pump() -> None:
            try:
                for line in process.stdout:
                    lines.put(line)
            finally:
                lines.put(None)

        reader = threading.Thread(target=pump, daemon=True)
        reader.start()
        eof = False
        timed_out = False
        while not eof or process.poll() is None:
            if time.monotonic() - start > timeout_s:
                timed_out = True
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                break
            try:
                line = lines.get(timeout=0.25)
            except queue.Empty:
                continue
            if line is None:
                eof = True
                continue
            log.write(line)
            log.flush()
            stripped = line.rstrip("\r\n")
            if stripped.startswith(("PULSE_CASE_COMPLETE", "ALL_AXIS_PULSE_RECORDING_COMPLETE")):
                print(json.dumps({"event": "progress", "label": label, "message": stripped}), flush=True)
            if stripped.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL")):
                record["errors"].append(stripped)
        if timed_out:
            # Drain available output after termination so the log captures the timeout point.
            while True:
                try:
                    line = lines.get_nowait()
                except queue.Empty:
                    break
                if line is None:
                    continue
                log.write(line)
                if line.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL")):
                    record["errors"].append(line.rstrip("\r\n"))
        reader.join(timeout=2)
        record["exit_code"] = 124 if timed_out else process.returncode
        record["timeout"] = timed_out
        record["elapsed_s"] = round(time.monotonic() - start, 3)
    print(json.dumps({"event": "finish", "label": label, "exit_code": record["exit_code"],
                      "timeout": record["timeout"], "errors": record["errors"],
                      "elapsed_s": record["elapsed_s"]}), flush=True)
    if record["exit_code"] != 0 or record["errors"]:
        raise RuntimeError(f"{label} failed; see {log_path}")


def check_replay(report_path: Path, mode: str, baseline_sha: str) -> dict:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if (report.get("status") != "ok" or not report.get("complete")
            or report.get("rows") != 1441 or report.get("mode") != mode
            or report.get("solver_changed")):
        raise RuntimeError(f"Invalid {mode} replay: {report_path}")
    if report.get("baseline_solver_sha256") != baseline_sha or report.get("current_solver_sha256") != baseline_sha:
        raise RuntimeError(f"Source solver identity mismatch in replay: {report_path}")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="read-only isolated imported app copy")
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--stik-baseline", type=Path, required=True,
                        help="archived prior Stik aircraft JSON bytes")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--capture-timeout", type=int, default=240)
    parser.add_argument("--process-timeout", type=int, default=180)
    args = parser.parse_args()
    app, godot = args.app.resolve(), args.godot.resolve()
    baseline_stik = args.stik_baseline.resolve()
    out = args.out.resolve()
    current_stik = app / "data/aircraft/jensen_ugly_stik_60.json"
    current_jet = app / "data/aircraft/sebart_avanti_s_a200.json"
    project_file = app / "project.godot"
    for path in [app, godot, baseline_stik, current_stik, current_jet, project_file]:
        if not path.exists():
            parser.error(f"required path does not exist: {path}")
    if out.exists():
        parser.error(f"output path already exists; refusing to overwrite: {out}")
    if sha256(baseline_stik) != BASELINE_STIK_SHA256:
        parser.error("archived baseline Stik bytes do not match the recorded R11 baseline identity")
    if sha256(current_stik) != CURRENT_STIK_SHA256:
        parser.error("isolated-app candidate Stik bytes do not match the recorded D11g candidate")
    if sha256(current_jet) != CURRENT_JET_SHA256:
        parser.error("isolated-app Avanti bytes differ from the reviewed unchanged Jet data")

    out.mkdir(parents=True, exist_ok=False)
    records_dir = out / "records"
    source_before = identity(app)
    project_before = sha256(project_file)
    watched_paths = {
        "new_probe": PROBE, "new_runner": Path(__file__).resolve(),
        "original_probe": OLD_PROBE, "original_runner": OLD_RUNNER,
        "fixture_identity_helper": IDENTITY_HELPER, "csv_comparer": COMPARER,
        "flight_log_cli": app / "tools/flight_log_cli.gd", "project_godot": project_file,
        "godot_binary": godot, "archived_baseline_stik": baseline_stik,
        "candidate_stik": current_stik, "unchanged_jet_data": current_jet,
    }
    watched_before = external_hashes(watched_paths)
    commands: list[dict] = []
    failures: list[dict] = []
    solver_sha = None
    flights: list[dict] = []
    prefix = [str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy"]

    try:
        run_process("record-28-baseline-tapes",
                    prefix + ["--script", str(PROBE), "--",
                              "--out=" + str(records_dir),
                              "--stik-baseline=" + str(baseline_stik),
                              "--jet-data=" + str(current_jet)],
                    out / "record-28-baseline-tapes.log", args.capture_timeout, commands)
        capture = json.loads((records_dir / "session-results.json").read_text(encoding="utf-8"))
        aircraft_rows = {row["name"]: row for row in capture.get("aircraft", [])}
        if set(aircraft_rows) != {"stik", "jet"}:
            raise RuntimeError("capture did not return both required aircraft")
        for name, expected_input in [("stik", BASELINE_STIK_SHA256), ("jet", CURRENT_JET_SHA256)]:
            row = aircraft_rows[name]
            if row.get("input_identity", {}).get("sha256") != expected_input:
                raise RuntimeError(f"capture input identity does not match selected {name} JSON")
            if len(row.get("flights", [])) != 14:
                raise RuntimeError(f"capture did not return 14 cases for {name}")
            for case in row["flights"]:
                tape = Path(case["recording"]).resolve()
                if not case.get("completed") or case.get("final_tick") != 1440 or not tape.is_file() or tape.stat().st_size == 0:
                    raise RuntimeError(f"incomplete capture {case.get('name')}")
                case["recording"] = str(tape)
                case["recording_sha256"] = sha256(tape)
                case["recording_bytes"] = tape.stat().st_size
                flights.append({"aircraft": name, **case})
        if len(flights) != 28:
            raise RuntimeError(f"expected 28 completed tapes, found {len(flights)}")
        solver_sha = capture.get("solver_sha256", "") or None
        if not solver_sha:
            raise RuntimeError("capture omitted its source solver identity")

        for case in flights:
            name = case["aircraft"]
            case_name = case["name"]
            tape = Path(case["recording"])
            case_dir = out / "runs" / case_name
            exact_dir, candidate_dir = case_dir / "exact", case_dir / "data-candidate"
            exact_dir.mkdir(parents=True, exist_ok=False)
            candidate_dir.mkdir(parents=True, exist_ok=False)
            exact_report = exact_dir / "replay.json"
            exact_csv = exact_dir / "flight.csv"
            candidate_report = candidate_dir / "replay.json"
            candidate_csv = candidate_dir / "flight.csv"
            base = prefix + ["--script", "res://tools/flight_log_cli.gd", "--"]
            try:
                run_process(case_name + "-exact",
                            base + ["--log=" + str(tape), "--csv=" + str(exact_csv),
                                    "--report=" + str(exact_report), "--replay"],
                            exact_dir / "command.log", args.process_timeout, commands)
                exact = check_replay(exact_report, "exact", solver_sha)
                # Requiring both identities to match catches an internally self-consistent but
                # wrongly captured replay report if it came from an unexpected source snapshot.
                if exact.get("current_solver_sha256") != solver_sha:
                    raise RuntimeError(f"unexpected solver identity for {case_name}")
            except (RuntimeError, OSError, ValueError, KeyError) as exc:
                failures.append({"case": case_name, "stage": "exact-replay", "error": str(exc)})
                continue

            candidate_model = current_stik if name == "stik" else current_jet
            try:
                run_process(case_name + "-data-candidate",
                            base + ["--log=" + str(tape), "--csv=" + str(candidate_csv),
                                    "--report=" + str(candidate_report), "--replay",
                                    "--candidate=" + str(candidate_model)],
                            candidate_dir / "command.log", args.process_timeout, commands)
                candidate = check_replay(candidate_report, "candidate", exact["baseline_solver_sha256"])
                if candidate.get("candidate_identity", {}).get("sha256") != sha256(candidate_model):
                    raise RuntimeError(f"candidate identity mismatch for {case_name}")
                if candidate.get("baseline_solver_sha256") != exact.get("baseline_solver_sha256"):
                    raise RuntimeError(f"exact/candidate source identity differs for {case_name}")
            except (RuntimeError, OSError, ValueError, KeyError) as exc:
                failures.append({"case": case_name, "stage": "candidate-replay", "error": str(exc)})
                continue

            comparison_path = case_dir / "comparison.json"
            try:
                run_process(case_name + "-compare",
                            [sys.executable, str(COMPARER), "compare", str(exact_csv), str(candidate_csv),
                             "--out", str(comparison_path)],
                            case_dir / "compare-command.log", 30, commands)
                comparison = json.loads(comparison_path.read_text(encoding="utf-8"))
                if comparison.get("status") != "ok" or comparison.get("rows") != 1441:
                    raise RuntimeError(f"unaligned comparison for {case_name}")
                if name == "jet":
                    stats = comparison.get("differences", {})
                    max_differences = [stats.get(group, {}).get("max_abs", 0.0)
                                       for group in ["position_m", "velocity_mps", "angular_rate_radps",
                                                     "quaternion_angle_rad"]]
                    if any(float(value) != 0.0 for value in max_differences):
                        raise RuntimeError(f"unchanged Jet negative control diverged for {case_name}")
                case["comparison"] = str(comparison_path)
                case["comparison_max_abs"] = {
                    key: value.get("max_abs", 0.0)
                    for key, value in comparison.get("differences", {}).items()
                }
            except (RuntimeError, OSError, ValueError, KeyError) as exc:
                failures.append({"case": case_name, "stage": "csv-compare", "error": str(exc)})

    except (RuntimeError, OSError, ValueError, KeyError) as exc:
        failures.append({"stage": "capture-or-manifest", "error": str(exc)})

    source_after = identity(app)
    project_after = sha256(project_file)
    watched_after = external_hashes(watched_paths)
    source_drift = sorted(path for path in source_before.keys() | source_after.keys()
                          if source_before.get(path) != source_after.get(path))
    external_drift = sorted(name for name in watched_before.keys()
                            if watched_before[name] != watched_after.get(name))
    report = {
        "ok": not failures and not source_drift and not external_drift
              and project_before == project_after and len(flights) == 28,
        "purpose": "Complete same-tape exact replay and data-candidate comparison across neutral and signed roll/pitch/yaw pulses for normal/full rate settings. Software sensitivity evidence only; not physical validation.",
        "case_count": len(flights), "cases": flights, "failures": failures,
        "source_drift": source_drift, "source_before": source_before, "source_after": source_after,
        "project_sha256_before": project_before, "project_sha256_after": project_after,
        "external_hashes_before": watched_before, "external_hashes_after": watched_after,
        "external_drift": external_drift, "commands": commands,
        "runner_sha256": sha256(Path(__file__).resolve()), "probe_sha256": sha256(PROBE),
        "godot_sha256": sha256(godot), "stik_baseline_sha256": sha256(baseline_stik),
        "stik_candidate_sha256": sha256(current_stik), "jet_data_sha256": sha256(current_jet),
        "bounded_process_timeouts_s": {"capture": args.capture_timeout, "replay": args.process_timeout,
                                        "csv_compare": 30},
    }
    (out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"event": "complete", "ok": report["ok"], "case_count": len(flights),
                      "failures": len(failures), "source_drift": source_drift,
                      "external_drift": external_drift}), flush=True)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
