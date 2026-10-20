"""PT1h-R1: subprocess failures and optional real-Godot diagnostic accuracy."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

from run_checked import run_checked


class RunnerFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc checked ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_code(self, code, **options):
        return run_checked([sys.executable, "-c", code], self.root, **options)


class CheckedRunnerTests(RunnerFixture):
    def test_clean_run_and_report_identity(self):
        report = self.run_code("print('42 checks passed')", required=["42 checks passed"])
        self.assertTrue(report["ok"])
        self.assertTrue(report["complete"])
        self.assertEqual(json.loads(Path(report["report"]).read_text()), report)
        self.assertEqual(report["counts"], {"error": 0, "warning": 0})

    def test_errors_on_both_streams_fail_with_zero_exit_and_keep_location(self):
        for kind in ("ERROR", "SCRIPT ERROR", "SHADER ERROR"):
            for output in ("sys.stdout", "sys.stderr"):
                with self.subTest(kind=kind, output=output):
                    report = self.run_code(f"import sys; print('\\x1b[31m  {kind}: broken\\x1b[0m\\n   at: res://probe.gd:7', file={output})")
                    self.assertEqual(report["reason"], "engine_error")
                    self.assertEqual(report["process_exit"], 0)
                    self.assertEqual(report["counts"]["error"], 1)
                    self.assertIn("res://probe.gd:7", report["diagnostics"][0]["context"][0])

    def test_normal_mentions_are_not_errors(self):
        report = self.run_code("print('expected ERROR: example\\n0 errors, error 0\\nSCRIPT ERROR count: 0')")
        self.assertTrue(report["ok"])

    def test_warnings_are_visible_and_optionally_fatal(self):
        code = "print('WARNING: ObjectDB instances leaked at exit')"
        report = self.run_code(code)
        self.assertTrue(report["ok"])
        self.assertEqual(report["counts"]["warning"], 1)
        self.assertEqual(self.run_code(code, warnings_as_errors=True)["reason"], "warning")

    def test_nonzero_exit_preserved(self):
        report = self.run_code("raise SystemExit(7)")
        self.assertEqual(report["exit_code"], 7)
        self.assertEqual(report["reason"], "process_exit")

    def test_timeout_retains_partial_diagnostics(self):
        report = self.run_code("import time; print('starting', flush=True); time.sleep(30)", timeout=0.5)
        self.assertEqual(report["exit_code"], 124)
        self.assertFalse(report["complete"])
        self.assertIn("starting", Path(report["log"]).read_text())
        self.assertLess(report["elapsed_seconds"], 15)

    def test_timeout_stops_child_writes(self):
        target = self.root / "late write.txt"
        child = f"import time; from pathlib import Path; print('child started', flush=True); time.sleep(2); Path({str(target)!r}).write_text('leaked')"
        code = f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}]); time.sleep(30)"
        report = self.run_code(code, timeout=1)
        self.assertEqual(report["reason"], "timeout")
        self.assertIn("child started", Path(report["log"]).read_text())
        time.sleep(2)
        self.assertFalse(target.exists(), "timed-out child survived and wrote late evidence")

    def test_launch_failure_is_actionable_and_retained(self):
        report = run_checked([str(self.root / "missing engine")], self.root)
        self.assertEqual(report["exit_code"], 127)
        self.assertFalse(report["complete"])
        self.assertTrue(report["detail"])
        self.assertTrue(Path(report["report"]).is_file())

    def test_flood_is_bounded_even_without_newlines(self):
        report = self.run_code("import os;\nwhile True: os.write(1,b'x'*65536)", max_log_bytes=2048)
        self.assertEqual(report["reason"], "log_limit")
        self.assertFalse(report["complete"])
        self.assertEqual(Path(report["log"]).stat().st_size, 2048)

    def test_exact_limit_is_accepted(self):
        report = self.run_code("import os; os.write(1,b'x'*2048)", max_log_bytes=2048)
        self.assertTrue(report["ok"])
        self.assertEqual(report["log_bytes"], 2048)

    def test_log_disk_write_failure_is_not_a_pass(self):
        original_open = Path.open

        def failing_open(path, *args, **kwargs):
            stream = original_open(path, *args, **kwargs)
            if path.name == "engine.log" and args == ("wb",):
                wrapped = mock.MagicMock(wraps=stream)
                wrapped.__enter__.return_value = wrapped
                wrapped.__exit__.side_effect = lambda *unused: stream.close()
                wrapped.write.side_effect = OSError("No space left on device (injected)")
                return wrapped
            return stream

        with mock.patch.object(Path, "open", failing_open):
            report = self.run_code("print('finished')")
        self.assertEqual(report["reason"], "runner_error")
        self.assertFalse(report["complete"])
        self.assertIn("No space left", report["detail"])

    def test_many_errors_counted_with_bounded_samples(self):
        report = self.run_code("print('ERROR: repeated\\n'*1000)")
        self.assertEqual(report["counts"]["error"], 1000)
        self.assertEqual(len(report["diagnostics"]), 20)

    def test_unsampled_error_cannot_inherit_context(self):
        report = self.run_code("for i in range(21): print(f'ERROR: error{i}\\n detail{i}')")
        self.assertEqual(report["counts"]["error"], 21)
        self.assertEqual(report["diagnostics"][-1]["message"], "error19")
        self.assertEqual(report["diagnostics"][-1]["context"], [" detail19"])

    def test_invalid_utf8_does_not_hide_error(self):
        report = self.run_code("import os; os.write(2,b'ERROR: bad \\xff\\n')")
        self.assertEqual(report["reason"], "engine_error")

    def test_required_completion_and_fresh_output(self):
        previous = self.run_code("print('finished')", required=["finished"])
        current = self.run_code("pass", required=["finished"])
        self.assertEqual(current["reason"], "missing_required_text")
        self.assertNotEqual(previous["report"], current["report"])
        self.assertEqual(Path(previous["log"]).read_text().strip(), "finished")

    def test_long_line_cannot_create_false_error_at_chunk_boundary(self):
        report = self.run_code("print('x'*65536+'ERROR: ordinary payload')")
        self.assertTrue(report["ok"])

    def test_marker_crossing_chunk_boundary(self):
        report = self.run_code("print('x'*65534+'finished')", required=["finished"])
        self.assertTrue(report["ok"])

    def test_invalid_options_do_not_launch(self):
        for options in ({"timeout": float("nan")}, {"timeout": float("inf")},
                        {"timeout": 0}, {"max_log_bytes": 0}, {"max_log_bytes": 1.5},
                        {"max_log_bytes": True}, {"required": [""]}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.run_code("raise SystemExit('must not execute')", **options)

    def test_cli_preserves_spaces_and_literal_arguments(self):
        script = Path(__file__).with_name("run_checked.py")
        result = subprocess.run([sys.executable, str(script), "--out-dir", str(self.root),
                                 "--require-text", "literal $() & value", "--", sys.executable,
                                 "-c", "import sys; print(sys.argv[1])", "literal $() & value"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cli_invalid_output_path_has_no_traceback(self):
        target = self.root / "file"
        target.write_text("preserve")
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("run_checked.py")),
                                 "--out-dir", str(target), "--", sys.executable, "-c", "pass"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn("configuration/output error", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(target.read_text(), "preserve")


@unittest.skipUnless(os.environ.get("OPENRC_TEST_GODOT"), "set OPENRC_TEST_GODOT for actual engine faults")
class NativeGodotTests(RunnerFixture):
    def test_real_godot_failure_matrix(self):
        project = self.root / "project"
        project.mkdir()
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Diagnostic fixture"\n')
        cases = {
            "clean": ('extends SceneTree\nfunc _initialize():\n print("fixture completed")\n quit(0)\n', "passed"),
            "script": ('extends SceneTree\nfunc _initialize():\n call_deferred("bad_call")\n create_timer(0.1).timeout.connect(func(): quit(0))\nfunc bad_call():\n var item: Variant = null\n item.missing()\n', "engine_error"),
            "resource": ('extends SceneTree\nfunc _initialize():\n load("res://absent.tres")\n quit(0)\n', "engine_error"),
            "parse": ('extends SceneTree\nfunc _initialize(:\n', "process_exit"),
            "hang": ('extends SceneTree\nfunc _initialize():\n print("waiting")\n', "timeout"),
        }
        engine = str(Path(os.environ["OPENRC_TEST_GODOT"]).resolve())
        for name, (source, expected) in cases.items():
            with self.subTest(name=name):
                script = project / (name + ".gd")
                script.write_text(source)
                report = run_checked([engine, "--headless", "--path", str(project), "--script", str(script)],
                                     self.root / "reports", timeout=2 if name == "hang" else 15)
                self.assertEqual(report["reason"], expected, report)
                if name in ("script", "resource"):
                    self.assertEqual(report["process_exit"], 0, report)
                    self.assertGreater(report["counts"]["error"], 0)


if __name__ == "__main__":
    unittest.main()
