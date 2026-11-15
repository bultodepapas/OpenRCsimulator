"""Checked-runner pool routing and frozen archive boundaries without remote work."""
import contextlib
import hashlib
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import Mock, patch

from tools.godot import run_checked
from tools.testqueue import pool_checked
from tools.testqueue.pool import verify_archive


class PoolCheckedTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="openrc-pool-checked-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.app = self.root / "app"
        self.app.mkdir()
        self.engine = self.root / "Godot.exe"
        self.output = self.root / "selected-output"
        self.script = "res://tests/test_math3d.gd"
        self.command = [str(self.engine), "--headless", "--path", str(self.app), "--script", self.script]
        self.env = patch.dict(os.environ, {"OPENRC_TESTPOOL_CONFIG": "fixture-config"}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_hook_preserves_output_settings_and_waiting_request_identity(self):
        pool = Mock()
        pool.snapshot.return_value = self.root / "frozen"
        pool.submit.side_effect = [{"state": "WAITING"}, {"state": "SUBMITTED", "receipt": "receipt.json"}]
        pool.status.return_value = {"state": "FINISHED"}
        report = {"pool_outcome": "PASSED", "log": "retained-log", "report": "retained-report"}
        pool.collect.return_value = report
        with patch("tools.testqueue.common.rpc", return_value={"engine": {"path": str(self.engine)}}), \
                patch("tools.testqueue.pool_checked.Pool", return_value=pool) as factory, \
                patch("tools.testqueue.pool_checked.time.sleep"), contextlib.redirect_stderr(io.StringIO()):
            result = run_checked.run_checked(self.command, self.output, timeout=123, max_log_bytes=2048,
                                             warnings_as_errors=True, required=["all passed"], label="targeted")
        self.assertIs(result, report)
        factory.assert_called_once_with("fixture-config")
        pool.snapshot.assert_called_once_with(self.app.parent.resolve())
        self.assertEqual(pool.submit.call_count, 2)
        first, second = pool.submit.call_args_list
        self.assertEqual(first, second)
        self.assertEqual(first.args, (pool.snapshot.return_value, self.script))
        self.assertEqual(first.kwargs["require"], ["all passed"])
        self.assertEqual(first.kwargs["timeout"], 123)
        self.assertEqual(first.kwargs["settings"], {"max_log_bytes": 2048, "warnings_as_errors": True,
                                                    "label": "targeted"})
        identifier = first.kwargs["request_id"]
        pool.status.assert_called_once_with(identifier)
        pool.collect.assert_called_once_with(identifier, out_dir=self.output)

    def test_duplicate_arguments_rejected_before_pool_submission(self):
        for duplicate in (["--script", "res://tests/other.gd"], ["--path", str(self.app)],
                          ["--audio-driver", "Dummy", "--audio-driver", "Dummy"]):
            with self.subTest(duplicate=duplicate), patch("tools.testqueue.pool_checked.Pool") as pool:
                with self.assertRaisesRegex(ValueError, "Duplicate pool checked argument"):
                    pool_checked.checked(self.command + duplicate, out_dir=self.output, timeout=30, required=[],
                                         max_log_bytes=1024, warnings_as_errors=False, label="fixture")
                pool.assert_not_called()

    def test_custom_engine_and_performance_scripts_skip_pool(self):
        custom_engine = [str(self.root / "custom-Godot.exe"), *self.command[1:]]
        performance = [*self.command[:-1], "res://tests/benchmark_solver.gd"]
        expected = {"ok": True, "source": "existing checked integration"}
        for command in (custom_engine, performance):
            with self.subTest(command=command), \
                    patch("tools.testqueue.common.rpc", return_value={"engine": {"path": str(self.engine)}}), \
                    patch("tools.testqueue.common.enabled", return_value=True), \
                    patch("tools.testqueue.common.inherited", return_value=False), \
                    patch("tools.testqueue.integration.checked", return_value=expected) as local, \
                    patch("tools.testqueue.pool_checked.checked") as distributed:
                self.assertIs(run_checked.run_checked(command, self.output, timeout=30), expected)
                distributed.assert_not_called()
                local.assert_called_once()
                self.assertEqual(local.call_args.args[0], command)


class ArchiveVerificationTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="openrc-pool-archive-")
        self.addCleanup(temp.cleanup)
        self.archive = Path(temp.name) / "source.tar"
        self.original = b"frozen snapshot data"
        self.manifest = {"files": {"app/project.godot": {"size": len(self.original),
                                                         "sha256": hashlib.sha256(self.original).hexdigest()}}}

    def write_archive(self, name, content):
        with tarfile.open(self.archive, "w") as bundle:
            entry = tarfile.TarInfo(name)
            entry.size = len(content)
            bundle.addfile(entry, io.BytesIO(content))

    def test_archive_mutation_and_member_substitution_are_refused(self):
        self.write_archive("app/project.godot", self.original)
        verify_archive(self.archive, self.manifest)
        # Same size exercises content verification rather than the size check.
        self.write_archive("app/project.godot", b"Frozen snapshot data")
        with self.assertRaisesRegex(ValueError, "Archive bytes differ"):
            verify_archive(self.archive, self.manifest)
        self.write_archive("app/replacement.godot", self.original)
        with self.assertRaisesRegex(ValueError, "Archive member set differs"):
            verify_archive(self.archive, self.manifest)


if __name__ == "__main__":
    unittest.main()
