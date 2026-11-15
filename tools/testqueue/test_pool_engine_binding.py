"""Pool pin checks consume the same engine bytes as the verified snapshot."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue import pool as pool_module, snapshots
from tools.testqueue.common import write_json


class PoolEngineBindingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-engine-binding-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.source = self.root / "source"
        self.source.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Snapshot Fixture")
        self.git("config", "user.email", "snapshot@example.invalid")
        self.write("app/project.godot", b"[application]\n")
        self.write("app/get-godot.sh", b"ENGINE_VERSION=4.5.0\n")
        self.write("tools/testqueue/adapter.py", b"# fixture adapter\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        self.snapshot = self.root / "snapshot"
        self.manifest = snapshots.capture(self.source, self.snapshot, scope=("app", "tools"))
        self.pin = self.snapshot / "source/app/get-godot.sh"
        self.original_pin = self.pin.read_bytes()
        self.original_stat = self.pin.stat()
        self.config = self.root / "config.json"

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.source), *args], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    def write(self, relative, data):
        path = self.source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def pool(self, version):
        write_json(self.config, {"state_root": str(self.root / "pool"), "hosts": [], "engine_version": version})
        return pool_module.Pool(self.config)

    def preflight(self, pool):
        return pool._preflight(self.snapshot, "res://tests/test_fixture.gd", "any", [], 90, None, None, None)

    def restore_pin(self):
        self.pin.parent.mkdir(parents=True, exist_ok=True)
        self.pin.write_bytes(self.original_pin)
        os.chmod(self.pin, self.original_stat.st_mode)
        os.utime(self.pin, ns=(self.original_stat.st_atime_ns, self.original_stat.st_mtime_ns))

    def test_genuine_pin_uses_the_original_verified_manifest(self):
        pool = self.pool("4.5.0")
        verified = []
        original_verify = snapshots.verify
        original_read = snapshots.read_verified_file

        def verify_once(*args, **kwargs):
            result = original_verify(*args, **kwargs)
            self.assertTrue(result["ok"])
            self.assertTrue(kwargs.get("include_manifest"))
            verified.append(result)
            return result

        def read_pin(snapshot, manifest, relative):
            self.assertIs(manifest, verified[0]["manifest"])
            self.assertEqual(relative, "app/get-godot.sh")
            return original_read(snapshot, manifest, relative)

        with patch.object(pool_module, "verify", side_effect=verify_once) as verify, \
             patch.object(pool_module, "read_verified_file", side_effect=read_pin) as read:
            manifest, options, job = self.preflight(pool)
        verify.assert_called_once()
        read.assert_called_once()
        self.assertIs(manifest, verified[0]["manifest"])
        self.assertEqual(manifest["source_digest"], self.manifest["source_digest"])
        self.assertEqual(job["cache_id"], self.manifest["source_digest"])
        self.assertEqual(options["script"], "res://tests/test_fixture.gd")

    def test_pin_replaced_after_verification_cannot_be_accepted(self):
        pool = self.pool("4.6.0")
        verified = []
        original_verify = snapshots.verify

        def replace_after_verification(*args, **kwargs):
            result = original_verify(*args, **kwargs)
            self.assertTrue(result["ok"])
            verified.append(result)
            self.pin.write_bytes(b"ENGINE_VERSION=4.6.0\n")
            return result

        try:
            with patch.object(pool_module, "verify", side_effect=replace_after_verification):
                with self.assertRaises((ValueError, OSError)):
                    self.preflight(pool)
        finally:
            self.restore_pin()
        self.assertEqual(len(verified), 1)
        self.assertEqual(verified[0]["manifest"]["files"]["app/get-godot.sh"]["sha256"],
                         self.manifest["files"]["app/get-godot.sh"]["sha256"])
        self.assertTrue(snapshots.verify(self.snapshot)["ok"])

    def test_missing_pin_after_verification_cannot_bypass_check(self):
        pool = self.pool("4.5.0")
        verified = []
        original_verify = snapshots.verify

        def remove_after_verification(*args, **kwargs):
            result = original_verify(*args, **kwargs)
            self.assertTrue(result["ok"])
            verified.append(result)
            self.pin.unlink()
            return result

        try:
            with patch.object(pool_module, "verify", side_effect=remove_after_verification):
                with self.assertRaises((ValueError, OSError)):
                    self.preflight(pool)
        finally:
            self.restore_pin()
        self.assertEqual(len(verified), 1)
        self.assertIn("app/get-godot.sh", verified[0]["manifest"]["files"])
        self.assertTrue(snapshots.verify(self.snapshot)["ok"])


if __name__ == "__main__":
    unittest.main()
