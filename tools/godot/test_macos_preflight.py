"""Portable tests for the serial-free macOS preflight receipt."""
from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

from tools.godot import macos_preflight as probe


class BoundedCommandTests(unittest.TestCase):
    def test_success_and_output_limit(self) -> None:
        ok = probe.bounded_command([sys.executable, "-c", "print('ok')"], timeout=5, max_bytes=100)
        self.assertEqual(ok.text.strip(), "ok")
        self.assertIsNone(ok.reason)
        limited = probe.bounded_command([sys.executable, "-c", "print('x' * 100000)"], timeout=5, max_bytes=256)
        self.assertIsNone(limited.text)
        self.assertEqual(limited.reason, "output_limit")

    def test_timeout_discards_output(self) -> None:
        start = time.monotonic()
        result = probe.bounded_command([sys.executable, "-c", "import time; time.sleep(5)"], timeout=0.15, max_bytes=100)
        self.assertEqual(result.reason, "timeout")
        self.assertIsNone(result.text)
        self.assertLess(time.monotonic() - start, 4)


class FoundationStateTests(unittest.TestCase):
    def snapshot(self, data: object) -> dict:
        outcome = probe.Outcome(json.dumps(data), None, 0)
        with mock.patch.object(probe, "bounded_command", return_value=outcome):
            return probe.foundation_state(time.monotonic() + 10)

    def test_valid_thermal_enums_and_boolean_are_strict(self) -> None:
        for code, name in enumerate(("nominal", "fair", "serious", "critical")):
            for value in (code, str(code)):
                with self.subTest(thermal=value):
                    result = self.snapshot({"thermal_state": {"status": "available", "value": value},
                                            "low_power_mode": {"status": "available", "value": False}})
                    self.assertEqual(result["thermal_state"],
                                     {"status": "available", "value": name, "enum": code, "reason": None})
                    self.assertEqual(result["low_power_mode"],
                                     {"status": "available", "value": False, "reason": None})
                    self.assertEqual(result["memory_pressure"]["status"], "unknown")
        result = self.snapshot({"thermal_state": {"status": "available", "value": "0"},
                                "low_power_mode": {"status": "available", "value": True}})
        self.assertIs(result["low_power_mode"]["value"], True)
        self.assertIn("NSProcessInfo", result["source"])
        self.assertIn("single", result["scope"])

    def test_unknown_values_are_never_coerced_to_nominal_or_false(self) -> None:
        for value in (-1, 4, True, False, 0.0, "01", " 0", "nominal", None):
            with self.subTest(thermal=value):
                result = self.snapshot({"thermal_state": {"status": "available", "value": value},
                                        "low_power_mode": {"status": "available", "value": False}})
                self.assertEqual(result["thermal_state"]["status"], "unknown")
                self.assertIsNone(result["thermal_state"]["value"])
                self.assertIsNone(result["thermal_state"]["enum"])
                self.assertIs(result["low_power_mode"]["value"], False)
        for value in (0, 1, "false", "true", None, []):
            with self.subTest(low_power=value):
                result = self.snapshot({"thermal_state": {"status": "available", "value": "2"},
                                        "low_power_mode": {"status": "available", "value": value}})
                self.assertEqual(result["low_power_mode"]["status"], "unknown")
                self.assertIsNone(result["low_power_mode"]["value"])
                self.assertEqual(result["thermal_state"]["value"], "serious")

    def test_independent_unsupported_error_and_malformed_fields(self) -> None:
        cases = (
            ({"status": "unsupported"}, "unsupported", "selector_unavailable"),
            ({"status": "error"}, "error", "property_query_failed"),
            ({"status": "available"}, "unknown", "value_unavailable"),
            ({"status": "unexpected"}, "error", "invalid_field_status"),
            (None, "error", "invalid_field"),
        )
        for raw, status, reason in cases:
            with self.subTest(raw=raw):
                result = self.snapshot({"thermal_state": raw,
                                        "low_power_mode": {"status": "available", "value": True}})
                self.assertEqual(result["thermal_state"]["status"], status)
                self.assertEqual(result["thermal_state"]["reason"], reason)
                self.assertIsNone(result["thermal_state"]["value"])
                self.assertIs(result["low_power_mode"]["value"], True)
        result = self.snapshot({"thermal_state": {"status": "available", "value": "1"},
                                "low_power_mode": {"status": "unsupported"}})
        self.assertEqual(result["thermal_state"]["value"], "fair")
        self.assertEqual(result["low_power_mode"]["status"], "unsupported")
        self.assertIsNone(result["low_power_mode"]["value"])

    def test_failed_or_malformed_command_reports_reason(self) -> None:
        for outcome, reason in ((probe.Outcome(None, "timeout", None), "timeout"),
                                (probe.Outcome(None, "nonzero_exit", 1), "nonzero_exit"),
                                (probe.Outcome(None, "launch_failed", None), "launch_failed"),
                                (probe.Outcome("not json", None, 0), "invalid_json"),
                                (probe.Outcome("[]", None, 0), "invalid_output")):
            with self.subTest(reason=reason), \
                 mock.patch.object(probe, "bounded_command", return_value=outcome):
                result = probe.foundation_state(time.monotonic() + 10)
                self.assertEqual(result["query"]["reason"], reason)
                for name in ("thermal_state", "low_power_mode"):
                    self.assertEqual(result[name]["status"], "error")
                    self.assertEqual(result[name]["reason"], reason)
                    self.assertIsNone(result[name]["value"])

    def test_query_respects_remaining_deadline_and_does_not_start_after_it(self) -> None:
        output = probe.Outcome('{"thermal_state":{"status":"unsupported"},'
                               '"low_power_mode":{"status":"unsupported"}}', None, 0)
        with mock.patch.object(probe.time, "monotonic", return_value=100.0), \
             mock.patch.object(probe, "bounded_command", return_value=output) as command:
            result = probe.foundation_state(100.25)
            self.assertEqual(result["query"]["timeout_seconds"], 0.25)
            args, kwargs = command.call_args
            self.assertEqual(args[0][:4], ["/usr/bin/osascript", "-l", "JavaScript", "-e"])
            self.assertEqual(kwargs, {"timeout": 0.25, "max_bytes": probe.FOUNDATION_OUTPUT_BYTES})
            self.assertNotIn("System Events", args[0][4])
            command.reset_mock()
            result = probe.foundation_state(1000.0)
            self.assertEqual(result["query"]["timeout_seconds"], probe.FOUNDATION_SECONDS)
            self.assertEqual(command.call_args.kwargs["timeout"], probe.FOUNDATION_SECONDS)
            command.reset_mock()
            result = probe.foundation_state(100.0)
            command.assert_not_called()
            self.assertEqual(result["query"]["reason"], "budget_exhausted")
            self.assertEqual(result["thermal_state"]["status"], "error")
            self.assertIsNone(result["low_power_mode"]["value"])


class FilteringTests(unittest.TestCase):
    def test_display_profile_does_not_retain_names_or_serials(self) -> None:
        data = {"SPDisplaysDataType": [{"_name": "Apple M1", "serial_number": "GPU-SECRET-123",
                "spdisplays_metal": "Metal 3", "spdisplays_ndrvs": [{"_name": "PRIVATE-DISPLAY-NAME",
                "display_serial_number": "SCREEN-SECRET-456", "_spdisplays_resolution": "2560 x 1600 Retina",
                "spdisplays_main": "spdisplays_yes", "spdisplays_connection_type": "spdisplays_internal"}]}]}
        filtered, truncated = probe.parse_profile(json.dumps(data))
        self.assertFalse(truncated)
        self.assertEqual(filtered[0]["model"], "Apple M1")
        self.assertEqual(filtered[0]["displays"][0]["reported_dimensions"], [2560, 1600])
        self.assertEqual(filtered[0]["displays"][0]["resolution_source"], "_spdisplays_resolution")
        self.assertTrue(filtered[0]["displays"][0]["main"])
        text = json.dumps(filtered)
        for value in ("GPU-SECRET-123", "SCREEN-SECRET-456", "PRIVATE-DISPLAY-NAME", "serial"):
            self.assertNotIn(value, text)

    def test_profile_limits_and_malformed_input(self) -> None:
        raw = json.dumps({"SPDisplaysDataType": [{"_name": "GPU", "spdisplays_ndrvs": [{}] * 40}]})
        data, truncated = probe.parse_profile(raw)
        self.assertTrue(truncated)
        self.assertEqual(len(data[0]["displays"]), probe.MAX_DISPLAYS)
        with self.assertRaises(ValueError):
            probe.parse_profile('{"SPDisplaysDataType": {}}')


class FileHashTests(unittest.TestCase):
    def test_hash_and_missing_file(self) -> None:
        with tempfile.TemporaryDirectory(prefix="openrc-preflight-") as folder:
            path = Path(folder) / "engine"
            path.write_bytes(b"engine fixture")
            identity, issue, stamp = probe.hash_file(path, time.monotonic() + 5)
            self.assertIsNone(issue)
            self.assertEqual(identity["sha256"], hashlib.sha256(b"engine fixture").hexdigest())
            self.assertEqual(identity["size_bytes"], len(b"engine fixture"))
            self.assertIsNotNone(stamp)
            self.assertEqual(probe.hash_file(path.parent / "missing", time.monotonic() + 5)[1], "engine_unreadable")

    @unittest.skipUnless(hasattr(os, "mkfifo"), "named pipes are unavailable")
    def test_named_pipe_is_rejected_without_blocking(self) -> None:
        with tempfile.TemporaryDirectory(prefix="openrc-preflight-") as folder:
            path = Path(folder) / "fifo"
            os.mkfifo(path)
            start = time.monotonic()
            self.assertEqual(probe.hash_file(path, start + 5)[1], "invalid_engine_file")
            self.assertLess(time.monotonic() - start, 2)


class CollectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-mac-inventory-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.engine = self.root / "engine"
        self.engine.write_bytes(b"frozen editor fixture")
        self.profile = json.dumps({"SPDisplaysDataType": [{"_name": "Apple M1", "serial_number": "SECRET",
            "spdisplays_ndrvs": [{"spdisplays_resolution": "1920 x 1080", "display_serial_number": "SECRET2"}]}]})

    def command(self, command: list[str], **kwargs) -> probe.Outcome:
        outputs = {
            ("/usr/sbin/sysctl", "-n", "hw.optional.arm64"): "1\n",
            ("/usr/sbin/sysctl", "-n", "hw.model"): "MacBookAir10,1\n",
            ("/usr/sbin/sysctl", "-n", "hw.memsize"): "8589934592\n",
            ("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"): "Apple M1\n",
            ("/usr/bin/sw_vers", "-productVersion"): "26.1\n",
            ("/usr/bin/sw_vers", "-buildVersion"): "25B78\n",
            ("/usr/sbin/system_profiler", "SPDisplaysDataType", "-json", "-detailLevel", "basic"): self.profile,
            ("/usr/bin/file", "-b", str(self.engine.absolute())): "Mach-O 64-bit executable arm64\n",
            (str(self.engine.absolute()), "--version"): "4.8.beta1.official.4d10419ca\n",
            ("/usr/bin/arch", "-arm64", str(self.engine.absolute()), "--version"): "4.8.beta1.official.4d10419ca\n",
            ("/usr/bin/xcode-select", "-p"): "/Applications/Xcode.app/Contents/Developer\n",
        }
        text = outputs.get(tuple(command))
        return probe.Outcome(text, None if text is not None else "launch_failed", 0 if text is not None else None)

    def test_complete_inventory_distinguishes_forced_engine_from_normal_launch(self) -> None:
        with mock.patch.object(probe.platform, "machine", return_value="arm64"), \
             mock.patch.object(probe, "process_translation", return_value=(False, None)), \
             mock.patch.object(probe, "bounded_command", side_effect=self.command):
            result = probe.collect(self.engine)
        self.assertTrue(result["collection"]["complete"], result["collection"]["issues"])
        self.assertTrue(result["host"]["python_process_native_arm64"])
        self.assertFalse(result["host"]["python_process_rosetta"])
        self.assertTrue(result["engine"]["forced_arm64_version_succeeded"])
        self.assertIsNone(result["engine"]["normal_launch_native_arm64"])
        self.assertTrue(result["engine"]["identity_stable_across_version_checks"])
        self.assertEqual(result["host_state"]["query"]["reason"], "launch_failed")
        self.assertEqual(result["host_state"]["thermal_state"]["status"], "error")
        self.assertNotIn("SECRET", json.dumps(result))

    def test_optional_host_state_is_collected_without_changing_inventory_success(self) -> None:
        def command(args: list[str], **kwargs) -> probe.Outcome:
            if args[0] == "/usr/bin/osascript":
                return probe.Outcome('{"thermal_state":{"status":"available","value":"3"},'
                                     '"low_power_mode":{"status":"available","value":false}}', None, 0)
            return self.command(args, **kwargs)
        with mock.patch.object(probe.platform, "machine", return_value="arm64"), \
             mock.patch.object(probe, "process_translation", return_value=(False, None)), \
             mock.patch.object(probe, "bounded_command", side_effect=command):
            result = probe.collect(self.engine)
        self.assertTrue(result["collection"]["complete"], result["collection"]["issues"])
        self.assertEqual(result["host_state"]["thermal_state"]["value"], "critical")
        self.assertIs(result["host_state"]["low_power_mode"]["value"], False)

    def test_rosetta_and_unknown_forced_probe_are_not_native_success(self) -> None:
        def command(args: list[str], **kwargs) -> probe.Outcome:
            if args[0] == "/usr/bin/arch":
                return probe.Outcome(None, "timeout", None)
            return self.command(args, **kwargs)
        with mock.patch.object(probe.platform, "machine", return_value="x86_64"), \
             mock.patch.object(probe, "process_translation", return_value=(True, None)), \
             mock.patch.object(probe, "bounded_command", side_effect=command):
            result = probe.collect(self.engine)
        self.assertTrue(result["host"]["python_process_rosetta"])
        self.assertFalse(result["host"]["python_process_native_arm64"])
        self.assertIsNone(result["engine"]["forced_arm64_version_succeeded"])
        self.assertIsNone(result["engine"]["normal_launch_native_arm64"])
        self.assertIn("engine:forced_arm64_unavailable", result["collection"]["issues"])

    def test_unreported_display_resolution_is_not_a_complete_inventory(self) -> None:
        self.profile = json.dumps({"SPDisplaysDataType": [{"_name": "Apple M1", "spdisplays_ndrvs": [{}]}]})
        with mock.patch.object(probe.platform, "machine", return_value="arm64"), \
             mock.patch.object(probe, "process_translation", return_value=(False, None)), \
             mock.patch.object(probe, "bounded_command", side_effect=self.command):
            result = probe.collect(self.engine)
        self.assertFalse(result["collection"]["complete"])
        self.assertIn("displays:resolution_unavailable", result["collection"]["issues"])
        self.assertIsNone(result["gpus"][0]["displays"][0]["reported_dimensions"])

    def test_missing_data_stays_unknown_and_marks_receipt_partial(self) -> None:
        def command(args: list[str], **kwargs) -> probe.Outcome:
            if args[0] == "/usr/sbin/system_profiler" or args[-1] == "hw.memsize":
                return probe.Outcome(None, "timeout", None)
            return self.command(args, **kwargs)
        with mock.patch.object(probe.platform, "machine", return_value="arm64"), \
             mock.patch.object(probe, "process_translation", return_value=(None, "sysctl_unavailable")), \
             mock.patch.object(probe, "bounded_command", side_effect=command):
            result = probe.collect(self.engine)
        self.assertFalse(result["collection"]["complete"])
        self.assertIsNone(result["host"]["memory_bytes"])
        self.assertIsNone(result["host"]["python_process_native_arm64"])
        self.assertEqual(result["gpus"], [])

    def test_engine_changed_after_hash_is_reported(self) -> None:
        def command(args: list[str], **kwargs) -> probe.Outcome:
            if args[0] == str(self.engine.absolute()):
                self.engine.write_bytes(b"different engine bytes")
            return self.command(args, **kwargs)
        with mock.patch.object(probe.platform, "machine", return_value="arm64"), \
             mock.patch.object(probe, "process_translation", return_value=(False, None)), \
             mock.patch.object(probe, "bounded_command", side_effect=command):
            result = probe.collect(self.engine)
        self.assertFalse(result["engine"]["identity_stable_across_version_checks"])
        self.assertIn("engine:changed_after_hash", result["collection"]["issues"])

    def test_dry_run_and_non_darwin_do_not_create_output(self) -> None:
        out = self.root / "not-created"
        command = [sys.executable, str(ROOT_SCRIPT), "--dry-run", "--out-dir", str(out)]
        dry = subprocess.run(command, text=True, capture_output=True, timeout=10, check=False)
        self.assertEqual(dry.returncode, 0, dry.stderr)
        dry_result = json.loads(dry.stdout)
        self.assertFalse(dry_result["collection_started"])
        self.assertIn("Foundation thermal and low-power snapshot", dry_result["collects"])
        self.assertFalse(out.exists())
        with mock.patch.object(probe.platform, "system", return_value="Linux"), \
             mock.patch.object(sys, "argv", ["macos_preflight.py", "--godot", str(self.engine), "--out-dir", str(out)]), \
             redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                probe.main()
        self.assertEqual(caught.exception.code, 2)
        self.assertFalse(out.exists())

    def test_every_receipt_uses_a_new_file(self) -> None:
        out = self.root / "output"
        fixture = {"collection": {"complete": True}, "format": "fixture"}
        args = ["macos_preflight.py", "--godot", str(self.engine), "--out-dir", str(out)]
        with mock.patch.object(probe.platform, "system", return_value="Darwin"), \
             mock.patch.object(probe, "collect", return_value=fixture), mock.patch.object(sys, "argv", args), \
             redirect_stdout(io.StringIO()):
            self.assertEqual(probe.main(), 0)
            self.assertEqual(probe.main(), 0)
        paths = list(out.glob("*.json"))
        self.assertEqual(len(paths), 2)
        self.assertEqual([json.loads(p.read_text(encoding="utf-8")) for p in paths], [fixture, fixture])


ROOT_SCRIPT = Path(__file__).resolve().parent / "macos_preflight.py"

if __name__ == "__main__":
    unittest.main()
