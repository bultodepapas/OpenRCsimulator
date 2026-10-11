#!/usr/bin/env python3
"""Regression controls for the exact maneuver evidence comparator (synthetic reports)."""
import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from compare_envelope import DURATIONS, compare, digest


class EnvelopeComparison(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.old = Path(self.temp.name) / "old"
        self.new = Path(self.temp.name) / "new"
        (self.old / "cases").mkdir(parents=True)
        report = {"format": "openrc-el2a-e1-envelope-v1", "ok": True, "cases": [],
                  "refinement": [0] * 22, "godot_version": "fixture", "godot_sha256": "engine",
                  "driver_sha256": "driver", "verifier_sha256": "verifier", "checked_rows": 0}
        for pack in ("4s", "6s"):
            for maneuver, duration in DURATIONS.items():
                for hz in (240, 480):
                    name = f"{pack}_{maneuver}_{hz}"
                    rows = duration * hz + 1
                    raw = b"# created_utc: fixture\n# format: fixture\ntick,value\n" + b"0,0\n" * rows
                    (self.old / "cases" / f"{name}.csv").write_bytes(raw)
                    report["cases"].append({"name": name, "flight": {"passed": True, "completed": True,
                        "trace": {"row_count": rows, "path": "old-location"}, "metric": 0},
                        "electrical": {"rows": rows, "trace_sha256": digest(raw), "metric": 0}})
                    report["checked_rows"] += rows
        (self.old / "report.json").write_text(json.dumps(report))
        shutil.copytree(self.old, self.new)
        self.report = copy.deepcopy(report)

    def save(self):
        (self.new / "report.json").write_text(json.dumps(self.report))

    def test_exact_copy_and_only_artifact_differences(self):
        self.assertTrue(compare(self.old, self.new)["ok"])
        case = self.report["cases"][0]
        path = self.new / "cases" / (case["name"] + ".csv")
        raw = path.read_bytes().replace(b"created_utc: fixture", b"created_utc: later")
        path.write_bytes(raw)
        case["electrical"]["trace_sha256"] = digest(raw)
        case["flight"]["trace"]["path"] = "new-location"
        self.save()
        self.assertTrue(compare(self.old, self.new)["ok"])

    def test_changed_sample_rejected_even_with_updated_hash(self):
        case = self.report["cases"][0]
        path = self.new / "cases" / (case["name"] + ".csv")
        raw = path.read_bytes().replace(b"0,0\n", b"0,1\n", 1)
        path.write_bytes(raw)
        case["electrical"]["trace_sha256"] = digest(raw)
        self.save()
        with self.assertRaisesRegex(ValueError, "telemetry/metadata differs"):
            compare(self.old, self.new)

    def test_corrupted_trace(self):
        path = self.new / "cases" / (self.report["cases"][0]["name"] + ".csv")
        path.write_bytes(path.read_bytes() + b"0,0\n")
        with self.assertRaisesRegex(ValueError, "corrupted trace"):
            compare(self.old, self.new)

    def test_incomplete_or_duplicate_cases(self):
        self.report["cases"][-1] = self.report["cases"][0]
        self.save()
        with self.assertRaisesRegex(ValueError, "incomplete/duplicate"):
            compare(self.old, self.new)

    def test_failed_verification(self):
        self.report["ok"] = False
        self.save()
        with self.assertRaisesRegex(ValueError, "did not pass"):
            compare(self.old, self.new)

    def test_changed_metrics(self):
        self.report["cases"][0]["flight"]["metric"] = 1
        self.save()
        with self.assertRaisesRegex(ValueError, "metrics differ"):
            compare(self.old, self.new)

    def test_different_engine(self):
        self.report["godot_sha256"] = "another engine"
        self.save()
        with self.assertRaisesRegex(ValueError, "changed godot_sha256"):
            compare(self.old, self.new)

    def test_boolean_cannot_replace_numeric_metric(self):
        self.report["cases"][0]["flight"]["metric"] = False
        self.save()
        with self.assertRaisesRegex(ValueError, "metrics differ"):
            compare(self.old, self.new)


if __name__ == "__main__":
    unittest.main()
