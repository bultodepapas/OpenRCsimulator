"""Guard measurement provenance with disposable in-memory fault fixtures."""
import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import refinement_report as report


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.read_text = Path.read_text
        # These are deliberate synthetic manifests for testing the report reader,
        # never saved as observations or substituted into retained bench outputs.
        self.runs = {path: json.loads(path.read_text(encoding="utf-8"))
                     for path in report.RUNS.values()}
        for value in self.runs.values():
            value["format"] = "openrc-glow-flight-experiment v3"
            value["source_sha256"] = {p: "f" * 64 for p in report.SOURCE_PATHS}
            for run in value["runs"]:
                run.setdefault("mode_events", [])

    def fixture(self):
        def read(path, *args, **kwargs):
            if path in self.runs:
                return json.dumps(self.runs[path])
            return self.read_text(path, *args, **kwargs)
        return patch.object(Path, "read_text", read)

    def test_matching_recorded_manifests_are_accepted(self):
        with self.fixture():
            runs, metadata = report.read_runs()
        self.assertEqual(set(runs), {240, 480, 960})
        self.assertEqual(len(metadata), 36)

    def test_changed_source_between_rates_is_rejected(self):
        self.runs[report.RUNS[480]]["source_sha256"][report.SOURCE_PATHS[0]] = "a" * 64
        with self.fixture(), self.assertRaisesRegex(ValueError, "identical.*source snapshots"):
            report.read_runs()

    def test_missing_or_malformed_hash_is_rejected(self):
        original = copy.deepcopy(self.runs)
        for invalid in ("", "not-a-sha", "G" * 64):
            self.runs = copy.deepcopy(original)
            self.runs[report.RUNS[240]]["source_sha256"][report.SOURCE_PATHS[0]] = invalid
            with self.fixture(), self.assertRaisesRegex(ValueError, "runtime source manifest"):
                report.read_runs()
        self.runs = copy.deepcopy(original)
        self.runs[report.RUNS[240]]["source_sha256"].pop(report.SOURCE_PATHS[0])
        with self.fixture(), self.assertRaisesRegex(ValueError, "runtime source manifest"):
            report.read_runs()

    def test_report_keeps_recorded_source_hashes(self):
        with self.fixture():
            built = report.build()
        self.assertEqual({row["sha256"] for row in built["source_hashes"]}, {"f" * 64})

    def test_lifecycle_event_order_and_tick_brackets_are_checked(self):
        event = dict(kind="accepted_step", lower_time_s=0.5, upper_time_s=0.5 + 1 / 240,
                     from_running=True, from_reason=0, to_running=False, to_reason=4)
        fine = dict(event, upper_time_s=0.5 + 1 / 960)
        self.assertTrue(report.compare_mode_events({"mode_events": [event]}, {"mode_events": [fine]}, 240)["passes_budget"])
        self.assertFalse(report.compare_mode_events({"mode_events": [event]}, {"mode_events": []}, 240)["passes_budget"])
        late = dict(fine, lower_time_s=0.6, upper_time_s=0.6 + 1 / 960)
        self.assertFalse(report.compare_mode_events({"mode_events": [event]}, {"mode_events": [late]}, 240)["passes_budget"])
        with self.assertRaisesRegex(ValueError, "time bracket"):
            report.mode_events({"mode_events": [dict(event, upper_time_s=0.6)]}, 240)
        with self.assertRaisesRegex(ValueError, "missing"):
            report.mode_events({}, 240)


if __name__ == "__main__":
    unittest.main()
