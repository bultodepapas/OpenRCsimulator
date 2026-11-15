"""The card runner must identify loaded bytes, including a file rewritten mid-run."""
import hashlib
import contextlib
import io
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location("flight_card_runner", HERE / "run.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class InputIdentityTests(unittest.TestCase):
    def run_card(self, change_file=False, omit_identity=False, only="aero_sweep", result_names=None):
        with tempfile.TemporaryDirectory(prefix="ft-input-", dir=ROOT / "tmp") as folder:
            directory = Path(folder).resolve()
            self.assertEqual(directory.parent, (ROOT / "tmp").resolve())
            source = directory / "candidate.json"
            source.write_text('{"id":"plane","version":1}', encoding="utf-8")
            loaded_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            output = directory / "out"

            def engine(_binary, _args, _timeout):
                target = output / "plane"
                target.mkdir(parents=True)
                names = ["aero_sweep"] if result_names is None else result_names
                profile = {"results": {name: {"valid": True} for name in names}}
                if not omit_identity:
                    profile["aircraft_input_sha256"] = loaded_hash
                (target / "profile.json").write_text(json.dumps(profile), encoding="utf-8")
                if change_file:
                    source.write_text('{"id":"plane","version":2}', encoding="utf-8")
                return subprocess.CompletedProcess([], 0, "probe completed\n", "")

            summarizer = types.SimpleNamespace(main_with=lambda *_: None)
            args = ["run.py", "--out", str(output), "--aircraft", "plane", "--data", str(source)]
            if only is not None:
                args += ["--only", only]
            with mock.patch.object(sys, "argv", args), \
                    mock.patch.object(RUNNER, "find_godot", return_value="test-engine"), \
                    mock.patch.object(RUNNER, "data_paths", return_value={"plane": source}), \
                    mock.patch.object(RUNNER, "godot", side_effect=engine), \
                    mock.patch.object(RUNNER, "git", return_value="source-snapshot"), \
                    mock.patch.object(RUNNER.subprocess, "run", return_value=types.SimpleNamespace(stdout="test-engine")), \
                    mock.patch.dict(sys.modules, {"summarize": summarizer}), \
                    contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    RUNNER.main()
            report = json.loads((output / "run.json").read_text())["aircraft"]["plane"]
            log = (output / "plane/run.log").read_text()
            return result.exception.code, report, loaded_hash, log

    def test_unchanged_input_is_reported_as_loaded(self):
        code, report, digest, _ = self.run_card()
        self.assertEqual(code, 0)
        self.assertEqual(report["data_sha256"], digest)
        self.assertTrue(report["data_identity_matches"])

    def test_rewrite_during_child_run_cannot_claim_the_new_bytes(self):
        code, report, digest, log = self.run_card(change_file=True)
        self.assertEqual(code, 1)
        self.assertEqual(report["exit"], "data_identity_mismatch")
        self.assertEqual(report["data_sha256"], digest)
        self.assertNotEqual(report["data_file_sha256_after"], digest)
        self.assertIn("loaded input identity", log)

    def test_missing_loaded_identity_is_not_credited(self):
        code, report, _, _ = self.run_card(omit_identity=True)
        self.assertEqual(code, 1)
        self.assertFalse(report["data_identity_matches"])

    def test_duplicate_ids_are_refused_before_launch(self):
        with mock.patch.object(sys, "argv", ["run.py", "--out", "unused", "--aircraft", "plane,plane"]), \
                mock.patch.object(RUNNER, "godot") as engine, \
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result:
            RUNNER.main()
        self.assertEqual(result.exception.code, 2)
        engine.assert_not_called()

    def test_invalid_test_selections_are_refused_before_engine_or_output(self):
        for selection in ["not_a_test", "aero_sweep,not_a_test", "", "aero_sweep,", "aero_sweep,aero_sweep"]:
            with self.subTest(selection=selection), \
                    tempfile.TemporaryDirectory(prefix="ft-selection-", dir=ROOT / "tmp") as folder:
                output = Path(folder) / "new-output"
                args = ["run.py", "--out", str(output), "--aircraft", "plane", "--only", selection]
                with mock.patch.object(sys, "argv", args), \
                        mock.patch.object(RUNNER, "find_godot", return_value="test-engine") as finder, \
                        mock.patch.object(RUNNER, "godot") as engine, \
                        contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result:
                    RUNNER.main()
                self.assertEqual(result.exception.code, 2)
                finder.assert_not_called()
                engine.assert_not_called()
                self.assertFalse(output.exists())

    def test_empty_aircraft_selection_is_refused_before_launch(self):
        for selection in ["", ",", "plane,", "all,plane"]:
            with self.subTest(selection=selection), \
                    mock.patch.object(sys, "argv", ["run.py", "--out", "unused", "--aircraft", selection]), \
                    mock.patch.object(RUNNER, "find_godot", return_value="test-engine") as finder, \
                    mock.patch.object(RUNNER, "godot") as engine, \
                    contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result:
                RUNNER.main()
            self.assertEqual(result.exception.code, 2)
            finder.assert_not_called()
            engine.assert_not_called()

    def test_empty_result_set_is_not_a_completed_card(self):
        code, report, _, log = self.run_card(result_names=[])
        self.assertEqual(code, 1)
        self.assertEqual(report["exit"], "test_roster_mismatch")
        self.assertEqual(report["missing_tests"], ["aero_sweep"])
        self.assertIn("requested test roster", log)

    def test_partial_result_set_cannot_hide_an_omitted_requested_test(self):
        code, report, _, _ = self.run_card(only="aero_sweep,trim_sweep")
        self.assertEqual(code, 1)
        self.assertEqual(report["missing_tests"], ["trim_sweep"])
        self.assertFalse(report["test_roster_matches"])

    def test_unrequested_result_is_not_credited(self):
        code, report, _, _ = self.run_card(result_names=["aero_sweep", "trim_sweep"])
        self.assertEqual(code, 1)
        self.assertEqual(report["unexpected_tests"], ["trim_sweep"])

    def test_default_full_card_cannot_succeed_with_a_partial_profile(self):
        code, report, _, _ = self.run_card(only=None)
        self.assertEqual(code, 1)
        self.assertIn("trim_sweep", report["missing_tests"])
        self.assertIn("power_step", report["missing_tests"])

    def test_unknown_aircraft_cannot_overwrite_a_log_outside_output(self):
        with tempfile.TemporaryDirectory(prefix="ft-unknown-", dir=ROOT / "tmp") as folder:
            directory = Path(folder).resolve()
            sentinel = directory / "run.log"
            sentinel.write_text("existing evidence", encoding="utf-8")
            output = directory / "new-output"
            for aircraft in [str(directory), "../existing", "not-a-catalog-aircraft"]:
                args = ["run.py", "--out", str(output), "--aircraft", aircraft]
                catalog = {aircraft: directory / "data.json"} if "/" in aircraft else {"plane": directory / "data.json"}
                with self.subTest(aircraft=aircraft), mock.patch.object(sys, "argv", args), \
                        mock.patch.object(RUNNER, "data_paths", return_value=catalog), \
                        mock.patch.object(RUNNER, "find_godot") as finder, \
                        mock.patch.object(RUNNER, "godot") as engine, \
                        contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result:
                    RUNNER.main()
                self.assertEqual(result.exception.code, 2)
                finder.assert_not_called()
                engine.assert_not_called()
                self.assertFalse(output.exists())
                self.assertEqual(sentinel.read_text(), "existing evidence")

    def test_complete_default_roster_is_accepted(self):
        code, report, _, _ = self.run_card(only=None, result_names=RUNNER.card_test_names())
        self.assertEqual(code, 0)
        self.assertTrue(report["test_roster_matches"])
        self.assertFalse(report["missing_tests"])

    def test_card_roster_retains_all_maneuvers_in_original_order(self):
        # Independent published card order, including the appended power-step case.
        names = RUNNER.card_test_names()
        self.assertEqual(len(names), 40)
        self.assertEqual(names[:5], ["trim_sweep", "stall_power_off", "vmax", "modes", "aero_sweep"])
        self.assertEqual(names[-3:], ["dead_stick_landing", "go_around", "power_step"])

    def test_old_profile_is_preserved_and_never_summarized(self):
        with tempfile.TemporaryDirectory(prefix="ft-stale-", dir=ROOT / "tmp") as folder:
            directory = Path(folder).resolve()
            self.assertEqual(directory.parent, (ROOT / "tmp").resolve())
            profile = directory / "plane/profile.json"
            profile.parent.mkdir()
            profile.write_text('{"old":true}', encoding="utf-8")
            with mock.patch.object(sys, "argv", ["run.py", "--out", folder, "--aircraft", "plane"]), \
                    mock.patch.object(RUNNER, "find_godot", return_value="test-engine"), \
                    mock.patch.object(RUNNER, "godot") as engine, \
                    contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result:
                RUNNER.main()
            self.assertEqual(result.exception.code, 2)
            engine.assert_not_called()
            self.assertEqual(profile.read_text(), '{"old":true}')
            self.assertFalse((directory / "summary.md").exists())


if __name__ == "__main__":
    unittest.main()
