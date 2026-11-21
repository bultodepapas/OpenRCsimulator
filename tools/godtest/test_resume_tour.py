"""Tour recovery tests use owned fixture receipts and never start an engine."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

import catalog
import godtest
import tour_report
from runner import read_json, write_json


class ResumeTourTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.addCleanup(self.temporary.cleanup)
        self.engine = self.root / "godot"
        self.engine.write_bytes(b"pinned fixture engine")
        self.observers = godtest._observer_sources()
        self.host_identity = {"format": "openrc-godtest-host-v1", "host_sha256": "a" * 64,
                              "boot_sha256": "b" * 64,
                              "scope": "OS installation and boot; cloned machine IDs cannot distinguish physical hosts"}
        host_patch = mock.patch.object(godtest.runner, "campaign_host_identity", return_value=self.host_identity)
        host_patch.start()
        self.addCleanup(host_patch.stop)
        self.planned = catalog.performance_tour({"headless": True})
        frozen = self.root / "frozen"
        (frozen / "app/.godot/imported").mkdir(parents=True)
        (frozen / "app/project.godot").write_bytes(b"project fixture")
        (frozen / "app/.godot/imported/file.ctex").write_bytes(b"import fixture")
        digest = lambda p: hashlib.sha256((frozen / p).read_bytes()).hexdigest()
        files = {"app/project.godot": digest("app/project.godot")}
        imports = {"app/.godot/imported/file.ctex": digest("app/.godot/imported/file.ctex")}
        self.snapshot = {"format": "openrc-godtest-source-v1", "root": str(frozen), "files": files, "imports": imports,
                         "source_digest": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(),
                         "imported_digest": hashlib.sha256(json.dumps(imports, sort_keys=True).encode()).hexdigest()}
        self.calls = []
        self.interrupt_on = None

    def _attempt(self, path, manifest, state="valid", *, stopped=True, snapshot=None):
        path.mkdir(parents=True)
        write_json(path / "manifest.requested.json", manifest)
        write_json(path / "manifest.resolved.json", dict(manifest, output_dir=str(path)))
        write_json(path / "snapshot.json", snapshot or self.snapshot)
        (path / "bridge").mkdir()
        launch = {"pid": 102, "launcher_pid": 101, "port": 49001}
        write_json(path / "bridge/launch.json", {"launcher_pid": 101, "port": 49001})
        shutdown = {"stopped": True, "pid": 102, "forced": False, "launcher_exit_code": 0} if stopped else {}
        write_json(path / "execution.json", {"state": "runtime_finished", "launch": launch, "shutdown": shutdown,
            "host_identity": self.host_identity,
            "command": ["xvfb-run", "-a", str(self.engine), "--path", "project"],
            "engine_files": {str(self.engine): hashlib.sha256(self.engine.read_bytes()).hexdigest()},
            "resource_sampling": True, "gpu_sampling": True,
            "resource_sampler_source_sha256": self.observers["tools/godot/resource_samples.py"],
            "resource_sampler_source_changed": False,
            "orchestrator_sources": {name: self.observers["tools/godtest/" + name] for name in godtest.ORCHESTRATOR_INPUTS},
            "frame_watch": {"source_sha256": {name: self.observers[name] for name in
                ("tools/godtest/frame_monitor.py", "tools/debug/frame_watch.py", "tools/debug/frame_capture.py", "tools/debug/debugctl.py")}}})
        write_json(path / "runtime.json", {"fixture_state": state})

    def _report(self, path, *, write=True):
        path = Path(path).resolve()
        manifest = read_json(path / "manifest.requested.json")
        valid = read_json(path / "runtime.json")["fixture_state"] == "valid"
        return {"run_dir": str(path), "scenario": manifest["id"], "aircraft": manifest["aircraft"],
                "execution": "completed" if valid else "failed", "data": "valid" if valid else "ineligible",
                "coverage": "complete" if valid else "partial", "flight": "completed" if valid else "partial",
                "performance": "not_qualified", "issues": [] if valid else ["fixture failure"],
                "rendered": False, "requested_headless": manifest["headless"],
                "rendering": {"status": "not_requested" if manifest["headless"] else "incomplete"},
                "monitoring": {"required": True, "complete": False}}

    def _run(self, manifest, output, *, godot, resources, snapshot):
        self.assertEqual(godot, str(self.engine))
        self.assertTrue(resources)
        self.assertEqual(snapshot, self.snapshot)
        self.calls.append(manifest["id"])
        self._attempt(Path(output), manifest, "invalid" if self.interrupt_on == len(self.calls) else "valid")
        if self.interrupt_on == len(self.calls):
            raise KeyboardInterrupt()
        return Path(output), {}

    def _summary(self, directory):
        index = read_json(Path(directory) / "suite.json")
        cases = [self._report(row["run_dir"], write=False) for row in index["cases"]]
        return {"data": "valid", "coverage": "complete", "performance": "not_qualified", "issues": [], "cases": cases}

    def _index(self, name="source", entries=None):
        suite = self.root / name
        suite.mkdir()
        if entries is None:
            entries = [godtest._pending_case(suite, i, case) for i, case in enumerate(self.planned)]
        write_json(suite / "suite.json", {"format": "openrc-godtest-suite-v1", "suite": "performance-tour-v1",
            "planned_cases": self.planned, "observer_sources": self.observers, "complete": False, "cases": entries})
        return suite

    def _resume(self, suite, output, summary=None):
        with mock.patch.object(godtest, "report", side_effect=self._report), mock.patch.object(godtest, "run", side_effect=self._run), mock.patch.object(tour_report, "report_tour", side_effect=summary or self._summary):
            return godtest.resume_suite(SimpleNamespace(suite=suite, out=output))

    def test_before_first_result_retains_all_slots_and_resumes(self):
        suite = self.root / "initial"
        self.interrupt_on = 1
        def initial_run(manifest, output, *, godot, resources, snapshot):
            self._attempt(Path(output), manifest, "invalid")
            raise KeyboardInterrupt()
        from tools.testqueue import common
        with mock.patch.object(common, "enabled", return_value=False), mock.patch.object(godtest, "run", side_effect=initial_run):
            self.assertEqual(godtest.main(["performance-tour", "--headless", "--out", str(suite)]), 130)
        index = read_json(suite / "suite.json")
        self.assertEqual(len(index["cases"]), 3)
        self.assertEqual([x["state"] for x in index["cases"]], ["starting", "pending", "pending"])
        self.interrupt_on = None
        self.assertEqual(self._resume(suite, self.root / "retry"), 0)
        self.assertEqual(self.calls, [case["id"] for case in self.planned])

    def test_between_cases_reuses_verified_complete_retries_bad_and_starts_tail(self):
        suite = self._index()
        index = read_json(suite / "suite.json")
        for i, state in ((0, "valid"), (1, "invalid")):
            path = Path(index["cases"][i]["run_dir"])
            self._attempt(path, self.planned[i], state)
            index["cases"][i] = dict(self._report(path), data="valid", coverage="complete") # stale claims are ignored
        write_json(suite / "suite.json", index)
        destination = self.root / "retry"
        self.assertEqual(self._resume(suite, destination), 0)
        result = read_json(destination / "suite.json")
        self.assertTrue(result["complete"] and result["cases"][0]["reused"])
        self.assertEqual(self.calls, [self.planned[1]["id"], self.planned[2]["id"]])
        self.assertEqual(result["cases"][1]["attempts"][0]["data"], "ineligible")
        self.assertEqual(result["cases"][0]["run_dir"], index["cases"][0]["run_dir"])

    def test_second_interruption_keeps_full_roster_and_partial_attempt(self):
        suite = self._index()
        index = read_json(suite / "suite.json")
        first = Path(index["cases"][0]["run_dir"])
        self._attempt(first, self.planned[0])
        index["cases"][0] = self._report(first)
        write_json(suite / "suite.json", index)
        self.interrupt_on = 1
        middle = self.root / "middle"
        with self.assertRaises(KeyboardInterrupt): self._resume(suite, middle)
        partial = read_json(middle / "suite.json")
        self.assertFalse(partial["complete"])
        self.assertEqual(len(partial["cases"]), 3)
        self.assertEqual(partial["cases"][1]["state"], "starting")
        self.interrupt_on = None
        self.assertEqual(self._resume(middle, self.root / "final"), 0)
        final = read_json(self.root / "final/suite.json")
        self.assertTrue(final["cases"][0]["reused"])
        self.assertEqual(final["cases"][1]["attempts"][-1]["data"], "ineligible")

    def test_interrupted_early_retry_retains_later_complete_references(self):
        suite = self._index()
        index = read_json(suite / "suite.json")
        for i, state in ((0, "invalid"), (1, "valid"), (2, "valid")):
            path = Path(index["cases"][i]["run_dir"])
            self._attempt(path, self.planned[i], state)
            index["cases"][i] = self._report(path)
        write_json(suite / "suite.json", index)
        self.interrupt_on = 1
        middle = self.root / "middle"
        with self.assertRaises(KeyboardInterrupt): self._resume(suite, middle)
        partial = read_json(middle / "suite.json")
        self.assertEqual([partial["cases"][i]["run_dir"] for i in (1, 2)],
                         [index["cases"][i]["run_dir"] for i in (1, 2)])
        self.interrupt_on = None
        destination = self.root / "final"
        self.assertEqual(self._resume(middle, destination), 0)
        final = read_json(destination / "suite.json")
        self.assertTrue(all(final["cases"][i]["reused"] for i in (1, 2)))
        self.assertEqual(self.calls, [self.planned[0]["id"], self.planned[0]["id"]])

    def test_blocked_resume_preserves_refs_and_can_be_resumed_after_reconciliation(self):
        suite = self._index()
        index = read_json(suite / "suite.json")
        for i, state in ((0, "valid"), (1, "invalid"), (2, "valid")):
            path = Path(index["cases"][i]["run_dir"])
            self._attempt(path, self.planned[i], state, stopped=i != 1)
            index["cases"][i] = self._report(path)
        index["cases"][1]["state"] = "starting"
        write_json(suite / "suite.json", index)
        blocked = self.root / "blocked"
        with self.assertRaisesRegex(ValueError, "original handle"):
            self._resume(suite, blocked)
        held = read_json(blocked / "suite.json")
        self.assertEqual([entry["run_dir"] for entry in held["cases"]],
                         [entry["run_dir"] for entry in index["cases"]])
        self.assertEqual(self.calls, [])
        original = Path(index["cases"][1]["run_dir"])
        execution = read_json(original / "execution.json")
        execution["shutdown"] = {"stopped": True, "pid": 102, "forced": False, "launcher_exit_code": 0}
        write_json(original / "execution.json", execution)
        destination = self.root / "final"
        self.assertEqual(self._resume(blocked, destination), 0)
        final = read_json(destination / "suite.json")
        self.assertTrue(all(final["cases"][i]["reused"] for i in (0, 2)))
        self.assertEqual(self.calls, [self.planned[1]["id"]])

    def test_unknown_or_active_original_owner_is_never_retried(self):
        suite = self._index()
        index = read_json(suite / "suite.json")
        path = Path(index["cases"][0]["run_dir"])
        self._attempt(path, self.planned[0], stopped=False)
        index["cases"][0]["state"] = "starting"
        write_json(suite / "suite.json", index)
        with self.assertRaisesRegex(ValueError, "original handle"):
            self._resume(suite, self.root / "blocked")
        self.assertEqual(self.calls, [])
        self.assertIn("shutdown", read_json(self.root / "blocked/suite.json")["resume_error"])

    def test_launch_receipt_without_execution_is_not_assumed_stopped(self):
        suite = self._index()
        index = read_json(suite / "suite.json")
        path = Path(index["cases"][0]["run_dir"])
        (path / "bridge").mkdir(parents=True)
        write_json(path / "bridge/launch.json", {"launcher_pid": 101, "port": 49001})
        index["cases"][0]["state"] = "starting"
        write_json(suite / "suite.json", index)
        with self.assertRaisesRegex(ValueError, "original handle"):
            self._resume(suite, self.root / "blocked")
        self.assertEqual(self.calls, [])

    def test_no_source_or_engine_identity_refuses_without_guessing(self):
        suite = self._index()
        with self.assertRaisesRegex(ValueError, "frozen source and matching engine"):
            self._resume(suite, self.root / "blocked")
        self.assertEqual(self.calls, [])

    def test_missing_or_different_host_and_boot_refuse_the_same_engine(self):
        for damage in ("missing", "other_host", "other_boot", "invalid"):
            with self.subTest(damage=damage):
                suite = self._index("source-host-" + damage)
                index = read_json(suite / "suite.json")
                path = Path(index["cases"][0]["run_dir"])
                self._attempt(path, self.planned[0])
                execution = read_json(path / "execution.json")
                if damage == "missing": execution.pop("host_identity")
                elif damage == "other_host": execution["host_identity"]["host_sha256"] = "c" * 64
                elif damage == "other_boot": execution["host_identity"]["boot_sha256"] = "c" * 64
                else: execution["host_identity"]["host_sha256"] = "not-a-hash"
                write_json(path / "execution.json", execution)
                index["cases"][0] = self._report(path)
                write_json(suite / "suite.json", index)
                with self.assertRaisesRegex(ValueError, "host or boot identity is missing or differs"):
                    self._resume(suite, self.root / ("blocked-host-" + damage))
        self.assertEqual(self.calls, [])

    def test_unavailable_current_host_refuses_without_starting(self):
        suite = self._index()
        with mock.patch.object(godtest.runner, "campaign_host_identity", return_value={}):
            with self.assertRaisesRegex(ValueError, "current host or boot identity is unavailable"):
                self._resume(suite, self.root / "blocked-no-host")
        self.assertEqual(self.calls, [])

    def test_changed_engine_and_unknown_observer_are_refused(self):
        suite = self._index()
        index = read_json(suite / "suite.json")
        path = Path(index["cases"][0]["run_dir"])
        self._attempt(path, self.planned[0])
        index["cases"][0] = self._report(path)
        write_json(suite / "suite.json", index)
        self.engine.write_bytes(b"changed engine")
        with self.assertRaisesRegex(ValueError, "engine executable is missing or changed"):
            self._resume(suite, self.root / "engine-blocked")
        index.pop("observer_sources")
        write_json(suite / "suite.json", index)
        with self.assertRaisesRegex(ValueError, "observer identity is missing or changed"):
            self._resume(suite, self.root / "observer-blocked")
        self.assertEqual(self.calls, [])

    def test_mismatched_missing_or_changed_cpu_sampler_cannot_resume(self):
        for damage in ("different", "missing", "changed", "unknown_change"):
            with self.subTest(damage=damage):
                suite = self._index("source-" + damage)
                index = read_json(suite / "suite.json")
                path = Path(index["cases"][0]["run_dir"])
                self._attempt(path, self.planned[0])
                execution = read_json(path / "execution.json")
                if damage == "different": execution["resource_sampler_source_sha256"] = "0" * 64
                elif damage == "missing": execution.pop("resource_sampler_source_sha256")
                elif damage == "changed": execution["resource_sampler_source_changed"] = True
                else: execution.pop("resource_sampler_source_changed")
                write_json(path / "execution.json", execution)
                index["cases"][0] = self._report(path)
                write_json(suite / "suite.json", index)
                with self.assertRaisesRegex(ValueError, "CPU sampler source differs, changed or is unknown"):
                    self._resume(suite, self.root / ("blocked-" + damage))
        self.assertEqual(self.calls, [])

    def test_rendered_incomplete_monitoring_cannot_report_success(self):
        good = {"data": "valid", "coverage": "complete", "performance": "screen_only", "cases": [
            {"data": "valid", "coverage": "complete", "requested_headless": False, "rendered": True,
             "rendering": {"status": "complete"}, "monitoring": {"required": True, "complete": False}}]}
        self.assertFalse(godtest._tour_success(good))
        good["cases"][0]["monitoring"]["complete"] = True
        self.assertTrue(godtest._tour_success(good))
        result = {"data": "valid", "coverage": "complete", "rendered": True, "monitoring": {"required": True, "complete": False}}
        self.assertFalse(godtest._case_success(result))

    def test_report_command_returns_failure_for_incomplete_rendered_monitoring(self):
        suite = self._index()
        summary = {"run_dir": str(suite), "suite": "performance-tour-v1", "data": "valid", "coverage": "complete",
                   "performance": "not_qualified", "issues": [], "cases": [{"rendered": True, "monitoring": {"complete": False}}]}
        with mock.patch.object(tour_report, "report_tour", return_value=summary):
            self.assertEqual(godtest.main(["report", str(suite)]), 1)

    def test_run_and_resume_reject_incomplete_rendered_monitoring(self):
        def incomplete(directory):
            summary = self._summary(directory)
            summary["cases"][0].update(rendered=True, monitoring={"complete": False})
            return summary
        def initial_run(manifest, output, *, godot, resources, snapshot):
            self._attempt(Path(output), manifest, snapshot=snapshot or self.snapshot)
            return Path(output), {}
        from tools.testqueue import common
        suite = self.root / "initial"
        with mock.patch.object(common, "enabled", return_value=False), mock.patch.object(godtest, "run", side_effect=initial_run), mock.patch.object(godtest, "report", side_effect=self._report), mock.patch.object(tour_report, "report_tour", side_effect=incomplete):
            self.assertEqual(godtest.main(["performance-tour", "--headless", "--out", str(suite)]), 1)
        self.assertEqual(self._resume(suite, self.root / "retry", summary=incomplete), 1)

    def test_reused_cases_pass_actual_reducer_provenance(self):
        from test_tour_report import fixture
        suite, index = fixture(self.root, headless=True)
        index["observer_sources"] = self.observers
        for entry in index["cases"]:
            path = Path(entry["run_dir"])
            execution = read_json(path / "execution.json")
            execution.update(launch={"pid": 42, "launcher_pid": 41, "port": 49001},
                command=[str(self.engine), "--path", "project"],
                engine_files={str(self.engine): hashlib.sha256(self.engine.read_bytes()).hexdigest()},
                host_identity=self.host_identity,
                resource_sampling=True, gpu_sampling=True,
                resource_sampler_source_sha256=self.observers["tools/godot/resource_samples.py"],
                resource_sampler_source_changed=False,
                orchestrator_sources={name: self.observers["tools/godtest/" + name] for name in godtest.ORCHESTRATOR_INPUTS})
            execution["shutdown"]["pid"] = 42
            execution["frame_watch"]["source_sha256"] = {name: self.observers[name] for name in
                ("tools/godtest/frame_monitor.py", "tools/debug/frame_watch.py", "tools/debug/frame_capture.py", "tools/debug/debugctl.py")}
            write_json(path / "execution.json", execution)
        write_json(suite / "suite.json", index)
        destination = self.root / "reused"
        with mock.patch.object(godtest, "run") as run:
            self.assertEqual(godtest.resume_suite(SimpleNamespace(suite=suite, out=destination)), 0)
            run.assert_not_called()
        result = tour_report.report_tour(destination, write=False)
        self.assertEqual((result["data"], result["coverage"]), ("valid", "complete"))
        self.assertTrue(all(entry["reused"] for entry in read_json(destination / "suite.json")["cases"]))


if __name__ == "__main__":
    unittest.main()
