"""PT1h-R2: collection integrity and standard JUnit evidence, without Godot."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

from run_checked import run_checked
from summarize import collect_runs, pixel_skip, write_junit

SEGMENT = "res://tests/test_lighting_segment_filter.gd"
SKIN = "res://tests/test_lighting_skin_patterns.gd"
SEGMENT_SKIP = "Lighting segment pixels SKIPPED: native rendering required at 1920x1080."
SKIN_SKIP = "Lighting skin pixels SKIPPED: native renderer required at 1920x1080."


class SummaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc summary ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.collection = self.root / "runs"
        self.collection.mkdir()

    def run_code(self, code, **options):
        return run_checked([sys.executable, "-c", code], self.collection, **options)

    def run_script(self, script, output, *, exit_code=0, engine_args=(), user_args=(), **options):
        code = f"print({output!r}); raise SystemExit({exit_code})"
        command = [sys.executable, "-c", code, *engine_args, "--script", script]
        if user_args:
            command += ["--", *user_args]
        return run_checked(command, self.collection, **options)

    @staticmethod
    def completed(script, count):
        name = "Lighting segment filter" if script == SEGMENT else "Lighting skin patterns"
        checks = "\n".join(f"ok   fixture assertion {index}" for index in range(count))
        return f"{checks}\n{name}: {count} checks, 0 failed"

    @staticmethod
    def change(report, **fields):
        report.update(fields)
        Path(report["report"]).write_text(json.dumps(report))

    def test_junit_preserves_command_verdicts_and_locations(self):
        self.run_code("print('success')")
        self.run_code("print('SCRIPT ERROR: bad <value> & argument\\n   at res://test.gd:8')")
        self.run_code("import time; time.sleep(20)", timeout=0.2)
        items = collect_runs(self.collection)
        output = self.root / "results.xml"
        write_junit(output, items)
        xml = ET.parse(output).getroot()
        self.assertEqual(xml.attrib["tests"], "3")
        self.assertEqual(xml.attrib["failures"], "1")
        self.assertEqual(xml.attrib["errors"], "1")
        self.assertIn("res://test.gd:8", xml.find(".//failure").text)
        self.assertIn("<value> & argument", xml.find(".//failure").text)
        self.assertEqual(xml.find(".//error").attrib["type"], "timeout")

    def test_relocated_artifact_does_not_follow_original_paths(self):
        report = self.run_code("print('ok')")
        relocated = self.root / "downloaded"
        shutil.copytree(self.collection, relocated)
        Path(report["log"]).write_text("ERROR: original path changed")
        items = collect_runs(relocated)
        self.assertTrue(items[0]["ok"], items)

    def test_changed_log_is_invalid_even_if_same_size(self):
        report = self.run_code("print('hello')")
        Path(report["log"]).write_bytes(b"xxxxx\n")
        item = collect_runs(self.collection)[0]
        self.assertEqual(item["reason"], "invalid_report")
        self.assertIn("hash mismatch", item["detail"])

    def test_missing_or_malformed_report_is_not_omitted(self):
        self.run_code("pass")
        (self.collection / "killed-before-report").mkdir()
        broken = self.collection / "malformed"
        broken.mkdir()
        (broken / "report.json").write_text("{not json")
        (broken / "engine.log").touch()
        items = collect_runs(self.collection)
        self.assertEqual(len(items), 3)
        self.assertEqual(sum(item["reason"] == "invalid_report" for item in items), 2)

    def test_empty_and_missing_collections_refused(self):
        with self.assertRaisesRegex(ValueError, "empty collection"):
            collect_runs(self.collection)
        with self.assertRaisesRegex(ValueError, "does not exist"):
            collect_runs(self.root / "missing")
        with self.assertRaisesRegex(ValueError, "empty"):
            write_junit(self.root / "empty.xml", [])

    def test_contradictory_success_refused(self):
        cases = [dict(complete=False), dict(process_exit=7), dict(exit_code=1),
                 dict(counts={"error": 1, "warning": 0}), dict(elapsed_seconds=float("nan")),
                 dict(elapsed_seconds=10 ** 400), dict(reason="unknown"), dict(required_text=[""]),
                 dict(log_sha256=""), dict(command=[])]
        for fields in cases:
            with self.subTest(fields=fields):
                report = self.run_code("pass")
                self.change(report, **fields)
        items = collect_runs(self.collection)
        self.assertTrue(all(item["reason"] == "invalid_report" for item in items), items)

    def test_error_cannot_be_relabelled_as_pass(self):
        report = self.run_code("print('ERROR: failure')")
        self.change(report, reason="passed", ok=True, exit_code=0)
        self.assertEqual(collect_runs(self.collection)[0]["reason"], "invalid_report")

    def test_warning_policy_and_missing_completion_remain_failures(self):
        self.run_code("print('WARNING: leak')", warnings_as_errors=True)
        self.run_code("pass", required=["checks completed"])
        items = collect_runs(self.collection)
        self.assertCountEqual([i["reason"] for i in items], ["warning", "missing_required_text"])
        self.assertFalse(any(i["ok"] for i in items))

    def test_lighting_headless_skips_are_distinct_in_junit_and_console(self):
        self.run_script(SEGMENT, SEGMENT_SKIP)
        self.run_script(SKIN, SKIN_SKIP)
        self.run_script(SEGMENT, self.completed(SEGMENT, 12))
        items = collect_runs(self.collection)
        self.assertEqual(sum(item["skipped"] for item in items), 2)
        self.assertEqual(sum(item["reason"] == "passed" for item in items), 1)
        output = self.root / "lighting.xml"
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("summarize.py")),
                                 str(self.collection), "--junit", str(output)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 passed, 2 skipped, 0 failed or invalid", result.stdout)
        self.assertIn(SEGMENT + " [skipped]", result.stdout)
        self.assertIn(SKIN + " [skipped]", result.stdout)
        xml = ET.parse(output).getroot()
        self.assertEqual(xml.attrib["tests"], "3")
        self.assertEqual(xml.attrib["skipped"], "2")
        self.assertEqual(len(xml.findall(".//skipped")), 2)
        self.assertTrue(all("Pixel assertions did not run" in node.attrib["message"]
                            for node in xml.findall(".//skipped")))

    def test_skip_markers_are_exact_and_limited_to_the_named_script(self):
        self.run_script("res://tests/test_unrelated.gd", SEGMENT_SKIP)
        self.run_script(SEGMENT, "prefix " + SEGMENT_SKIP)
        self.run_script(SKIN, SKIN_SKIP + " suffix")
        # Even a marker at a 64 KiB read boundary is not a whole line.
        self.run_script(SEGMENT, "x" * 65536 + SEGMENT_SKIP)
        items = collect_runs(self.collection)
        self.assertEqual(sum(item["reason"] == "passed" for item in items), 1)
        self.assertEqual(sum(item["reason"] == "invalid_report" for item in items), 3)
        self.assertFalse(any(item["skipped"] for item in items))

    def test_duplicate_mismatched_and_contradictory_skip_markers_are_invalid(self):
        self.run_script(SEGMENT, SEGMENT_SKIP + "\n" + SEGMENT_SKIP)
        self.run_script(SEGMENT, SKIN_SKIP)
        self.run_script(SKIN, SKIN_SKIP + "\nLighting skin patterns: 13 checks, 0 failed")
        self.run_script(SEGMENT, SEGMENT_SKIP + "\nFAIL dense-filter energy balance")
        self.run_script(SKIN, "ok   wave pixels match Patterns.sample\n" + SKIN_SKIP)
        items = collect_runs(self.collection)
        self.assertTrue(all(item["reason"] == "invalid_report" and not item["skipped"] for item in items), items)
        self.assertTrue(all("lighting" in item["detail"] for item in items), items)

    def test_pixel_execution_requires_one_complete_consistent_terminal_marker(self):
        # No output or missing marker cannot pass, even with a zero exit status.
        run_checked([sys.executable, "-c", "pass", "--script", SEGMENT], self.collection)
        cases = [
            (SEGMENT, "Godot startup complete"),
            (SEGMENT, "Lighting segment filter: 0 checks, 0 failed"),
            (SKIN, "Lighting skin patterns: 0 checks, 0 failed"),
            (SEGMENT, self.completed(SEGMENT, 11)),
            (SKIN, self.completed(SKIN, 12)),
            (SEGMENT, self.completed(SKIN, 13)),
            (SKIN, self.completed(SEGMENT, 12)),
            (SEGMENT, self.completed(SEGMENT, 12) + "\nLighting segment filter: 12 checks, 0 failed"),
            (SKIN, self.completed(SKIN, 13) + "\nok   late assertion"),
            (SEGMENT, self.completed(SEGMENT, 12) + "\nFAIL late assertion"),
            (SEGMENT, "Lighting segment filter: 12 checks, 0 failed"),
            (SKIN, self.completed(SKIN, 13).replace("13 checks, 0 failed", "13 checks, 1 failed")),
            (SKIN, self.completed(SKIN, 13) + "\nLighting skin patterns: malformed"),
            (SEGMENT, SEGMENT_SKIP + "\nLighting segment pixels SKIPPED: malformed"),
        ]
        for script, output in cases:
            self.run_script(script, output)
        items = collect_runs(self.collection)
        self.assertEqual(len(items), len(cases) + 1)
        self.assertTrue(all(item["reason"] == "invalid_report" and not item["skipped"] for item in items), items)

    def test_matching_completion_counts_can_grow_and_check_only_is_exempt(self):
        for script, count in ((SEGMENT, 12), (SKIN, 13), (SEGMENT, 15), (SKIN, 26)):
            self.run_script(script, self.completed(script, count))
        self.run_script(SEGMENT, "parse only", engine_args=("--check-only",))
        self.run_script(SKIN, "parse only", engine_args=("--check-only",))
        self.run_script(SKIN, "SCRIPT ERROR: parse failure", engine_args=("--check-only",))
        # A user argument cannot impersonate the engine's --check-only flag.
        self.run_script(SEGMENT, "no completion", user_args=("--check-only",))
        items = collect_runs(self.collection)
        self.assertEqual(sum(item["reason"] == "passed" for item in items), 6)
        self.assertEqual(sum(item["reason"] == "invalid_report" for item in items), 1)
        self.assertEqual(sum(item["reason"] == "engine_error" for item in items), 1)
        self.assertFalse(any(item["skipped"] for item in items))

    def test_skip_inspection_rechecks_size_and_hash(self):
        log = self.root / "pixel.log"
        original = (SEGMENT_SKIP + "\n").encode()
        digest = hashlib.sha256(original).hexdigest()
        command = ["godot", "--script", SEGMENT]
        log.write_bytes(original)
        self.assertEqual(pixel_skip(log, command, len(original), digest), SEGMENT_SKIP)
        for changed in (b"x" * len(original), original + b"extra"):
            with self.subTest(size=len(changed)):
                log.write_bytes(changed)
                with self.assertRaisesRegex(ValueError, "changed during skip inspection"):
                    pixel_skip(log, command, len(original), digest)

    def test_skip_marker_cannot_hide_failure_or_changed_log(self):
        self.run_script(SEGMENT, SEGMENT_SKIP + "\nSCRIPT ERROR: failed")
        self.run_script(SKIN, SKIN_SKIP, exit_code=3)
        self.run_script(SEGMENT, SEGMENT_SKIP, required=["Lighting segment filter: 12 checks, 0 failed"])
        run_checked([sys.executable, "-u", "-c", f"import time; print({SEGMENT_SKIP!r}); time.sleep(20)",
                     "--script", SEGMENT], self.collection, timeout=0.2)
        report = self.run_script(SKIN, SKIN_SKIP)
        Path(report["log"]).write_text(SKIN_SKIP + "\nchanged\n")
        items = collect_runs(self.collection)
        self.assertCountEqual([item["reason"] for item in items],
                              ["engine_error", "process_exit", "missing_required_text", "timeout", "invalid_report"])
        self.assertFalse(any(item["skipped"] for item in items))
        output = self.root / "failed-lighting.xml"
        write_junit(output, items)
        xml = ET.parse(output).getroot()
        self.assertEqual(xml.attrib["skipped"], "0")
        self.assertEqual(len(xml.findall(".//failure")) + len(xml.findall(".//error")), 5)

    def test_failure_reason_must_match_process_and_log(self):
        report = self.run_code("raise SystemExit(7)")
        self.change(report, reason="engine_error")
        self.assertEqual(collect_runs(self.collection)[0]["reason"], "invalid_report")

    def test_output_cannot_overwrite_log_or_older_junit(self):
        report = self.run_code("print('preserve')")
        items = collect_runs(self.collection)
        for path in (Path(report["log"]), self.root / "older.xml"):
            if not path.exists():
                path.write_text("original")
            before = path.read_bytes()
            with self.assertRaises(FileExistsError):
                write_junit(path, items)
            self.assertEqual(path.read_bytes(), before)

    def test_reader_limits_and_oversized_metadata(self):
        self.run_code("print('12345')")
        self.run_code("pass")
        with self.assertRaisesRegex(ValueError, "too many"):
            collect_runs(self.collection, max_runs=1)
        self.assertEqual(sum(i["reason"] == "invalid_report" for i in collect_runs(self.collection, max_log_bytes=2)), 1)
        report = self.run_code("pass")
        Path(report["report"]).write_bytes(b" " * (256 * 1024 + 1))
        self.assertIn("metadata limit", next(i for i in collect_runs(self.collection)
                                              if i["directory"] == Path(report["report"]).parent.name)["detail"])

    def test_collection_log_budget(self):
        self.run_code("print('12345')")
        self.run_code("print('12345')")
        with self.assertRaisesRegex(ValueError, "max-total-log-bytes"):
            collect_runs(self.collection, max_total_log_bytes=10)
        self.assertTrue(all(i["ok"] for i in collect_runs(self.collection, max_total_log_bytes=14)))

    def test_control_characters_are_safe_xml(self):
        self.run_code("print('ERROR: null \\x00 text')", label="bad\x01label")
        output = self.root / "results.xml"
        write_junit(output, collect_runs(self.collection))
        self.assertIn("null \ufffd text", ET.parse(output).find(".//failure").text)

    def test_aggregate_duration_cannot_publish_infinity(self):
        for _ in range(2):
            report = self.run_code("pass")
            self.change(report, elapsed_seconds=1e308)
        output = self.root / "results.xml"
        with self.assertRaisesRegex(ValueError, "aggregate elapsed"):
            write_junit(output, collect_runs(self.collection))
        self.assertFalse(output.exists())

    def test_linked_log_is_rejected(self):
        report = self.run_code("pass")
        link = Path(report["log"])
        link.unlink()
        target = self.root / "external.log"
        target.touch()
        try:
            link.symlink_to(target)
        except OSError:
            self.skipTest("host does not permit unprivileged symlinks")
        self.assertEqual(collect_runs(self.collection)[0]["reason"], "invalid_report")

    def test_cli_exit_and_new_junit(self):
        self.run_code("raise SystemExit(7)")
        output = self.root / "results.xml"
        command = [sys.executable, str(Path(__file__).with_name("summarize.py")), str(self.collection),
                   "--junit", str(output)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("1 failed or invalid", result.stdout)
        self.assertEqual(ET.parse(output).find(".//failure").get("type"), "process_exit")
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stderr)

    @unittest.skipUnless(os.name == "nt", "Windows directory junction")
    def test_junction_run_directory_is_rejected(self):
        report = self.run_code("pass")
        target = self.root / "outside-run"
        Path(report["report"]).parent.rename(target)
        junction = self.collection / "linked-run"
        result = subprocess.run(["cmd.exe", "/c", "mklink", "/J", str(junction), str(target)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(junction.is_symlink())
        self.assertEqual(collect_runs(self.collection)[0]["reason"], "invalid_report")


if __name__ == "__main__":
    unittest.main()
