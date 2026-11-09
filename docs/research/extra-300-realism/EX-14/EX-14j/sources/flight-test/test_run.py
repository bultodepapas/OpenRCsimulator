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
    def run_card(self, change_file=False, omit_identity=False):
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
                profile = {"results": {"probe": {"valid": True}}}
                if not omit_identity:
                    profile["aircraft_input_sha256"] = loaded_hash
                (target / "profile.json").write_text(json.dumps(profile), encoding="utf-8")
                if change_file:
                    source.write_text('{"id":"plane","version":2}', encoding="utf-8")
                return subprocess.CompletedProcess([], 0, "probe completed\n", "")

            summarizer = types.SimpleNamespace(main_with=lambda *_: None)
            args = ["run.py", "--out", str(output), "--aircraft", "plane", "--data", str(source)]
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
