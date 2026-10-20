"""Validate one intentionally failing CLI run without counting it as a passing check."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "godot"))
from run_checked import inspect_log


def assert_expected_diagnostic(error_count: int, error_messages: list[str], expected_prefix: str) -> None:
    if error_count != 1:
        raise ValueError(f"expected exactly one engine error, found {error_count}")
    if len(error_messages) != 1 or not error_messages[0].startswith(expected_prefix):
        raise ValueError(f"the sole engine error did not start with {expected_prefix!r}: {error_messages!r}")


def validate_run(run: Path, collection: Path, expected_exit: int, expected_prefix: str) -> None:
    if type(expected_exit) is not int or not 1 <= expected_exit <= 123:
        raise ValueError("expected process exit must be between 1 and 123")
    if not expected_prefix or "\n" in expected_prefix or "\r" in expected_prefix:
        raise ValueError("expected diagnostic prefix must be a nonempty single line")
    collection = collection.resolve()
    if run.is_symlink():
        raise ValueError("checked-run directory is linked")
    run = run.resolve()
    report_path, log_path = run / "report.json", run / "engine.log"
    if (run.is_symlink() or report_path.is_symlink() or log_path.is_symlink()
            or run.parent != collection or not report_path.is_file() or not log_path.is_file()):
        raise ValueError("checked-run evidence is missing, linked or outside its case collection")
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if not isinstance(report, dict) or report.get("format") != "openrc-godot-check v1":
        raise ValueError("unsupported checked-run report")
    if (report.get("reason") != "process_exit" or report.get("complete") is not True
            or report.get("ok") is not False or type(report.get("process_exit")) is not int
            or report.get("process_exit") != expected_exit or type(report.get("exit_code")) is not int
            or report.get("exit_code") != expected_exit):
        raise ValueError("checked-run verdict or exact process exit does not match the expected failure")
    if report.get("required_text") != [expected_prefix]:
        raise ValueError("checked-run report does not require the expected diagnostic")
    if (Path(str(report.get("log", ""))).name != "engine.log"
            or Path(str(report.get("report", ""))).name != "report.json"):
        raise ValueError("checked-run report paths do not name the standard evidence files")
    raw_log = log_path.read_bytes()
    if (type(report.get("log_bytes")) is not int or report["log_bytes"] != len(raw_log)
            or report.get("log_sha256") != hashlib.sha256(raw_log).hexdigest()):
        raise ValueError("checked-run report and raw log identity disagree")
    scanned = inspect_log(log_path, [expected_prefix], max_chars=len(raw_log))
    if (report.get("counts") != scanned["counts"]
            or report.get("missing_required_text") != scanned["missing_required_text"]
            or report.get("diagnostics") != scanned["diagnostics"]):
        raise ValueError("checked-run diagnostics disagree with the retained raw log")
    errors = [item["message"] for item in scanned["diagnostics"] if item["severity"] == "error"]
    assert_expected_diagnostic(scanned["counts"]["error"], errors, expected_prefix)
    if scanned["missing_required_text"]:
        raise ValueError(f"expected diagnostic was absent from the raw log: {scanned['missing_required_text']}")


class ExpectedFailureContractTests(unittest.TestCase):
    def test_one_matching_engine_error_is_accepted(self):
        assert_expected_diagnostic(1, ["invalid option: --t must be finite"], "invalid option:")

    def test_additional_unexpected_engine_error_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "exactly one engine error"):
            assert_expected_diagnostic(2, ["invalid option", "unexpected runtime error"], "invalid option")

    def test_unexpected_diagnostic_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "sole engine error"):
            assert_expected_diagnostic(1, ["unexpected runtime error"], "invalid option")


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(ExpectedFailureContractTests)
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    if len(sys.argv) != 5:
        print(f"usage: {Path(sys.argv[0]).name} RUN_DIRECTORY COLLECTION EXPECTED_EXIT EXPECTED_ERROR_PREFIX", file=sys.stderr)
        return 2
    try:
        validate_run(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), sys.argv[4])
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(f"Expected CLI failure rejected: {error}", file=sys.stderr)
        return 1
    print(f"validated expected CLI failure (exit {sys.argv[3]}): {sys.argv[4]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
