#!/usr/bin/env python3
"""Read-only implementation probes of flight-card evidence failure paths.

Temporary reports and substituted child responses deliberately model malformed
or interrupted runs. The timeout uses an actual Python subprocess, not Godot.
Production tool files are imported/executed unchanged. No aircraft data is edited.
"""

import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / "research/flight-test"


def load_runner():
    spec = importlib.util.spec_from_file_location("audit_followup_runner", TOOLS / "run.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def wrapper_case(kind):
    runner = load_runner()
    with tempfile.TemporaryDirectory(prefix="audit-evidence-", dir=ROOT / "tmp") as temporary:
        folder = Path(temporary)
        output = folder / "output"
        source = folder / "aircraft.json"
        source.write_text('{"id":"audit-fixture"}\n')
        identity = hashlib.sha256(source.read_bytes()).hexdigest()
        details = {}

        def child(_binary, _arguments, _timeout):
            if kind == "timeout":
                program = (
                    "import sys,time; print('AUDIT_STDOUT_BEFORE_TIMEOUT',flush=True); "
                    "print('ERROR: AUDIT_STDERR_BEFORE_TIMEOUT',file=sys.stderr,flush=True); time.sleep(5)"
                )
                try:
                    return subprocess.run([sys.executable, "-c", program], capture_output=True, text=True, timeout=0.25)
                except subprocess.TimeoutExpired as expired:
                    details.update({"actual_timeout_stdout_type": type(expired.stdout).__name__,
                                    "actual_timeout_stderr_type": type(expired.stderr).__name__,
                                    "exception_stdout": (expired.stdout or b"").decode() if isinstance(expired.stdout, bytes) else expired.stdout,
                                    "exception_stderr": (expired.stderr or b"").decode() if isinstance(expired.stderr, bytes) else expired.stderr})
                    raise
            target = output / "plane"
            target.mkdir(parents=True)
            if kind == "malformed_json":
                (target / "profile.json").write_text('{"results":')
                return subprocess.CompletedProcess([], 2, "AUDIT_CHILD_STARTED\n", "ERROR: injected child failure\n")
            profile = {"aircraft_input_sha256": identity}
            if kind == "complete_control":
                profile.update({"name": "Synthetic evidence fixture", "mass_kg": 1.0,
                                "start_speed_mps": 15.0})
                profile["results"] = {"aero_sweep": {"valid": True}}
            (target / "profile.json").write_text(json.dumps(profile))
            return subprocess.CompletedProcess([], 0, "AUDIT_CHILD_STARTED\n", "")

        argv = ["run.py", "--out", str(output), "--aircraft", "plane", "--only", "aero_sweep"]
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, "argv", argv), \
                mock.patch.object(runner, "find_godot", return_value=sys.executable), \
                mock.patch.object(runner, "data_paths", return_value={"plane": source}), \
                mock.patch.object(runner, "godot", side_effect=child), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                runner.main()
            except SystemExit as error:
                details["exit"] = error.code
            except Exception as error:
                details["exception"] = type(error).__name__
                details["exception_message"] = str(error)
        details.update({"case": kind, "stdout": stdout.getvalue(), "stderr": stderr.getvalue(),
                        "run_manifest_exists": (output / "run.json").is_file(),
                        "run_log_exists": (output / "plane/run.log").is_file(),
                        "summary_exists": (output / "summary.md").is_file()})
        if details["run_log_exists"]:
            details["retained_run_log"] = (output / "plane/run.log").read_text()
        if details["run_manifest_exists"]:
            details["run_aircraft"] = json.loads((output / "run.json").read_text())["aircraft"]["plane"]
            details["run_aircraft"].pop("wall_s", None)
            details["run_aircraft"].pop("data_file", None)
        return details


def profile(results):
    return {"format": "ft-card-v5", "aircraft": "plane", "name": "Synthetic evidence fixture",
            "data_sha256": "a" * 64, "results": results}


def comparison_case(kind):
    with tempfile.TemporaryDirectory(prefix="audit-compare-", dir=ROOT / "tmp") as temporary:
        folder = Path(temporary)
        baseline, candidate = folder / "baseline", folder / "candidate"
        baseline.mkdir()
        candidate.mkdir()
        arguments = []
        if kind == "no_shared_tests":
            a = profile({"aero_sweep": {"valid": True, "metrics": {"one": 1.0}}})
            b = profile({"trim_sweep": {"valid": True, "metrics": {"two": 2.0}}})
            arguments = ["--shared-tests"]
        elif kind == "duplicate_case_hidden_change":
            a = profile({"roll_rate": {"valid": True, "table": [{"case": "start", "rate": 5.0}, {"case": "start", "rate": 10.0}]}})
            b = profile({"roll_rate": {"valid": True, "table": [{"case": "start", "rate": 500.0}, {"case": "start", "rate": 10.0}]}})
        elif kind == "ordinary_change_control":
            a = profile({"roll_rate": {"valid": True, "table": [{"case": "start", "rate": 5.0}]}})
            b = profile({"roll_rate": {"valid": True, "table": [{"case": "start", "rate": 500.0}]}})
        elif kind == "candidate_only_aircraft":
            a = profile({"roll_rate": {"valid": True, "table": [{"case": "start", "rate": 5.0}]}})
            b = a
        else:
            a = b = None
        if a is not None:
            for parent, data in [(baseline, a), (candidate, b)]:
                (parent / "plane").mkdir()
                (parent / "plane/profile.json").write_text(json.dumps(data))
        if kind == "candidate_only_aircraft":
            (candidate / "new-plane").mkdir()
            added = profile({"roll_rate": {"valid": True, "table": [{"case": "start", "rate": 500.0}]}})
            added["aircraft"] = "new-plane"
            added["name"] = "Candidate-only evidence fixture"
            (candidate / "new-plane/profile.json").write_text(json.dumps(added))
        result = subprocess.run([sys.executable, str(TOOLS / "compare.py"), str(baseline), str(candidate), "--fail-on-change", *arguments], capture_output=True, text=True)
        return {"case": kind, "exit": result.returncode,
                "stdout": result.stdout.replace(str(folder), "<temporary_fixture>"), "stderr": result.stderr}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    wrappers = [wrapper_case(kind) for kind in ["complete_control", "timeout", "malformed_json", "missing_results"]]
    comparisons = [comparison_case(kind) for kind in ["empty_directories", "no_shared_tests", "duplicate_case_hidden_change", "candidate_only_aircraft", "ordinary_change_control"]]
    result = {"format": "openrc-audit-tool-evidence-v1", "source_head": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
              "python": sys.version, "tool_sha256": {name: hashlib.sha256((TOOLS / name).read_bytes()).hexdigest() for name in ["run.py", "compare.py"]},
              "scope": "Actual production Python tools with temporary synthetic profiles/child responses; timeout is an actual Python child, not an engine run.",
              "wrapper_cases": wrappers, "comparison_cases": comparisons}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"wrapper_outcomes": [{"case": x["case"], "exit": x.get("exit"), "exception": x.get("exception"), "manifest": x["run_manifest_exists"]} for x in wrappers],
                      "comparison_outcomes": [{"case": x["case"], "exit": x["exit"]} for x in comparisons]}, indent=2))


if __name__ == "__main__":
    main()
