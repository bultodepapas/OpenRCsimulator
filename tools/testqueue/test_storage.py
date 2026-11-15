"""Focused contracts for the read-only storage CLI."""
from __future__ import annotations

import contextlib
import io
import json
import ntpath
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

from tools.testqueue import storage, testctl


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "root"
        self.root.mkdir()

    def call(self, *args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = testctl.main(["storage", *map(str, args)])
        return code, stdout.getvalue(), stderr.getvalue()

    def budget_args(self, *extra):
        return ("budget", "--root", self.root, "--peak-bytes", "10",
                "--reserved-bytes", "20", "--floor-bytes", "30", *extra)

    def symlink(self, link, target, directory=False):
        try:
            link.symlink_to(target, target_is_directory=directory)
        except (OSError, NotImplementedError) as error:
            self.skipTest(f"symlinks unavailable: {error}")

    def test_inventory_uses_existing_scanner_and_excludes_git_and_links(self):
        (self.root / "file.dat").write_bytes(b"abc")
        (self.root / ".git").mkdir()
        (self.root / ".git" / "private").write_bytes(b"not counted")
        outside = self.base / "outside"
        outside.mkdir()
        (outside / "unseen").write_bytes(b"not scanned")
        self.symlink(self.root / "link", outside, directory=True)
        with mock.patch.object(storage.storage_audit, "scan_storage", wraps=storage.storage_audit.scan_storage) as scan:
            code, output, error = self.call("inventory", "--root", self.root)
        self.assertEqual((code, error), (0, ""))
        scan.assert_called_once()
        report = json.loads(output)
        result = report["roots"][0]
        self.assertTrue(report["complete"])
        self.assertEqual(result["scan"]["logical_file_bytes"], 3)
        self.assertEqual(result["scan"]["excluded_entries"], 1)
        self.assertEqual(result["scan"]["symlink_entries_skipped"], 1)
        self.assertEqual([entry["path"] for entry in result["largest_files"]], ["file.dat"])
        self.assertIn("not assessed", report["lifecycle"])

    def test_scanner_exclusion_matches_windows_and_posix_component_semantics(self):
        audit = storage.storage_audit
        with mock.patch.object(audit.os, "name", "nt"), mock.patch.object(audit.os.path, "normcase", ntpath.normcase):
            self.assertTrue(audit._excluded("project/.git/config", [".git"]))
            self.assertTrue(audit._excluded("project/.GIT/config", [".git"]))
            self.assertTrue(audit._excluded("Cache/NESTED/file", ["cache/nested"]))
            self.assertTrue(audit._excluded("cache/nested", ["Cache/Nested"]))
            self.assertFalse(audit._excluded("cache/nestedly/file", ["cache/nested"]))
            self.assertFalse(audit._excluded("other/cache/nested", ["cache/nested"]))
        with mock.patch.object(audit.os, "name", "posix"):
            self.assertTrue(audit._excluded("project/.git/config", [".git"]))
            self.assertTrue(audit._excluded("project/.GIT/config", [".git"]))
            self.assertTrue(audit._excluded("cache/nested/file", ["cache/nested"]))
            self.assertFalse(audit._excluded("Cache/nested/file", ["cache/nested"]))
            self.assertFalse(audit._excluded("cache/nestedly/file", ["cache/nested"]))

    def test_windows_output_names_refuse_streams_and_reserved_devices(self):
        storage._validate_windows_output_path(r"C:\reports\result.json")
        for path in (r"C:\reports\result.json:stream", r"C:\reports:stream\result.json",
                     r"C:\reports\NUL", r"C:\reports\CON.txt", r"C:\COM1\result.json"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                storage._validate_windows_output_path(path)

    def test_incomplete_scan_is_not_promoted_to_complete(self):
        for index in range(3):
            (self.root / f"file{index}").write_bytes(b"x")
        code, output, _ = self.call("inventory", "--root", self.root, "--max-entries", "1")
        report = json.loads(output)
        self.assertEqual(code, 1)
        self.assertFalse(report["complete"])
        self.assertEqual(report["roots"][0]["status"], "partial")
        self.assertIn("entry_limit", report["roots"][0]["partial_reasons"])
        self.assertEqual(report["roots"][0]["scan"]["entries_encountered"], 1)

    def test_directory_swapped_for_symlink_during_open_is_partial(self):
        child = self.root / "child"
        child.mkdir()
        outside = self.base / "outside"
        outside.mkdir()
        (outside / "not-in-root").write_bytes(b"outside contents")
        original_scandir = os.scandir

        def swap_before_open(path):
            if os.fspath(path) == str(child):
                child.rename(self.base / "old-child")
                self.symlink(child, outside, directory=True)
            return original_scandir(path)

        with mock.patch.object(storage.storage_audit.os, "scandir", side_effect=swap_before_open):
            result = storage.inventory([self.root])
        audit = result["roots"][0]
        self.assertFalse(result["complete"])
        self.assertIn("directory_changed", audit["partial_reasons"])
        self.assertEqual(audit["scan"]["logical_file_bytes"], 0)
        self.assertEqual(audit["largest_files"], [])

    def test_root_swapped_for_symlink_during_open_is_partial(self):
        outside = self.base / "outside"
        outside.mkdir()
        (outside / "not-in-root").write_bytes(b"outside contents")
        original_scandir = os.scandir

        def swap_before_open(path):
            if os.fspath(path) == str(self.root):
                self.root.rename(self.base / "old-root")
                self.symlink(self.root, outside, directory=True)
            return original_scandir(path)

        with mock.patch.object(storage.storage_audit.os, "scandir", side_effect=swap_before_open):
            result = storage.inventory([self.root])
        self.assertFalse(result["complete"])
        self.assertIn("directory_changed", result["roots"][0]["partial_reasons"])
        self.assertEqual(result["roots"][0]["scan"]["file_count"], 0)

    def test_directory_replaced_with_another_directory_is_partial(self):
        child = self.root / "child"
        child.mkdir()
        replacement = self.base / "replacement"
        replacement.mkdir()
        (replacement / "different").write_bytes(b"different")
        original_scandir = os.scandir

        def swap_before_open(path):
            if os.fspath(path) == str(child):
                child.rename(self.base / "old-child")
                replacement.rename(child)
            return original_scandir(path)

        with mock.patch.object(storage.storage_audit.os, "scandir", side_effect=swap_before_open):
            result = storage.inventory([self.root])
        self.assertFalse(result["complete"])
        self.assertIn("directory_changed", result["roots"][0]["partial_reasons"])
        self.assertEqual(result["roots"][0]["scan"]["file_count"], 0)

    def test_roots_must_be_bounded_distinct_nonoverlapping_and_outside_git(self):
        nested = self.root / "nested"
        nested.mkdir()
        git = self.root / ".git"
        git.mkdir()
        upper_git = self.base / ".GIT"
        upper_git.mkdir()
        for roots in ([self.root, self.root], [self.root, nested], [git], [upper_git], [self.root] * 5):
            with self.subTest(roots=roots), mock.patch.object(storage.storage_audit, "scan_storage") as scan:
                with self.assertRaises(ValueError):
                    storage.inventory(roots)
                scan.assert_not_called()

    def test_existing_ancestor_identity_detects_alias_overlap(self):
        alias = self.base / "alias"
        nested = alias / "nested"
        nested.mkdir(parents=True)
        original_samefile = os.path.samefile

        def samefile(first, second):
            if Path(first) == self.root and Path(second) == alias:
                return True
            return original_samefile(first, second)

        with mock.patch.object(storage.os.path, "samefile", side_effect=samefile):
            with self.assertRaisesRegex(ValueError, "overlap"):
                storage.inventory([self.root, nested])

    def test_multiple_roots_remain_separate_and_are_not_summed(self):
        second = self.base / "second"
        second.mkdir()
        (self.root / "first").write_bytes(b"a")
        (second / "second").write_bytes(b"bc")
        report = storage.inventory([self.root, second])
        self.assertEqual([row["scan"]["logical_file_bytes"] for row in report["roots"]], [1, 2])
        self.assertNotIn("volume_free_bytes", report)
        self.assertIn("not summed", report["capacity"])

    def test_later_root_unavailable_preserves_earlier_results(self):
        second = self.base / "second"
        second.mkdir()
        (self.root / "first").write_bytes(b"a")
        original_scan = storage.storage_audit.scan_storage

        def scan_with_disappearance(root, **kwargs):
            if root == second:
                second.rename(self.base / "moved-second")
            return original_scan(root, **kwargs)

        with mock.patch.object(storage.storage_audit, "scan_storage", side_effect=scan_with_disappearance):
            code, output, error = self.call("inventory", "--root", self.root, "--root", second)
        self.assertEqual((code, error), (1, ""))
        report = json.loads(output)
        self.assertFalse(report["complete"])
        self.assertEqual(report["roots"][0]["scan"]["logical_file_bytes"], 1)
        self.assertEqual(report["roots"][1]["status"], "unavailable")
        self.assertIn("root_unavailable_after_validation", report["roots"][1]["partial_reasons"])
        with mock.patch.object(storage.storage_audit, "scan_storage") as scan:
            code, output, _ = self.call("inventory", "--root", second)
            self.assertEqual((code, output), (2, ""))
            scan.assert_not_called()

    def test_bounds_are_checked_before_scanning(self):
        for arguments in ({"max_entries": 0}, {"max_entries": 100_001},
                          {"max_seconds": 0}, {"max_seconds": float("nan")},
                          {"max_seconds": float("inf")}, {"max_seconds": 31},
                          {"max_depth": 0}, {"top": 101}):
            with self.subTest(arguments=arguments), mock.patch.object(storage.storage_audit, "scan_storage") as scan:
                with self.assertRaises(ValueError):
                    storage.inventory([self.root], **arguments)
                scan.assert_not_called()

    def test_budget_zero_exact_boundary_insufficient_and_unknown(self):
        for free, peak, reserved, floor, expected, code in (
                (0, 0, 0, 0, "observed_fit", 0),
                (60, 10, 20, 30, "observed_fit", 0),
                (59, 10, 20, 30, "insufficient", 1),
                (10, 0, 20, 0, "insufficient", 1)):
            args = ("budget", "--root", self.root, "--peak-bytes", peak,
                    "--reserved-bytes", reserved, "--floor-bytes", floor)
            with self.subTest(free=free), mock.patch.object(storage.shutil, "disk_usage", return_value=types.SimpleNamespace(free=free)):
                actual, output, _ = self.call(*args)
                result = json.loads(output)
                self.assertEqual((actual, result["assessment"]), (code, expected))
                self.assertEqual(result["headroom_after_reservations_and_floor_bytes"], free - reserved - floor)
        with mock.patch.object(storage.shutil, "disk_usage", side_effect=OSError("not available")):
            code, output, _ = self.call(*self.budget_args())
        self.assertEqual(code, 2)
        self.assertEqual(json.loads(output)["assessment"], "indeterminate")
        self.assertIsNone(json.loads(output)["volume_free_bytes"])

    def test_budget_rejects_malformed_negative_and_missing_values(self):
        for malformed in ("-1", "1.5", "NaN", "1_0", "+1", "0x10", str(storage.MAX_BYTES + 1)):
            arguments = ["budget", "--root", str(self.root), "--peak-bytes", malformed,
                         "--reserved-bytes", "0", "--floor-bytes", "0"]
            with self.subTest(value=malformed), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    testctl.main(["storage", *arguments])
                self.assertEqual(error.exception.code, 2)
        for value in (-1, True, 1.5, storage.MAX_BYTES + 1):
            with self.assertRaises(ValueError):
                storage.budget(self.root, peak_bytes=value, reserved_bytes=0, floor_bytes=0)
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                testctl.main(["storage", "budget", "--root", str(self.root), "--peak-bytes", "0"])
            with self.assertRaises(SystemExit):
                testctl.main(["storage", "budget", "--root", str(self.root), "--peak", "0",
                              "--reserved-bytes", "0", "--floor-bytes", "0"])

    def test_root_and_output_parent_refuse_symlink_components(self):
        real_parent = self.base / "real"
        real_parent.mkdir()
        real_root = real_parent / "child"
        real_root.mkdir()
        linked_parent = self.base / "linked"
        self.symlink(linked_parent, real_parent, directory=True)
        code, _, error = self.call("inventory", "--root", linked_parent / "child")
        self.assertEqual(code, 2)
        self.assertIn("symlink", error)
        code, _, error = self.call(*self.budget_args("--out", linked_parent / "report.json"))
        self.assertEqual(code, 2)
        self.assertIn("symlink", error)
        self.assertFalse((real_parent / "report.json").exists())

    def test_reparse_point_at_any_path_component_is_refused(self):
        with mock.patch.object(storage.storage_audit, "_is_reparse_point", return_value=True):
            with self.assertRaisesRegex(ValueError, "reparse"):
                storage.budget(self.root, peak_bytes=0, reserved_bytes=0, floor_bytes=0)
            with self.assertRaisesRegex(ValueError, "reparse"):
                storage._output_path(self.base / "report.json")

    def test_parent_replaced_with_symlink_after_validation_is_refused(self):
        parent = self.base / "parent"
        parent.mkdir()
        outside = self.base / "outside"
        outside.mkdir()
        report = storage._output_path(parent / "report.json")
        parent.rename(self.base / "original-parent")
        self.symlink(parent, outside, directory=True)
        with self.assertRaises((OSError, ValueError)):
            storage._write_report(report, "{}\n")
        self.assertFalse((outside / "report.json").exists())

    def test_output_created_after_validation_is_never_overwritten(self):
        report = storage._output_path(self.base / "report.json")
        report.write_bytes(b"created by another process")
        with self.assertRaises(FileExistsError):
            storage._write_report(report, "{}\n")
        self.assertEqual(report.read_bytes(), b"created by another process")

    @unittest.skipUnless(os.name == "nt", "native Windows junction fixture")
    def test_native_windows_junction_refused(self):
        junction = self.base / "junction"
        result = subprocess.run(["cmd", "/d", "/c", "mklink", "/J", str(junction), str(self.root)],
                                capture_output=True, text=True, check=False)
        if result.returncode:
            self.skipTest("junction creation unavailable")
        with self.assertRaisesRegex(ValueError, "reparse"):
            storage.budget(junction, peak_bytes=0, reserved_bytes=0, floor_bytes=0)
        with self.assertRaisesRegex(ValueError, "reparse"):
            storage._output_path(junction / "report.json")

    def test_output_exclusive_no_parent_creation_and_no_link_following(self):
        report = self.base / "report.json"
        with mock.patch.object(storage.shutil, "disk_usage", return_value=types.SimpleNamespace(free=100)):
            code, output, error = self.call(*self.budget_args("--out", report))
            self.assertEqual((code, output, error), (0, "", ""))
            self.assertEqual(json.loads(report.read_text())["assessment"], "observed_fit")
            original = report.read_bytes()
            code, _, _ = self.call(*self.budget_args("--out", report))
            self.assertEqual(code, 2)
            self.assertEqual(report.read_bytes(), original)
            code, _, _ = self.call(*self.budget_args("--out", self.base / "missing" / "report.json"))
            self.assertEqual(code, 2)
            self.assertFalse((self.base / "missing").exists())
            link = self.base / "report-link.json"
            self.symlink(link, report)
            code, _, _ = self.call(*self.budget_args("--out", link))
            self.assertEqual(code, 2)
            self.assertEqual(report.read_bytes(), original)
            dangling = self.base / "dangling.json"
            self.symlink(dangling, self.base / "does-not-exist.json")
            code, _, _ = self.call(*self.budget_args("--out", dangling))
            self.assertEqual(code, 2)
            self.assertFalse((self.base / "does-not-exist.json").exists())

    def test_storage_cli_never_contacts_worker_or_changes_root(self):
        existing = self.root / "unchanged"
        existing.write_bytes(b"original")
        fake_worker = types.ModuleType("tools.testqueue.worker")
        fake_worker.Worker = mock.Mock(side_effect=AssertionError("worker started"))
        with mock.patch.object(testctl, "rpc", side_effect=AssertionError("RPC called")) as rpc, \
                mock.patch.object(testctl, "state_root", side_effect=AssertionError("state root read")) as state_root, \
                mock.patch.dict(sys.modules, {"tools.testqueue.worker": fake_worker}), \
                mock.patch.object(storage.shutil, "disk_usage", return_value=types.SimpleNamespace(total=200, used=100, free=100)):
            for args in (("inventory", "--root", self.root), self.budget_args()):
                code, output, error = self.call(*args)
                self.assertEqual((code, error), (0, ""))
                self.assertIsInstance(json.loads(output), dict)
        rpc.assert_not_called()
        state_root.assert_not_called()
        fake_worker.Worker.assert_not_called()
        self.assertEqual(list(self.root.iterdir()), [existing])
        self.assertEqual(existing.read_bytes(), b"original")

    def test_script_entrypoint_outputs_json_without_creating_queue_state(self):
        queue_root = self.base / "unused-queue"
        bytecode_root = self.base / "bytecode"
        bytecode_root.mkdir()
        environment = {**os.environ, "OPENRC_TESTQUEUE_ROOT": str(queue_root),
                       "PYTHONPYCACHEPREFIX": str(bytecode_root)}
        arguments = [sys.executable, "-B", str(Path(testctl.__file__)), "storage", "budget", "--root", str(self.root),
                     "--peak-bytes", "0", "--reserved-bytes", "0", "--floor-bytes", "0"]
        result = subprocess.run(arguments, capture_output=True, text=True, env=environment, check=False)
        self.assertEqual((result.returncode, result.stderr), (0, ""))
        self.assertEqual(json.loads(result.stdout)["assessment"], "observed_fit")
        self.assertFalse(queue_root.exists())
        self.assertEqual(list(bytecode_root.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
