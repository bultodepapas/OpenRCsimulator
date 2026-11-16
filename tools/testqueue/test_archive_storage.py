"""Reclaim only failed archive builds owned by this invocation."""
from __future__ import annotations

import errno
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tools.testqueue import pool as pool_module
from tools.testqueue.pool_batch import run_batch


class ArchiveStorageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-archive-retention-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        config = self.root / "config.json"
        config.write_text(json.dumps({"state_root": str(self.root / "pool"), "hosts": []}))
        self.pool = pool_module.Pool(config)
        self.snapshot = self.root / "snapshot"
        source = self.snapshot / "source/app"
        source.mkdir(parents=True)
        content = b"verified frozen input\n"
        (source / "test.gd").write_bytes(content)
        self.manifest = {"source_digest": "a" * 64, "source_root": str(self.root / "developer"), "files": {
            "app/test.gd": {"size": len(content), "sha256": hashlib.sha256(content).hexdigest()}}}
        self.archives = self.pool.root / "archives"
        self.archives.mkdir()

    def configure_hosts(self):
        self.pool.hosts.extend([
            {'id': name, 'ssh': name, 'python': 'python3', 'root': '/remote/' + name,
             'engine': '/engine', 'engine_sha256': 'b' * 64}
            for name in ('remote', 'second')])
        self.pool.hosts.append({'id': 'local', 'local': True})

    @staticmethod
    def accepted(host, action, request):
        return {'request_id': request['request_id'], 'payload_sha256': pool_module.request_digest(request),
                'state': 'STARTING'}

    def pending(self):
        return list(self.archives.glob("*.pending"))

    def test_success_publishes_verified_cache_without_temporary(self):
        archive = self.pool._prepare_archive(self.snapshot, self.manifest)
        pool_module.verify_archive(archive, self.manifest)
        before = archive.read_bytes()
        with patch.object(pool_module.tempfile, "mkstemp", side_effect=AssertionError("cache rebuilt")):
            self.assertEqual(self.pool._prepare_archive(self.snapshot, self.manifest), archive)
        self.assertEqual(archive.read_bytes(), before)
        self.assertEqual(self.pending(), [])

    def test_enospc_build_removes_only_its_new_temporary(self):
        older = self.archives / ("a" * 64 + ".pending")
        older.write_bytes(b"unresolved earlier writer")
        unrelated = self.archives / "different-request.pending"
        unrelated.write_bytes(b"other client")
        with patch.object(pool_module.tarfile.TarFile, "add", side_effect=OSError(errno.ENOSPC, "fixture full")):
            with self.assertRaises(OSError):
                self.pool._prepare_archive(self.snapshot, self.manifest)
        self.assertEqual(set(self.pending()), {older, unrelated})
        self.assertEqual(older.read_bytes(), b"unresolved earlier writer")
        self.assertEqual(unrelated.read_bytes(), b"other client")
        self.assertFalse((self.archives / ("a" * 64 + ".tar")).exists())
        # The failed call released its persistent lock; a later build can finish.
        pool_module.verify_archive(self.pool._prepare_archive(self.snapshot, self.manifest), self.manifest)

    def test_failed_verification_removes_unpublished_copy(self):
        with patch.object(pool_module, "verify_archive", side_effect=ValueError("source changed")):
            with self.assertRaisesRegex(ValueError, "source changed"):
                self.pool._prepare_archive(self.snapshot, self.manifest)
        self.assertEqual(self.pending(), [])
        self.assertEqual(list(self.archives.glob("*.tar")), [])

    def test_failed_publication_removes_unpublished_copy(self):
        with patch.object(Path, "replace", side_effect=OSError("publication denied")):
            with self.assertRaisesRegex(OSError, "publication denied"):
                self.pool._prepare_archive(self.snapshot, self.manifest)
        self.assertEqual(self.pending(), [])

    def test_failed_fsync_removes_unpublished_copy(self):
        with patch.object(pool_module.os, "fsync", side_effect=OSError("flush failed")):
            with self.assertRaisesRegex(OSError, "flush failed"):
                self.pool._prepare_archive(self.snapshot, self.manifest)
        self.assertEqual(self.pending(), [])

    def test_insufficient_archive_volume_refuses_before_creating_file(self):
        with patch.object(pool_module.shutil, "disk_usage", return_value=SimpleNamespace(free=0)) as usage, \
                patch.object(pool_module.tempfile, "mkstemp") as temporary:
            with self.assertRaisesRegex(OSError, "INSUFFICIENT_SPACE"):
                self.pool._prepare_archive(self.snapshot, self.manifest)
        usage.assert_called_once_with(self.archives)
        temporary.assert_not_called()
        self.assertEqual(self.pending(), [])

    def test_known_low_space_defers_before_dispatch_receipt_or_remote_call(self):
        self.pool.hosts.append({'id': 'remote', 'local': False})
        with patch.object(self.pool, '_preflight', return_value=(self.manifest, {}, {})), \
                patch.object(self.pool, 'probe', return_value=[]), \
                patch.object(pool_module, 'plan', return_value={'selected': 'remote'}), \
                patch.object(pool_module.shutil, 'disk_usage', return_value=SimpleNamespace(free=0)), \
                patch.object(self.pool, 'remote') as remote, \
                patch.object(pool_module.subprocess, 'run') as transfer:
            with self.assertRaisesRegex(pool_module.SubmissionDeferred, 'archive preparation unavailable'):
                self.pool.submit(self.snapshot, 'res://tests/test_fixture.gd', request_id='lowdisk')
        self.assertFalse((self.pool.root / 'jobs/lowdisk.json').exists())
        self.assertEqual(self.pending(), [])
        remote.assert_not_called()
        transfer.assert_not_called()

    def test_failed_build_is_retryable_without_a_stranded_host_reservation(self):
        self.configure_hosts()
        with patch.object(self.pool, '_preflight', return_value=(self.manifest, {}, {})), \
                patch.object(self.pool, 'probe', return_value=[]), \
                patch.object(pool_module, 'plan', return_value={'selected': 'remote'}), \
                patch.object(self.pool, 'remote', side_effect=self.accepted) as remote, \
                patch.object(pool_module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
            with patch.object(pool_module.tarfile.TarFile, 'add', side_effect=OSError(errno.ENOSPC, 'late disk full')):
                with self.assertRaisesRegex(pool_module.SubmissionDeferred, 'archive preparation unavailable'):
                    self.pool.submit(self.snapshot, 'res://tests/test_fixture.gd', request_id='sameid')
            self.assertFalse((self.pool.root / 'jobs/sameid.json').exists())
            remote.assert_not_called()
            result = self.pool.submit(self.snapshot, 'res://tests/test_fixture.gd', request_id='sameid')
        self.assertEqual(result['state'], 'SUBMITTED')
        self.assertEqual(remote.call_count, 1)
        self.assertEqual(remote.call_args.args[2]['request_id'], 'sameid')
        self.assertEqual(self.pending(), [])

    def test_archive_preparation_releases_global_lock_and_reselects_remote(self):
        self.configure_hosts()
        original = self.pool._prepare_archive
        def prepare(snapshot, manifest):
            other_dispatch = pool_module.Singleton(self.pool.root / 'dispatch.lock')
            other_dispatch.close()
            self.assertFalse((self.pool.root / 'jobs/moving.json').exists())
            return original(snapshot, manifest)
        with patch.object(self.pool, '_preflight', return_value=(self.manifest, {}, {})), \
                patch.object(self.pool, 'probe', return_value=[]) as probe, \
                patch.object(pool_module, 'plan', side_effect=[{'selected': 'remote'}, {'selected': 'second'}]), \
                patch.object(self.pool, '_prepare_archive', side_effect=prepare) as build, \
                patch.object(self.pool, 'remote', side_effect=self.accepted) as remote, \
                patch.object(pool_module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
            result = self.pool.submit(self.snapshot, 'res://tests/test_fixture.gd', request_id='moving')
        self.assertEqual(result['state'], 'SUBMITTED')
        self.assertEqual(probe.call_count, 2)
        self.assertEqual(build.call_count, 1)
        self.assertEqual(remote.call_args.args[0]['id'], 'second')
        self.assertEqual(json.loads(Path(result['receipt']).read_text())['host'], 'second')

    def test_reselection_can_use_local_without_remote_dispatch(self):
        self.configure_hosts()
        with patch.object(self.pool, '_preflight', return_value=(self.manifest, {}, {})), \
                patch.object(self.pool, 'probe', return_value=[]), \
                patch.object(pool_module, 'plan', side_effect=[{'selected': 'remote'}, {'selected': 'local'}]), \
                patch.object(self.pool, 'remote') as remote, \
                patch.object(pool_module.subprocess, 'run') as transfer, \
                patch.object(pool_module, 'rpc', return_value={'job': 'local-job'}) as rpc:
            result = self.pool.submit(self.snapshot, 'res://tests/test_fixture.gd', request_id='localafter')
        self.assertEqual(result['state'], 'SUBMITTED')
        remote.assert_not_called()
        transfer.assert_not_called()
        self.assertEqual(rpc.call_args.kwargs['expected_source_digest'], self.manifest['source_digest'])
        self.assertEqual(rpc.call_args.kwargs['snapshot'], str(self.snapshot))
        self.assertEqual(json.loads(Path(result['receipt']).read_text())['host'], 'local')

    def test_reselection_with_no_capacity_waits_without_a_receipt(self):
        self.configure_hosts()
        with patch.object(self.pool, '_preflight', return_value=(self.manifest, {}, {})), \
                patch.object(self.pool, 'probe', return_value=[]), \
                patch.object(pool_module, 'plan', side_effect=[{'selected': 'remote'}, {'selected': None}]), \
                patch.object(self.pool, 'remote') as remote, \
                patch.object(pool_module.subprocess, 'run') as transfer:
            result = self.pool.submit(self.snapshot, 'res://tests/test_fixture.gd', request_id='busyafter')
        self.assertEqual(result['state'], 'WAITING')
        self.assertFalse((self.pool.root / 'jobs/busyafter.json').exists())
        remote.assert_not_called()
        transfer.assert_not_called()

    def test_corrupt_existing_archive_blocks_before_a_receipt(self):
        self.configure_hosts()
        archive = self.archives / ('a' * 64 + '.tar')
        archive.write_bytes(b'corrupt existing cache')
        with patch.object(self.pool, '_preflight', return_value=(self.manifest, {}, {})), \
                patch.object(self.pool, 'probe', return_value=[]), \
                patch.object(pool_module, 'plan', return_value={'selected': 'remote'}), \
                patch.object(self.pool, 'remote') as remote:
            with self.assertRaisesRegex(RuntimeError, 'requires inspection'):
                self.pool.submit(self.snapshot, 'res://tests/test_fixture.gd', request_id='corrupt')
        self.assertFalse((self.pool.root / 'jobs/corrupt.json').exists())
        self.assertEqual(archive.read_bytes(), b'corrupt existing cache')
        remote.assert_not_called()

    def test_unremovable_temporary_blocks_batch_without_repeated_builds(self):
        self.configure_hosts()
        (self.snapshot / 'manifest.json').write_text(json.dumps(self.manifest))
        batch = self.root / 'batch.json'
        batch.write_text(json.dumps({'snapshot': str(self.snapshot),
                                     'jobs': [{'script': 'res://tests/test_fixture.gd'}]}))
        state = self.root / 'batch-state.json'
        create = pool_module.tempfile.mkstemp
        with (patch.object(self.pool, '_preflight', return_value=(self.manifest, {}, {})),
              patch.object(self.pool, 'probe', return_value=[]),
              patch.object(pool_module, 'plan', return_value={'selected': 'remote'}),
              patch.object(pool_module, 'verify_archive', side_effect=ValueError('changed source')),
              patch.object(Path, 'unlink', side_effect=PermissionError('cleanup denied')),
              patch.object(pool_module.tempfile, 'mkstemp', wraps=create) as builds,
              patch.object(self.pool, 'remote') as remote):
            first = run_batch(self.pool, self.pool.config_path, batch, state, timeout=0.03, poll_interval=0.005)
            second = run_batch(self.pool, self.pool.config_path, batch, state, timeout=0.03, poll_interval=0.005)
        self.assertEqual(first['jobs'][0]['phase'], 'BLOCKED')
        self.assertEqual(second['jobs'][0]['phase'], 'BLOCKED')
        self.assertEqual(builds.call_count, 1)
        self.assertEqual(len(self.pending()), 1)
        self.assertIn('temporary could not be removed', first['jobs'][0]['first_error'])
        remote.assert_not_called()

    def test_unlink_failure_reports_the_retained_owned_temporary(self):
        with patch.object(pool_module, "verify_archive", side_effect=ValueError("verification failed")), \
                patch.object(Path, "unlink", side_effect=PermissionError("delete denied")):
            with self.assertRaisesRegex(RuntimeError, "temporary could not be removed") as error:
                self.pool._prepare_archive(self.snapshot, self.manifest)
        remaining = self.pending()
        self.assertEqual(len(remaining), 1)
        self.assertIn(str(remaining[0]), str(error.exception))
        self.assertTrue(remaining[0].is_file())

    def test_replaced_temporary_is_retained_without_touching_foreign_file(self):
        foreign = self.root / "foreign.txt"
        foreign.write_bytes(b"must survive")
        seen = []

        def replace_temporary(path, _manifest):
            seen.append(path)
            path.unlink()
            try:
                path.symlink_to(foreign)
            except OSError as error:
                self.skipTest(f"symlink fixture unavailable: {error}")
            raise ValueError("replacement detected")

        with patch.object(pool_module, "verify_archive", side_effect=replace_temporary):
            with self.assertRaisesRegex(RuntimeError, "identity changed"):
                self.pool._prepare_archive(self.snapshot, self.manifest)
        self.assertEqual(foreign.read_bytes(), b"must survive")
        self.assertTrue(seen[0].is_symlink())
        self.assertEqual(list(self.archives.glob("*.tar")), [])

    def test_cached_archive_link_is_refused(self):
        foreign = self.root / "foreign.tar"
        foreign.write_bytes(b"not a managed cache")
        archive = self.archives / ("a" * 64 + ".tar")
        try:
            archive.symlink_to(foreign)
        except OSError as error:
            self.skipTest(f"symlink fixture unavailable: {error}")
        with self.assertRaisesRegex(ValueError, "regular file"):
            self.pool._prepare_archive(self.snapshot, self.manifest)
        self.assertEqual(foreign.read_bytes(), b"not a managed cache")
        self.assertTrue(archive.is_symlink())

    def test_reparse_temporary_is_not_removed(self):
        path = self.archives / "reparse.pending"
        path.write_bytes(b"retain")
        info = path.stat()
        reparse = SimpleNamespace(st_mode=info.st_mode, st_dev=info.st_dev, st_ino=info.st_ino,
                                  st_file_attributes=0x400)
        with patch.object(Path, "lstat", return_value=reparse):
            with self.assertRaisesRegex(RuntimeError, "identity changed"):
                pool_module._discard_owned_archive_temporary(path, (info.st_dev, info.st_ino))
        self.assertEqual(path.read_bytes(), b"retain")


if __name__ == "__main__":
    unittest.main()
