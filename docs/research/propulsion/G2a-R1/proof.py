#!/usr/bin/env python3
"""Run one external Godot parity probe against a frozen app and the working app."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any


PROOF_FORMAT = "openrc-stage-parity-proof v1"
PROBE_FORMAT = "openrc-stage-parity-probe v1"
EXPECTED_TICKS = [0, 1, 120, 240, 480]
EXPECTED_CASE_IDS = {
    "split-jensen-das-ugly-stik-60",
    "split-gp-extra-300s-60",
    "split-p51d-mustang-120",
    "split-sebart-avanti-s-a200-p100rx",
    "p51-coupled-calm",
    "p51-coupled-gust",
    "p51-coupled-ou-atmosphere",
    "p51-coupled-transported-wash",
}
PROBE = Path(__file__).with_name("parity.gd").resolve()


def app_directory(value: str, label: str) -> tuple[Path, Path]:
    path = Path(value).expanduser().resolve()
    if path.name == "app" and (path / "project.godot").is_file():
        app = path
    elif (path / "app" / "project.godot").is_file():
        app = path / "app"
    else:
        raise ValueError(f"{label} must be a repository root or its app/ directory: {path}")
    return app.parent, app


def godot_command(value: str) -> str:
    expanded = str(Path(value).expanduser())
    if os.sep in expanded:
        path = Path(expanded).resolve()
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ValueError(f"Godot executable is missing or not executable: {path}")
        return str(path)
    found = shutil.which(value)
    if found is None:
        raise ValueError(f"Godot executable was not found on PATH: {value}")
    return found


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_probe(label: str, repo_root: Path, app_dir: Path, godot: str, out_dir: Path) -> dict[str, Any]:
    report_path = out_dir / f"{label}.json"
    log_path = out_dir / f"{label}.log"
    report_path.unlink(missing_ok=True)
    command = [
        godot,
        "--headless",
        "--path",
        str(app_dir),
        "--script",
        str(PROBE),
        "--",
        f"--out={report_path}",
    ]
    try:
        process = subprocess.run(
            command,
            cwd=repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
            check=False,
        )
        log_text = process.stdout
        return_code = process.returncode
        timed_out = False
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        log_text = str(partial) + "\nprobe timed out after 600 seconds\n"
        return_code = 124
        timed_out = True
    log_path.write_text(log_text, encoding="utf-8")

    result: dict[str, Any] = {
        "label": label,
        "repo_root": str(repo_root),
        "app_dir": str(app_dir),
        "command": command,
        "exit_code": return_code,
        "timed_out": timed_out,
        "report_path": str(report_path),
        "log_path": str(log_path),
        "report": None,
        "error": None,
    }
    if return_code != 0:
        result["error"] = f"Godot exited with status {return_code}; see {log_path}"
        return result
    if not report_path.is_file():
        result["error"] = f"Godot exited successfully without writing {report_path}"
        return result
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        result["error"] = f"cannot read probe report {report_path}: {error}"
        return result
    validation_error = validate_probe(report)
    if validation_error:
        result["error"] = validation_error
        return result
    result["report"] = report
    return result


def validate_probe(report: Any) -> str | None:
    if not isinstance(report, dict) or report.get("format") != PROBE_FORMAT:
        return f"probe report format must be {PROBE_FORMAT!r}"
    if not isinstance(report.get("engine"), str) or not report["engine"]:
        return "probe report has no Godot engine version"
    if report.get("tick_hz") != 240 or report.get("ticks") != 480:
        return "probe report has unexpected tick rate or duration"
    if report.get("checkpoint_ticks") != EXPECTED_TICKS:
        return f"probe checkpoint ticks must be {EXPECTED_TICKS}"
    cases = report.get("cases")
    if not isinstance(cases, list) or len(cases) != 8:
        return "probe report must contain exactly eight cases"
    seen: set[str] = set()
    for case in cases:
        if not isinstance(case, dict) or not isinstance(case.get("id"), str):
            return "probe case is missing its id"
        if case["id"] in seen:
            return f"duplicate probe case id: {case['id']}"
        seen.add(case["id"])
        if case.get("rows") != 481:
            return f"{case['id']}: expected 481 trajectory rows"
        trajectory = case.get("trajectory_sha256")
        if not is_sha256(trajectory):
            return f"{case['id']}: invalid trajectory SHA-256"
        hashes = case.get("checkpoint_sha256")
        if not isinstance(hashes, list) or len(hashes) != len(EXPECTED_TICKS):
            return f"{case['id']}: expected five checkpoint hashes"
        ticks: list[int] = []
        for item in hashes:
            if not isinstance(item, dict) or not isinstance(item.get("tick"), int):
                return f"{case['id']}: malformed checkpoint hash entry"
            ticks.append(item["tick"])
            if not is_sha256(item.get("sha256")):
                return f"{case['id']} tick {item['tick']}: invalid checkpoint SHA-256"
        if ticks != EXPECTED_TICKS:
            return f"{case['id']}: checkpoint ticks are {ticks}, expected {EXPECTED_TICKS}"
    if seen != EXPECTED_CASE_IDS:
        return f"probe case ids differ from the registered G2a-R1 set: {sorted(seen)}"
    return None


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(char in "0123456789abcdef" for char in value)


def compare_reports(baseline: dict[str, Any], current: dict[str, Any], probe_hash: str) -> dict[str, Any]:
    mismatches: list[str] = []
    left = baseline["report"]
    right = current["report"]
    if left["engine"] != right["engine"]:
        mismatches.append(f"Godot engine differs: baseline={left['engine']!r}, current={right['engine']!r}")

    baseline_cases = {case["id"]: case for case in left["cases"]}
    current_cases = {case["id"]: case for case in right["cases"]}
    if baseline_cases.keys() != current_cases.keys():
        mismatches.append("case id sets differ")
    case_results: list[dict[str, Any]] = []
    for case_id in sorted(baseline_cases.keys() & current_cases.keys()):
        base_case = baseline_cases[case_id]
        current_case = current_cases[case_id]
        descriptors_match = all(
            base_case.get(key) == current_case.get(key)
            for key in ("aircraft_id", "shaft_integrator", "fixture", "rows")
        )
        if not descriptors_match:
            mismatches.append(f"{case_id}: case descriptors differ")
        base_checkpoints = {item["tick"]: item["sha256"] for item in base_case["checkpoint_sha256"]}
        current_checkpoints = {item["tick"]: item["sha256"] for item in current_case["checkpoint_sha256"]}
        checkpoint_matches = base_checkpoints == current_checkpoints
        trajectory_matches = base_case["trajectory_sha256"] == current_case["trajectory_sha256"]
        if not checkpoint_matches:
            for tick in EXPECTED_TICKS:
                if base_checkpoints.get(tick) != current_checkpoints.get(tick):
                    mismatches.append(f"{case_id}: checkpoint hash differs at tick {tick}")
        if not trajectory_matches:
            mismatches.append(f"{case_id}: 481-row trajectory hash differs")
        case_results.append(
            {
                "id": case_id,
                "checkpoint_match": checkpoint_matches,
                "trajectory_match": trajectory_matches,
                "baseline_checkpoint_sha256": base_checkpoints,
                "current_checkpoint_sha256": current_checkpoints,
                "baseline_trajectory_sha256": base_case["trajectory_sha256"],
                "current_trajectory_sha256": current_case["trajectory_sha256"],
            }
        )

    return {
        "format": PROOF_FORMAT,
        "result": "PASS" if not mismatches else "FAIL",
        "probe_sha256": probe_hash,
        "engine": left["engine"] if left["engine"] == right["engine"] else None,
        "tick_hz": 240,
        "ticks": 480,
        "checkpoint_ticks": EXPECTED_TICKS,
        "case_count": len(case_results),
        "cases": case_results,
        "mismatches": mismatches,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="exact Godot executable used for both runs")
    parser.add_argument("--baseline", required=True, help="frozen repository root or app/ directory")
    parser.add_argument("--current", required=True, help="working repository root or app/ directory")
    parser.add_argument("--out-dir", required=True, type=Path, help="directory for reports, logs, and proof.json")
    args = parser.parse_args()

    try:
        baseline_root, baseline_app = app_directory(args.baseline, "baseline")
        current_root, current_app = app_directory(args.current, "current")
        godot = godot_command(args.godot)
    except ValueError as error:
        parser.error(str(error))
    if not PROBE.is_file():
        parser.error(f"parity probe is missing: {PROBE}")
    if baseline_app == current_app:
        parser.error("baseline and current must name different app directories")
    args.out_dir = args.out_dir.expanduser().resolve()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Running baseline parity probe: {baseline_app}", flush=True)
    baseline = run_probe("baseline", baseline_root, baseline_app, godot, args.out_dir)
    print(f"Running current parity probe: {current_app}", flush=True)
    current = run_probe("current", current_root, current_app, godot, args.out_dir)

    failures = [run["error"] for run in (baseline, current) if run["error"]]
    proof: dict[str, Any]
    if failures:
        proof = {
            "format": PROOF_FORMAT,
            "result": "FAIL",
            "probe_sha256": hashlib.sha256(PROBE.read_bytes()).hexdigest(),
            "runs": {
                "baseline": {key: value for key, value in baseline.items() if key != "report"},
                "current": {key: value for key, value in current.items() if key != "report"},
            },
            "mismatches": failures,
        }
    else:
        proof = compare_reports(
            baseline,
            current,
            hashlib.sha256(PROBE.read_bytes()).hexdigest(),
        )
        proof["baseline"] = str(baseline_app)
        proof["current"] = str(current_app)
        proof["godot"] = godot
    write_json(args.out_dir / "proof.json", proof)

    if proof["result"] != "PASS":
        print(f"G2a-R1 parity failed; inspect {args.out_dir / 'proof.json'}", file=sys.stderr)
        for mismatch in proof.get("mismatches", []):
            print(f"- {mismatch}", file=sys.stderr)
        return 1
    print(f"G2a-R1 exact parity passed for {proof['case_count']} cases.")
    print(f"Proof: {args.out_dir / 'proof.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
