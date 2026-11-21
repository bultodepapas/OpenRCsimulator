"""Frame monitor ownership and cleanup contracts; no Godot process is launched."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import runner
from tools.debug.test_frame_watch import FakeBridge, steady
from tools.godtest import frame_monitor


class ScriptedBridge:
    class Refused(Exception):
        pass

    def __init__(self):
        self.fake = FakeBridge(steady(20))
        self.calls = []
        self.fail = False
        self.bad = False

    def result_of(self, command, args, *, timeout, to_port):
        self.calls.append((command, dict(args), to_port))
        if self.fail:
            raise TimeoutError("bridge timed out")
        self.fake.advance(0.032)
        reply = self.fake.fetch(command, args, timeout)
        if self.bad:
            reply["format"] = "unexpected"
        reply["request_usec"] = self.fake.clock_us
        return reply


class MonitorTests(unittest.TestCase):
    def test_arm_then_stop_publishes_original_reports_and_explicit_port(self):
        with tempfile.TemporaryDirectory() as root:
            bridge = ScriptedBridge()
            monitor = frame_monitor.FrameMonitor(bridge, 48733, Path(root), timeout_s=60)
            monitor.start()
            self.assertTrue(monitor.armed_event.wait(2), "watch did not arm")
            ready = json.loads((Path(root) / "frame-watch.ready.json").read_text())
            self.assertEqual(ready["format"], frame_monitor.READY_FORMAT)
            self.assertEqual(ready["run_id"], Path(root).name)
            self.assertEqual(ready["identity"]["launch_instance"], bridge.fake.launch)
            self.assertEqual(ready["request_usec"], bridge.fake.clock_us)
            self.assertFalse((Path(root) / "frame-watch.ready.json.pending").exists())
            result = monitor.stop()
            self.assertEqual(result["status"], "complete", result)
            self.assertEqual(result["outcome"], "owner_stopped")
            self.assertEqual(result["final_poll"], "complete")
            self.assertEqual(result["identity"], result["stop_identity"])
            self.assertGreaterEqual(result["stop_request_usec"], result["observed_end_usec"])
            self.assertGreater(result["frames_observed"], 0)
            self.assertFalse(result["thread_alive"])
            self.assertEqual(result["policy"]["snapshot_rows"], 0)
            self.assertTrue(Path(result["report_path"]).is_file())
            self.assertEqual(result["report_sha256"], hashlib.sha256(Path(result["report_path"]).read_bytes()).hexdigest())
            self.assertTrue(Path(result["html_path"]).is_file())
            self.assertTrue((Path(root) / "frame-watch" / "seconds.csv").is_file())
            self.assertIn("tools/debug/frame_watch.py", result["source_sha256"])
            self.assertTrue(all(port == 48733 for _, _, port in bridge.calls))
            self.assertTrue(all(command == "frames" and args.get("lean") and args.get("passive")
                                for command, args, _ in bridge.calls))

    def test_protocol_failure_never_publishes_ready(self):
        with tempfile.TemporaryDirectory() as root:
            bridge = ScriptedBridge()
            bridge.bad = True
            monitor = frame_monitor.FrameMonitor(bridge, 48734, Path(root), timeout_s=60)
            monitor.start()
            self.assertTrue(monitor.finished_event.wait(2))
            self.assertFalse(monitor.armed_event.is_set())
            self.assertFalse((Path(root) / "frame-watch.ready.json").exists())
            self.assertIn("protocol_error", monitor.early_failure())
            result = monitor.stop()
            self.assertEqual(result["status"], "incomplete")
            self.assertFalse(result["thread_alive"])

    def test_final_poll_failure_is_visible(self):
        with tempfile.TemporaryDirectory() as root:
            bridge = ScriptedBridge()
            monitor = frame_monitor.FrameMonitor(bridge, 48735, Path(root), timeout_s=60)
            monitor.start()
            self.assertTrue(monitor.armed_event.wait(2))
            bridge.fail = True
            result = monitor.stop()
            self.assertEqual(result["status"], "incomplete")
            self.assertIn("final", result["error"])
            self.assertFalse(result["thread_alive"])

    def test_missing_reconciliation_and_changed_identity_fail_closed(self):
        for damage in ("missing_total", "different_identity"):
            with self.subTest(damage=damage), tempfile.TemporaryDirectory() as root:
                bridge = ScriptedBridge()
                monitor = frame_monitor.FrameMonitor(bridge, 48736, Path(root), timeout_s=60)
                original = monitor.watcher.summary

                def damaged_summary():
                    result = original()
                    if damage == "missing_total":
                        result["segments"][0]["reconciliation"].pop("stall_total")
                    else:
                        result["stop_identity"]["launch_instance"] = "wrong"
                    return result

                monitor.watcher.summary = damaged_summary
                monitor.start()
                self.assertTrue(monitor.armed_event.wait(2))
                result = monitor.stop()
                self.assertEqual(result["status"], "incomplete")
                self.assertIn("reconcile" if damage == "missing_total" else "identities", result["error"])


class RunnerTests(unittest.TestCase):
    def test_runner_finishes_monitor_before_owned_bridge(self):
        with tempfile.TemporaryDirectory() as root:
            # The runner pins the resolved engine (macOS /private/var, Windows 8.3 names).
            root_path = Path(root).resolve()
            engine = root_path / "godot"
            engine.write_bytes(b"test engine")
            events = []

            class Bridge:
                def launch(self, args):
                    pass

                def stop(self, args):
                    pass

                def session_for(self, port):
                    return {"command": [str(engine)]}

                def alive(self, pid):
                    return True

            bridge = Bridge()

            class Monitor:
                def __init__(self, owner, port, path, *, timeout_s):
                    self.path = path
                    self.thread = mock.Mock()
                    self.thread.is_alive.return_value = False
                    self.owner, self.port = owner, port

                def start(self):
                    events.append("monitor_start")
                    (self.path / "runtime.json").write_text("{}")

                def early_failure(self):
                    return None

                def stop(self):
                    events.append("monitor_stop")
                    return {"requested": True, "status": "complete", "outcome": "owner_stopped"}

            def call(function, args):
                if function == bridge.launch:
                    events.append("bridge_launch")
                    return 0, {"ok": True, "port": 48733, "pid": 1}
                events.append("bridge_stop")
                return 0, {"stopped": True}

            manifest = {"id": "test", "watch_frames": True, "timeout_s": 30,
                        "resolution": [1920, 1080], "headless": True, "scene_detail": "medium"}
            with mock.patch.object(runner, "validate"), \
                    mock.patch.object(runner.sys, "platform", "linux"), \
                    mock.patch.object(runner, "_bridge", return_value=bridge), \
                    mock.patch.object(runner, "_call", side_effect=call), \
                    mock.patch.object(runner, "source_identity", return_value={"digest": "same"}), \
                    mock.patch.object(runner, "freeze_inputs", return_value={"root": str(root_path)}), \
                    mock.patch.object(runner, "check_frozen", return_value=[]), \
                    mock.patch.object(frame_monitor, "FrameMonitor", Monitor), \
                    mock.patch("tools.testqueue.common.enabled", return_value=False):
                _, result = runner.run(manifest, root_path / "run", godot=str(engine))
            self.assertEqual(events, ["bridge_launch", "monitor_start", "monitor_stop", "bridge_stop"])
            self.assertEqual(result["frame_watch"]["status"], "complete")
            self.assertEqual(result["failure"], "")


if __name__ == "__main__":
    unittest.main()
