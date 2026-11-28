"""TQ-07-E4a: only the files a host lacks cross the network; the job still runs verified bytes."""
from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

from tools.testqueue import remote_agent as agent
from tools.testqueue.common import write_json
from tools.testqueue.pool import Pool, TransferFailure
from tools.testqueue.test_remote_agent import FAKE_RUNNER

SOURCE = {
    "app/project.godot": '[application]\nconfig/name="OpenRC Simulator"\n',
    "app/tests/test_sample.gd": "extends SceneTree\n",
    "tools/godot/run_checked.py": FAKE_RUNNER,
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tar_of(blobs):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as bundle:
        for name, data in blobs.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            bundle.addfile(info, io.BytesIO(data))
    buffer.seek(0)
    return buffer


class AgentStoreTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-store-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / "incoming").mkdir()
        (self.root / "jobs").mkdir()
        self.engine = self.root / "engine-fixture"
        self.engine.write_bytes(b"#!/bin/sh\nexit 0\n")
        self.engine.chmod(0o755)
        self.files = {path: {"size": len(text.encode()), "sha256": sha(text.encode())} for path, text in SOURCE.items()}
        self.blob = json.dumps({"files": self.files}, sort_keys=True, separators=(",", ":")).encode()
        self.manifest_sha = sha(self.blob)

    def upload(self, *paths, manifest=True):
        blobs = {sha(SOURCE[path].encode()): SOURCE[path].encode() for path in paths}
        if manifest:
            blobs[self.manifest_sha] = self.blob
        return agent.store_put(self.root, tar_of(blobs))

    def request(self, identifier="job1"):
        return {"request_id": identifier, "preset": "checked", "source_manifest": {"sha256": self.manifest_sha},
                "engine_path": str(self.engine), "expected_engine_sha256": agent.digest(self.engine),
                "options": {"script": "res://tests/test_sample.gd", "require": ["0 failed"], "timeout": 90}}

    def launch(self):
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent.subprocess, "Popen"):
            return agent.launch(self.root, self.request())

    def test_have_reports_only_what_is_missing_and_put_is_idempotent(self):
        digests = [entry["sha256"] for entry in self.files.values()] + [self.manifest_sha]
        self.assertEqual(sorted(agent.store_have(self.root, {"digests": digests})["missing"]), sorted(digests))
        first = self.upload("app/project.godot")
        self.assertEqual((first["stored"], first["already_present"]), (2, 0))
        again = self.upload("app/project.godot")
        self.assertEqual((again["stored"], again["already_present"]), (0, 2))
        missing = agent.store_have(self.root, {"digests": digests})["missing"]
        self.assertEqual(sorted(missing), sorted([self.files["app/tests/test_sample.gd"]["sha256"],
                                                   self.files["tools/godot/run_checked.py"]["sha256"]]))

    def test_put_refuses_bytes_that_do_not_match_their_name_and_leaves_nothing(self):
        wrong = "0" * 64
        with self.assertRaises(agent.Refused):
            agent.store_put(self.root, tar_of({wrong: b"not those bytes"}))
        self.assertFalse(agent.store_path(self.root, wrong).exists())
        self.assertEqual(list(agent.store_path(self.root, wrong).parent.glob("*")), [])  # no stray temporary
        with self.assertRaises(agent.Refused):
            agent.store_put(self.root, tar_of({"../escape": b"x"}))

    def test_launch_refuses_an_incomplete_store_then_runs_from_it(self):
        self.upload("app/project.godot")  # the test script and runner are still missing
        with self.assertRaises(agent.Refused) as refused:
            self.launch()
        self.assertIn("lacks 2 file", str(refused.exception))
        self.upload(*SOURCE)
        self.assertEqual(self.launch()["state"], "STARTING")
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=False):
            self.assertEqual(agent.supervise(self.root, "job1"), 0)
        status = agent.status(self.root, "job1")
        self.assertEqual((status["outcome"], status["evidence"], status["input_mode"]), ("PASSED", "COMPLETE", "content-store"))
        inventory = agent.read_json(self.root / "jobs/job1/source-inventory.json")
        self.assertEqual(inventory["manifest_sha256"], self.manifest_sha)
        self.assertFalse((self.root / "jobs/job1/input.tar").exists())
        # The job's tree is a private copy: rewriting it never changes the store.
        (self.root / "jobs/job1/source/app/tests/test_sample.gd").write_text("changed")
        stored = agent.store_path(self.root, self.files["app/tests/test_sample.gd"]["sha256"]).read_bytes()
        self.assertEqual(stored, SOURCE["app/tests/test_sample.gd"].encode())

    def test_a_damaged_store_entry_heals_instead_of_failing_every_job(self):
        self.upload(*SOURCE)
        damaged = agent.store_path(self.root, self.files["app/tests/test_sample.gd"]["sha256"])
        damaged.write_bytes(b"bitrot")
        with self.assertRaisesRegex(agent.Refused, "damaged and has been removed"):
            agent.materialize_from_store(self.root, self.files, self.root / "tree")
        self.assertFalse(damaged.exists())
        missing = agent.store_have(self.root, {"digests": [self.files["app/tests/test_sample.gd"]["sha256"]]})["missing"]
        self.assertEqual(len(missing), 1)  # the next job uploads it again

    def test_reclaim_input_of_a_content_store_job_is_a_clear_skip(self):
        self.upload(*SOURCE)
        self.launch()
        with mock.patch.object(agent, "authority_enrolled", return_value=False), \
                mock.patch.object(agent, "external_engine_present", return_value=False):
            agent.supervise(self.root, "job1")
        if not agent._retention_supported():
            self.skipTest("descriptor-relative POSIX retention required")
        result = agent.reclaim_success_input(self.root, "job1")
        self.assertEqual(result["state"], "SKIPPED")
        self.assertIn("content-store", result["reason"])

    def test_requests_need_exactly_one_input_kind(self):
        request = self.request()
        agent.validate_request(request)
        for broken in ({**request, "archive": {"path": "/x.tar", "sha256": "a" * 64}},
                       {key: value for key, value in request.items() if key != "source_manifest"},
                       {**request, "source_manifest": {"sha256": "XYZ"}}):
            with self.subTest(broken=sorted(broken)), self.assertRaises(agent.Refused):
                agent.validate_request(broken)

    def test_cli_store_put_reads_a_tar_stream(self):
        data = b"cli bytes"
        command = [sys.executable, str(Path(agent.__file__).resolve()), "store-put", "--root", str(self.root)]
        result = subprocess.run(command, input=tar_of({sha(data): data}).read(), capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["result"]["stored"], 1)
        self.assertEqual(agent.store_path(self.root, sha(data)).read_bytes(), data)


class CoordinatorTransferTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-content-transfer-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.host = {"id": "linux", "ssh": "linux", "python": "python3", "root": "/r", "agent": "/r/agent.py",
                     "engine": "/e", "engine_sha256": "f" * 64}
        write_json(root / "config.json", {"state_root": str(root / "pool"), "hosts": [self.host]})
        self.pool = Pool(root / "config.json")
        self.snapshot = root / "snapshot"
        for path, text in SOURCE.items():
            target = self.snapshot / "source" / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(text.encode())
        self.manifest = {"files": {path: {"size": len(text.encode()), "sha256": sha(text.encode()), "mode": 438}
                                   for path, text in SOURCE.items()}}

    def test_only_missing_files_are_sent(self):
        _, blob, manifest_sha = Pool.source_manifest_blob(self.manifest)
        held = {self.manifest["files"]["app/project.godot"]["sha256"]}
        received = {}

        def remote(host, action, payload, timeout=45):
            self.assertEqual(action, "store-have")
            return {"missing": [digest for digest in payload["digests"] if digest not in held and digest not in received]}

        class FakeProcess:
            returncode = 0

            def __init__(self, *args, **kwargs):
                self.stdin = io.BytesIO()
                self.stdin.close = lambda: None

            def communicate(self, timeout=None):
                self.stdin.seek(0)
                with tarfile.open(fileobj=self.stdin, mode="r|") as bundle:
                    for member in bundle:
                        received[member.name] = bundle.extractfile(member).read()
                return json.dumps({"ok": True, "result": {"stored": len(received)}}).encode(), b""

            def kill(self):
                pass

            def poll(self):
                return self.returncode

            def wait(self, timeout=None):
                return self.returncode

        with mock.patch.object(self.pool, "remote", side_effect=remote), \
                mock.patch("tools.testqueue.pool.subprocess.Popen", FakeProcess):
            sent = self.pool._transfer_content(self.host, self.snapshot, self.manifest)
        self.assertEqual(sent["files_total"], 3)
        self.assertEqual(sent["files_sent"], 3)  # two source files and the manifest, not the held one
        self.assertNotIn(self.manifest["files"]["app/project.godot"]["sha256"], received)
        self.assertEqual(received[manifest_sha], blob)
        self.assertEqual(json.loads(blob)["files"]["app/project.godot"], {"size": len(SOURCE["app/project.godot"]),
                                                                          "sha256": sha(SOURCE["app/project.godot"].encode())})

    def test_submit_to_a_content_store_host_builds_no_archive(self):
        observation = {"id": "linux", "platform": "linux", "online": True, "busy": False, "local": False,
                       "capabilities": ["headless"], "features": ["content-store"], "free_disk_bytes": 10**11,
                       "free_memory_bytes": 10**10, "load": 0.0, "cores": 8}
        job = {"platform": "linux", "workload": "headless", "source_bytes": 10, "cache_id": "src",
               "duration_key": "res://tests/test_sample.gd", "estimated_seconds": 90,
               "memory_bytes": 1, "disk_bytes": 1}
        manifest = {**self.manifest, "source_digest": "src", "source_root": "/s"}
        options = {"script": "res://tests/test_sample.gd", "require": [], "timeout": 90, "headless": True}
        sent = {"files_total": 3, "files_sent": 1, "bytes_sent": 10, "manifest_sha256": "c" * 64}
        runs = []

        def remote(host, action, payload, timeout=45):
            runs.append(payload)
            from tools.testqueue.pool import request_digest
            return {"request_id": payload["request_id"], "payload_sha256": request_digest(payload), "state": "STARTING"}

        with mock.patch.object(self.pool, "_preflight", return_value=(manifest, options, job)), \
                mock.patch.object(self.pool, "probe", return_value=[observation]), \
                mock.patch.object(self.pool, "_prepare_archive", side_effect=AssertionError("no archive")), \
                mock.patch.object(self.pool, "_transfer_content", return_value=sent), \
                mock.patch.object(self.pool, "remote", side_effect=remote):
            result = self.pool.submit(self.snapshot, "res://tests/test_sample.gd", platform="linux", request_id="cs1")
        self.assertEqual(result["state"], "SUBMITTED")
        self.assertEqual(runs[0]["source_manifest"], {"sha256": "c" * 64})
        self.assertNotIn("archive", runs[0])
        receipt = json.loads((self.pool.root / "jobs/cs1.json").read_text())
        self.assertEqual(receipt["content_transfer"]["files_sent"], 1)

    @unittest.skipUnless(sys.platform != "win32", "runs the agent through sh in place of ssh")
    def test_real_streaming_to_a_local_agent(self):
        # The real Popen/communicate path, with ssh replaced by a local shell.
        store_root = Path(tempfile.mkdtemp(prefix="openrc-store-e2e-"))
        self.addCleanup(lambda: __import__("shutil").rmtree(store_root, ignore_errors=True))
        host = {**self.host, "python": sys.executable, "agent": str(Path(agent.__file__).resolve()),
                "root": str(store_root)}
        with mock.patch("tools.testqueue.pool.ssh_command", lambda host, command, **_: ["sh", "-c", command]):
            first = self.pool._transfer_content(host, self.snapshot, self.manifest)
            again = self.pool._transfer_content(host, self.snapshot, self.manifest)
        self.assertEqual((first["files_sent"], again["files_sent"]), (4, 0))  # three files and the manifest, then none
        files = agent.read_source_manifest(store_root, first["manifest_sha256"])
        self.assertEqual(set(files), set(SOURCE))

    def test_the_digest_question_is_asked_in_chunks(self):
        # Review finding: the agent reads at most 1 MiB of JSON per request.
        many = {f"app/file{index}.txt": {"size": 1, "sha256": f"{index:064x}"} for index in range(12_001)}
        calls = []

        def remote(host, action, payload, timeout=45):
            calls.append(len(payload["digests"]))
            return {"missing": []}

        with mock.patch.object(self.pool, "remote", side_effect=remote):
            sent = self.pool._transfer_content(self.host, self.snapshot, {"files": many})
        self.assertEqual(sent["files_sent"], 0)
        self.assertTrue(all(count <= Pool.STORE_HAVE_CHUNK for count in calls))
        self.assertEqual(sum(calls), 12_002)  # every file plus the manifest
        self.assertLess(len(json.dumps({"digests": ["f" * 64] * Pool.STORE_HAVE_CHUNK})), 1024 * 1024)

    def test_a_refusal_mid_stream_keeps_the_agents_reason(self):
        class Broken:
            returncode = 1

            def __init__(self, *args, **kwargs):
                class Pipe:
                    def write(self, data):
                        raise BrokenPipeError(32, "Broken pipe")

                    def flush(self):
                        pass
                self.stdin = Pipe()

            def communicate(self, timeout=None):
                return json.dumps({"ok": False, "error": "insufficient disk for the content store and reserve"}).encode(), b""

            def kill(self):
                pass

            def poll(self):
                return self.returncode

            def wait(self, timeout=None):
                return self.returncode

        with mock.patch.object(self.pool, "remote", return_value={"missing": [sha(SOURCE["app/project.godot"].encode())]}), \
                mock.patch("tools.testqueue.pool.subprocess.Popen", Broken), \
                self.assertRaises(TransferFailure) as failure:
            self.pool._transfer_content(self.host, self.snapshot, self.manifest)
        self.assertIn("insufficient disk", str(failure.exception))

    def test_a_failed_or_incomplete_upload_is_a_typed_nondispatch(self):
        with mock.patch.object(self.pool, "remote", side_effect=RuntimeError("ssh: connect timed out")), \
                self.assertRaises(TransferFailure) as failure:
            self.pool._transfer_content(self.host, self.snapshot, self.manifest)
        self.assertEqual((failure.exception.stage, failure.exception.code), ("have", "TRANSFER_FAILED"))

        class Refusing:
            returncode = 1

            def __init__(self, *args, **kwargs):
                self.stdin = io.BytesIO()
                self.stdin.close = lambda: None

            def communicate(self, timeout=None):
                return json.dumps({"ok": False, "error": "uploaded bytes differ"}).encode(), b""

            def kill(self):
                pass

            def poll(self):
                return self.returncode

            def wait(self, timeout=None):
                return self.returncode

        with mock.patch.object(self.pool, "remote", return_value={"missing": ["a" * 64]}), \
                mock.patch("tools.testqueue.pool.subprocess.Popen", Refusing), \
                self.assertRaises(TransferFailure) as failure:
            self.pool._transfer_content(self.host, self.snapshot, self.manifest)
        self.assertEqual(failure.exception.stage, "put")


if __name__ == "__main__":
    unittest.main()
