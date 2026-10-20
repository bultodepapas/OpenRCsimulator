"""Focused validation tests for lifecycle_check's report contract and CLI."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

try:
    from . import lifecycle_check as checker
except ImportError:  # unittest discovery from tools/godot
    import lifecycle_check as checker


CAPTURE_ID = "runner-capture-123"
CONFIG = {
    "scenario": "both",
    "cycles": 3,
    "warmup_cycles": 1,
    "settle_frames": 8,
    "dwell_seconds": 0.25,
}
IDENTITY = {"label": "retired fixture", "id": "object-7", "class": "Node", "script": "res://fixture.gd"}
MIB = 1024 * 1024


def make_report(*, node_counts=None, orphan_counts=None, object_counts=None,
                resource_counts=None, memory_bytes=None, config=None) -> dict:
    config = copy.deepcopy(config or CONFIG)
    sample_count = config["cycles"] + 1
    node_counts = node_counts or [100] * sample_count
    orphan_counts = orphan_counts or [0] * sample_count
    object_counts = object_counts or [300] * sample_count
    resource_counts = resource_counts or [30] * sample_count
    memory_bytes = memory_bytes or [8 * 1024 * 1024] * sample_count
    samples = []
    for index in range(sample_count):
        samples.append({
            "phase": "home_baseline" if index == 0 else "home_settled",
            "cycle": index,
            "monotonic_usec": 1000 + index * 1000,
            "node_count": node_counts[index],
            "orphan_node_count": orphan_counts[index],
            "object_count": object_counts[index],
            "resource_count": resource_counts[index],
            "static_memory_bytes": memory_bytes[index],
            "retired_objects_checked": index,
            "retired_objects_alive": [],
            "orphan_details": [],
            "orphan_details_truncated": False,
            "sample_overhead_usec": 20,
        })
    return {
        "format": checker.FORMAT,
        "capture_id": CAPTURE_ID,
        "complete": True,
        "failure": "",
        "config": config,
        "debug_build": False,
        "samples": samples,
        "cleanup": {
            "retired_objects_checked": 3,
            "retired_objects_alive": [],
            "complete": True,
        },
        "total_retired_alive": 0,
    }


class LifecycleAnalysisTests(unittest.TestCase):
    def analyze(self, report, **options):
        return checker.analyze_report(report, CAPTURE_ID, CONFIG, **options)

    def test_flat_counts_pass(self):
        result = self.analyze(make_report())
        self.assertTrue(result["complete"])
        self.assertTrue(result["ok"])
        self.assertEqual(result["findings"], [])
        self.assertEqual(result["metrics"]["max_node_growth"], 0)

    def test_baseline_counts_after_warmup_can_be_large_without_growth(self):
        report = make_report(node_counts=[900, 900, 900, 900],
                             object_counts=[12000, 12000, 12000, 12000])
        result = self.analyze(report)
        self.assertTrue(result["ok"], result["findings"])
        self.assertEqual(result["metrics"]["baseline_cycle"], 0)

    def test_one_node_per_cycle_fails_against_baseline(self):
        result = self.analyze(make_report(node_counts=[100, 101, 102, 103]))
        self.assertFalse(result["ok"])
        self.assertTrue(any(item.startswith("node_growth:") for item in result["findings"]))
        self.assertEqual(result["metrics"]["max_node_growth"], 3)

    def test_retired_alive_object_fails_when_global_counts_are_flat(self):
        report = make_report()
        report["samples"][1]["retired_objects_alive"] = [copy.deepcopy(IDENTITY)]
        report["total_retired_alive"] = 1
        result = self.analyze(report)
        self.assertFalse(result["ok"])
        self.assertTrue(any(item.startswith("retired_objects_alive:") for item in result["findings"]))

    def test_object_resource_and_memory_trends_are_informational_by_default(self):
        report = make_report(object_counts=[300, 305, 310, 315],
                             resource_counts=[30, 31, 32, 33],
                             memory_bytes=[8 * 1024 * 1024, 9 * 1024 * 1024,
                                           10 * 1024 * 1024, 11 * 1024 * 1024])
        result = self.analyze(report)
        self.assertTrue(result["ok"], result["findings"])
        self.assertEqual(result["metrics"]["max_object_growth"], 15)
        self.assertEqual(result["metrics"]["max_resource_growth"], 3)
        self.assertEqual(result["metrics"]["max_static_memory_growth_mib"], 3)

    def test_optional_static_memory_budget_gates_growth(self):
        report = make_report(memory_bytes=[0, MIB, MIB, MIB])
        over = self.analyze(report, max_static_growth_mib=0.5)
        within = self.analyze(report, max_static_growth_mib=1.0)
        self.assertFalse(over["ok"])
        self.assertTrue(any(item.startswith("static_memory_growth:") for item in over["findings"]))
        self.assertTrue(within["ok"], within["findings"])

    def test_incomplete_prefix_is_diagnostic_and_never_passes(self):
        report = make_report()
        report["samples"] = report["samples"][:2]
        report["complete"] = False
        report["failure"] = "injected timeout"
        result = self.analyze(report)
        self.assertFalse(result["complete"])
        self.assertFalse(result["ok"])
        self.assertFalse(any(item.startswith("invalid_report:") for item in result["findings"]))
        self.assertTrue(any(item.startswith("probe_incomplete:") for item in result["findings"]))

    def test_invalid_identity_schema_is_rejected(self):
        report = make_report()
        report["samples"][1]["orphan_details"] = [{"id": "missing other identity fields"}]
        result = self.analyze(report)
        self.assertFalse(result["ok"])
        self.assertTrue(any(item.startswith("invalid_report:") for item in result["findings"]))

    def test_mismatched_ids_nonfinite_values_timestamps_and_sample_count_are_rejected(self):
        cases = []
        cases.append((make_report(), "wrong-run-id", CONFIG, "capture id"))
        nan_report = make_report()
        nan_report["samples"][1]["static_memory_bytes"] = float("nan")
        cases.append((nan_report, CAPTURE_ID, CONFIG, "nonnegative bounded integer"))
        timestamp_report = make_report()
        timestamp_report["samples"][2]["monotonic_usec"] = timestamp_report["samples"][1]["monotonic_usec"]
        cases.append((timestamp_report, CAPTURE_ID, CONFIG, "increase strictly"))
        short_report = make_report()
        short_report["samples"].pop()
        cases.append((short_report, CAPTURE_ID, CONFIG, "exactly 4 samples"))
        bad_config = dict(CONFIG, settle_frames=1000)
        cases.append((make_report(), CAPTURE_ID, bad_config, "expected_config.settle_frames"))
        for report, capture_id, config, expected_text in cases:
            with self.subTest(expected_text=expected_text):
                result = checker.analyze_report(report, capture_id, config)
                self.assertFalse(result["ok"])
                self.assertTrue(any(expected_text in item for item in result["findings"]), result["findings"])

    def test_json_loader_rejects_duplicate_keys_and_nonfinite_literals(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "lifecycle.json"
            for content in ('{"format":"one","format":"two"}', '{"value":NaN}'):
                with self.subTest(content=content):
                    path.write_text(content, encoding="utf-8")
                    with self.assertRaises(ValueError):
                        checker.load_report(path)


class LifecycleCliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lifecycle checker ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.godot = self.root / "godot.exe"
        self.godot.write_bytes(b"fake executable")
        self.probe = self.root / "lifecycle_probe.gd"
        self.probe.write_text("# command construction fixture\n", encoding="utf-8")
        self.probe_patch = mock.patch.object(checker, "PROBE_SCRIPT", self.probe)
        self.probe_patch.start()
        self.addCleanup(self.probe_patch.stop)

    def args(self, **overrides):
        values = {
            "godot": self.godot,
            "out_dir": self.root / "runs",
            "scenario": "both",
            "cycles": 3,
            "warmup_cycles": 1,
            "settle_frames": 8,
            "dwell_seconds": 0.25,
            "timeout": 300.0,
            "max_node_growth": 0,
            "max_orphan_growth": 0,
            "max_static_growth_mib": None,
            "resources": False,
        }
        values.update(overrides)
        return checker.argparse.Namespace(**values)

    @staticmethod
    def runner_with_report(*, ok=True, reason="passed"):
        def run(command, *, out_dir, timeout, label, resources):
            output_arg = next(item for item in command if item.startswith("--out-dir="))
            probe_dir = Path(output_arg.split("=", 1)[1])
            probe_dir.mkdir()
            values = {item.split("=", 1)[0]: item.split("=", 1)[1]
                      for item in command if item.startswith(("--scenario=", "--cycles=",
                                                              "--warmup-cycles=", "--settle-frames=",
                                                              "--dwell-seconds="))}
            config = {
                "scenario": values["--scenario"],
                "cycles": int(values["--cycles"]),
                "warmup_cycles": int(values["--warmup-cycles"]),
                "settle_frames": int(values["--settle-frames"]),
                "dwell_seconds": float(values["--dwell-seconds"]),
            }
            report = make_report(config=config)
            report["capture_id"] = CAPTURE_ID
            (probe_dir / "lifecycle.json").write_text(json.dumps(report), encoding="utf-8")
            checked_dir = Path(out_dir) / "fake-run"
            checked_dir.mkdir(parents=True)
            log = checked_dir / "engine.log"
            log.write_text("phase: settled\n", encoding="utf-8")
            runner_report = checked_dir / "report.json"
            runner_report.write_text("{}", encoding="utf-8")
            return {
                "ok": ok,
                "complete": True,
                "reason": reason,
                "process_exit": 0,
                "capture_id": CAPTURE_ID,
                "report": str(runner_report),
                "log": str(log),
            }
        return run

    def test_runner_failure_cannot_be_masked_by_a_passing_probe(self):
        code, summary = checker.run_lifecycle(
            self.args(), runner=self.runner_with_report(ok=False, reason="engine_error"))
        self.assertEqual(code, 1)
        self.assertTrue(summary["complete"])
        self.assertFalse(summary["ok"])
        self.assertTrue(any(item.startswith("engine_check_failed:") for item in summary["findings"]))
        summary_path = next((self.root / "runs").glob("run-*/summary.json"))
        saved = json.loads(summary_path.read_text(encoding="utf-8"))
        self.assertEqual(saved["probe_report"], "probe/lifecycle.json")
        self.assertEqual(saved["engine"]["log"], "checked/fake-run/engine.log")

    def test_command_uses_headless_dummy_audio_direct_exe_and_fresh_probe_path(self):
        observed = {}

        def runner(command, *, out_dir, timeout, label, resources):
            observed.update(command=command, out_dir=Path(out_dir), timeout=timeout,
                            label=label, resources=resources)
            return self.runner_with_report()(command, out_dir=out_dir, timeout=timeout,
                                             label=label, resources=resources)

        code, summary = checker.run_lifecycle(
            self.args(scenario="flight", cycles=2, resources=True), runner=runner)
        self.assertEqual(code, 0, summary)
        command = observed["command"]
        self.assertEqual(command[0], str(self.godot.resolve()))
        self.assertEqual(command[1:6], ["--headless", "--path", str(checker.APP_DIR),
                                        "--audio-driver", "Dummy"])
        self.assertIn("--max-fps", command)
        self.assertIn("--script", command)
        self.assertIn("--scenario=flight", command)
        self.assertIn("--cycles=2", command)
        self.assertTrue(Path(next(item.split("=", 1)[1] for item in command
                                  if item.startswith("--out-dir="))).is_dir())
        self.assertTrue(observed["resources"])

    def test_invalid_configuration_and_output_path_do_not_start_process(self):
        runner = mock.Mock(side_effect=AssertionError("runner must not start"))
        code, _ = checker.run_lifecycle(self.args(max_node_growth=10_001), runner=runner)
        self.assertEqual(code, 2)
        runner.assert_not_called()

        blocked = self.root / "not-a-directory"
        blocked.write_text("preserve", encoding="utf-8")
        code, _ = checker.run_lifecycle(self.args(out_dir=blocked), runner=runner)
        self.assertEqual(code, 2)
        runner.assert_not_called()
        self.assertEqual(blocked.read_text(encoding="utf-8"), "preserve")

    def test_console_executable_is_rejected_before_process_start(self):
        console = self.root / "godot_console.exe"
        console.write_bytes(b"console executable")
        runner = mock.Mock(side_effect=AssertionError("runner must not start"))
        code, _ = checker.run_lifecycle(self.args(godot=console), runner=runner)
        self.assertEqual(code, 2)
        runner.assert_not_called()


if __name__ == "__main__":
    unittest.main()
