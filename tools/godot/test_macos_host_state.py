"""Portable protocol and process-lifetime fixtures for the Mac host companion."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

from macos_host_state import HostStateCapture, MAX_BYTES, validate_stream

CAPTURE = "12345678-1234-4234-8234-123456789abc"
PID = 12345


def rows():
    thermal = {"status": "available", "value": "nominal", "enum": 0, "reason": None}
    low = {"status": "available", "value": False, "reason": None}
    ac = {"status": "available", "value": "ac", "reason": None}
    state = lambda start, end: {"query_start_usec": start, "query_end_usec": end,
                                "thermal": copy.deepcopy(thermal), "low_power": copy.deepcopy(low)}
    items = [
        {"type": "header", "format": "openrc-macos-host-v1", "game_pid": PID,
         "test_mode": False,
         "clock_source": "clock_gettime(CLOCK_MONOTONIC)", "memory_pressure_initial": "unknown",
         "snapshot_limit": 4096, "event_limit": 1024, "byte_limit": 4194304,
         "clock_start": {"monotonic_usec": 10000000, "unix_usec": 1700000010000000, "uncertainty_usec": 20000},
         "monotonic_usec": 10000100},
        {"type": "initial", "before": state(10000200, 10000300), "after": state(10000400, 10000500),
         "thermal_observer_registered": True, "low_power_observer_registered": True, "monotonic_usec": 10000600},
        {"type": "ready", "pressure_stream": "registered", "monotonic_usec": 10000700},
        {"type": "snapshot", **state(11000000, 11000100), "power_source": copy.deepcopy(ac), "monotonic_usec": 11000200},
        {"type": "snapshot", **state(12000000, 12000100), "power_source": copy.deepcopy(ac), "monotonic_usec": 12000200},
        {"type": "trailer", "reason": "stop", "complete": True, "pressure_ready": True,
         "snapshots": 2, "events": 0, "missed_ticks": 0, "local_drops": 0,
         "os_coalesced_or_dropped": None,
         "clock_end": {"monotonic_usec": 13000000, "unix_usec": 1700000013000000, "uncertainty_usec": 20000},
         "monotonic_usec": 13000100},
    ]
    return resequence(items)


def resequence(items):
    for index, row in enumerate(items):
        row["sequence"] = index
        row["capture_id"] = CAPTURE
    return items


def raw_rows():
    items = rows()
    items[0]["format"] = "openrc-macos-host-v2"
    items[0]["clock_source"] = "clock_gettime(CLOCK_UPTIME_RAW)"
    raw = {"status": "available", "domain": "darwin_mach_absolute_time",
           "offset_lower_usec": 0, "offset_upper_usec": 0}
    items[0]["clock_start"]["raw_uptime"] = copy.deepcopy(raw)
    items[-1]["clock_end"]["raw_uptime"] = copy.deepcopy(raw)
    items[0]["sleep_start"] = {"uptime_before_usec": 10000010, "continuous_usec": 20000015,
                               "uptime_after_usec": 10000020}
    items[-1]["sleep_end"] = {"uptime_before_usec": 13000010, "continuous_usec": 23000015,
                              "uptime_after_usec": 13000020}
    return items


def encode(items):
    return b"".join((json.dumps(row, separators=(",", ":")) + "\n").encode() for row in items)


class HostProtocolTests(unittest.TestCase):
    def test_raw_domain_accepts_wall_slew_as_diagnostic_and_detects_sleep(self):
        items = raw_rows()
        items[-1]["clock_end"]["unix_usec"] += 116000
        result = validate_stream(encode(items), CAPTURE, PID)
        self.assertEqual(result["coverage"], "complete")
        self.assertEqual(result["clock_offset_drift_usec"], 116000)
        self.assertTrue(result["sleep_check"]["within_tolerance"])
        self.assertEqual(result["sleep_check"]["bracket_uncertainty_usec"], 24)
        items[-1]["sleep_end"]["continuous_usec"] += 100000
        result = validate_stream(encode(items), CAPTURE, PID)
        self.assertEqual(result["coverage"], "partial")
        self.assertFalse(result["sleep_check"]["within_tolerance"])
        self.assertIn("sleep_or_clock_discontinuity_exceeds_tolerance", result["issues"])
        legacy = rows()
        legacy[-1]["clock_end"]["unix_usec"] += 116000
        with self.assertRaisesRegex(ValueError, "clock anchor drift"):
            validate_stream(encode(legacy), CAPTURE, PID)

    def test_raw_domain_rejects_missing_wrong_or_unbounded_evidence(self):
        cases = [
            lambda x: x[0]["clock_start"].pop("raw_uptime"),
            lambda x: x[-1]["clock_end"]["raw_uptime"].update(domain="wrong"),
            lambda x: x[-1]["clock_end"]["raw_uptime"].update(offset_upper_usec=1),
            lambda x: x[0].pop("sleep_start"),
            lambda x: x[-1]["sleep_end"].update(uptime_before_usec=13000030),
            lambda x: x[-1]["sleep_end"].update(uptime_after_usec=13000200),
        ]
        for mutate in cases:
            items = raw_rows()
            mutate(items)
            with self.subTest(items=items), self.assertRaises(ValueError):
                validate_stream(encode(items), CAPTURE, PID)

    def test_complete_stream_does_not_invent_initial_pressure(self):
        result = validate_stream(encode(rows()), CAPTURE, PID)
        self.assertEqual(result["coverage"], "complete")
        self.assertEqual(result["memory_pressure_initial"], "unknown")
        self.assertEqual(result["memory_pressure_callbacks"], 0)
        self.assertIsNone(result["os_coalesced_or_dropped"])
        self.assertEqual(result["max_snapshot_gap_usec"], 1000000)

    def test_change_during_registration_and_pressure_before_ready(self):
        items = rows()
        items[1]["after"]["thermal"].update(value="fair", **{"enum": 1})
        items.insert(2, {"type": "event", "source": "memory_pressure", "flags": 3,
                         "monotonic_usec": 10000650})
        items[-1]["events"] = 1
        result = validate_stream(encode(resequence(items)), CAPTURE, PID)
        self.assertEqual(result["coverage"], "complete")
        self.assertEqual(result["memory_pressure_callbacks"], 1)
        self.assertIsNone(result["os_coalesced_or_dropped"])

    def test_unsupported_field_is_partial_not_zero(self):
        items = rows()
        items[3]["low_power"] = {"status": "unsupported", "value": None, "reason": "selector_unavailable"}
        result = validate_stream(encode(items), CAPTURE, PID)
        self.assertEqual(result["coverage"], "partial")
        self.assertEqual(result["required_field_available_counts"]["low_power"], 1)

    def test_reported_local_loss_is_retained_as_partial(self):
        items = rows()
        items[-1].update(complete=False, local_drops=17)
        result = validate_stream(encode(items), CAPTURE, PID)
        self.assertEqual(result["coverage"], "partial")
        self.assertEqual(result["local_drops"], 17)
        self.assertIn("helper_reported_incomplete:stop", result["issues"])

    def test_unknown_enum_and_invalid_boolean_rejected(self):
        for mutate in (lambda x: x[3]["thermal"].update(value="nominal", **{"enum": 4}),
                       lambda x: x[3]["low_power"].update(value=0),
                       lambda x: x[1].update(thermal_observer_registered=1)):
            items = rows()
            mutate(items)
            with self.subTest(items=items), self.assertRaises(ValueError):
                validate_stream(encode(items), CAPTURE, PID)

    def test_test_mode_can_never_be_accepted_as_measurement(self):
        items = rows()
        items[0]["test_mode"] = True
        with self.assertRaises(ValueError):
            validate_stream(encode(items), CAPTURE, PID)

    def test_invalid_identity_order_counts_clock_and_incomplete(self):
        cases = [
            lambda x: x[3].update(capture_id="wrong"),
            lambda x: x[3].update(sequence=4),
            lambda x: x[3].update(monotonic_usec=x[2]["monotonic_usec"]),
            lambda x: x[1]["after"].update(query_start_usec=10000200),
            lambda x: x[-1].update(events=1),
            lambda x: x[-1].update(missed_ticks=1),
            lambda x: x[-1].update(reason="duration_limit"),
            lambda x: x[-1]["clock_end"].update(unix_usec=1700000015000000),
            lambda x: x.pop(),
        ]
        for mutate in cases:
            items = rows()
            mutate(items)
            with self.subTest(items=items), self.assertRaises(ValueError):
                validate_stream(encode(items), CAPTURE, PID)
        with self.assertRaises(ValueError):
            validate_stream(b"x" * (MAX_BYTES + 1), CAPTURE, PID)
        with self.assertRaises(ValueError):
            validate_stream(encode(rows())[:-1], CAPTURE, PID)

    def test_sampling_gap_marks_partial(self):
        items = rows()
        items[4]["monotonic_usec"] += 1200000
        items[4]["query_start_usec"] += 1200000
        items[4]["query_end_usec"] += 1200000
        items[-1]["monotonic_usec"] += 1200000
        items[-1]["clock_end"]["monotonic_usec"] += 1200000
        items[-1]["clock_end"]["unix_usec"] += 1200000
        self.assertEqual(validate_stream(encode(items), CAPTURE, PID)["coverage"], "partial")

    def test_duplicate_json_keys_rejected(self):
        data = encode(rows()).replace(b'"type":"header"', b'"type":"header","type":"header"', 1)
        with self.assertRaises(ValueError):
            validate_stream(data, CAPTURE, PID)


class HostSupervisorTests(unittest.TestCase):
    def test_child_stops_on_eof_and_publishes_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            executable = root / "fake-helper"
            executable.write_text(f"#!{sys.executable}\nimport sys\nsys.stdin.buffer.read()\nsys.stdout.buffer.write({encode(rows())!r})\nsys.stdout.buffer.flush()\n")
            executable.chmod(0o700)
            with mock.patch("macos_host_state.platform.system", return_value="Darwin"):
                capture = HostStateCapture(executable, CAPTURE, PID, 10, root / "host.jsonl")
                result = capture.finish()
            self.assertEqual(result["coverage"], "complete", result)
            self.assertEqual(result["helper_exit"], 0)
            self.assertEqual(result["bytes"], len(encode(rows())))
            self.assertEqual(result["memory_pressure_initial"], "unknown")
            self.assertEqual(result["identity_checks"], "stable_at_prelaunch_postlaunch_and_stop")
            self.assertEqual(result["identity_errors"], [])
            self.assertFalse(capture.thread.is_alive())

    def test_helper_or_source_replaced_during_capture_is_partial(self):
        for target in ("helper", "source"):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                executable = root / "fake-helper"
                marker = root / "started"
                source = root / "fixture.m"
                source.write_text("original source\n")
                executable.write_text(f"#!{sys.executable}\nimport sys\nfrom pathlib import Path\nPath({str(marker)!r}).touch()\nsys.stdin.buffer.read()\nsys.stdout.buffer.write({encode(rows())!r})\nsys.stdout.buffer.flush()\n")
                executable.chmod(0o700)
                with mock.patch("macos_host_state.platform.system", return_value="Darwin"), \
                        mock.patch("macos_host_state.__file__", str(root / "fixture.py")):
                    capture = HostStateCapture(executable, CAPTURE, PID, 10, root / "host.jsonl")
                    try:
                        deadline = time.monotonic() + 3
                        while not marker.exists() and time.monotonic() < deadline:
                            time.sleep(0.01)
                        self.assertTrue(marker.exists(), "helper did not start")
                        if target == "helper":
                            replacement = root / "replacement"
                            replacement.write_bytes(executable.read_bytes())
                            replacement.chmod(0o700)
                            os.replace(replacement, executable)
                        else:
                            source.write_text("changed source\n")
                    finally:
                        result = capture.finish()
                self.assertEqual(result["coverage"], "partial", result)
                self.assertIn(f"{target}_identity_changed_after_stop", result["identity_errors"])
                self.assertEqual(result["error"], "helper_or_source_identity_changed")

    def test_helper_replaced_during_launch_is_partial(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            executable = root / "fake-helper"
            executable.write_text(f"#!{sys.executable}\nimport sys\nsys.stdin.buffer.read()\nsys.stdout.buffer.write({encode(rows())!r})\nsys.stdout.buffer.flush()\n")
            executable.chmod(0o700)
            real_popen = subprocess.Popen

            def launch_then_replace(*args, **kwargs):
                child = real_popen(*args, **kwargs)
                replacement = root / "replacement"
                replacement.write_bytes(executable.read_bytes())
                replacement.chmod(0o700)
                os.replace(replacement, executable)
                return child

            with mock.patch("macos_host_state.platform.system", return_value="Darwin"), \
                    mock.patch("macos_host_state.subprocess.Popen", side_effect=launch_then_replace):
                capture = HostStateCapture(executable, CAPTURE, PID, 10, root / "host.jsonl")
                result = capture.finish()
            self.assertEqual(result["coverage"], "partial", result)
            self.assertIn("helper_identity_changed_after_launch", result["identity_errors"])

    def test_nonzero_child_is_partial_and_reaped(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            executable = root / "fake-helper"
            executable.write_text(f"#!{sys.executable}\nraise SystemExit(7)\n")
            executable.chmod(0o700)
            with mock.patch("macos_host_state.platform.system", return_value="Darwin"):
                capture = HostStateCapture(executable, CAPTURE, PID, 10, root / "host.jsonl")
                result = capture.finish()
            self.assertEqual(result["coverage"], "partial")
            self.assertEqual(result["helper_exit"], 7)
            self.assertFalse(capture.thread.is_alive())

    def test_non_darwin_does_not_spawn(self):
        with mock.patch("macos_host_state.platform.system", return_value="Linux"), \
                mock.patch("macos_host_state.subprocess.Popen") as launch:
            with self.assertRaisesRegex(RuntimeError, "Darwin"):
                HostStateCapture(Path("missing"), CAPTURE, PID, 10, Path("unused"))
            launch.assert_not_called()


@unittest.skipUnless(os.environ.get("OPENRC_TEST_MAC_HOST_HELPER"), "set OPENRC_TEST_MAC_HOST_HELPER for native flood fixture")
class NativeHostTests(unittest.TestCase):
    def test_raw_clock_sample_and_complete_host_stream(self):
        helper = os.environ["OPENRC_TEST_MAC_HOST_HELPER"]
        one = subprocess.run([helper, "--clock-sample"], capture_output=True, timeout=3, check=True)
        self.assertLess(len(one.stdout), 4096)
        sample = json.loads(one.stdout)
        self.assertEqual(sample["format"], "openrc-raw-clock-v1")
        self.assertEqual(sample["clock"], "CLOCK_UPTIME_RAW")
        self.assertIs(type(sample["raw_uptime_usec"]), int)
        self.assertGreater(sample["raw_uptime_usec"], 0)
        child = subprocess.Popen([helper, CAPTURE, str(os.getpid()), "10"],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            time.sleep(1.2)
            data, error = child.communicate(input=b"", timeout=3)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=3)
        self.assertEqual(child.returncode, 0, error)
        result = validate_stream(data, CAPTURE, os.getpid())
        self.assertEqual(result["coverage"], "complete", result)
        self.assertTrue(result["sleep_check"]["within_tolerance"])
        self.assertEqual(result["clock"]["start"]["raw_uptime"]["offset_lower_usec"], 0)

    def test_notification_flood_is_bounded_and_incomplete(self):
        helper = os.environ["OPENRC_TEST_MAC_HOST_HELPER"]
        child = subprocess.Popen([helper, CAPTURE, str(os.getpid()), "10", "--test-flood"],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            code = child.wait(timeout=10)
            data = child.stdout.read()
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=3)
            child.stdin.close()
            child.stdout.close()
            child.stderr.close()
        result = [json.loads(line) for line in data.splitlines()]
        self.assertEqual(code, 1)
        self.assertTrue(result[0]["test_mode"])
        self.assertEqual(result[-1]["type"], "trailer")
        self.assertFalse(result[-1]["complete"])
        self.assertGreaterEqual(result[-1]["local_drops"], 1000)
        self.assertLessEqual(result[-1]["events"], 1024)
        with self.assertRaises(ValueError):
            validate_stream(data, CAPTURE, os.getpid())


if __name__ == "__main__":
    unittest.main()
