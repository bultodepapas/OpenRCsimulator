"""Offline device identity, degradation, and bounded cleanup contracts."""
from __future__ import annotations

import csv
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import threading
import time
import unittest
from unittest import mock

from tools.godtest.hardware import GpuSampler


def csv_output(rows):
    stream = io.StringIO(newline="")
    csv.writer(stream, lineterminator="\n").writerows(rows)
    return stream.getvalue().encode()


# Linux sysfs fixtures name directories after PCI addresses such as 0000:01:00.0.
# Windows paths cannot contain ':'; Linux and macOS CI still run these fixtures.
linux_sysfs_fixture = unittest.skipIf(
    os.name == "nt", "Linux sysfs fixture needs ':' in directory names; covered on Linux/macOS")


def nvidia_row(uuid, pci, name, *, util="65", memory_util="12", clock="1800", mem_clock="7000",
               temp="55", power="125.5", used="1000", total="8000"):
    return [uuid, pci, name, util, memory_util, clock, mem_clock, temp, power, used, total]


class ScriptedRunner:
    def __init__(self, outcomes):
        self.outcomes = list(outcomes)
        self.called = threading.Event()
        self.calls = []

    def __call__(self, argv, **kwargs):
        self.calls.append((argv, kwargs))
        outcome = self.outcomes[min(len(self.calls) - 1, len(self.outcomes) - 1)]
        self.called.set()
        if isinstance(outcome, Exception):
            raise outcome
        return subprocess.CompletedProcess(argv, 0, stdout=outcome, stderr=b"")


def wait_samples(sampler, count, timeout=3):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        with sampler._lock:
            if len(sampler._samples) >= count:
                return
        threading.Event().wait(.005)
    raise AssertionError(f"GPU sampler did not collect {count} samples")


def run_two(sampler, runner):
    sampler.interval = .1  # Keep offline fixture polling fast.
    sampler.start()
    if not runner.called.wait(2):
        raise AssertionError("GPU sampler did not invoke backend")
    wait_samples(sampler, 2)
    return sampler.stop()


def backend(report, name):
    return next(item for item in report["samples"][0]["backends"] if item["backend"] == name)


class GpuSamplerTests(unittest.TestCase):
    def symlink(self, path, target):
        try:
            path.symlink_to(target, target_is_directory=True)
        except (OSError, NotImplementedError) as error:
            self.skipTest(f"sysfs fixture requires symlink support: {error}")

    def amd_host(self, root):
        drm, pci = root / "drm", root / "pci"
        drm.mkdir()
        pci.mkdir()
        device, driver = root / "0000:01:00.0", root / "amdgpu"
        device.mkdir()
        driver.mkdir()
        self.symlink(device / "driver", driver)
        (device / "vendor").write_text("0x1002")
        (device / "device").write_text("0x7310")
        (device / "gpu_busy_percent").write_text("42")
        (drm / "card0").mkdir()
        self.symlink(drm / "card0" / "device", device)
        self.symlink(pci / device.name, device)
        return drm, pci

    def test_nvidia_multiple_devices_keep_stable_ids_and_metric_units(self):
        first = nvidia_row("GPU-b", "00000000:02:00.0", "Second, GPU", util="20", used="2")
        second = nvidia_row("GPU-a", "00000000:01:00.0", "First GPU", util="80", used="4")
        runner = ScriptedRunner([csv_output([first, second]), csv_output([second, first])])
        sampler = GpuSampler(platform="win32", runner=runner, interval=.1)
        sampler.start()
        deadline = time.monotonic() + 2
        while len(runner.calls) < 2 and time.monotonic() < deadline:
            threading.Event().wait(.01)
        result = sampler.stop()
        self.assertEqual(result["status"], "available", result)
        self.assertEqual(result["scope"], "whole_device_not_process")
        self.assertIn("earlier startup is not observed", result["coverage"])
        self.assertEqual(set(result["summary_by_device"]), {"nvidia:uuid:GPU-a", "nvidia:uuid:GPU-b"})
        summary = result["summary_by_device"]["nvidia:uuid:GPU-b"]
        self.assertGreaterEqual(summary["samples"], 2)
        self.assertEqual(summary["identity"]["pci_bus_id"], "00000000:02:00.0")
        self.assertEqual(summary["identity"]["name"], "Second, GPU")
        self.assertEqual(summary["metrics"]["gpu_utilization_pct"]["mean"], 20)
        self.assertEqual(summary["metrics"]["memory_used_bytes"]["mean"], 2 * 1048576)
        item = backend(result, "nvidia_smi")["devices"][0]
        self.assertEqual(item["raw"]["utilization.gpu"], "20")
        self.assertEqual(item["metrics"]["gpu_utilization_pct"], 20)
        self.assertGreaterEqual(result["samples"][0]["end_monotonic_usec"], result["samples"][0]["start_monotonic_usec"])
        self.assertGreaterEqual(result["samples"][0]["backends"][0]["end_monotonic_usec"], result["samples"][0]["backends"][0]["start_monotonic_usec"])
        self.assertEqual(runner.calls[0][1]["timeout"], 2.0)
        self.assertFalse(result["thread_alive"])
        self.assertEqual(len(result["source_sha256"]), 64)
        json.dumps(result, allow_nan=False)

    def test_ioreg_plist_keeps_exact_per_boot_ids_and_shared_memory(self):
        output = plistlib.dumps([
            {"IORegistryEntryID": 4294967301, "IORegistryEntryName": "AGX A", "IOObjectClass": "AGXAcceleratorG1",
             "PerformanceStatistics": {"Device Utilization %": 23, "Renderer Utilization %": 22,
                                       "In use system memory": 1048576, "Alloc system memory": 4194304}},
            {"IORegistryEntryID": 4294967302, "IORegistryEntryName": "AGX B",
             "PerformanceStatistics": {"Device Utilization %": 78, "Tiler Utilization %": 77}},
        ])
        runner = ScriptedRunner([output])
        result = run_two(GpuSampler(platform="darwin", runner=runner), runner)
        self.assertEqual(result["status"], "available")
        self.assertEqual(set(result["summary_by_device"]), {"apple:ioreg:4294967301", "apple:ioreg:4294967302"})
        first = backend(result, "apple_ioreg_agx")["devices"][0]
        self.assertEqual(first["identity"]["registry_id_scope"], "until_reboot")
        self.assertEqual(first["raw"]["Device Utilization %"], 23)
        self.assertEqual(first["metrics"]["memory_used_bytes"], 1048576)
        self.assertEqual(first["metrics"]["memory_allocated_bytes"], 4194304)
        self.assertIsNone(first["metrics"]["temperature_c"])
        self.assertEqual(first["metric_status"]["temperature_c"], "unsupported")
        self.assertIn("shared system memory", result["coverage_limitations"])
        self.assertEqual(runner.calls[0][0], ["ioreg", "-a", "-r", "-d", "1", "-c", "AGXAccelerator"])
        json.dumps(result, allow_nan=False)

    def test_unavailable_tool_and_timeout_are_diagnostic_not_zero(self):
        for error, reason in ((FileNotFoundError("not installed"), "tool_not_found"),
                              (PermissionError("not permitted"), "permission_denied"),
                              (subprocess.TimeoutExpired("nvidia-smi", 2), "timeout")):
            with self.subTest(error=error):
                runner = ScriptedRunner([error])
                result = run_two(GpuSampler(platform="win32", runner=runner), runner)
                self.assertEqual(result["status"], "unavailable")
                self.assertFalse(result["thread_alive"])
                self.assertEqual(result["summary_by_device"], {})
                self.assertIn(reason, result["errors"][0]["reason"])
                self.assertEqual(backend(result, "nvidia_smi")["devices"], [])
                json.dumps(result, allow_nan=False)

    def test_na_nan_and_invalid_fields_are_never_numeric_observations(self):
        row = nvidia_row("GPU-x", "00000000:01:00.0", "GPU", util="N/A", memory_util="NaN",
                         clock="inf", temp="-999", power="[Not Supported]", used="-1", total="8000")
        runner = ScriptedRunner([csv_output([row])])
        result = run_two(GpuSampler(platform="win32", runner=runner), runner)
        self.assertEqual(result["status"], "partial")
        item = backend(result, "nvidia_smi")["devices"][0]
        for key in ("gpu_utilization_pct", "memory_utilization_pct", "graphics_clock_mhz", "temperature_c",
                    "power_w", "memory_used_bytes"):
            self.assertIsNone(item["metrics"][key], key)
        self.assertEqual(item["metric_status"]["gpu_utilization_pct"], "unsupported")
        self.assertEqual(item["metric_status"]["memory_utilization_pct"], "invalid")
        self.assertEqual(item["raw"]["utilization.memory"], "NaN")
        self.assertEqual(item["metrics"]["memory_total_bytes"], 8000 * 1048576)
        json.dumps(result, allow_nan=False)

    def test_duplicate_and_missing_ids_preserve_devices_without_merging(self):
        rows = [nvidia_row("GPU-duplicate", "0000:01:00.0", "GPU one", util="5"),
                nvidia_row("GPU-duplicate", "0000:02:00.0", "GPU two", util="90"),
                nvidia_row("N/A", "N/A", "GPU unknown", util="70")]
        runner = ScriptedRunner([csv_output(rows)])
        result = run_two(GpuSampler(platform="win32", runner=runner), runner)
        self.assertEqual(result["status"], "partial")
        devices = backend(result, "nvidia_smi")["devices"]
        self.assertEqual(len(devices), 3)
        self.assertEqual([item["metrics"]["gpu_utilization_pct"] for item in devices], [5, 90, 70])
        self.assertEqual(result["summary_by_device"], {})
        self.assertEqual([item["identity"]["status"] for item in devices],
                         ["duplicate_id", "duplicate_id", "unavailable"])

    def test_optional_missing_and_invalid_metrics_do_not_fail_utilization_coverage(self):
        row = nvidia_row("GPU-x", "00000000:01:00.0", "GPU", util="71", clock="NaN",
                         mem_clock="N/A", temp="N/A", power="N/A", used="N/A", total="N/A")
        runner = ScriptedRunner([csv_output([row])])
        result = run_two(GpuSampler(platform="win32", runner=runner), runner)
        item = backend(result, "nvidia_smi")["devices"][0]
        self.assertEqual(result["status"], "available")
        self.assertEqual(item["metrics"]["gpu_utilization_pct"], 71)
        self.assertEqual(item["metric_status"]["graphics_clock_mhz"], "invalid")
        self.assertEqual(item["metric_status"]["temperature_c"], "unsupported")

    def test_device_set_change_marks_coverage_partial(self):
        first = nvidia_row("GPU-a", "0000:01:00.0", "First")
        second = nvidia_row("GPU-b", "0000:02:00.0", "Second")
        for sequences in (([first, second], [first]), ([first], [first, second])):
            with self.subTest(sequences=sequences):
                runner = ScriptedRunner([csv_output(rows) for rows in sequences])
                sampler = GpuSampler(platform="win32", runner=runner, interval=.1)
                sampler.start()
                deadline = time.monotonic() + 2
                while len(runner.calls) < 2 and time.monotonic() < deadline:
                    threading.Event().wait(.01)
                result = sampler.stop()
                self.assertEqual(result["status"], "partial")
                self.assertEqual(result["backends"]["nvidia_smi"]["device_set_changes"], 1)
                self.assertEqual(set(result["summary_by_device"]), {"nvidia:uuid:GPU-a", "nvidia:uuid:GPU-b"})

    def test_backend_failure_after_a_good_poll_marks_partial(self):
        runner = ScriptedRunner([csv_output([nvidia_row("GPU-x", "0000:01:00.0", "GPU")]),
                                 subprocess.TimeoutExpired("nvidia-smi", 2)])
        sampler = GpuSampler(platform="win32", runner=runner, interval=.1)
        sampler.start()
        deadline = time.monotonic() + 2
        while len(runner.calls) < 2 and time.monotonic() < deadline:
            threading.Event().wait(.01)
        result = sampler.stop()
        self.assertEqual(result["status"], "partial")
        self.assertIn("nvidia:uuid:GPU-x", result["summary_by_device"])
        self.assertIn("timeout", result["errors"][0]["reason"])

    def test_nonfinite_apple_values_are_safe_and_not_zero(self):
        data = [{"IORegistryEntryID": 2, "PerformanceStatistics": {"Device Utilization %": float("nan")}}]
        runner = ScriptedRunner([plistlib.dumps(data)])
        result = run_two(GpuSampler(platform="darwin", runner=runner), runner)
        item = backend(result, "apple_ioreg_agx")["devices"][0]
        self.assertEqual(result["status"], "unavailable")
        self.assertIsNone(item["metrics"]["gpu_utilization_pct"])
        self.assertEqual(item["metric_status"]["gpu_utilization_pct"], "invalid")
        self.assertEqual(item["raw"]["Device Utilization %"], "nan")
        json.dumps(result, allow_nan=False)

    def test_bounded_stop_seals_report_if_backend_does_not_return(self):
        entered, release, exited = threading.Event(), threading.Event(), threading.Event()
        def stuck(argv, **kwargs):
            entered.set()
            release.wait(3)
            exited.set()
            return subprocess.CompletedProcess(argv, 0, stdout=csv_output([nvidia_row("GPU-x", "0", "x")]), stderr=b"")
        sampler = GpuSampler(platform="win32", runner=stuck)
        sampler.start()
        self.assertTrue(entered.wait(1))
        began = time.monotonic()
        result = sampler.stop(join_timeout=.05)
        elapsed = time.monotonic() - began
        self.assertLess(elapsed, .5)
        self.assertTrue(result["thread_alive"])
        self.assertEqual(result["worker_exit_reason"], "deadline_exceeded")
        self.assertEqual(result["status"], "unavailable")
        self.assertEqual(result["samples"], [])
        release.set()
        self.assertTrue(exited.wait(1))
        sampler._thread.join(1)
        self.assertEqual(sampler.stop(), result)
        self.assertEqual(result["samples"], [])

    def test_sample_and_error_caps_stop_polling(self):
        runner = ScriptedRunner([FileNotFoundError("missing")])
        sampler = GpuSampler(platform="win32", runner=runner, interval=.1, max_samples=22)
        sampler.start()
        sampler._thread.join(4)
        self.assertFalse(sampler._thread.is_alive())
        result = sampler.stop()
        self.assertEqual(result["sample_count"], 22)
        self.assertTrue(result["sample_cap_reached"])
        self.assertEqual(result["worker_exit_reason"], "sample_cap_reached")
        self.assertEqual(result["error_count"], 22)
        self.assertEqual(len(result["errors"]), 20)
        self.assertEqual(len(runner.calls), 22)
        self.assertEqual(result["status"], "unavailable")

    @linux_sysfs_fixture
    def test_linux_amdgpu_read_only_sysfs_and_separate_devices(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            drm, pci = root / "drm", root / "pci"
            drm.mkdir()
            pci.mkdir()
            driver = root / "drivers" / "amdgpu"
            driver.mkdir(parents=True)
            for number, busy in ((1, 32), (2, 75)):
                device = root / "devices" / f"0000:0{number}:00.0"
                device.mkdir(parents=True)
                self.symlink(device / "driver", driver)
                (device / "vendor").write_text("0x1002\n")
                (device / "device").write_text(f"0x73{number}0\n")
                (device / "gpu_busy_percent").write_text(f"{busy}\n")
                (device / "mem_info_vram_used").write_text("1024\n")
                (device / "mem_info_vram_total").write_text("4096\n")
                (device / "pp_dpm_sclk").write_text("0: 500Mhz\n1: 1.5Ghz *\n")
                hwmon = device / "hwmon" / f"hwmon{number}"
                hwmon.mkdir(parents=True)
                (hwmon / "name").write_text("amdgpu\n")
                (hwmon / "temp1_input").write_text("45000\n")
                (hwmon / "power1_average").write_text("123000000\n")
                card = drm / f"card{number}"
                card.mkdir()
                self.symlink(card / "device", device)
                self.symlink(pci / device.name, device)
            # A connector path must not be interpreted as another GPU.
            (drm / "card1-DP-1").mkdir()
            runner = ScriptedRunner([FileNotFoundError("no NVIDIA tool")])
            result = run_two(GpuSampler(platform="linux", runner=runner, sysfs_root=drm, pci_root=pci), runner)
            self.assertEqual(result["status"], "available")
            self.assertEqual(backend(result, "nvidia_smi")["status"], "not_applicable")
            self.assertEqual(result["error_count"], 0)
            self.assertEqual(result["samples"][0]["linux_inventory"]["status"], "visible_pci_and_drm_consistent")
            devices = backend(result, "amdgpu_sysfs")["devices"]
            self.assertEqual(len(devices), 2)
            self.assertEqual([item["identity"]["pci_bus_id"] for item in devices], ["0000:01:00.0", "0000:02:00.0"])
            self.assertEqual([item["metrics"]["gpu_utilization_pct"] for item in devices], [32, 75])
            self.assertEqual(devices[0]["metrics"]["graphics_clock_mhz"], 1500)
            self.assertEqual(devices[0]["metrics"]["temperature_c"], 45)
            self.assertEqual(devices[0]["metrics"]["power_w"], 123)
            self.assertEqual(devices[0]["metrics"]["memory_used_bytes"], 1024)
            self.assertEqual(devices[0]["identity"]["device_id"], "0x7310")
            self.assertEqual(len(result["summary_by_device"]), 2)
            json.dumps(result, allow_nan=False)
            # Both independent backends must coexist in the same poll.
            runner = ScriptedRunner([csv_output([nvidia_row("GPU-nv", "0000:03:00.0", "NVIDIA")])])
            mixed = run_two(GpuSampler(platform="linux", runner=runner, sysfs_root=drm), runner)
            self.assertEqual(mixed["status"], "available")
            self.assertIn("nvidia:uuid:GPU-nv", mixed["summary_by_device"])
            self.assertEqual(len(mixed["summary_by_device"]), 3)

    @linux_sysfs_fixture
    def test_linux_absence_requires_consistent_inventory_and_keeps_failures_partial(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            drm, pci = self.amd_host(root)
            def sample(outcome, *, pci_path=pci):
                runner = ScriptedRunner([outcome])
                return run_two(GpuSampler(platform="linux", runner=runner, sysfs_root=drm, pci_root=pci_path), runner)

            absent = sample(FileNotFoundError("missing"))
            self.assertEqual(absent["status"], "available")
            self.assertEqual(backend(absent, "nvidia_smi")["status"], "not_applicable")
            self.assertEqual(absent["samples"][0]["linux_inventory"]["pci_vendor_ids"], ["0x1002"])
            self.assertIn("visible PCI", absent["coverage_limitations"])
            self.assertIn("tool_not_found", backend(absent, "nvidia_smi")["unavailable_reason"])

            unknown = sample(FileNotFoundError("missing"), pci_path=root / "no-pci")
            self.assertEqual(unknown["status"], "partial")
            self.assertEqual(unknown["samples"][0]["linux_inventory"]["status"], "unknown")
            self.assertEqual(backend(unknown, "nvidia_smi")["status"], "unavailable")

            # A visible NVIDIA vendor entry, even without a DRM card, prevents
            # declaring its missing tool inapplicable.
            nvidia = root / "0000:03:00.0"
            nvidia.mkdir()
            (nvidia / "vendor").write_text("0x10de")
            self.symlink(pci / nvidia.name, nvidia)
            present = sample(FileNotFoundError("missing"))
            self.assertEqual(present["status"], "partial")
            self.assertEqual(backend(present, "nvidia_smi")["status"], "unavailable")
            self.assertIn("0x10de", present["samples"][0]["linux_inventory"]["pci_vendor_ids"])

            # Failure to inspect any PCI vendor is not evidence of absence.
            real_file = GpuSampler._file
            def denied(path):
                return (None, "permission_denied") if path.parent.parent == pci else real_file(path)
            with mock.patch.object(GpuSampler, "_file", side_effect=denied):
                denied_result = sample(FileNotFoundError("missing"))
            self.assertEqual(denied_result["status"], "partial")
            self.assertIn("pci_vendor_unavailable", denied_result["samples"][0]["linux_inventory"]["reason"])

            timed_out = sample(subprocess.TimeoutExpired("nvidia-smi", 2))
            self.assertEqual(timed_out["status"], "partial")
            self.assertIn("timeout", timed_out["errors"][0]["reason"])

    @linux_sysfs_fixture
    def test_non_pci_drm_device_makes_absence_unknown(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            drm, pci = self.amd_host(root)
            platform_gpu = root / "platform-gpu"
            platform_gpu.mkdir()
            (platform_gpu / "vendor").write_text("0x8086")
            (drm / "card1").mkdir()
            self.symlink(drm / "card1" / "device", platform_gpu)
            runner = ScriptedRunner([FileNotFoundError("missing")])
            result = run_two(GpuSampler(platform="linux", runner=runner, sysfs_root=drm, pci_root=pci), runner)
            self.assertEqual(result["status"], "partial")
            self.assertEqual(result["samples"][0]["linux_inventory"]["status"], "unknown")
            self.assertIn("drm_identity", result["samples"][0]["linux_inventory"]["reason"])

    @linux_sysfs_fixture
    def test_linux_gpu_disappearing_cannot_become_not_applicable_without_degrading(self):
        with tempfile.TemporaryDirectory() as temporary:
            drm, pci = self.amd_host(Path(temporary))
            nvidia = csv_output([nvidia_row("GPU-x", "0000:03:00.0", "NVIDIA")])
            for outcomes in ([nvidia, FileNotFoundError("removed")], [FileNotFoundError("missing"), nvidia]):
                with self.subTest(outcomes=outcomes):
                    runner = ScriptedRunner(outcomes)
                    result = run_two(GpuSampler(platform="linux", runner=runner, sysfs_root=drm, pci_root=pci), runner)
                    self.assertEqual(result["status"], "partial")
                    self.assertEqual(result["backends"]["nvidia_smi"]["device_set_changes"], 1)
                    self.assertIn("device_set_changed", result["status_reasons"])

    @linux_sysfs_fixture
    def test_amd_device_model_change_does_not_merge_two_identities(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            drm, pci = self.amd_host(root)
            calls = []
            def runner(argv, **kwargs):
                calls.append(argv)
                if len(calls) == 2:
                    (root / "0000:01:00.0" / "device").write_text("0x7330")
                raise FileNotFoundError("missing")
            sampler = GpuSampler(platform="linux", runner=runner, sysfs_root=drm, pci_root=pci, interval=.1)
            sampler.start()
            wait_samples(sampler, 2)
            result = sampler.stop()
            self.assertEqual(result["status"], "partial")
            self.assertEqual(result["backends"]["amdgpu_sysfs"]["device_set_changes"], 1)
            ids = {item["identity"]["device_id"] for item in result["summary_by_device"].values()}
            self.assertEqual(ids, {"0x7310", "0x7330"})
            self.assertEqual(len(result["summary_by_device"]), 2)
            self.assertIn("not a serial", result["coverage_limitations"])

    @linux_sysfs_fixture
    def test_linux_nvidia_only_amd_not_applicable_but_hidden_amd_keeps_partial(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            drm, pci, device = root / "drm", root / "pci", root / "0000:03:00.0"
            drm.mkdir()
            pci.mkdir()
            device.mkdir()
            (device / "vendor").write_text("0x10de")
            (drm / "card0").mkdir()
            self.symlink(drm / "card0" / "device", device)
            self.symlink(pci / device.name, device)
            def sample():
                runner = ScriptedRunner([csv_output([nvidia_row("GPU-x", "00000000:03:00.0", "GPU")])])
                return run_two(GpuSampler(platform="linux", runner=runner, sysfs_root=drm, pci_root=pci), runner)
            result = sample()
            self.assertEqual(result["status"], "available")
            self.assertEqual(backend(result, "amdgpu_sysfs")["status"], "not_applicable")
            amd = root / "0000:04:00.0"
            amd.mkdir()
            (amd / "vendor").write_text("0x1002")
            self.symlink(pci / amd.name, amd)
            result = sample()
            self.assertEqual(result["status"], "partial")
            self.assertEqual(backend(result, "amdgpu_sysfs")["status"], "unavailable")

    def test_source_hash_changed_or_missing_cannot_qualify(self):
        for initial, final, changed in (("a" * 64, "b" * 64, True),
                                        (None, "a" * 64, None), ("a" * 64, None, None)):
            with self.subTest(initial=initial, final=final), \
                    mock.patch("tools.godtest.hardware._source_digest", side_effect=[initial, final]):
                runner = ScriptedRunner([csv_output([nvidia_row("GPU-x", "0", "GPU")])])
                result = run_two(GpuSampler(platform="win32", runner=runner), runner)
                self.assertEqual(result["status"], "partial")
                self.assertIs(result["source_changed"], changed)
                self.assertEqual(result["source_sha256"], initial)
                self.assertEqual(result["source_end_sha256"], final)
                self.assertIn("source_changed_or_unverifiable", result["status_reasons"])
                self.assertEqual(result["timing_coverage"]["status"], "complete")

    def test_one_valid_utilization_sample_cannot_qualify(self):
        runner = ScriptedRunner([csv_output([nvidia_row("GPU-x", "0", "GPU")])])
        sampler = GpuSampler(platform="win32", runner=runner, interval=60)
        sampler.start()
        wait_samples(sampler, 1)
        result = sampler.stop()
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["worker_exit_reason"], "owner_stopped")
        self.assertLessEqual(result["stop_requested_monotonic_usec"], result["stop_monotonic_usec"])
        self.assertEqual(result["timing_coverage"]["status"], "incomplete")
        self.assertIn("fewer_than_two_utilization_samples_per_device", result["timing_coverage"]["reasons"])

    def test_each_device_needs_two_valid_utilization_observations(self):
        rows = [nvidia_row("GPU-a", "0000:01:00.0", "GPU one"),
                nvidia_row("GPU-b", "0000:02:00.0", "GPU two", util="N/A")]
        runner = ScriptedRunner([csv_output(rows)])
        result = run_two(GpuSampler(platform="win32", runner=runner), runner)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["summary_by_device"]["nvidia:uuid:GPU-a"]["metrics"]["gpu_utilization_pct"]["count"], 2)
        self.assertEqual(result["summary_by_device"]["nvidia:uuid:GPU-b"]["metrics"]["gpu_utilization_pct"]["count"], 0)
        self.assertEqual(result["timing_coverage"]["status"], "incomplete")
        self.assertIn("fewer_than_two_utilization_samples_per_device", result["timing_coverage"]["reasons"])

    def test_long_poll_gap_cannot_qualify(self):
        calls = []
        def slow_second(argv, **kwargs):
            calls.append(argv)
            if len(calls) == 2:
                threading.Event().wait(.8)
            return subprocess.CompletedProcess(argv, 0, stdout=csv_output([nvidia_row("GPU-x", "0", "GPU")]), stderr=b"")
        sampler = GpuSampler(platform="win32", runner=slow_second, interval=.1)
        sampler.start()
        wait_samples(sampler, 3)
        result = sampler.stop()
        timing = result["timing_coverage"]
        self.assertEqual(result["status"], "partial")
        self.assertEqual(timing["status"], "incomplete")
        self.assertGreater(timing["max_inter_sample_start_gap_usec"], timing["gap_limit_usec"])
        self.assertIn("device_observation_gap", timing["reasons"])
        self.assertIn("poll_gap", timing["reasons"])

    def test_worker_failure_and_start_stop_bracket_coverage_are_explicit(self):
        sampler = GpuSampler(platform="win32", runner=ScriptedRunner([b""]), interval=.1)
        sampler._start_us = 1_000_000
        samples = [{"start_monotonic_usec": 1_700_000, "end_monotonic_usec": 1_700_001,
                    "backends": [{"start_monotonic_usec": 1_700_000, "end_monotonic_usec": 1_700_001}]},
                   {"start_monotonic_usec": 1_800_000, "end_monotonic_usec": 1_800_001,
                    "backends": [{"start_monotonic_usec": 1_800_000, "end_monotonic_usec": 1_800_001}]}]
        timing = sampler._timing_coverage(samples, 2_500_000, {"gpu": [(1_700_000, 1_700_001),
                                                                       (1_800_000, 1_800_001)]})
        self.assertEqual(timing["gap_limit_usec"], 550_000)
        self.assertIn("first_observation_delayed", timing["reasons"])
        self.assertIn("last_observation_too_early", timing["reasons"])
        self.assertEqual(timing["status"], "incomplete")

        runner = ScriptedRunner([csv_output([nvidia_row("GPU-x", "0", "GPU")])])
        sampler = GpuSampler(platform="win32", runner=runner, interval=.1)
        def unexpected_exit():
            for _ in range(2):
                sample = sampler._poll()
                with sampler._lock:
                    sampler._samples.append(sample)
            raise RuntimeError("injected worker fault")
        with mock.patch.object(sampler, "_run_loop", side_effect=unexpected_exit):
            sampler.start()
            sampler._thread.join(1)
        result = sampler.stop()
        self.assertEqual(result["worker_exit_reason"], "error")
        self.assertEqual(result["status"], "partial")
        self.assertIn("worker_error", result["status_reasons"])

    @linux_sysfs_fixture
    def test_permissions_on_optional_sysfs_metric_are_reported(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            drm, device, driver = root / "drm", root / "0000:01:00.0", root / "amdgpu"
            drm.mkdir()
            device.mkdir()
            driver.mkdir()
            (drm / "card0").mkdir()
            self.symlink(drm / "card0" / "device", device)
            self.symlink(device / "driver", driver)
            (device / "vendor").write_text("0x1002")
            (device / "gpu_busy_percent").write_text("10")
            real_file = GpuSampler._file
            def read(path):
                return (None, "permission_denied") if path.name == "mem_info_vram_used" else real_file(path)
            runner = ScriptedRunner([FileNotFoundError("missing")])
            with mock.patch.object(GpuSampler, "_file", side_effect=read):
                result = run_two(GpuSampler(platform="linux", runner=runner, sysfs_root=drm), runner)
            item = backend(result, "amdgpu_sysfs")["devices"][0]
            self.assertEqual(item["metric_status"]["memory_used_bytes"], "permission_denied")
            self.assertIsNone(item["metrics"]["memory_used_bytes"])
            self.assertEqual(result["status"], "partial")
            self.assertFalse(result["thread_alive"])

    def test_unsupported_platform_and_invalid_options(self):
        sampler = GpuSampler(platform="unsupported")
        sampler.start()
        result = sampler.stop()
        self.assertEqual(result["status"], "unavailable")
        self.assertFalse(result["thread_alive"])
        for kwargs in ({"interval": 0}, {"interval": float("nan")}, {"interval": True},
                       {"interval": 10**1000}, {"max_samples": True}, {"max_samples": 10001}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                GpuSampler(**kwargs)
        for timeout in (6, 10**1000):
            with self.assertRaises(ValueError):
                GpuSampler().stop(join_timeout=timeout)


if __name__ == "__main__":
    unittest.main()
