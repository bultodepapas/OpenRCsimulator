from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "godot"))

from research.performance import sustained_resources as reducer
from research.performance.test_native_summary import save_benchmark_report, write_backend_benchmark_run
from test_perfetto_export import resource_report
from test_macos_host_state import raw_rows, encode as host_encode


def encoded(value):
    return (json.dumps(value, allow_nan=False) + "\n").encode()


class ResourceFixture:
    """A checked v3 flight plus independent one-second cumulative CPU polls."""

    def __init__(self, directory: Path):
        self.root = directory
        self.run, self.health_path, health = write_backend_benchmark_run(directory, "run-1", "native", long=True)
        frame = json.loads(self.run.read_text())
        self.capture_id = frame["capture_id"]
        frame["pid"] = 42
        base = 1_700_000_000_000_000
        clock_end = frame["clock"]["end"]["monotonic_usec"]
        frame["clock"] = {"source": "godot_ticks_usec", "origin_usec": 0,
                          "start": {"monotonic_usec": 900_000, "unix_usec": base + 900_000, "uncertainty_usec": 20_000},
                          "end": {"monotonic_usec": clock_end, "unix_usec": base + clock_end, "uncertainty_usec": 20_000}}
        save_benchmark_report(self.run, health, frame)
        self.health_path.write_text(json.dumps(health))
        self.checked_path = directory / "checked-run-1.json"
        self.checked = json.loads(self.checked_path.read_text())
        self.checked.update(report="/evidence/checks/godot-fixture/report.json",
                            log="/evidence/checks/godot-fixture/engine.log", cwd="/frozen",
                            started_utc="2023-11-14T22:13:20+00:00", elapsed_seconds=56.0)
        self.capture = directory / "checks" / "godot-fixture"
        self.capture.mkdir(parents=True)
        (self.capture / "engine.log").write_bytes(self.run.with_suffix(".log").read_bytes())
        rc = {"source": "python_perf_counter", "origin_usec": 0,
              "start": {"monotonic_usec": 0, "unix_usec": base, "uncertainty_usec": 20_000},
              "end": {"monotonic_usec": 56_000_000, "unix_usec": base + 56_000_000, "uncertainty_usec": 20_000}}
        self.resource = resource_report(capture_id=self.capture_id, clock=rc, elapsed=tuple(range(56)))
        self.resource.update(pid=42, process_create_time=1_700_000_000.0, identity_status="verified",
                             interval_seconds=1.0, max_samples=100, required_coverage="complete",
                             summary={"counter_resets": []},
                             tool_source_sha256={"run_checked.py": "a" * 64, "resource_samples.py": "b" * 64})
        for sample in self.resource["samples"]:
            sample["poll_overhead_usec"] = 1000
        self.resource["required_field_counts"] = {field: 56 for field in (
            "rss_bytes", "cpu_user_seconds", "cpu_system_seconds", "virtual_memory_available_bytes")}
        self.resource["invocation"] = {k: self.checked[k] for k in (
            "capture_id", "command", "cwd", "started_utc", "process_exit", "reason", "log_sha256", "elapsed_seconds")}
        self.save_resource()

    def save_resource(self):
        raw = encoded(self.resource)
        (self.capture / "resources.json").write_bytes(raw)
        self.checked["resources"] = {"file": "resources.json", "published": True,
                                     "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
                                     **{key: self.resource[key] for key in (
                                         "coverage", "required_coverage", "sample_count", "measurement_status", "summary")}}
        self.save_checked()

    def save_checked(self):
        raw = encoded(self.checked)
        self.checked_path.write_bytes(raw)
        (self.capture / "report.json").write_bytes(raw)


class SustainedResourcesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.fixture = ResourceFixture(Path(self.temp.name))

    def test_full_checked_flight_uses_cumulative_cpu_and_interior_polls(self):
        result = reducer.reduce_run(self.fixture.run)
        self.assertEqual(result["backend"], "native")
        self.assertAlmostEqual(result["cpu"]["percent_of_one_core"], 6.0)
        self.assertNotEqual(result["cpu"]["percent_of_one_core"], 60.0)  # synthetic cpu_percent is deliberately wrong
        self.assertLess(result["window"]["selected_wall_fraction_of_frame_window"], 1.0)
        self.assertGreater(result["window"]["omitted_frame_start_usec_upper_bound"], 0)
        self.assertGreater(result["window"]["omitted_frame_end_usec_upper_bound"], 0)
        self.assertEqual(result["window"]["requested_poll_interval_seconds"], 1.0)
        self.assertEqual(result["host_state"]["status"], "unknown")
        self.assertIsNone(result["host_state"]["memory_pressure"]["events"])
        self.assertEqual(result["process_memory"]["footprint_bytes"]["status"], "unknown")

    def test_original_receipt_and_bytes_cannot_be_replaced_or_tampered(self):
        path = self.fixture.capture / "resources.json"
        path.write_bytes(path.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "original checked receipt"):
            reducer.reduce_run(self.fixture.run)
        self.fixture.save_resource()
        nested = self.fixture.capture / "report.json"
        nested.write_bytes(nested.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "differs from original nested"):
            reducer.reduce_run(self.fixture.run)

    def test_wrong_capture_id_pid_and_create_time_fail(self):
        for field, value, message in (("capture_id", "wrong", "invocation"),
                                      ("pid", 43, "PID"),
                                      ("process_create_time", 1_699_990_000.0, "creation time")):
            with self.subTest(field=field):
                original = copy.deepcopy(self.fixture.resource)
                self.fixture.resource[field] = value
                self.fixture.save_resource()
                with self.assertRaisesRegex(ValueError, message):
                    reducer.reduce_run(self.fixture.run)
                self.fixture.resource = original
                self.fixture.save_resource()

    def test_cpu_reset_missing_status_and_counter_gaps_fail(self):
        for change in ("reset", "missing", "identity", "capped", "poll_gap"):
            with self.subTest(change=change):
                original = copy.deepcopy(self.fixture.resource)
                q = self.fixture.resource
                if change == "reset":
                    q["samples"][15]["cpu_user_seconds"] = 0.0
                elif change == "missing":
                    q["samples"][15]["cpu_system_seconds"] = None
                    q["samples"][15]["field_status"]["cpu_system_seconds"] = "unavailable"
                    q["required_field_counts"]["cpu_system_seconds"] -= 1
                    q["required_coverage"] = "partial"
                elif change == "identity":
                    q["identity_status"] = "reused"
                elif change == "capped":
                    q.update(capped=True, coverage="capped", stop_reason="sample_limit", required_coverage="capped")
                else:
                    for sample in q["samples"][15:]:
                        sample["elapsed_seconds"] += 3
                    q["clock"]["end"].update(monotonic_usec=59_000_000, unix_usec=1_700_000_059_000_000)
                self.fixture.save_resource()
                with self.assertRaises(ValueError):
                    reducer.reduce_run(self.fixture.run)
                self.fixture.resource = original
                self.fixture.save_resource()

    def test_unavailable_optional_memory_is_unknown_not_zero(self):
        q = self.fixture.resource
        for sample in q["samples"]:
            sample["swap_used_bytes"] = None
            sample["field_status"]["swap_used_bytes"] = "unsupported"
            sample["rss_bytes"] = None
            sample["field_status"]["rss_bytes"] = "unsupported"
        q["required_field_counts"]["rss_bytes"] = 0
        q["required_coverage"] = "partial"
        self.fixture.save_resource()
        result = reducer.reduce_run(self.fixture.run)
        swap = result["host_memory"]["swap_used_bytes"]
        self.assertEqual(swap["status"], "unknown")
        self.assertIsNone(swap["sampled_peak"])
        self.assertEqual(result["process_memory"]["rss_bytes"]["status"], "unknown")
        self.assertIsNone(result["process_memory"]["rss_bytes"]["end_minus_start"])

    def test_cpu_percent_can_exceed_one_hundred(self):
        for index, sample in enumerate(self.fixture.resource["samples"]):
            sample["cpu_user_seconds"] = index * 2.0
            sample["cpu_system_seconds"] = index * 0.1
        self.fixture.save_resource()
        self.assertAlmostEqual(reducer.reduce_run(self.fixture.run)["cpu"]["percent_of_one_core"], 210.0)

    def test_host_stream_is_bound_and_pressure_is_never_assumed_zero(self):
        rows = raw_rows()
        rows[0]["game_pid"] = 42
        middle = copy.deepcopy(rows[3])
        middle.update(query_start_usec=11_500_000, query_end_usec=11_500_100, monotonic_usec=11_500_200)
        serious = copy.deepcopy(middle)
        serious.update(type="event", source="thermal", query_start_usec=11_550_000,
                       query_end_usec=11_550_100, monotonic_usec=11_550_200)
        serious.pop("power_source")
        serious["thermal"].update(value="serious", **{"enum": 2})
        recovery = copy.deepcopy(serious)
        recovery.update(query_start_usec=11_700_000, query_end_usec=11_700_100, monotonic_usec=11_700_200)
        recovery["thermal"].update(value="nominal", **{"enum": 0})
        extras = [middle, serious, recovery,
                  {"type": "event", "source": "memory_pressure", "flags": 2, "monotonic_usec": 11_600_000},
                  {"type": "event", "source": "memory_pressure", "flags": 1, "monotonic_usec": 11_099_500}]
        rows = rows[:-1] + extras + rows[-1:]
        rows[3:-1] = sorted(rows[3:-1], key=lambda row: row["monotonic_usec"])
        rows[-1].update(snapshots=3, events=4)
        for index, row in enumerate(rows):
            row.update(sequence=index, capture_id=self.fixture.capture_id)
        raw = host_encode(rows)
        path = self.fixture.capture / "host-state.jsonl"
        path.write_bytes(raw)
        observed = reducer.host.validate_stream(raw, self.fixture.capture_id, 42)
        receipt = {**observed, "file": path.name, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
                   "capture_id": self.fixture.capture_id, "helper_sha256": "a" * 64, "helper_exit": 0,
                   "identity_checks": "stable_at_prelaunch_postlaunch_and_stop", "identity_errors": []}
        checked = {"host_state": receipt}
        frame = {"capture_id": self.fixture.capture_id, "pid": 42}
        window = {"clock": {"mode": "aligned_raw_uptime", "frame_raw_offset": {"helper_sha256": "a" * 64}},
                  "poll_start_usec": 11_099_000, "poll_end_usec": 11_901_000,
                  "first_poll_end_usec": 11_100_000, "last_poll_start_usec": 11_900_000, "margin_usec": 0}
        result = reducer._host_context(self.fixture.capture, checked, frame, window, {})
        self.assertEqual(result["status"], "complete")
        self.assertEqual(result["thermal"]["values"], ["nominal", "serious"])
        self.assertEqual(len(result["state_transitions"]["events"]), 2)
        self.assertEqual(result["low_power"]["values"], [False])
        self.assertEqual(result["memory_pressure"]["initial"], "unknown")
        self.assertEqual(result["memory_pressure"]["events"][0]["flags"], 2)
        self.assertEqual(result["memory_pressure"]["boundary_uncertain_events"][0]["flags"], 1)
        self.assertIsNone(result["memory_pressure"]["os_coalesced_or_dropped"])
        window["poll_start_usec"] = 10_500_000
        self.assertEqual(reducer._host_context(self.fixture.capture, checked, frame, window, {})["status"], "partial")
        window["poll_start_usec"] = 11_099_000
        snapshot = next(row for row in rows if row.get("type") == "snapshot" and row["monotonic_usec"] == 11_500_200)
        snapshot["thermal"] = {"status": "unsupported", "value": None, "reason": "unavailable"}
        unavailable = host_encode(rows)
        path.write_bytes(unavailable)
        receipt.update(reducer.host.validate_stream(unavailable, self.fixture.capture_id, 42))
        receipt.update(bytes=len(unavailable), sha256=hashlib.sha256(unavailable).hexdigest())
        result = reducer._host_context(self.fixture.capture, checked, frame, window, {})
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["thermal"]["status"], "unknown")
        self.assertIsNone(result["thermal"]["values"])
        path.write_bytes(raw + b" ")
        with self.assertRaisesRegex(ValueError, "original receipt"):
            reducer._host_context(self.fixture.capture, checked, frame, window, {})

    def test_raw_clock_requires_host_helper_and_sleep_evidence(self):
        window = {"clock": {"mode": "aligned_raw_uptime"}}
        with self.assertRaisesRegex(ValueError, "host helper and sleep evidence"):
            reducer._host_context(self.fixture.capture, {}, {"capture_id": self.fixture.capture_id, "pid": 42}, window, {})

    def test_non_bracketing_or_wide_poll_cannot_use_warmup_or_teardown(self):
        for change in ("no_bracket", "wide_poll", "clock_drift"):
            with self.subTest(change=change):
                original = copy.deepcopy(self.fixture.resource)
                q = self.fixture.resource
                if change == "no_bracket":
                    for sample in q["samples"]:
                        sample["elapsed_seconds"] += 2
                    q["clock"]["end"].update(monotonic_usec=58_000_000, unix_usec=1_700_000_058_000_000)
                elif change == "wide_poll":
                    q["samples"][3]["poll_overhead_usec"] = 1_000_001
                else:
                    q["clock"]["end"]["unix_usec"] += 2_000_000
                self.fixture.save_resource()
                with self.assertRaises(ValueError):
                    reducer.reduce_run(self.fixture.run)
                self.fixture.resource = original
                self.fixture.save_resource()

    def test_changed_health_and_original_hierarchy_are_rejected(self):
        health_path = self.fixture.health_path
        health = json.loads(health_path.read_text())
        health["backend_proof"]["backend_unchanged"] = False
        health_path.write_text(json.dumps(health))
        with self.assertRaisesRegex(ValueError, "health or checked-run"):
            reducer.reduce_run(self.fixture.run)

    def test_only_original_hierarchy_can_be_rebased(self):
        self.fixture.checked["report"] = "/elsewhere/checks/godot-fixture/report.json"
        self.fixture.save_checked()
        with self.assertRaisesRegex(ValueError, "share their original run directory"):
            reducer.reduce_run(self.fixture.run)

    def test_output_is_fresh_and_multiple_runs_cannot_reuse_capture_id(self):
        out = self.fixture.root / "out.json"
        self.assertEqual(reducer.main(["--run", str(self.fixture.run), "--out", str(out)]), 0)
        before = out.read_bytes()
        self.assertEqual(reducer.main(["--run", str(self.fixture.run), "--out", str(out)]), 1)
        self.assertEqual(out.read_bytes(), before)
        other = self.fixture.root / "other.json"
        self.assertEqual(reducer.main(["--run", str(self.fixture.run), "--run", str(self.fixture.run),
                                       "--out", str(other)]), 1)
        self.assertFalse(other.exists())


if __name__ == "__main__":
    unittest.main()
