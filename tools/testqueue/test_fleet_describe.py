"""TQ-07-B1/B4: hosts describe themselves; the pool sees cache and runtime drift; deploys are guarded."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from tools.testqueue import remote_agent as agent
from tools.testqueue.common import write_json
from tools.testqueue.pool import Pool, runtime_digest, runtime_files


def committed_git(argv, **kwargs):
    """Fake Git that knows every blob, so the deploy guard passes."""
    if "hash-object" in argv:
        return subprocess.CompletedProcess(argv, 0, stdout=b"2" * 40 + b"\n")
    return subprocess.CompletedProcess(argv, 0)


class DescribeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-describe-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "jobs").mkdir()
        (self.root / "incoming").mkdir()

    def test_probe_describes_runtime_caches_and_slots(self):
        (self.root / "incoming" / ("a" * 64 + ".tar")).write_bytes(b"x")
        (self.root / "incoming" / "partial.pending").write_bytes(b"x")
        cache = self.root / "import-cache" / ("e" * 64)
        cache.mkdir(parents=True)
        write_json(cache / "cache.json", {"files": 3, "bytes": 10, "source_job": "j1"})
        description = agent.probe(self.root, {"engine_path": None})["description"]
        self.assertEqual(description["caches"]["incoming_archives"], ["a" * 64])
        self.assertEqual(description["caches"]["import_cache_engines"]["e" * 64]["files"], 3)
        self.assertEqual(description["slots"], {"headless": 1, "running": [], "unknown": []})
        # Other fixtures may stub the platform module; the value only has to be a string.
        self.assertIsInstance(description["hardware"]["arch"], str)
        self.assertIsInstance(description["volatile"]["clock"], float)
        # The agent's runtime digest uses the coordinator's formula over the deployed bytes.
        here = Path(agent.__file__).resolve().parent
        raw = {name: (here / name).read_bytes() for name in agent.RUNTIME_FILES}
        self.assertEqual(description["runtime"]["digest"], runtime_digest(raw))
        self.assertTrue((self.root / "hardware.json").is_file())  # slow facts are cached

    def test_a_failing_fact_never_hides_the_host(self):
        with mock.patch.object(agent, "_hardware", side_effect=RuntimeError("sysctl hung")):
            result = agent.probe(self.root, {"engine_path": None})
        self.assertIn("sysctl hung", result["description"]["error"])
        self.assertIn("capacity", result)


class PoolViewTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-pool-describe-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.host = {"id": "mac", "ssh": "mac", "python": "python3", "root": "/r",
                     "agent": "/r/runtime/tools/testqueue/remote_agent.py", "engine": "/e", "engine_sha256": "f" * 64}
        write_json(root / "config.json", {"state_root": str(root / "pool"), "hosts": [self.host]})
        self.pool = Pool(root / "config.json")
        (self.pool.root / "archives").mkdir()
        (self.pool.root / "archives" / ("s" * 64 + ".tar.sha256")).write_text("a" * 64 + "\n")

    def probe_reply(self, runtime):
        return {"host": {"system": "Darwin"}, "engine": {"available": True, "sha256": "f" * 64},
                "capacity": {"free_bytes": 10**11, "free_memory_bytes": 10**10, "cpu_count": 8},
                "admission": {"busy": False, "quarantined": False, "enrolled": False}, "capabilities": ["headless"],
                "features": ["describe"],
                "description": {"runtime": {"digest": runtime}, "caches": {"incoming_archives": ["a" * 64]}}}

    def test_held_archives_cost_no_transfer_and_drift_is_visible(self):
        with mock.patch.object(self.pool, "remote", return_value=self.probe_reply(self.pool.expected_runtime())):
            current = self.pool.probe_host(self.host)
        self.assertEqual(current["cached_inputs"], ["s" * 64])
        self.assertEqual(current["runtime"], "current")
        with mock.patch.object(self.pool, "remote", return_value=self.probe_reply("0" * 64)):
            self.assertEqual(self.pool.probe_host(self.host)["runtime"], "behind")

    def test_deploy_refuses_uncommitted_bytes_and_busy_hosts(self):
        def git(argv, **kwargs):
            if "hash-object" in argv:
                return subprocess.CompletedProcess(argv, 0, stdout=b"1" * 40 + b"\n")
            return subprocess.CompletedProcess(argv, 1)  # cat-file: not in the repository
        with mock.patch("tools.testqueue.pool.subprocess.run", side_effect=git), \
                self.assertRaisesRegex(ValueError, "not committed"):
            self.pool.deploy_runtime("mac", execute=True)
        busy = self.probe_reply("0" * 64)
        busy["admission"]["busy"] = True
        with mock.patch("tools.testqueue.pool.subprocess.run", side_effect=committed_git), \
                mock.patch.object(self.pool, "remote", return_value=busy), \
                self.assertRaisesRegex(ValueError, "not idle"):
            self.pool.deploy_runtime("mac", execute=True)

    def test_deploy_rolls_back_when_the_host_does_not_report_the_new_runtime(self):
        expected = self.pool.expected_runtime()
        calls = []

        def run(argv, **kwargs):
            command = argv[-1] if argv and argv[0] == "ssh" else ""
            calls.append("install" if " - " in command and command.endswith(" 0") else
                         "rollback" if " - " in command and command.endswith(" 1") else "other")
            if " - " in command:
                payload = {"ok": True, "installed": ["remote_agent.py"]} if command.endswith(" 0") else {"ok": True, "restored": ["remote_agent.py"]}
                return subprocess.CompletedProcess(argv, 0, stdout=json.dumps(payload).encode(), stderr=b"")
            if argv and argv[0] == "git":
                return committed_git(argv)
            return subprocess.CompletedProcess(argv, 0, stdout=b"", stderr=b"")

        probes = [self.probe_reply("0" * 64), self.probe_reply("9" * 64)]  # never reports the new runtime
        with mock.patch("tools.testqueue.pool.subprocess.run", side_effect=run), \
                mock.patch.object(self.pool, "remote", side_effect=probes):
            report = self.pool.deploy_runtime("mac", execute=True)
        self.assertEqual(report["expected"], expected)
        self.assertFalse(report["up_to_date"])
        self.assertEqual(report["rollback"], {"ok": True, "restored": ["remote_agent.py"]})
        self.assertEqual([call for call in calls if call != "other"], ["install", "rollback"])


@unittest.skipUnless(os.name == "posix", "the installer runs on POSIX pool hosts")
class InstallerTests(unittest.TestCase):
    def test_installer_swaps_under_the_lock_keeps_previous_and_refuses_open_jobs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime, staging = root / "runtime", root / "staging"
            runtime.mkdir()
            staging.mkdir()
            (root / "jobs").mkdir()
            (runtime / "remote_agent.py").write_bytes(b"old")
            (staging / "remote_agent.py").write_bytes(b"new")
            expected = json.dumps({"remote_agent.py": hashlib.sha256(b"new").hexdigest()})

            def install(rollback="0"):
                return subprocess.run([sys.executable, "-", str(staging), str(runtime), str(root), expected, rollback],
                                      input=Pool._INSTALLER, capture_output=True, text=True, timeout=30)

            (root / "jobs" / "j1").mkdir()
            (root / "jobs" / "j1" / "state.json").write_text('{"state": "RUNNING"}')
            refused = install()
            self.assertIn("BUSY", refused.stdout)
            self.assertEqual((runtime / "remote_agent.py").read_bytes(), b"old")
            (root / "jobs" / "j1" / "state.json").write_text('{"state": "FINISHED"}')
            done = install()
            self.assertEqual(json.loads(done.stdout)["installed"], ["remote_agent.py"], done.stderr)
            self.assertEqual((runtime / "remote_agent.py").read_bytes(), b"new")
            self.assertEqual((runtime / "remote_agent.py.prev-deploy").read_bytes(), b"old")
            self.assertEqual(json.loads(install("1").stdout)["restored"], ["remote_agent.py"])
            self.assertEqual((runtime / "remote_agent.py").read_bytes(), b"old")


class RuntimeFilesTests(unittest.TestCase):
    def test_runtime_bytes_are_normalized_to_what_git_stores(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("remote_agent.py", "processes.py", "common.py"):
                (directory / name).write_bytes(b"line\r\nnext\r\n")
            files = runtime_files(directory)
        self.assertTrue(all(data == b"line\nnext\n" for data in files.values()))


if __name__ == "__main__":
    unittest.main()
