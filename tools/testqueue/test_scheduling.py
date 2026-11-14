"""Admission policy, starvation and lifecycle boundaries without a graphics driver."""
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue import presets
from tools.testqueue.store import Store
from tools.testqueue.worker import Worker


class PolicyTests(unittest.TestCase):
    def policy(self, preset, **options):
        return presets.scheduling(preset, presets.validate(preset, options))

    def test_mixed_and_unrestricted_presets_are_exclusive_even_if_headless(self):
        for preset in ("debug-session", "debug-smoke", "suite", "ci", "capture", "landscape", "godtest"):
            with self.subTest(preset=preset):
                options = {"headless": True, "argv": ["all"] if preset == "godtest" else []}
                self.assertEqual(self.policy(preset, **options)["mode"], "exclusive")

    def test_unknown_script_is_exclusive_and_declared_functional_is_parallel(self):
        script = "res://tests/test_simulation.gd"
        self.assertEqual(self.policy("checked", script=script)["mode"], "exclusive")
        policy = self.policy("checked", script=script, workload="functional")
        self.assertEqual(policy["mode"], "parallel")
        self.assertIn("headless", policy["resources"])

    def test_performance_cannot_be_downgraded_by_functional_declaration(self):
        for script in ("bench_physics.gd", "benchmark_landscape_collision.gd", "test_perf_cpu.gd", "test_latency.gd"):
            with self.subTest(script=script):
                policy = self.policy("checked", script="res://tests/" + script, workload="functional")
                self.assertEqual(policy["mode"], "exclusive")
                self.assertEqual(policy["workload"], "performance")
        self.assertEqual(self.policy("checked", script="res://tests/test_fixture.gd", workload="performance")["mode"], "exclusive")

    def test_functional_declaration_cannot_downgrade_general_rendered_or_debug_work(self):
        for preset, options in (("debug-session", {"headless": True}),
                                ("checked", {"script": "res://tests/test_fixture.gd", "headless": False}),
                                ("aircraft-screenshot", {"aircraft": "trainer"})):
            with self.subTest(preset=preset), self.assertRaises(ValueError):
                presets.validate(preset, {**options, "workload": "functional"})

    def test_studio_capture_has_only_safe_typed_inputs_and_can_opt_into_exclusivity(self):
        policy = self.policy("aircraft-screenshot", aircraft="trainer")
        self.assertEqual(policy["mode"], "parallel")
        self.assertIn("rendered", policy["resources"])
        self.assertNotIn("headless", policy["resources"])
        self.assertEqual(self.policy("aircraft-screenshot", aircraft="trainer", workload="performance")["mode"], "exclusive")
        for options in ({}, {"aircraft": "../other"}, {"aircraft": "a,b"},
                        {"aircraft": "a", "argv": ["--script", "other.gd"]},
                        {"aircraft": "a", "resources": {"rendered": 0}}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                presets.validate("aircraft-screenshot", options)

    def test_headless_engine_flag_is_inserted_before_game_argument_delimiter(self):
        options = presets.validate("debug-session", {"headless": True, "argv": ["--", "--headless"]})
        self.assertEqual(options["argv"], ["--headless", "--", "--headless"])


class ExclusiveStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-exclusive-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.store = Store(self.root)
        self.addCleanup(lambda: self.store.db.close())
        self.counter = 0

    def job(self):
        self.counter += 1
        return self.store.submit(str(self.counter), {"owner": "fixture"}, "x" * 32)["job"]

    def test_exclusive_conflicts_with_any_existing_resource_claim(self):
        first, second = self.job(), self.job()
        attempt = self.store.allocate(first, {"future-device": 1}, {"future-device": 1})
        self.assertIsNotNone(attempt)
        self.assertIsNone(self.store.allocate(second, {"exclusive": 1}, {"exclusive": 1}))
        self.store.update(first, attempt, "FINISHED", {"cleanup": "CONFIRMED"})
        self.assertIsNotNone(self.store.allocate(second, {"exclusive": 1}, {"exclusive": 1}))

    def test_active_and_unknown_exclusive_block_every_other_job(self):
        first, second = self.job(), self.job()
        self.store.allocate(first, {"exclusive": 1}, {"exclusive": 1})
        self.assertIsNone(self.store.allocate(second, {"headless": 1}, {"headless": 8}))
        self.store.db.close()
        self.store = Store(self.root)
        self.assertEqual(self.store.get(first)["state"], "UNKNOWN")
        self.assertIsNone(self.store.allocate(second, {"rendered": 1}, {"rendered": 4}))

    def test_upgrade_quarantines_legacy_attempt_without_exclusive_marker(self):
        first, second = self.job(), self.job()
        self.store.allocate(first, {"rendered": 1}, {"rendered": 1})
        self.store.db.close()
        self.store = Store(self.root)
        self.assertEqual(self.store.get(first)["state"], "UNKNOWN")
        self.assertIsNone(self.store.allocate(second, {"headless": 1}, {"headless": 8}))
        self.assertIsNone(self.store.allocate(second, {"rendered": 1}, {"rendered": 4}))


class SchedulerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-scheduling-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.worker = Worker(self.base / "authority", self.base / "repo", Path(sys.executable),
                             slots=2, capture_slots=2, fixture=True)
        self.addCleanup(self.worker.singleton.close)
        self.addCleanup(self.worker.store.db.close)
        self.counter = 0
        self.threads = patch("tools.testqueue.worker.threading.Thread").start()
        self.addCleanup(patch.stopall)

    def queue(self, preset="checked", **options):
        self.counter += 1
        if preset == "checked":
            options.setdefault("script", "res://tests/test_fixture.gd")
            options.setdefault("workload", "functional")
        payload = {"preset": preset, "options": presets.validate(preset, options)}
        return self.worker.store.submit(str(self.counter), payload, "s" * 32)["job"]

    def state(self, job):
        return self.worker.store.get(job)

    def finish(self, job):
        attempt = self.state(job)["attempts"][-1]["id"]
        self.worker.store.update(job, attempt, "FINISHED", {"cleanup": "CONFIRMED"})
        self.worker.active.pop(attempt, None)

    def test_exclusive_waits_for_both_resource_classes_then_blocks_younger_jobs(self):
        headless = self.queue()
        capture = self.queue("aircraft-screenshot", aircraft="trainer")
        self.worker.schedule_once()
        exclusive = self.queue("godtest", argv=["all"])
        later = self.queue()
        self.worker.schedule_once()
        self.assertEqual(self.state(exclusive)["state"], "QUEUED")
        self.assertIn("WAITING_FOR_EXCLUSIVE", self.state(later)["reason"])
        self.finish(headless)
        self.worker.schedule_once()
        self.assertEqual(self.state(exclusive)["state"], "QUEUED")
        self.finish(capture)
        self.worker.schedule_once()
        self.assertEqual(self.state(exclusive)["state"], "DISPATCHING")
        self.assertEqual(self.state(later)["state"], "QUEUED")
        self.finish(exclusive)
        self.worker.schedule_once()
        self.assertEqual(self.state(later)["state"], "DISPATCHING")

    def test_canceling_exclusive_barrier_unblocks_younger_feasible_work(self):
        self.queue()
        self.worker.schedule_once()
        exclusive = self.queue("debug-session")
        later = self.queue()
        self.worker.schedule_once()
        self.assertEqual(self.state(later)["state"], "QUEUED")
        self.worker.store.cancel(exclusive)
        self.worker.schedule_once()
        self.assertEqual(self.state(later)["state"], "DISPATCHING")

    def test_human_reservation_does_not_idle_functional_headless_work(self):
        self.worker.reservation = {"owner": "pilot"}
        exclusive = self.queue("debug-session")
        headless_performance = self.queue(workload="performance")
        later = self.queue()
        self.worker.schedule_once()
        self.assertTrue(self.state(exclusive)["reason"].startswith("HUMAN_RESERVATION"))
        self.assertTrue(self.state(headless_performance)["reason"].startswith("HUMAN_RESERVATION"))
        self.assertEqual(self.state(later)["state"], "DISPATCHING")

    def test_capture_capacity_is_bounded(self):
        jobs = [self.queue("aircraft-screenshot", aircraft="trainer") for _ in range(3)]
        self.worker.schedule_once()
        self.assertEqual([self.state(job)["state"] for job in jobs], ["DISPATCHING", "DISPATCHING", "QUEUED"])

    def test_performance_scope_requires_actual_exclusive_claim(self):
        job = self.queue()
        self.worker.schedule_once()
        attempt = self.state(job)["attempts"][-1]["id"]
        self.worker.store.update(job, attempt, "RUNNING", {})
        self.worker.contexts[attempt] = (job, "secret")
        with self.assertRaisesRegex(ValueError, "exclusive"):
            self.worker._validate_context(attempt + ":secret", "performance")
        self.finish(job)
        exclusive = self.queue(workload="performance")
        self.worker.schedule_once()
        attempt = self.state(exclusive)["attempts"][-1]["id"]
        self.worker.store.update(exclusive, attempt, "RUNNING", {})
        self.worker.contexts[attempt] = (exclusive, "secret")
        self.assertEqual(self.worker._validate_context(attempt + ":secret", "performance")["job"], exclusive)

    def test_closed_process_is_removed_before_occupancy_or_evidence_collection(self):
        class Process:
            closed = False

            def close(self):
                self.closed = True

            def pids(self):
                if self.closed:
                    raise RuntimeError("closed process must not be observed")
                return {1234}

        process = Process()
        self.worker.active["attempt"] = process
        self.worker._close_process("attempt", process)
        with patch("tools.testqueue.worker.external_simulators", return_value=[]):
            self.assertEqual(self.worker._external_conflicts(refresh=True), set())

    def test_studio_binding_rejects_changed_launchers_and_added_package_initializers(self):
        authority = self.base / "reviewed"
        for name in ("tools/readme/capture_aircraft.gd", "tools/testqueue/adapter.py",
                     "tools/testqueue/__init__.py", "tools/testqueue/common.py", "tools/godot/run_checked.py"):
            path = authority / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# reviewed\n")
        self.worker.studio_adapter_identity = self.worker._studio_identity(authority)
        candidate = self.base / "candidate"
        shutil.copytree(authority, candidate)
        self.worker._verify_studio_adapter(candidate)
        for name in ("tools/readme/capture_aircraft.gd", "tools/testqueue/adapter.py", "tools/godot/run_checked.py",
                     "tools/__init__.py", "tools/godot/__init__.py", "tools/testqueue/json.py"):
            with self.subTest(path=name):
                path = candidate / name
                existed = path.exists()
                original = path.read_text() if existed else None
                path.write_text("# unreviewed execution\n")
                with self.assertRaisesRegex(ValueError, "ADAPTER_MISMATCH"):
                    self.worker._verify_studio_adapter(candidate)
                if existed:
                    path.write_text(original)
                else:
                    path.unlink()

    def test_resource_sampling_cannot_escape_a_shared_inherited_attempt(self):
        from tools.godot import run_checked

        def grant(scope):
            if scope == "performance":
                raise ValueError("performance operation requires an exclusive attempt")
            return True

        with patch("tools.testqueue.common.enabled", return_value=True), \
                patch("tools.testqueue.common.inherited", side_effect=grant) as inherited, \
                patch.object(run_checked.subprocess, "Popen") as launch:
            with self.assertRaisesRegex(ValueError, "exclusive"):
                run_checked.run_checked(["godot", "--headless"], self.base / "sample", resources=True)
        launch.assert_not_called()
        self.assertEqual([call.args[0] for call in inherited.call_args_list], ["headless", "performance"])


if __name__ == "__main__":
    unittest.main()
