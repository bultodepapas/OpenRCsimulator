"""Exercise native-check orchestration with a disposable fake Godot process."""
from __future__ import annotations

import hashlib
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

import check_rcv_native


@unittest.skipIf(os.name == "nt", "executable fixture uses a POSIX shebang")
class NativeChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-rcv-native-check-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "app").mkdir()
        lock = self.root / "research/rc-monster-truck/native/toolchain-lock.json"
        lock.parent.mkdir(parents=True)
        lock.write_text(json.dumps({"godot": {"version": "4.8.beta2.official.fixture"}}))
        self.engine = self.root / "fake-godot"
        self.engine.write_text(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            "mode = os.environ.get('RCV_FIXTURE_MODE', '')\n"
            "if '--version' in sys.argv:\n"
            "    print('wrong.version' if mode == 'wrong_version' else '4.8.beta2.official.fixture')\n"
            "elif '--import' in sys.argv:\n"
            "    print('SCRIPT ERROR: import failed' if mode == 'bad_import' else 'import complete')\n"
            "elif 'res://tests/test_rcv_session.gd' in sys.argv:\n"
            "    print('SKIP native Session backend-switch guard' if mode == 'skip_session' else 'RCV_NATIVE_SESSION_GUARDS verdict=pass')\n"
            "    if mode == 'session_error': print('SCRIPT ERROR: failed assertion')\n"
            "elif 'res://tests/test_rcv_vehicle_dynamics.gd' in sys.argv:\n"
            "    print('SKIP native/reference trajectory comparison' if mode == 'skip_trajectory' else 'RCV_NATIVE_TRAJECTORY verdict=pass')\n"
            "    if mode == 'trajectory_exit': sys.exit(3)\n"
            "    if mode == 'mutate_editor':\n"
            "        with open(__file__, 'a', encoding='utf-8') as file: file.write('# changed during run\\n')\n"
            "else:\n"
            "    sys.exit(2)\n",
            encoding="utf-8",
        )
        self.engine.chmod(0o755)
        digest = hashlib.sha512(self.engine.read_bytes()).hexdigest()
        (self.root / "app/get-godot.sh").write_text(
            "VERSION=4.8-beta2\nENGINE_VERSION=4.8.beta2.official.fixture\n"
            f"    BINARY_SHA512=({digest})\n"
            f"    BINARY_SHA512=({digest} {digest})\n",
            encoding="utf-8",
        )
        self.out = self.root / "checks"

    def run_case(self, mode: str = "") -> bool:
        with mock.patch.dict(os.environ, {"RCV_FIXTURE_MODE": mode}), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return check_rcv_native.run(self.root, self.engine, self.out, host="linux")

    def reports(self) -> dict:
        result = {}
        for path in self.out.glob("*/report.json"):
            report = json.loads(path.read_text(encoding="utf-8"))
            result[report["label"]] = report
        return result

    def test_success_requires_both_markers_and_retains_each_report(self):
        self.assertTrue(self.run_case())
        reports = self.reports()
        self.assertEqual(set(reports), {"rcv-editor-version", "rcv-native-import", "rcv-native-session", "rcv-native-trajectory"})
        self.assertTrue(all(report["ok"] and Path(report["log"]).is_file() for report in reports.values()))
        self.assertEqual(reports["rcv-native-session"]["required_text"], ["RCV_NATIVE_SESSION_GUARDS verdict=pass"])
        self.assertEqual(reports["rcv-native-trajectory"]["required_text"], ["RCV_NATIVE_TRAJECTORY verdict=pass"])

    def test_either_native_skip_fails_despite_zero_exit(self):
        for mode, label in (("skip_session", "rcv-native-session"), ("skip_trajectory", "rcv-native-trajectory")):
            with self.subTest(mode=mode):
                self.out = self.root / mode
                self.assertFalse(self.run_case(mode))
                report = self.reports()[label]
                self.assertEqual(report["reason"], "missing_required_text")
                self.assertEqual(report["process_exit"], 0)

    def test_diagnostic_and_nonzero_exit_fail_even_with_marker(self):
        for mode, label, reason in (("session_error", "rcv-native-session", "engine_error"),
                                    ("trajectory_exit", "rcv-native-trajectory", "process_exit")):
            with self.subTest(mode=mode):
                self.out = self.root / mode
                self.assertFalse(self.run_case(mode))
                self.assertEqual(self.reports()[label]["reason"], reason)

    def test_import_diagnostic_stops_test_launches(self):
        self.assertFalse(self.run_case("bad_import"))
        reports = self.reports()
        self.assertEqual(set(reports), {"rcv-editor-version", "rcv-native-import"})
        self.assertEqual(reports["rcv-native-import"]["reason"], "engine_error")

    def test_wrong_version_and_changed_editor_are_rejected(self):
        self.assertFalse(self.run_case("wrong_version"))
        self.assertEqual(self.reports()["rcv-editor-version"]["reason"], "missing_required_text")
        self.out = self.root / "changed-editor"
        self.engine.write_text(self.engine.read_text() + "# changed\n")
        self.assertFalse(self.run_case())
        self.assertIn("differs from the pinned editor", (self.out / "failure.txt").read_text())
        self.assertEqual(self.reports(), {})

    def test_editor_change_during_checks_fails_after_both_cases(self):
        self.assertFalse(self.run_case("mutate_editor"))
        self.assertTrue(self.reports()["rcv-native-session"]["ok"])
        self.assertTrue(self.reports()["rcv-native-trajectory"]["ok"])
        self.assertIn("differs from the pinned editor", (self.out / "failure.txt").read_text())

    def test_existing_evidence_directory_is_not_reused(self):
        self.out.mkdir()
        retained = self.out / "retained.txt"
        retained.write_text("earlier result")
        with self.assertRaises(FileExistsError):
            self.run_case()
        self.assertEqual(retained.read_text(), "earlier result")

    def test_windows_console_and_gui_are_both_checked(self):
        gui = self.root / "Godot_v4.8-beta2_win64.exe"
        gui.write_bytes(self.engine.read_bytes())
        self.assertEqual(check_rcv_native.check_editor(self.root, self.engine, "win32"), "4.8.beta2.official.fixture")
        gui.write_bytes(b"changed GUI binary")
        with self.assertRaisesRegex(ValueError, "differs from the pinned editor"):
            check_rcv_native.check_editor(self.root, self.engine, "win32")


if __name__ == "__main__":
    unittest.main()
