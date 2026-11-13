"""Portable policy tests for the disposable Apple sanitizer diagnostics."""
from __future__ import annotations

import copy
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("openrc_macos_diagnostic_tests", HERE / "macos_diagnostics.py")
diag = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diag)


class DiagnosticPolicyTests(unittest.TestCase):
    def test_compile_defines_match_instrumentation_for_candidate_and_control(self):
        for mode, expected, excluded in (
            ("ubsan", "-DUBSAN_ENABLED", "-DASAN_ENABLED"),
            ("asan", "-DASAN_ENABLED", "-DUBSAN_ENABLED"),
        ):
            with self.subTest(mode=mode):
                link = diag.sanitizer_flags(mode)
                candidate = diag.sanitizer_compile_flags(mode)
                control = diag.sanitizer_compile_flags(mode, control=True)
                self.assertTrue(set(link).issubset(candidate))
                self.assertTrue(set(candidate).issubset(control))
                self.assertEqual(candidate.count(expected), 1)
                self.assertEqual(control.count(expected), 1)
                self.assertNotIn(excluded, candidate)
                self.assertNotIn(excluded, control)
                self.assertNotIn("-DLSAN_ENABLED", candidate)
                self.assertNotIn("-DLSAN_ENABLED", control)
                self.assertFalse(any(flag.startswith("-D") for flag in link))
                self.assertNotIn("-DOPENRC_MAC_SANITIZER_CONTROL=1", candidate)
                self.assertIn("-DOPENRC_MAC_SANITIZER_CONTROL=1", control)
                self.assertEqual("-DOPENRC_MAC_SANITIZER_ASAN=1" in control, mode == "asan")
        with self.assertRaises(ValueError):
            diag.sanitizer_compile_flags("profile")

    def test_modes_and_controls_are_separate_from_candidate_source(self):
        original = (HERE / "src/nk_kernel.cpp").read_text(encoding="utf-8")
        for mode, flag, fault in (("ubsan", "-fsanitize=undefined", "INT_MAX"),
                                  ("asan", "-fsanitize=address", "values[index] = 42")):
            with self.subTest(mode=mode):
                self.assertIn(flag, diag.sanitizer_flags(mode))
                self.assertIn("-fno-sanitize-recover=all", diag.sanitizer_flags(mode))
                changed = diag.control_source(original, mode)
                self.assertIn("#if defined(OPENRC_MAC_SANITIZER_CONTROL)", changed)
                self.assertIn(f"{diag.CONTROL_MARKER} mode={mode}", changed)
                self.assertIn(fault, changed)
                self.assertNotIn(diag.CONTROL_MARKER, original)
        with self.assertRaises(ValueError):
            diag.control_source(original.replace("#include <cstdint>\n", ""), "ubsan")
        with self.assertRaises(ValueError):
            diag.sanitizer_flags("profile")

    def test_positive_control_needs_matching_origin_marker_diagnostic_and_exit(self):
        report = {"complete": True, "reason": "process_exit", "process_exit": 1}
        source, library = Path("/tmp/control/nk_kernel.cpp"), Path("/tmp/control/libopenrc_native_kernel.dylib")
        for mode, diagnostic in (("ubsan", f"{source}:27: runtime error: signed integer overflow"),
                                 ("asan", f"ERROR: AddressSanitizer: heap-buffer-overflow in {library}")):
            marker = f"{diag.CONTROL_MARKER} mode={mode}\n"
            log = marker + diagnostic
            self.assertTrue(diag.detected_control(mode, report, log, source, library))
            for bad in (diagnostic, marker + "unrelated error", diagnostic + "\n" + marker):
                self.assertFalse(diag.detected_control(mode, report, bad, source, library))
            for altered in (dict(report, complete=False), dict(report, process_exit=0), dict(report, reason="timeout")):
                self.assertFalse(diag.detected_control(mode, altered, log, source, library))

    def test_sanitizer_environment_is_local_and_restored(self):
        initial = {"DYLD_INSERT_LIBRARIES": "previous", "ASAN_OPTIONS": "old", "PATH": "safe"}
        with patch.dict(os.environ, initial, clear=True):
            with diag.sanitizer_environment("ubsan", None):
                self.assertNotIn("DYLD_INSERT_LIBRARIES", os.environ)
                self.assertIn("halt_on_error=1", os.environ["UBSAN_OPTIONS"])
            self.assertEqual(dict(os.environ), initial)
            with self.assertRaisesRegex(ValueError, "runtime"):
                with diag.sanitizer_environment("asan", None):
                    pass
            self.assertEqual(dict(os.environ), initial)
            with self.assertRaisesRegex(RuntimeError, "stop"):
                with diag.sanitizer_environment("asan", Path("/runtime.dylib")):
                    self.assertEqual(os.environ["DYLD_INSERT_LIBRARIES"], str(Path("/runtime.dylib")))
                    raise RuntimeError("stop")
            self.assertEqual(dict(os.environ), initial)

    def test_clean_oracle_needs_real_component_and_rejects_sanitizer_stderr(self):
        report = {"ok": True, "complete": True, "reason": "passed", "process_exit": 0,
                  "counts": {"error": 0}, "missing_required_text": []}
        result = {"format": "openrc-nk3-stage-oracle v1", "verdict": "pass", "failures": [],
                  "seed": 7, "states": 64, "self_test": {"passed": True}, "identity": {"backend": "native"},
                  "components": {"stage_bytes": {"count": 64, "identical": 64}},
                  "total": {"compared": 64, "identical": 64, "mismatched": 0},
                  "coverage": {"stage_air": {"states": 20}, "stage_ground": {"states": 25},
                               "stage_hull": {"states": 19}}}
        self.assertEqual(diag.oracle_error("stage_oracle.gd", result, report, "", 7, 64), "")
        self.assertTrue(diag.oracle_error("stage_oracle.gd", result, report, "runtime error: overflow", 7, 64))
        for changes in ({"components": {}}, {"identity": {"backend": "reference"}}, {"states": 1}):
            bad = copy.deepcopy(result)
            bad.update(changes)
            self.assertTrue(diag.oracle_error("stage_oracle.gd", bad, report, "", 7, 64))
        bad_report = dict(report, complete=False)
        self.assertTrue(diag.oracle_error("stage_oracle.gd", result, bad_report, "", 7, 64))


if __name__ == "__main__":
    unittest.main()
