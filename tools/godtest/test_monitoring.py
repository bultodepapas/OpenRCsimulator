"""A functional run must not turn missing CPU/GPU evidence into a clean screen."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from analysis import hardware_report, report
from runner import write_json
from test_godtest import artifacts


class MonitoringTests(unittest.TestCase):
    def _resources(self, path):
        value = {"format": "openrc-resource-samples v1", "identity_status": "verified", "pid": 1234,
                 "measurement_status": "ok", "required_coverage": "complete", "sample_count": 2,
                 "samples": [{"elapsed_seconds": 0, "cpu_user_seconds": 1, "cpu_system_seconds": 1, "rss_bytes": 1024},
                             {"elapsed_seconds": 2, "cpu_user_seconds": 3, "cpu_system_seconds": 2, "rss_bytes": 2048}],
                 "summary": {"peaks": {"cpu_percent": 150}}, "errors": []}
        write_json(path / "resources.json", value)
        return value

    def _receipt(self, path):
        return {"launch": {"pid": 1234}, "resource_sampling": True, "gpu_sampling": True,
                "resource_sampler_source_sha256": "b" * 64, "resource_sampler_source_changed": False,
                "orchestrator_sources": {"hardware.py": "c" * 64},
                **{key + "_sha256": hashlib.sha256((path / (key + ".json")).read_bytes()).hexdigest()
                   for key in ("resources", "gpu") if (path / (key + ".json")).exists()}}

    def _gpu(self, path):
        identity = {"key": "fixture:device", "name": "Test GPU"}
        samples = []
        for start, utilization in ((0, 25), (1_000_000, 75)):
            device = {"identity": identity, "metrics": {"gpu_utilization_pct": utilization},
                      "metric_status": {"gpu_utilization_pct": "available"}}
            backend = {"backend": "fixture", "status": "available", "devices": [device],
                       "start_monotonic_usec": start, "end_monotonic_usec": start + 1000}
            samples.append({"start_monotonic_usec": start, "end_monotonic_usec": start + 1000, "backends": [backend]})
        value = {"format": "openrc-godtest-gpu-v1", "status": "available", "source_sha256": "c" * 64,
                 "source_end_sha256": "c" * 64, "source_changed": False, "thread_alive": False,
                 "sample_cap_reached": False, "worker_exit_reason": "owner_stopped", "interval_seconds": 1,
                 "start_monotonic_usec": 0, "stop_requested_monotonic_usec": 2_000_000,
                 "timing_coverage": {"status": "complete"}, "sample_count": 2, "samples": samples,
                 "summary_by_device": {identity["key"]: {"identity": identity, "backend": "fixture", "samples": 2,
                     "metrics": {"gpu_utilization_pct": {"count": 2, "min": 25, "max": 75, "mean": 50}}}}}
        write_json(path / "gpu.json", value)
        return value

    def test_complete_monitoring_requires_usable_raw_gpu_observations(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            self._resources(path)
            self._gpu(path)
            _, gpu, monitoring = hardware_report(path, self._receipt(path), True)
            self.assertTrue(monitoring["complete"], monitoring["issues"])
            self.assertEqual(gpu["summary_by_device"]["fixture:device"]["metrics"]["gpu_utilization_pct"]["mean"], 50)

    def test_available_label_cannot_hide_missing_samples_changed_source_or_false_summary(self):
        for fault in ("empty", "one", "source_changed", "source_unknown", "source_mismatch", "clock", "gap", "summary", "identity", "utilization", "coverage"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary)
                self._resources(path)
                value = self._gpu(path)
                if fault in ("empty", "one"):
                    value["samples"] = value["samples"][:0 if fault == "empty" else 1]
                    value["sample_count"] = len(value["samples"])
                elif fault == "source_changed": value["source_changed"] = True
                elif fault == "source_unknown": value.pop("source_changed")
                elif fault == "source_mismatch": value["source_sha256"] = "d" * 64
                elif fault == "clock": value["samples"][1]["start_monotonic_usec"] = 0
                elif fault == "gap": value["stop_requested_monotonic_usec"] = 9_000_000
                elif fault == "summary": value["summary_by_device"]["fixture:device"]["metrics"]["gpu_utilization_pct"]["mean"] = 0
                elif fault == "identity": value["samples"][1]["backends"][0]["devices"][0]["identity"] = {"key": "wrong:device"}
                elif fault == "utilization": value["samples"][1]["backends"][0]["devices"][0]["metrics"]["gpu_utilization_pct"] = None
                else: value["timing_coverage"]["status"] = "incomplete"
                write_json(path / "gpu.json", value)
                resources, gpu, monitoring = hardware_report(path, self._receipt(path), True)
                self.assertFalse(monitoring["complete"])
                self.assertEqual(resources["status"], "ok")
                self.assertEqual(gpu["status"], "unavailable")

    def test_unknown_or_changed_cpu_observer_prevents_complete_monitoring(self):
        for changed in (None, True):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary)
                self._resources(path)
                self._gpu(path)
                receipt = dict(self._receipt(path), resource_sampler_source_changed=changed)
                resources, _, monitoring = hardware_report(path, receipt, True)
                self.assertFalse(monitoring["complete"])
                self.assertEqual(resources["status"], "unavailable")

    def test_unavailable_gpu_preserves_process_evidence_without_complete_monitoring(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            self._resources(path)
            write_json(path / "gpu.json", {"format": "openrc-godtest-gpu-v1", "status": "unavailable", "summary_by_device": {}})
            resources, gpu, monitoring = hardware_report(path, self._receipt(path), True)
            self.assertEqual(resources["cpu_percent_mean"], 150)
            self.assertEqual(resources["rss_delta_bytes"], 1024)
            self.assertEqual(gpu["status"], "unavailable")
            self.assertFalse(monitoring["complete"])

    def test_changed_artifact_pid_reuse_and_counter_reset_are_not_accepted(self):
        for fault in ("hash", "pid", "counter"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary)
                value = self._resources(path)
                receipt = self._receipt(path)
                if fault == "pid":
                    value["pid"] = 2222
                else:
                    value["samples"][-1]["cpu_user_seconds"] = 0
                write_json(path / "resources.json", value)
                if fault != "hash":
                    receipt = self._receipt(path)
                resources, _, monitoring = hardware_report(path, receipt, True)
                self.assertFalse(monitoring["complete"])
                self.assertEqual(resources["status"], "unavailable")

    def test_missing_hardware_does_not_erase_valid_frames_or_claim_performance(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path)
            manifest = json.loads((path / "manifest.resolved.json").read_text())
            manifest["monitor_hardware"] = True
            write_json(path / "manifest.resolved.json", manifest)
            result = report(path)
            self.assertEqual(result["data"], "valid")
            self.assertEqual(result["coverage"], "complete")
            self.assertEqual(result["performance"], "not_qualified")
            self.assertFalse(result["monitoring"]["complete"])
            self.assertIn("unavailable", (path / "report.html").read_text())

    def test_software_renderer_is_not_target_gpu_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "run"
            artifacts(path)
            runtime = json.loads((path / "runtime.json").read_text())
            runtime["identity"]["diagnostics"]["adapter_name"] = "llvmpipe (LLVM)"
            write_json(path / "runtime.json", runtime)
            result = report(path)
            self.assertEqual(result["performance"], "not_qualified")
            self.assertTrue(any("software renderer" in issue for issue in result["issues"]))


if __name__ == "__main__":
    unittest.main()
