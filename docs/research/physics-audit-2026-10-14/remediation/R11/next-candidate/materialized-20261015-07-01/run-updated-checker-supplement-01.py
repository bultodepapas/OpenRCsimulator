#!/usr/bin/env python3
"""Run frozen acceptance suites with only the approved checker path substituted."""
from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path("/home/bulto/openrc-r11-b09-r05b-20261015-07")
APP = ROOT / "app"
TESTS = APP / "tests"
GODOT = ROOT / ".tools/Godot_v4.7.2-stable_linux.x86_64"
LIVE_APP = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator/app")
LIVE_CHECKER = LIVE_APP / "tests/check_trimmed_flight.py"
LIVE_TRACE_TEST = LIVE_APP / "tests/test_trace_acceptance.py"
EVIDENCE = Path(
    "/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/"
    "remediation/R11/next-candidate/materialized-20261015-07-01/updated-checker-supplement-01"
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {name} from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def run_suite(name: str, suite: unittest.TestSuite, module: object, *, app_override: Path | None = None) -> dict:
    output = io.StringIO()
    result = unittest.TextTestRunner(stream=output, verbosity=2).run(suite)
    log = output.getvalue()
    (EVIDENCE / f"{name}.log").write_text(log, encoding="utf-8")
    row = {
        "name": name,
        "tests_run": result.testsRun,
        "failures": len(result.failures),
        "errors": len(result.errors),
        "skipped": len(result.skipped),
        "was_successful": result.wasSuccessful(),
        "app_override": str(app_override or APP),
        "checker_override": str(LIVE_CHECKER),
        "log": str(EVIDENCE / f"{name}.log"),
    }
    if hasattr(module, "APP"):
        row["module_app"] = str(module.APP)
    return row


if EVIDENCE.exists():
    raise SystemExit(f"refusing to overwrite {EVIDENCE}")
EVIDENCE.mkdir(parents=True)
sys.path.insert(0, str(TESTS))
os.environ["OPENRC_TEST_GODOT"] = str(GODOT)

checker = load_module(LIVE_CHECKER, "check_trimmed_flight")
trace_module = load_module(TESTS / "test_trace_acceptance.py", "frozen_test_trace_acceptance")
trace_module.CHECKER = LIVE_CHECKER
trace_suite = unittest.defaultTestLoader.loadTestsFromTestCase(trace_module.TraceAcceptance)
print("START frozen_trace_acceptance_updated_checker", flush=True)
trace_row = run_suite("frozen-trace-acceptance-updated-checker", trace_suite, trace_module)
print(f"END frozen_trace_acceptance_updated_checker {trace_row['was_successful']} {trace_row['tests_run']} tests", flush=True)

shaft_module = load_module(TESTS / "test_shaft_cli.py", "frozen_test_shaft_cli")
shaft_module.CHECKER = checker.check
selected = unittest.TestSuite([
    shaft_module.ShaftCLI("test_explicit_split_preserves_default_rows"),
    shaft_module.ShaftCLI("test_reference_trim_and_model_identity"),
])
print("START frozen_selected_shaft_updated_checker", flush=True)
shaft_row = run_suite("frozen-shaft-two-tests-updated-checker", selected, shaft_module)
print(f"END frozen_selected_shaft_updated_checker {shaft_row['was_successful']} {shaft_row['tests_run']} tests", flush=True)

# Load the live test implementation but direct all app/Godot work at the immutable frozen app.
live_trace_module = load_module(LIVE_TRACE_TEST, "live_test_trace_acceptance")
live_trace_module.APP = APP
live_trace_module.CHECKER = LIVE_CHECKER
one_test = unittest.TestSuite([
    live_trace_module.TraceAcceptance("test_continuous_turbine_metadata_rejects_mixed_sampling")
])
print("START live_continuous_metadata_frozen_app", flush=True)
live_row = run_suite(
    "live-one-continuous-metadata-test-frozen-app",
    one_test,
    live_trace_module,
    app_override=APP,
)
print(f"END live_continuous_metadata_frozen_app {live_row['was_successful']} {live_row['tests_run']} tests", flush=True)

report = {
    "format": "R11 updated-checker supplemental v1",
    "candidate_root": str(ROOT),
    "candidate_head": subprocess.run(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"],
        check=True, capture_output=True, text=True,
    ).stdout.strip(),
    "godot_sha256": digest(GODOT),
    "candidate_test_sh_sha256": digest(APP / "test.sh"),
    "frozen_checker_sha256": digest(TESTS / "check_trimmed_flight.py"),
    "live_checker_sha256": digest(LIVE_CHECKER),
    "frozen_trace_acceptance_sha256": digest(TESTS / "test_trace_acceptance.py"),
    "live_trace_acceptance_sha256": digest(LIVE_TRACE_TEST),
    "suites": [trace_row, shaft_row, live_row],
    "overall_pass": all(row["was_successful"] for row in (trace_row, shaft_row, live_row)),
}
(EVIDENCE / "results.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2), flush=True)
if not report["overall_pass"]:
    sys.exit(1)
