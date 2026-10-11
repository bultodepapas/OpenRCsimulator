#!/usr/bin/env python3
"""Run EL2a-P1 oracle positives and real mutation controls in a disposable app copy."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
DEFAULT_APP = REPO / "app"
RESEARCH_FILES = (
    "rotor_oracle.gd",
    "source_oracle.gd",
    "frozen_electric_motor.gd",
    "frozen_electric_supply.gd",
)
BASELINE_HASH_FILES = (
    "physics/rotor_coupling.gd",
    "physics/electric_supply.gd",
    "tests/test_electric_dynamics.gd",
)
SUMMARY = {
    "rotor": re.compile(
        r"EL2a-P1 rotor oracle: (?P<count>\d+) checks, (?P<failures>\d+) failed, "
        r"seed=(?P<seed>\d+), valid_samples=(?P<samples>\d+)"
    ),
    "source": re.compile(
        r"EL2a-P1 electric source oracle: (?P<count>\d+) byte comparisons, "
        r"(?P<failures>\d+) failures"
    ),
    "app": re.compile(r"EL2a-P1 electric dynamics: (?P<count>\d+) checks, (?P<failures>\d+) failed"),
}
EXPECTED_COUNTS = {"rotor": 10020, "source": 40106, "app": 74}
ENGINE_ERROR = re.compile(r"^(?:SCRIPT )?ERROR:|Parse Error|SCRIPT ERROR:", re.MULTILINE)


class VerifyError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tree_ignore(_directory: str, names: list[str]) -> set[str]:
    return {name for name in names if name in {".godot", "captures", ".DS_Store"}}


def write_report(out: Path, report: dict) -> None:
    out.mkdir(parents=True, exist_ok=True)
    (out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def run_godot(godot: Path, app_copy: Path, script: str, log_path: Path, timeout: int) -> subprocess.CompletedProcess[str]:
    command = [str(godot), "--headless", "--path", str(app_copy), "--script", script]
    try:
        result = subprocess.run(
            command,
            cwd=app_copy,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode("utf-8", "replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode("utf-8", "replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        output = stdout + stderr
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(output + f"\nTIMEOUT after {timeout}s\n", encoding="utf-8")
        raise VerifyError(f"{script} exceeded the {timeout}s timeout") from exc
    output = result.stdout + result.stderr
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(output, encoding="utf-8")
    return result


def output_of(result: subprocess.CompletedProcess[str]) -> str:
    return result.stdout + result.stderr


def read_summary(kind: str, output: str) -> dict:
    match = SUMMARY[kind].search(output)
    if not match:
        raise VerifyError(f"{kind} run did not print its completion/count line")
    return {key: int(value) for key, value in match.groupdict().items()}


def require_clean_output(result: subprocess.CompletedProcess[str], kind: str, expected_count: int) -> dict:
    output = output_of(result)
    if ENGINE_ERROR.search(output):
        raise VerifyError(f"{kind} run reported a Godot parse/runtime error")
    summary = read_summary(kind, output)
    if result.returncode != 0 or summary["failures"] != 0 or summary["count"] != expected_count:
        raise VerifyError(
            f"{kind} positive run failed: exit={result.returncode}, summary={summary}, "
            f"expected_count={expected_count}"
        )
    return summary


def require_intended_failure(
    result: subprocess.CompletedProcess[str], kind: str, expected_evidence: str
) -> dict:
    output = output_of(result)
    if ENGINE_ERROR.search(output):
        raise VerifyError(f"mutation for {kind} produced a parse/runtime error instead of an oracle mismatch")
    summary = read_summary(kind, output)
    if result.returncode == 0 or summary["failures"] <= 0 or expected_evidence not in output:
        raise VerifyError(
            f"mutation for {kind} was not rejected as intended: exit={result.returncode}, "
            f"summary={summary}, evidence={expected_evidence!r}"
        )
    return summary


def replace_once(source: bytes, old: bytes, new: bytes, label: str) -> bytes:
    count = source.count(old)
    if count < 1:
        raise VerifyError(f"mutation target not found: {label}")
    return source.replace(old, new, 1)


def run_mutation(
    name: str,
    target: Path,
    old: bytes,
    new: bytes,
    kind: str,
    script: str,
    log_path: Path,
    timeout: int,
    evidence: str,
    report: dict,
) -> None:
    original = target.read_bytes()
    changed = replace_once(original, old, new, name)
    if changed == original:
        raise VerifyError(f"mutation made no change: {name}")
    entry = {
        "name": name,
        "target": str(target),
        "sha256_before": sha256(original),
        "sha256_mutated": sha256(changed),
        "oracle": script,
        "log": str(log_path),
        "expected_evidence": evidence,
    }
    report["mutations"].append(entry)
    try:
        target.write_bytes(changed)
        result = run_godot(Path(report["godot"]), Path(report["workspace_app"]), script, log_path, timeout)
        entry["exit_code"] = result.returncode
        entry["summary"] = require_intended_failure(result, kind, evidence)
        entry["rejected_as_expected"] = True
    finally:
        target.write_bytes(original)
        entry["sha256_after_restore"] = sha256(target.read_bytes())
        entry["restored"] = target.read_bytes() == original
    if not entry["restored"]:
        raise VerifyError(f"mutation target was not restored: {target}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="absolute path to the Godot console executable")
    parser.add_argument("--app", type=Path, default=DEFAULT_APP, help="source app directory (default: repo/app)")
    parser.add_argument("--out", type=Path, required=True, help="new or empty output directory for copy, logs, and report")
    parser.add_argument("--timeout-seconds", type=int, default=120, help="per-process timeout (default: 120)")
    args = parser.parse_args()

    godot = Path(args.godot).expanduser()
    app_source = args.app.expanduser().resolve()
    out = args.out.expanduser().resolve()
    if not godot.is_absolute():
        parser.error("--godot must be an absolute path")
    if not godot.is_file():
        parser.error(f"Godot executable does not exist: {godot}")
    if not (app_source / "project.godot").is_file():
        parser.error(f"--app is not a Godot project directory: {app_source}")
    if args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error(f"--out must be a fresh or empty directory: {out}")
    out.mkdir(parents=True, exist_ok=True)

    workspace = out / "workspace"
    app_copy = workspace / "app"
    research_copy = workspace / "research" / "propulsion" / "el2a-p1"
    report = {
        "format": "openrc-el2a-p1-oracle-verification v1",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "godot": str(godot.resolve()),
        "app_source": str(app_source),
        "workspace_app": str(app_copy),
        "timeout_seconds": args.timeout_seconds,
        "status": "running",
        "excluded_from_app_snapshot": [".godot", "captures", ".DS_Store"],
        "evidence_notes": [
            "A subnormal-capacity overflow fixture was rejected before reaching the SOC-rate guard on this runtime.",
            "The retained guard fixture uses normal finite capacity/current/voltage scales; only the derived SOC rate overflows.",
        ],
        "positive_runs": {},
        "mutations": [],
        "source_hashes": {},
    }
    mutable_paths: dict[Path, bytes] = {}

    try:
        shutil.copytree(app_source, app_copy, ignore=tree_ignore)
        research_copy.mkdir(parents=True)
        for relative in RESEARCH_FILES:
            shutil.copy2(REPO / "research" / "propulsion" / "el2a-p1" / relative, research_copy / relative)
        report["source_hashes"] = {
            f"app/{relative}": sha256((app_source / relative).read_bytes())
            for relative in BASELINE_HASH_FILES
        }
        report["source_hashes"].update(
            {
                f"research/propulsion/el2a-p1/{relative}": sha256(
                    (REPO / "research" / "propulsion" / "el2a-p1" / relative).read_bytes()
                )
                for relative in RESEARCH_FILES
            }
        )
        for relative in BASELINE_HASH_FILES[:2]:
            copied = app_copy / relative
            mutable_paths[copied] = copied.read_bytes()
        report["snapshot_hashes"] = {
            str(path.relative_to(app_copy)): sha256(data) for path, data in mutable_paths.items()
        }

        positive_cases = (
            ("rotor", "res://../research/propulsion/el2a-p1/rotor_oracle.gd"),
            ("source", "res://../research/propulsion/el2a-p1/source_oracle.gd"),
            ("app", "res://tests/test_electric_dynamics.gd"),
        )
        for kind, script in positive_cases:
            log = out / "logs" / f"positive_{kind}.log"
            result = run_godot(godot.resolve(), app_copy, script, log, args.timeout_seconds)
            summary = require_clean_output(result, kind, EXPECTED_COUNTS[kind])
            report["positive_runs"][kind] = {
                "script": script,
                "exit_code": result.returncode,
                "summary": summary,
                "expected_count": EXPECTED_COUNTS[kind],
                "log": str(log),
            }

        rotor_path = app_copy / "physics" / "rotor_coupling.gd"
        supply_path = app_copy / "physics" / "electric_supply.gd"
        mutable_paths[rotor_path] = rotor_path.read_bytes()
        mutable_paths[supply_path] = supply_path.read_bytes()

        run_mutation(
            "rotor reaction sign inverted",
            rotor_path,
            b"var reaction_scale: float = -rotor_inertia * acceleration",
            b"var reaction_scale: float = rotor_inertia * acceleration",
            "rotor",
            "res://../research/propulsion/el2a-p1/rotor_oracle.gd",
            out / "logs" / "mutation_rotor_sign.log",
            args.timeout_seconds,
            "first failure: seeded valid sample 0",
            report,
        )
        run_mutation(
            "compact pack current sign inverted",
            supply_path,
            b'"pack_current_a": pack_current_a',
            b'"pack_current_a": -pack_current_a',
            "source",
            "res://../research/propulsion/el2a-p1/source_oracle.gd",
            out / "logs" / "mutation_pack_current.log",
            args.timeout_seconds,
            "first mismatch: seed 00000 evaluate dynamics result",
            report,
        )
        run_mutation(
            "scalar SOC-rate finite guard removed",
            supply_path,
            b"and is_finite(soc_rate_per_s)",
            b"",
            "source",
            "res://../research/propulsion/el2a-p1/source_oracle.gd",
            out / "logs" / "mutation_soc_rate_guard.log",
            args.timeout_seconds,
            "first mismatch: invalid SOC-rate overflow evaluate public result",
            report,
        )

        report["status"] = "passed"
    except Exception as exc:  # Keep logs and a machine-readable failure report for diagnosis.
        report["status"] = "failed"
        report["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        report["restored_hashes"] = {}
        for path, original in mutable_paths.items():
            if path.exists():
                if path.read_bytes() != original:
                    path.write_bytes(original)
                report["restored_hashes"][str(path.relative_to(app_copy))] = {
                    "sha256": sha256(path.read_bytes()),
                    "matches_snapshot": path.read_bytes() == original,
                }
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        write_report(out, report)

    print(f"EL2a-P1 oracle verification: {report['status']}")
    print(f"report: {out / 'report.json'}")
    if report["status"] != "passed":
        print(report.get("error", "verification failed"), file=sys.stderr)
        return 1
    for kind, result in report["positive_runs"].items():
        print(f"{kind}: {result['summary']['count']} checks/comparisons, 0 failures")
    print("three production mutations were rejected and restored")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VerifyError as exc:
        print(f"verify_oracles: {exc}", file=sys.stderr)
        raise SystemExit(1)
