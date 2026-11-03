"""Resource monitoring must never hide a command failure or change default runs."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

from run_checked import run_checked


class ResourceRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc resources ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_code(self, code="import time; time.sleep(.15)", **options):
        return run_checked([sys.executable, "-c", code], self.root, **options)

    def mocked_sampler(self):
        backend = mock.patch("resource_samples.load_backend", return_value=object())
        backend.start()
        self.addCleanup(backend.stop)
        sampler = mock.patch("resource_samples.ResourceSampler")
        factory = sampler.start()
        self.addCleanup(sampler.stop)
        factory.return_value.finish.return_value = {
            "format": "openrc-resource-samples v1", "coverage": "sampled", "samples": []}
        return factory

    def resource_report(self, checked):
        return json.loads((Path(checked["report"]).parent / "resources.json").read_text())

    def test_default_does_not_load_backend_or_create_samples(self):
        with mock.patch("resource_samples.load_backend", side_effect=AssertionError("unexpected import")):
            checked = self.run_code("pass")
        self.assertTrue(checked["ok"])
        self.assertNotIn("resources", checked)
        self.assertFalse((Path(checked["report"]).parent / "resources.json").exists())
        self.assertNotIn("host_state", checked)

    def test_capture_identity_reaches_child_and_is_unique(self):
        code = "import os; print(os.environ['OPENRC_DIAGNOSTIC_CAPTURE_ID'])"
        first = self.run_code(code)
        second = self.run_code(code)
        self.assertTrue(first["ok"])
        self.assertNotEqual(first["capture_id"], second["capture_id"])
        self.assertEqual(Path(first["log"]).read_text().strip(), first["capture_id"])

    def test_resource_receipt_identifies_bytes_and_same_invocation(self):
        factory = self.mocked_sampler()
        checked = self.run_code(resources=True, resource_interval=.2, resource_disk_paths=[self.root], resource_threads=True)
        self.assertTrue(checked["ok"])
        self.assertTrue(factory.return_value.poll.called)
        self.assertEqual(factory.call_args.kwargs["interval"], .2)
        self.assertTrue(factory.call_args.kwargs["include_threads"])
        self.assertFalse(factory.call_args.kwargs["raw_uptime"])
        raw = (Path(checked["report"]).parent / "resources.json").read_bytes()
        self.assertEqual(checked["resources"]["bytes"], len(raw))
        self.assertEqual(checked["resources"]["sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(json.loads(raw)["invocation"]["log_sha256"], checked["log_sha256"])
        self.assertEqual(json.loads(raw)["capture_id"], checked["capture_id"])
        self.assertEqual(json.loads(raw)["invocation"]["capture_id"], checked["capture_id"])
        self.assertEqual(set(json.loads(raw)["tool_source_sha256"]), {"run_checked.py", "resource_samples.py"})

    def test_poll_failure_keeps_healthy_command_and_marks_partial(self):
        factory = self.mocked_sampler()
        factory.return_value.poll.side_effect = RuntimeError("counter unavailable")
        checked = self.run_code(resources=True)
        self.assertTrue(checked["ok"])
        self.assertEqual(checked["resources"]["coverage"], "partial")
        self.assertIn("counter unavailable", self.resource_report(checked)["runner_sampler_error"])
        self.assertEqual(factory.return_value.poll.call_count, 1)

    def test_constructor_and_finish_failure_are_visible(self):
        factory = self.mocked_sampler()
        factory.side_effect = RuntimeError("attach failed")
        checked = self.run_code(resources=True)
        self.assertTrue(checked["ok"])
        self.assertIn("attach failed", checked["resources"]["error"])
        self.assertFalse(checked["resources"]["published"])
        self.assertFalse((Path(checked["report"]).parent / "resources.json").exists())
        factory.side_effect = None
        factory.return_value.finish.side_effect = RuntimeError("finish failed")
        checked = self.run_code(resources=True)
        self.assertTrue(checked["ok"])
        self.assertEqual(checked["resources"]["coverage"], "unavailable")
        self.assertFalse(checked["resources"]["published"])
        self.assertIsNone(checked["resources"]["file"])

    def test_nonzero_and_timeout_cannot_be_overridden_by_resources(self):
        self.mocked_sampler()
        for code, timeout, expected in (("raise SystemExit(7)", 10, "process_exit"),
                                        ("import time; time.sleep(10)", .15, "timeout")):
            with self.subTest(expected=expected):
                checked = self.run_code(code, resources=True, timeout=timeout)
                self.assertFalse(checked["ok"])
                self.assertEqual(checked["reason"], expected)
                self.assertEqual(self.resource_report(checked)["invocation"]["reason"], expected)

    def test_launch_failure_has_no_fake_sample(self):
        factory = self.mocked_sampler()
        checked = run_checked([str(self.root / "missing")], self.root, resources=True)
        self.assertEqual(checked["reason"], "launch_error")
        factory.assert_not_called()
        self.assertEqual(checked["resources"]["coverage"], "unavailable")
        self.assertFalse(checked["resources"]["published"])
        self.assertFalse((Path(checked["report"]).parent / "resources.json").exists())

    def test_disk_full_during_resource_publication_is_visible(self):
        self.mocked_sampler()
        original = Path.open

        def open_path(path, *args, **kwargs):
            if path.name == "resources.json":
                raise OSError("No space left on device (injected)")
            return original(path, *args, **kwargs)

        with mock.patch.object(Path, "open", open_path):
            checked = self.run_code(resources=True)
        self.assertTrue(checked["ok"])
        self.assertEqual(checked["resources"]["coverage"], "unavailable")
        self.assertIn("No space left", checked["resources"]["error"])
        self.assertFalse(checked["resources"]["published"])
        self.assertIsNone(checked["resources"]["file"])
        self.assertTrue(Path(checked["report"]).exists())

    def test_bad_options_and_launcher_refused_before_launch(self):
        self.mocked_sampler()
        bad = [{"resource_interval": .5}, {"resource_disk_paths": [self.root]},
               {"resource_threads": True},
               {"resources": "yes"},
               {"resources": True, "resource_interval": float("nan")},
               {"resources": True, "resource_max_samples": 0},
               {"resources": True, "resource_disk_paths": [self.root / "missing"]}]
        with mock.patch("run_checked.subprocess.Popen") as launch:
            for options in bad:
                with self.subTest(options=options), self.assertRaises(ValueError):
                    self.run_code(**options)
            with self.assertRaisesRegex(ValueError, "direct Godot"):
                run_checked(["Godot_v4.7.2-stable_win64_console.exe"], self.root, resources=True)
            launch.assert_not_called()

    def test_host_capture_reuses_id_and_records_separate_overhead(self):
        from macos_host_state import _file_identity
        helper = self.root / "fixture-helper"
        helper.write_bytes(b"frozen helper fixture\n")
        helper.chmod(0o700)
        factory = self.mocked_sampler()
        with mock.patch("run_checked.sys.platform", "darwin"), \
                mock.patch("macos_host_state.HostStateCapture") as host_factory:
            host_factory.return_value.helper_identity = _file_identity(helper)
            host_factory.return_value.identity_errors = []
            host_factory.return_value.process.pid = 12345
            host_factory.return_value.finish.return_value = {
                "coverage": "complete", "memory_pressure_initial": "unknown"}
            checked = self.run_code(resources=True, host_state_helper=helper)
        self.assertTrue(checked["ok"])
        self.assertEqual(checked["host_state"]["capture_id"], checked["capture_id"])
        self.assertEqual(host_factory.call_args.args[1], checked["capture_id"])
        self.assertEqual(factory.call_count, 3)  # game, helper and runner
        self.assertTrue(all(call.kwargs["raw_uptime"] for call in factory.call_args_list))
        overhead_file = Path(checked["report"]).parent / checked["host_state"]["overhead"]["file"]
        self.assertEqual(json.loads(overhead_file.read_text())["capture_id"], checked["capture_id"])

    def test_host_failure_does_not_end_healthy_game(self):
        self.mocked_sampler()
        with mock.patch("macos_host_state.HostStateCapture", side_effect=RuntimeError("unavailable")):
            checked = self.run_code(resources=True, host_state_helper=Path("missing"))
        self.assertTrue(checked["ok"])
        self.assertEqual(checked["host_state"]["coverage"], "unavailable")
        self.assertIn("unavailable", checked["host_state"]["error"])

    def test_darwin_host_helper_binds_raw_clock_to_child_and_samplers(self):
        from macos_host_state import _file_identity
        helper = self.root / "clock-helper"
        helper.write_bytes(b"frozen helper\n")
        helper.chmod(0o700)
        identity = _file_identity(helper)
        factory = self.mocked_sampler()
        code = ("import json, os; print(json.dumps([os.environ.get('OPENRC_RAW_CLOCK_HELPER'),"
                "os.environ.get('OPENRC_RAW_CLOCK_HELPER_SHA256')]))")
        with mock.patch("run_checked.sys.platform", "darwin"), \
                mock.patch("macos_host_state.HostStateCapture") as host_factory:
            host_factory.return_value.helper_identity = identity
            host_factory.return_value.identity_errors = []
            host_factory.return_value.process.pid = 12345
            host_factory.return_value.finish.return_value = {"coverage": "complete"}
            checked = self.run_code(code, resources=True, host_state_helper=helper)
        self.assertTrue(checked["ok"])
        self.assertEqual(json.loads(Path(checked["log"]).read_text()), [str(helper), identity[0]])
        self.assertEqual(factory.call_count, 3)
        self.assertTrue(all(call.kwargs["raw_uptime"] for call in factory.call_args_list))
        self.assertEqual(host_factory.return_value.identity_errors, [])

    def test_invalid_raw_helper_clears_stale_environment_and_game_continues(self):
        self.mocked_sampler()
        code = ("import json, os; print(json.dumps([os.environ.get('OPENRC_RAW_CLOCK_HELPER'),"
                "os.environ.get('OPENRC_RAW_CLOCK_HELPER_SHA256')]))")
        with mock.patch.dict(os.environ, {"OPENRC_RAW_CLOCK_HELPER": "stale", "OPENRC_RAW_CLOCK_HELPER_SHA256": "stale"}), \
                mock.patch("run_checked.sys.platform", "darwin"), \
                mock.patch("macos_host_state.HostStateCapture", side_effect=RuntimeError("unavailable")):
            checked = self.run_code(code, resources=True, host_state_helper=self.root / "missing")
        self.assertTrue(checked["ok"])
        self.assertEqual(json.loads(Path(checked["log"]).read_text()), [None, None])
        self.assertEqual(checked["host_state"]["coverage"], "unavailable")

    def test_host_option_requires_resources_before_launch(self):
        with mock.patch("run_checked.subprocess.Popen") as launch:
            with self.assertRaisesRegex(ValueError, "requires --resources"):
                self.run_code(host_state_helper=Path("helper"))
            launch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
