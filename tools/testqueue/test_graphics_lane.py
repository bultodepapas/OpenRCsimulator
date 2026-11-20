"""TQ-06 GPU lane: rendered checks on a remote host with a declared GPU."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools.testqueue import pool_batch, pool_mcp
from tools.testqueue import remote_agent as agent
from tools.testqueue.pool_policy import plan

INTEL_VULKAN = "Vulkan 1.4.305 - Forward+ - Using Device #0: Intel - Intel(R) UHD Graphics 630 (CFL GT2)"
INTEL_GL = ("OpenGL API 4.6 (Core Profile) Mesa 25.0.7-2+deb13u1 - Compatibility - Using Device: "
            "Intel - Mesa Intel(R) UHD Graphics 630 (CFL GT2)")
CONFIG = {"compositor": "weston-headless", "gpu": "intel-uhd630", "adapter": "UHD Graphics 630",
          "render_node": "/dev/dri/renderD128"}


def request(**options):
    base = {"script": "res://tests/test_sample.gd", "require": ["0 failed"], "timeout": 90}
    base_dir = Path(tempfile.gettempdir()).resolve()
    return {"request_id": "job1", "preset": "checked",
            "archive": {"path": str(base_dir / "job1.tar"), "sha256": "a" * 64},
            "engine_path": str(base_dir / "godot"), "options": {**base, **options}}


class CommandTests(unittest.TestCase):
    def test_headless_commands_are_unchanged(self):
        options = {"script": "res://tests/test_x.gd"}
        self.assertEqual(agent.checked_command("/e", "/s/app", options, "import"),
                         ["/e", "--headless", "--path", "/s/app", "--audio-driver", "Dummy", "--import"])
        self.assertEqual(agent.checked_command("/e", "/s/app", options, "check"),
                         ["/e", "--headless", "--path", "/s/app", "--audio-driver", "Dummy",
                          "--script", "res://tests/test_x.gd"])

    def test_graphics_check_renders_but_import_stays_headless(self):
        options = {"script": "res://tests/test_x.gd", "workload": "graphics", "rendering_driver": "vulkan"}
        self.assertEqual(agent.checked_command("/e", "/s/app", options, "check"),
                         ["/e", "--path", "/s/app", "--audio-driver", "Dummy", "--display-driver", "wayland",
                          "--rendering-driver", "vulkan", "--resolution", "1920x1080",
                          "--script", "res://tests/test_x.gd"])
        self.assertIn("--headless", agent.checked_command("/e", "/s/app", options, "import"))


class ValidationTests(unittest.TestCase):
    def test_graphics_options_are_accepted(self):
        for driver in agent.RENDERING_DRIVERS:
            agent.validate_request(request(headless=False, workload="graphics", rendering_driver=driver))

    def test_invalid_graphics_combinations_are_refused(self):
        for options in ({"headless": True, "workload": "graphics", "rendering_driver": "vulkan"},
                        {"headless": False, "workload": "graphics"},
                        {"headless": False, "workload": "graphics", "rendering_driver": "d3d12"},
                        {"rendering_driver": "vulkan"},
                        {"headless": False},
                        {"headless": False, "workload": "graphics", "rendering_driver": "vulkan", "argv": ["--x"]}):
            with self.subTest(options=options), self.assertRaises(agent.Refused):
                agent.validate_request(request(**options))


class VerdictTests(unittest.TestCase):
    def test_declared_adapter_passes(self):
        for line, driver in ((INTEL_VULKAN, "vulkan"), (INTEL_GL, "opengl3")):
            verdict = agent.gpu_verdict("Godot Engine v4.8\n" + line + "\nall checks passed\n", CONFIG, driver)
            self.assertTrue(verdict["ok"], verdict)

    def test_requested_driver_must_match(self):
        verdict = agent.gpu_verdict(INTEL_GL, CONFIG, "vulkan")
        self.assertEqual((verdict["ok"], verdict["reason"]), (False, "unexpected_driver"))

    def test_engine_line_wins_over_later_script_output(self):
        text = INTEL_VULKAN.replace("Intel(R) UHD", "llvmpipe UHD") + "\n" + INTEL_VULKAN
        self.assertEqual(agent.gpu_verdict(text, CONFIG, "vulkan")["reason"], "software_renderer")

    def test_software_missing_or_other_adapters_fail(self):
        cases = {"software_renderer": "Vulkan 1.4 - Forward+ - Using Device #0: Mesa - llvmpipe (LLVM 19, 256 bits)",
                 "unexpected_adapter": "Vulkan 1.4 - Forward+ - Using Device #0: AMD - Radeon 780M",
                 "no_device_line": "Godot Engine v4.8"}
        for reason, text in cases.items():
            with self.subTest(reason=reason):
                verdict = agent.gpu_verdict(text, CONFIG, "vulkan")
                self.assertFalse(verdict["ok"])
                self.assertEqual(verdict["reason"], reason)

    def test_colour_codes_do_not_hide_the_device(self):
        self.assertTrue(agent.gpu_verdict("\x1b[1m" + INTEL_VULKAN + "\x1b[0m", CONFIG, "vulkan")["ok"])


class ConfigTests(unittest.TestCase):
    def test_config_needs_valid_declaration_and_usable_host(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertIsNone(agent.graphics_config(root))
            Path(root, agent.GRAPHICS_CONFIG).write_text(json.dumps({**CONFIG, "render_node": "/dev/sda"}))
            self.assertIsNone(agent.graphics_config(root))
            Path(root, agent.GRAPHICS_CONFIG).write_text(json.dumps(CONFIG))
            with mock.patch.object(agent, "POSIX", True), \
                    mock.patch.object(agent.os, "access", return_value=True), \
                    mock.patch.object(agent.shutil, "which", return_value="/usr/bin/weston"):
                self.assertEqual(agent.graphics_config(root)["gpu"], "intel-uhd630")
            with mock.patch.object(agent, "POSIX", True), \
                    mock.patch.object(agent.os, "access", return_value=False), \
                    mock.patch.object(agent.shutil, "which", return_value="/usr/bin/weston"):
                self.assertIsNone(agent.graphics_config(root))


class CoordinatorTests(unittest.TestCase):
    def test_mcp_jobs_pass_the_driver_only_when_given(self):
        jobs = pool_mcp._jobs([{"script": "res://tests/test_math3d.gd", "platform": "linux"},
                               {"script": "res://tests/test_math3d.gd", "platform": "linux",
                                "rendering_driver": "opengl3"}])
        self.assertNotIn("rendering_driver", jobs[0])
        self.assertEqual(jobs[1]["rendering_driver"], "opengl3")
        with self.assertRaises(ValueError):
            pool_mcp._jobs([{"script": "res://tests/test_math3d.gd", "rendering_driver": "metal"}])

    def test_fleet_view_names_the_gpu_of_graphics_hosts(self):
        from tools.testqueue.agent_view import _host_view
        base = {"platform": "linux", "online": True, "busy": False, "load": 0.0, "cores": 4}
        gpu = _host_view({**base, "id": "primis", "capabilities": ["headless", "graphics", "gpu:intel-uhd630"]}, {})
        plain = _host_view({**base, "id": "linux", "capabilities": ["headless"]}, {})
        self.assertEqual(gpu["gpu"], "intel-uhd630")
        self.assertNotIn("gpu", plain)

    def test_gpu_jobs_default_to_linux(self):
        jobs = pool_mcp._jobs([{"script": "res://tests/test_math3d.gd", "rendering_driver": "vulkan"}])
        self.assertEqual(jobs[0]["platform"], "linux")

    def test_batch_manifest_keeps_the_driver(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder, "batch.json")
            path.write_text(json.dumps({"snapshot": folder, "jobs": [
                {"script": "res://tests/test_math3d.gd", "platform": "linux", "rendering_driver": "vulkan"},
                {"script": "res://tests/test_math3d.gd", "platform": "linux"}]}))
            _snapshot, jobs = pool_batch._manifest(path)
        self.assertEqual(jobs[0]["rendering_driver"], "vulkan")
        self.assertNotIn("rendering_driver", jobs[1])

    def test_graphics_jobs_need_the_graphics_capability(self):
        host = {"online": True, "busy": False, "platform": "linux", "free_disk_bytes": 50 * 1024**3,
                "free_memory_bytes": 4 * 1024**3, "load": 0.0, "cores": 4}
        hosts = [{**host, "id": "linux", "capabilities": ["checked", "headless", "linux"]},
                 {**host, "id": "primis", "capabilities": ["checked", "headless", "linux", "graphics", "gpu:intel-uhd630"]}]
        self.assertEqual(plan({"platform": "linux", "workload": "graphics"}, hosts)["selected"], "primis")
        self.assertIsNone(plan({"platform": "linux", "workload": "graphics"}, hosts[:1])["selected"])


if __name__ == "__main__":
    unittest.main()
