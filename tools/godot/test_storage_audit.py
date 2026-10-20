from __future__ import annotations

import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import storage_audit
from storage_audit import (
    AuditConfigurationError,
    main,
    normalize_exclude_prefix,
    scan_storage,
    write_new_report,
)


class StorageAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc storage audit ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "tree"
        self.root.mkdir()

    def add_file(self, relative: str, content: bytes) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def test_realistic_totals_separate_logical_bytes_from_volume_capacity(self):
        self.add_file("app/.godot/imported/cache.bin", b"c" * 17)
        self.add_file("app/assets/stik.glb", b"a" * 23)
        self.add_file("tmp/logs/engine.log", b"l" * 7)
        self.add_file("logs/storage.log", b"L" * 13)
        self.add_file("research/sample.csv", b"r" * 11)
        self.add_file("README.md", b"R" * 5)
        self.add_file(".git/objects/fake", b"g" * 1000)

        report = scan_storage(self.root)

        self.assertTrue(report["complete"])
        self.assertEqual(report["scan"]["logical_file_bytes"], 76)
        self.assertEqual(report["scan"]["file_count"], 6)
        self.assertEqual(report["excluded_prefixes"], [".git"])
        self.assertEqual(report["scan"]["excluded_entries"], 1)
        by_category = {item["category"]: item for item in report["categories"]}
        self.assertEqual(by_category["app/.godot cache"]["logical_file_bytes"], 17)
        self.assertEqual(by_category["app/assets"]["logical_file_bytes"], 23)
        self.assertEqual(by_category["tmp/logs"]["logical_file_bytes"], 7)
        self.assertEqual(by_category["logs"]["logical_file_bytes"], 13)
        self.assertEqual(by_category["research"]["logical_file_bytes"], 11)
        self.assertEqual(report["largest_files"][0]["logical_bytes"], 23)
        self.assertEqual(report["largest_files"][0]["path"], "app/assets/stik.glb")
        self.assertTrue(report["volume_capacity"]["available"])
        self.assertIn("separate", report["volume_capacity"]["meaning"])
        self.assertIn("hard links count once per path", report["scope"]["logical_file_bytes"])

    def test_file_contents_are_never_opened(self):
        self.add_file("payload.bin", b"payload")
        with mock.patch.object(Path, "open", side_effect=AssertionError("scanner must not open file contents")):
            report = scan_storage(self.root)
        self.assertEqual(report["scan"]["logical_file_bytes"], 7)

    def test_symlink_cycle_is_counted_but_never_traversed(self):
        target = self.root / "target"
        target.mkdir()
        (target / "inside.bin").write_bytes(b"target")
        try:
            (self.root / "alias").symlink_to(target, target_is_directory=True)
            (self.root / "cycle").symlink_to(self.root, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symbolic links are unavailable in this environment")

        report = scan_storage(self.root)

        self.assertTrue(report["complete"])
        self.assertEqual(report["scan"]["logical_file_bytes"], 6)
        self.assertEqual(report["scan"]["file_count"], 1)
        self.assertEqual(report["scan"]["symlink_entries_skipped"], 2)

    def test_root_symlink_is_rejected_as_configuration(self):
        alias = Path(self.temp.name) / "root-alias"
        try:
            alias.symlink_to(self.root, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symbolic links are unavailable in this environment")
        with self.assertRaisesRegex(AuditConfigurationError, "root itself is a symlink"):
            scan_storage(alias)

    @unittest.skipUnless(os.name == "nt", "Windows junction behavior requires Windows")
    def test_windows_junction_is_skipped_as_reparse_point(self):
        target = self.root / "target"
        target.mkdir()
        (target / "inside.bin").write_bytes(b"target")
        junction = self.root / "junction"
        result = subprocess.run(["cmd.exe", "/c", "mklink", "/J", str(junction), str(target)],
                                capture_output=True, text=True, check=False)
        if result.returncode != 0:
            self.skipTest(f"could not create a junction: {result.stderr or result.stdout}")
        try:
            report = scan_storage(self.root)
            self.assertTrue(report["complete"])
            self.assertEqual(report["scan"]["logical_file_bytes"], 6)
            self.assertGreaterEqual(report["scan"]["reparse_entries_skipped"], 1)
        finally:
            try:
                os.rmdir(junction)
            except OSError:
                pass

    def test_entry_depth_and_elapsed_limits_return_explicit_partial_reports(self):
        for index in range(5):
            self.add_file(f"files/{index}.dat", bytes([index]) * (index + 1))
        entry_limited = scan_storage(self.root, max_entries=2)
        self.assertFalse(entry_limited["complete"])
        self.assertIn("entry_limit", entry_limited["partial_reasons"])
        self.assertEqual(entry_limited["scan"]["entries_encountered"], 2)

        deep = self.root / "deep" / "one" / "two"
        deep.mkdir(parents=True)
        (deep / "end.bin").write_bytes(b"end")
        depth_limited = scan_storage(self.root, max_depth=1)
        self.assertFalse(depth_limited["complete"])
        self.assertIn("depth_limit", depth_limited["partial_reasons"])
        self.assertNotIn("deep/one/two/end.bin", {item["path"] for item in depth_limited["largest_files"]})

        clock = iter((0.0, 0.0, 0.6, 0.6, 0.6))
        with mock.patch.object(storage_audit.time, "monotonic", side_effect=lambda: next(clock, 0.6)):
            time_limited = scan_storage(self.root, max_seconds=0.5)
        self.assertFalse(time_limited["complete"])
        self.assertIn("elapsed_time_limit", time_limited["partial_reasons"])
        self.assertLessEqual(time_limited["scan"]["entries_encountered"], 1)

    def test_root_relative_excludes_and_default_git_do_not_hide_godot_cache(self):
        self.add_file("app/.godot/cache.bin", b"cache")
        self.add_file("app/.godot-cache/visible.bin", b"shown")
        self.add_file(".godot/root-cache.bin", b"root")
        self.add_file(".git/ignored", b"git")

        report = scan_storage(self.root, excludes=("./app/.godot/",))

        self.assertEqual(report["excluded_prefixes"], [".git", "app/.godot"])
        self.assertEqual(report["scan"]["logical_file_bytes"], 9)
        paths = {item["path"] for item in report["largest_files"]}
        self.assertNotIn("app/.godot/cache.bin", paths)
        self.assertIn("app/.godot-cache/visible.bin", paths)
        self.assertIn(".godot/root-cache.bin", paths)

    def test_git_exclusion_uses_windows_case_rules_but_posix_remains_case_sensitive(self):
        with mock.patch.object(storage_audit.os, "name", "nt"), \
                mock.patch.object(storage_audit.os.path, "normcase", side_effect=str.casefold):
            self.assertTrue(storage_audit._prefix_matches("nested/.GIT/objects/item", ".git"))
            self.assertFalse(storage_audit._prefix_matches("nested/.GITignore/item", ".git"))

        with mock.patch.object(storage_audit.os, "name", "posix"), \
                mock.patch.object(storage_audit.os.path, "normcase", side_effect=lambda value: value):
            self.assertFalse(storage_audit._prefix_matches("nested/.GIT/objects/item", ".git"))

    def test_largest_files_ties_retain_lexicographically_smallest_paths(self):
        kept = []
        for path in ("a", "z", "b"):
            storage_audit._retain_largest_file(kept, (10, path, "other"), 2)
        self.assertEqual([entry[1] for entry in kept], ["a", "b"])
        self.assertLessEqual(len(kept), 2)

    def test_invalid_exclude_prefixes_are_rejected(self):
        for raw in ("", ".", "../outside", "app/../../outside", "/absolute", "C:\\outside"):
            with self.subTest(raw=raw), self.assertRaises(AuditConfigurationError):
                normalize_exclude_prefix(raw)
        self.assertEqual(normalize_exclude_prefix("./app\\.godot"), "app/.godot")

    def test_scan_limits_are_finite_and_capped(self):
        invalid_options = (
            {"top": 0}, {"top": 101},
            {"max_entries": 0}, {"max_entries": 1_000_001},
            {"max_seconds": 0}, {"max_seconds": math.nan}, {"max_seconds": math.inf}, {"max_seconds": 301},
            {"max_depth": 0}, {"max_depth": 1025},
        )
        for options in invalid_options:
            with self.subTest(options=options), self.assertRaises(AuditConfigurationError):
                scan_storage(self.root, **options)

    def test_unreadable_child_and_many_filesystem_errors_are_bounded_and_partial(self):
        children = [self.root / f"blocked-{index:02d}" for index in range(25)]
        for child in children:
            child.mkdir()
        real_scandir = os.scandir

        def scandir_with_denials(path):
            if Path(path) in children:
                raise PermissionError(13, "fixture denies child scan", str(path))
            return real_scandir(path)

        with mock.patch.object(storage_audit.os, "scandir", side_effect=scandir_with_denials):
            report = scan_storage(self.root)

        self.assertFalse(report["complete"])
        self.assertIn("filesystem_error", report["partial_reasons"])
        self.assertEqual(report["filesystem_errors"]["count"], 25)
        self.assertEqual(len(report["filesystem_errors"]["samples"]), 20)
        self.assertEqual(report["filesystem_errors"]["samples_omitted"], 5)

    def test_hard_links_are_counted_per_path_as_documented(self):
        source = self.add_file("source.bin", b"same bytes")
        alias = self.root / "alias.bin"
        try:
            os.link(source, alias)
        except OSError:
            self.skipTest("hard links are unavailable in this environment")

        report = scan_storage(self.root)

        self.assertEqual(report["scan"]["file_count"], 2)
        self.assertEqual(report["scan"]["logical_file_bytes"], 2 * len(b"same bytes"))

    def test_missing_or_file_root_is_configuration_failure_without_traceback(self):
        file_root = self.add_file("not-a-root", b"file")
        missing = self.root / "missing"
        for bad_root in (missing, file_root):
            with self.subTest(root=bad_root):
                with self.assertRaises(AuditConfigurationError):
                    scan_storage(bad_root)
                output = self.root.parent / "diagnostic.json"
                stderr = tempfile.TemporaryFile(mode="w+t", encoding="utf-8")
                try:
                    with mock.patch.object(sys, "stderr", stderr):
                        code = main([str(bad_root), "--out", str(output)])
                    stderr.seek(0)
                    message = stderr.read()
                finally:
                    stderr.close()
                self.assertEqual(code, 2)
                self.assertNotIn("Traceback", message)
                self.assertFalse(output.exists())

    def test_output_is_exclusive_and_cli_reports_output_failures_cleanly(self):
        report_file = self.root.parent / "existing.json"
        report_file.write_text("preserve", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            write_new_report(report_file, {"format": "test"})
        self.assertEqual(report_file.read_text(encoding="utf-8"), "preserve")

        target = self.root.parent / "target.json"
        target.write_text("keep target", encoding="utf-8")
        link = self.root.parent / "output-link.json"
        try:
            link.symlink_to(target)
        except (OSError, NotImplementedError):
            link = None
        if link is not None:
            with self.assertRaises(FileExistsError):
                write_new_report(link, {"format": "test"})
            self.assertEqual(target.read_text(encoding="utf-8"), "keep target")

        stderr = tempfile.TemporaryFile(mode="w+t", encoding="utf-8")
        try:
            with mock.patch.object(sys, "stderr", stderr):
                code = main([str(self.root), "--out", str(report_file)])
            stderr.seek(0)
            message = stderr.read()
        finally:
            stderr.close()
        self.assertEqual(code, 2)
        self.assertIn("configuration/output error", message)
        self.assertNotIn("Traceback", message)
        self.assertEqual(report_file.read_text(encoding="utf-8"), "preserve")

    def test_cli_writes_complete_report_and_returns_zero(self):
        self.add_file("app/assets/plane.glb", b"aircraft")
        output = self.root.parent / "audit.json"
        result = subprocess.run([sys.executable, str(Path(storage_audit.__file__)), str(self.root), "--out", str(output)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("storage audit: complete", result.stdout)
        self.assertIn("largest 1: app/assets/plane.glb - 0.00 MiB (8 bytes)", result.stdout)
        saved = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(saved["format"], "openrc-storage-audit v1")
        self.assertEqual(saved["scan"]["logical_file_bytes"], len(b"aircraft"))

    def test_cli_writes_partial_report_and_returns_one(self):
        self.add_file("one.bin", b"1")
        self.add_file("two.bin", b"22")
        output = self.root.parent / "partial.json"
        result = subprocess.run([sys.executable, str(Path(storage_audit.__file__)), str(self.root),
                                 "--out", str(output), "--max-entries", "1"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("storage audit: partial", result.stdout)
        self.assertIn("partial: entry_limit", result.stderr)
        saved = json.loads(output.read_text(encoding="utf-8"))
        self.assertFalse(saved["complete"])
        self.assertEqual(saved["scan"]["entries_encountered"], 1)


if __name__ == "__main__":
    unittest.main()
