#!/usr/bin/env python3
"""Verify EL2a-P3 motor compact results against the frozen EL2a-P1 motor."""

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
FROZEN_MOTOR = REPO / "research" / "propulsion" / "el2a-p1" / "frozen_electric_motor.gd"
# Pin Git's LF source content; permit checkout CRLF while recording raw evidence hashes.
FROZEN_MOTOR_SHA256 = "9fc0bbdf613d23e5826e2e6aed440d915efb431b2d9bf33ac103e7014cc8782b"
MOTOR_ORACLE = REPO / "research" / "propulsion" / "el2a-p3" / "motor_oracle.gd"
APP_TEST = "res://tests/test_electric_motor_compact.gd"
ORACLE_SCRIPT = "res://../research/propulsion/el2a-p3/motor_oracle.gd"
SUMMARY = {
    "oracle": re.compile(
        r"EL2a-P3 motor oracle: (?P<count>\d+) byte comparisons, "
        r"(?P<failures>\d+) failures, samples=(?P<samples>\d+)"
    ),
    "app": re.compile(r"EL2a-P3 compact motor: (?P<count>\d+) checks, (?P<failures>\d+) failed"),
}
ENGINE_ERROR = re.compile(r"^(?:SCRIPT )?ERROR:|Parse Error|SCRIPT ERROR:", re.MULTILINE)
EXPECTED_ORACLE_COMPARISONS = 20043
EXPECTED_APP_CHECKS = 13
EXPECTED_GODOT_VERSION = "4.7.2.stable.official.ed1daf0bf"


class VerifyError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def verify_frozen_source(data: bytes) -> None:
    if sha256(data.replace(b"\r\n", b"\n")) != FROZEN_MOTOR_SHA256:
        raise VerifyError("frozen EL2a-P1 motor source hash changed; review the baseline explicitly")


def verify_output_location(app: Path, output: Path) -> None:
    if output.resolve().is_relative_to(app.resolve()):
        raise VerifyError("--out must be outside --app; copying an app into itself is invalid")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_ignore(_directory: str, names: list[str]) -> set[str]:
    return {name for name in names if name in {".godot", "captures", ".DS_Store"}}


def run_godot(
    godot: Path, app_copy: Path, script: str, log_path: Path, timeout: int
) -> subprocess.CompletedProcess[str]:
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
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(stdout + stderr + f"\nTIMEOUT after {timeout}s\n", encoding="utf-8")
        raise VerifyError(f"{script} exceeded the {timeout}s timeout") from exc
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(result.stdout + result.stderr, encoding="utf-8")
    return result


def output_of(result: subprocess.CompletedProcess[str]) -> str:
    return result.stdout + result.stderr


def read_summary(kind: str, output: str) -> dict[str, int]:
    match = SUMMARY[kind].search(output)
    if not match:
        raise VerifyError(f"{kind} run did not print its completion/count line")
    return {key: int(value) for key, value in match.groupdict().items()}


def require_clean_output(
    result: subprocess.CompletedProcess[str], kind: str, expected_count: int
) -> dict[str, int]:
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


def require_mutation_rejection(
    result: subprocess.CompletedProcess[str], expected_evidence: str
) -> dict[str, int]:
    output = output_of(result)
    if ENGINE_ERROR.search(output):
        raise VerifyError("motor mutation caused a parse/runtime error instead of an oracle mismatch")
    summary = read_summary("oracle", output)
    if result.returncode == 0 or summary["failures"] <= 0 or expected_evidence not in output:
        raise VerifyError(
            f"motor mutation was not rejected as intended: exit={result.returncode}, "
            f"summary={summary}, evidence={expected_evidence!r}"
        )
    return summary


def replace_once(source: bytes, old: bytes, new: bytes, label: str) -> bytes:
    line_ending = b"\r\n" if b"\r\n" in source else b"\n"
    old = old.replace(b"\n", line_ending)
    new = new.replace(b"\n", line_ending)
    count = source.count(old)
    if count != 1:
        raise VerifyError(f"expected one mutation target for {label}, found {count}")
    return source.replace(old, new, 1)


def run_mutation(
    *,
    name: str,
    target: Path,
    old: bytes,
    new: bytes,
    evidence: str,
    godot: Path,
    app_copy: Path,
    log_path: Path,
    timeout: int,
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
        "oracle": ORACLE_SCRIPT,
        "log": str(log_path),
        "expected_evidence": evidence,
    }
    report["mutations"].append(entry)
    try:
        target.write_bytes(changed)
        result = run_godot(godot, app_copy, ORACLE_SCRIPT, log_path, timeout)
        entry["exit_code"] = result.returncode
        entry["summary"] = require_mutation_rejection(result, evidence)
        entry["rejected_as_expected"] = True
    finally:
        target.write_bytes(original)
        entry["sha256_after_restore"] = sha256(target.read_bytes())
        entry["restored"] = target.read_bytes() == original
    if not entry["restored"]:
        raise VerifyError(f"mutation target was not restored: {target}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="absolute path to Godot console executable")
    parser.add_argument("--app", type=Path, default=DEFAULT_APP, help="candidate Godot app source")
    parser.add_argument("--out", type=Path, required=True, help="fresh or empty output directory")
    parser.add_argument("--timeout-seconds", type=int, default=120, help="per process timeout")
    args = parser.parse_args()

    godot = Path(args.godot).expanduser().resolve()
    app_source = args.app.expanduser().resolve()
    out = args.out.expanduser().resolve()
    verify_output_location(app_source, out)
    if not godot.is_file():
        parser.error(f"Godot executable does not exist: {godot}")
    if not (app_source / "project.godot").is_file():
        parser.error(f"--app is not a Godot project directory: {app_source}")
    required_files = [
        app_source / "physics" / "electric_motor.gd",
        app_source / "physics" / "electric_supply.gd",
        app_source / "tests" / "test_electric_motor_compact.gd",
        FROZEN_MOTOR,
        MOTOR_ORACLE,
        Path(__file__).resolve(),
    ]
    missing_files = [path for path in required_files if not path.is_file()]
    if missing_files:
        parser.error("required verifier source file(s) missing: " + ", ".join(map(str, missing_files)))
    if args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error(f"--out must be a fresh or empty directory: {out}")
    frozen_bytes = FROZEN_MOTOR.read_bytes()
    verify_frozen_source(frozen_bytes)

    try:
        version_result = subprocess.run(
            [str(godot), "--version"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=15,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise VerifyError("Godot --version exceeded the 15s preflight timeout") from exc
    godot_version = version_result.stdout.strip()
    godot_version_log = version_result.stdout + version_result.stderr

    out.mkdir(parents=True, exist_ok=True)
    version_log_path = out / "logs" / "godot_version.log"
    version_log_path.parent.mkdir(parents=True, exist_ok=True)
    version_log_path.write_text(godot_version_log, encoding="utf-8")
    app_copy = out / "workspace" / "app"
    p1_copy = out / "workspace" / "research" / "propulsion" / "el2a-p1"
    p3_copy = out / "workspace" / "research" / "propulsion" / "el2a-p3"
    report = {
        "format": "openrc-el2a-p3-motor-verification v1",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "godot": str(godot),
        "godot_executable_sha256": sha256_file(godot),
        "godot_version": {
            "expected": EXPECTED_GODOT_VERSION,
            "actual": godot_version,
            "exit_code": version_result.returncode,
            "log": str(version_log_path),
        },
        "app_source": str(app_source),
        "workspace_app": str(app_copy),
        "timeout_seconds": args.timeout_seconds,
        "status": "running",
        "source_hashes": {
            "candidate/physics/electric_motor.gd": sha256((app_source / "physics/electric_motor.gd").read_bytes()),
            "candidate/physics/electric_supply.gd": sha256(
                (app_source / "physics" / "electric_supply.gd").read_bytes()
            ),
            "candidate/tests/test_electric_motor_compact.gd": sha256(
                (app_source / "tests" / "test_electric_motor_compact.gd").read_bytes()
            ),
            "frozen/EL2a-P1/electric_motor.gd": sha256(frozen_bytes),
            "motor_oracle.gd": sha256(MOTOR_ORACLE.read_bytes()),
            "verify_motor.py": sha256(Path(__file__).resolve().read_bytes()),
        },
        "positive_runs": {},
        "mutations": [],
        "frozen_motor_lf_sha256": FROZEN_MOTOR_SHA256,
    }

    try:
        if version_result.returncode != 0 or godot_version != EXPECTED_GODOT_VERSION:
            raise VerifyError(
                "Godot --version mismatch: "
                f"exit={version_result.returncode}, actual={godot_version!r}, "
                f"expected={EXPECTED_GODOT_VERSION!r}"
            )
        shutil.copytree(app_source, app_copy, ignore=tree_ignore)
        p1_copy.mkdir(parents=True)
        p3_copy.mkdir(parents=True)
        shutil.copy2(FROZEN_MOTOR, p1_copy / "frozen_electric_motor.gd")
        shutil.copy2(MOTOR_ORACLE, p3_copy / "motor_oracle.gd")
        candidate_motor = app_copy / "physics" / "electric_motor.gd"

        oracle_result = run_godot(
            godot, app_copy, ORACLE_SCRIPT, out / "logs" / "positive_oracle.log", args.timeout_seconds
        )
        oracle_summary = require_clean_output(
            oracle_result, "oracle", EXPECTED_ORACLE_COMPARISONS
        )
        report["positive_runs"]["oracle"] = {
            "script": ORACLE_SCRIPT,
            "exit_code": oracle_result.returncode,
            "summary": oracle_summary,
            "log": str(out / "logs" / "positive_oracle.log"),
        }

        app_result = run_godot(godot, app_copy, APP_TEST, out / "logs" / "positive_app_test.log", args.timeout_seconds)
        app_summary = require_clean_output(app_result, "app", EXPECTED_APP_CHECKS)
        report["positive_runs"]["app_test"] = {
            "script": APP_TEST,
            "exit_code": app_result.returncode,
            "summary": app_summary,
            "expected_count": EXPECTED_APP_CHECKS,
            "log": str(out / "logs" / "positive_app_test.log"),
        }

        run_mutation(
            name="compact torque offset",
            target=candidate_motor,
            old=b"shaft_torque_nm = torque,\n\t\t\tmotor_current_a = current",
            new=b"shaft_torque_nm = torque + 1.0,\n\t\t\tmotor_current_a = current",
            evidence="first mismatch: seed 00000 compact source",
            godot=godot,
            app_copy=app_copy,
            log_path=out / "logs" / "mutation_compact_torque.log",
            timeout=args.timeout_seconds,
            report=report,
        )
        run_mutation(
            name="shared bus-power finite guard removed",
            target=candidate_motor,
            old=b"and is_finite(shaft_power) and is_finite(bus_power) and is_finite(copper_loss)",
            new=b"and is_finite(shaft_power) and is_finite(copper_loss)",
            evidence="first mismatch: overflow bus power overflow full",
            godot=godot,
            app_copy=app_copy,
            log_path=out / "logs" / "mutation_bus_power_guard.log",
            timeout=args.timeout_seconds,
            report=report,
        )

        report["status"] = "passed"
    except Exception as exc:  # Preserve output and a machine-readable report for diagnosis.
        report["status"] = "failed"
        report["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(f"EL2a-P3 motor verification: {report['status']}")
    print(f"report: {out / 'report.json'}")
    if report["status"] != "passed":
        print(report.get("error", "verification failed"), file=sys.stderr)
        return 1
    for name, result in report["positive_runs"].items():
        print(f"{name}: {result['summary']['count']} checks/comparisons, 0 failures")
    print("two motor implementation mutations were rejected and restored")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VerifyError as exc:
        print(f"verify_motor: {exc}", file=sys.stderr)
        raise SystemExit(1)
