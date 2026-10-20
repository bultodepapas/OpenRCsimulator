"""PT1h-R2: collection integrity and standard JUnit evidence, without Godot."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

from run_checked import run_checked
from summarize import collect_runs, write_junit


class SummaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc summary ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.collection = self.root / "runs"
        self.collection.mkdir()

    def run_code(self, code, **options):
        return run_checked([sys.executable, "-c", code], self.collection, **options)

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

    def test_control_characters_are_safe_xml(self):
        self.run_code("print('ERROR: null \\x00 text')", label="bad\x01label")
        output = self.root / "results.xml"
        write_junit(output, collect_runs(self.collection))
        self.assertIn("null \ufffd text", ET.parse(output).find(".//failure").text)

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


if __name__ == "__main__":
    unittest.main()
