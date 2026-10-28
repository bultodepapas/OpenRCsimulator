#!/usr/bin/env python3
"""Failure-oriented regressions for the NK-3 development wrapper; no native build required."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import devtools as dev


class DevelopmentToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)

    def database(self, mode="sanitize"):
        flags = [*dev.FP_FLAGS, "-std=c++17", "-fexceptions", "-fno-omit-frame-pointer"]
        if mode == "sanitize":
            flags += dev.SANITIZERS
        for header in ("godot_cpp/core/defs.hpp", "godot_cpp/classes/ref_counted.hpp"):
            path = self.work / "include" / header
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        flags += [f"-I{self.work / 'include'}", f"-I{dev.HERE / 'src'}"]
        return [{"directory": str(self.work), "file": str(source),
                 "command": "g++ " + " ".join(flags) + " -c " + str(source)}
                for source in (dev.HERE / "src").glob("*.cpp")]

    def validate(self, rows, mode="sanitize"):
        path = self.work / "compile_commands.json"
        path.write_text(json.dumps(rows))
        return dev.validate_compdb(path, mode)

    def test_db_requires_actual_native_translation_units(self):
        self.assertTrue(self.validate(self.database()))
        with self.assertRaisesRegex(ValueError, "misses"):
            self.validate([])
        with self.assertRaisesRegex(ValueError, "misses"):
            self.validate([{ "file": "unrelated.cpp", "directory": str(self.work), "command": "g++"}])

    def test_db_rejects_lost_instrumentation_or_fp_policy(self):
        for flag in [*dev.FP_FLAGS, *dev.SANITIZERS, "-std=c++17", "-fno-omit-frame-pointer"]:
            with self.subTest(flag=flag):
                rows = self.database()
                rows[0]["command"] = rows[0]["command"].replace(flag, "")
                with self.assertRaisesRegex(ValueError, "required flags"):
                    self.validate(rows)

    def test_profile_database_does_not_require_sanitizers(self):
        self.assertTrue(self.validate(self.database("profile"), "profile"))

    def test_database_needs_generated_headers_and_strict_flags(self):
        rows = self.database()
        (self.work / "include/godot_cpp/classes/ref_counted.hpp").unlink()
        with self.assertRaisesRegex(ValueError, "cannot resolve"):
            self.validate(rows)
        rows = self.database()
        rows[0]["command"] += " -ffast-math"
        with self.assertRaisesRegex(ValueError, "unsafe floating-point"):
            self.validate(rows)

    def test_sanitizer_stderr_does_not_look_like_godot_errors(self):
        for diagnostic in ["==123==ERROR: AddressSanitizer: heap-buffer-overflow",
                           "test.cpp:9:8: runtime error: signed integer overflow",
                           "SUMMARY: UndefinedBehaviorSanitizer: undefined-behavior"]:
            path = self.work / "engine.log"
            path.write_text(diagnostic)
            self.assertEqual(dev.sanitizer_lines(path), [diagnostic])
        path.write_text("Godot Engine\nNK3_ORACLE verdict=pass\n")
        self.assertEqual(dev.sanitizer_lines(path), [])

    def test_recovering_sanitizer_error_overrides_zero_exit(self):
        report = dev.checked(["python3", "-c", "print('x.cpp:2: runtime error: bad operation')"],
                             self.work, "recovering", 10)
        self.assertEqual(report["process_exit"], 0)
        self.assertFalse(report["ok"])
        self.assertTrue(report["sanitizer_diagnostics"])
        saved = json.loads(Path(report["diagnostic_report"]).read_text())
        self.assertFalse(saved["ok"])

    def test_literal_only_oracle_cannot_pass(self):
        oracle = {"verdict": "pass", "failures": [], "format": "openrc-nk3-stage-oracle v1",
                  "components": {"literals": {"count": 30, "identical": 30}},
                  "total": {"compared": 30, "identical": 30, "mismatched": 0}, "coverage": {}}
        checked = {"ok": True, "complete": True, "reason": "passed", "process_exit": 0,
                   "counts": {"error": 0}}
        self.assertTrue(dev.coverage_error(oracle, checked, "stage_oracle.gd", 12000))

    def test_private_userdata_environment(self):
        values = dev.private_environment(self.work)
        self.assertIn(f"XDG_DATA_HOME={self.work / 'xdg-data'}", values)

    def test_missing_marker_is_not_a_pass(self):
        report = dev.checked(["python3", "-c", "pass"], self.work, "empty", 10, ["NK3_ORACLE verdict=pass"])
        self.assertFalse(report["ok"])

    def test_outputs_cannot_overwrite_or_escape_tmp(self):
        with patch.object(dev, "ROOT", self.work):
            made = dev.fresh(self.work / "tmp/new")
            self.assertTrue(made.is_dir())
            with self.assertRaises(FileExistsError):
                dev.fresh(made)
            for path in [self.work / "app", self.work / "tmp", self.work / "tmp/../app"]:
                with self.assertRaisesRegex(ValueError, "new directory"):
                    dev.fresh(path)


if __name__ == "__main__":
    unittest.main()
