"""Pool dispatch receipts preserve ambiguous submissions and platform selection."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue.pool import Pool
from tools.testqueue.pool_batch import run_batch
from tools.testqueue.pool_checked import checked


class PoolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        config = root / 'config.json'
        config.write_text(json.dumps({'state_root': str(root / 'state'), 'hosts': [
            {'id': 'windows', 'local': True}]}))
        self.pool = Pool(config)
        self.snapshot = root / 'snapshot'
        self.snapshot.mkdir()
        (self.snapshot / 'manifest.json').write_text(json.dumps({
            'source_root': str(root), 'source_digest': 'test', 'files': {}}))

    def test_unreachable_hosts_never_submit(self):
        with patch('tools.testqueue.pool.verify', return_value={'ok': True}), \
             patch.object(self.pool, 'probe', return_value=[{'id': 'windows', 'online': False}]), \
             patch('tools.testqueue.pool.rpc') as rpc:
            result = self.pool.submit(self.snapshot, 'res://tests/test_math3d.gd')
        self.assertEqual(result['state'], 'WAITING')
        rpc.assert_not_called()

    def test_lost_reply_keeps_exact_request_and_destination(self):
        with patch('tools.testqueue.pool.verify', return_value={'ok': True}), \
             patch.object(self.pool, 'probe', return_value=[]), \
             patch('tools.testqueue.pool.plan', return_value={'selected': 'windows'}), \
             patch('tools.testqueue.pool.rpc', side_effect=RuntimeError('lost reply')):
            result = self.pool.submit(self.snapshot, 'res://tests/test_math3d.gd')
        receipt = json.loads(Path(result['receipt']).read_text())
        self.assertEqual(receipt['state'], 'SUBMISSION_UNCONFIRMED')
        self.assertEqual(receipt['host'], 'windows')
        self.assertEqual(receipt['request']['request_id'], result['job'])
        with patch('tools.testqueue.pool.rpc', side_effect=RuntimeError('offline')) as rpc:
            status = self.pool.status(result['job'])
        self.assertEqual(status['state'], 'UNKNOWN')
        self.assertEqual(rpc.call_args.args[0], 'recover')

    def test_timing_script_cannot_be_distributed_as_functional(self):
        with patch('tools.testqueue.pool.verify', return_value={'ok': True}), \
             patch.object(self.pool, 'probe') as probe:
            with self.assertRaisesRegex(ValueError, 'Performance'):
                self.pool.submit(self.snapshot, 'res://tests/benchmark_solver.gd')
        probe.assert_not_called()

    def test_observed_completion_clears_uncertain_submission_reservation(self):
        with patch('tools.testqueue.pool.verify', return_value={'ok': True}), \
             patch.object(self.pool, 'probe', return_value=[]), \
             patch('tools.testqueue.pool.plan', return_value={'selected': 'windows'}), \
             patch('tools.testqueue.pool.rpc', side_effect=RuntimeError('lost reply')):
            submitted = self.pool.submit(self.snapshot, 'res://tests/test_math3d.gd')
        with patch('tools.testqueue.pool.rpc', side_effect=[{'job': 'existing'}, {'state': 'FINISHED', 'outcome': 'PASSED'}]):
            self.pool.status(submitted['job'])
        receipt = json.loads(Path(submitted['receipt']).read_text())
        self.assertEqual(receipt['state'], 'SUBMITTED')

    def test_preparation_recovery_releases_host_without_dispatch(self):
        path = self.pool.root / 'jobs' / 'prepared.json'
        path.parent.mkdir()
        path.write_text(json.dumps({'state': 'PREPARING', 'host': 'windows'}))
        with patch('tools.testqueue.pool.rpc') as rpc:
            result = self.pool.recover('prepared')
        self.assertEqual(result['state'], 'FINISHED')
        self.assertEqual(json.loads(path.read_text())['state'], 'NOT_DISPATCHED')
        rpc.assert_not_called()

    def receipt(self, identifier, host):
        path = self.pool.root / 'jobs' / (identifier + '.json')
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps({'host': host, 'options': {'script': 'res://tests/test_math3d.gd'}}))

    def test_collect_local_infrastructure_failure_preserves_full_status(self):
        self.receipt('failed', 'windows')
        status = {'state': 'FINISHED', 'outcome': 'INFRA_FAILED', 'cleanup': 'CONFIRMED',
                  'evidence': 'INCOMPLETE', 'error': 'import failed', 'runner_verdict': None}
        with patch.object(self.pool, 'status', return_value=status):
            report = self.pool.collect('failed')
        self.assertEqual(report['pool_job'], 'failed')
        self.assertEqual(report['pool_host'], 'windows')
        self.assertEqual(report['pool_outcome'], 'INFRA_FAILED')
        self.assertEqual(json.loads(Path(report['pool_status']).read_text()), status)
        self.assertEqual(json.loads(Path(report['pool_report']).read_text()), report)
        self.assertNotIn('ok', report)
        self.assertNotIn('complete', report)
        self.assertFalse((Path(report['pool_status']).parent / 'engine.log').exists())

    def test_collect_remote_infrastructure_failure_retains_verified_artifacts(self):
        self.pool.hosts.append({'id': 'mac', 'ssh': 'example-mac'})
        self.receipt('remote', 'mac')
        log = b'import failure details\n'
        native_report = b'{"native": "failed"}'
        status = {'state': 'FINISHED', 'outcome': 'INFRA_FAILED', 'error': 'import failed',
                  'output': '/remote/job', 'artifacts': {'import/engine.log': {
                      'size': len(log), 'sha256': hashlib.sha256(log).hexdigest()},
                      'report.json': {'size': len(native_report), 'sha256': hashlib.sha256(native_report).hexdigest()}}}
        def copy_artifact(command, **kwargs):
            Path(command[-1]).write_bytes(native_report if command[-1].endswith('report.json') else log)
        with patch.object(self.pool, 'status', return_value=status), \
             patch('tools.testqueue.pool.subprocess.run', side_effect=copy_artifact):
            report = self.pool.collect('remote')
        destination = Path(report['pool_status']).parent
        self.assertEqual((destination / 'import/engine.log').read_bytes(), log)
        self.assertEqual((destination / 'report.json').read_bytes(), native_report)
        self.assertEqual(json.loads(Path(report['pool_status']).read_text()), status)
        self.assertEqual(report['pool_outcome'], 'INFRA_FAILED')

    def test_collect_rejects_remote_artifact_digest_mismatch(self):
        self.pool.hosts.append({'id': 'mac', 'ssh': 'example-mac'})
        self.receipt('corrupt', 'mac')
        status = {'state': 'FINISHED', 'outcome': 'INFRA_FAILED', 'output': '/remote/job',
                  'artifacts': {'import/engine.log': {'size': 3, 'sha256': hashlib.sha256(b'abc').hexdigest()}}}
        def copy_artifact(command, **kwargs):
            Path(command[-1]).write_bytes(b'xyz')
        with patch.object(self.pool, 'status', return_value=status), \
             patch('tools.testqueue.pool.subprocess.run', side_effect=copy_artifact), \
             self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.pool.collect('corrupt')
        saved = self.pool.root / 'results/corrupt/pool-status.json'
        self.assertEqual(json.loads(saved.read_text()), status)

    def test_remote_artifact_cannot_overwrite_retained_status(self):
        self.pool.hosts.append({'id': 'mac', 'ssh': 'example-mac'})
        self.receipt('collision', 'mac')
        status = {'state': 'FINISHED', 'outcome': 'INFRA_FAILED', 'output': '/remote/job',
                  'artifacts': {'pool-status.json': {'size': 0, 'sha256': hashlib.sha256(b'').hexdigest()}}}
        with patch.object(self.pool, 'status', return_value=status), \
             patch('tools.testqueue.pool.subprocess.run') as scp, \
             self.assertRaisesRegex(ValueError, 'conflicts with saved pool evidence'):
            self.pool.collect('collision')
        scp.assert_not_called()
        saved = self.pool.root / 'results/collision/pool-status.json'
        self.assertEqual(json.loads(saved.read_text()), status)

    def test_passed_without_checked_report_remains_an_error(self):
        self.receipt('missing', 'windows')
        status = {'state': 'FINISHED', 'outcome': 'PASSED', 'runner_verdict': {}}
        with patch.object(self.pool, 'status', return_value=status), \
             self.assertRaisesRegex(ValueError, 'no checked report'):
            self.pool.collect('missing')
        self.assertEqual(json.loads((self.pool.root / 'results/missing/pool-status.json').read_text()), status)
        self.assertFalse((self.pool.root / 'results/missing/report.json').exists())

    def test_batch_finishes_failed_infrastructure_without_retry(self):
        manifest = Path(self.temp.name) / 'batch.json'
        manifest.write_text(json.dumps({'snapshot': str(self.snapshot), 'jobs': [
            {'script': 'res://tests/test_math3d.gd', 'platform': 'windows'}]}))
        state_path = Path(self.temp.name) / 'batch-state.json'
        status = {'state': 'FINISHED', 'outcome': 'INFRA_FAILED', 'error': 'import failed',
                  'cleanup': 'CONFIRMED', 'evidence': 'INCOMPLETE'}
        def submit(_snapshot, _script, *, request_id, **kwargs):
            self.receipt(request_id, 'windows')
            return {'job': request_id}
        with patch.object(self.pool, 'submit', side_effect=submit) as mocked_submit, \
             patch.object(self.pool, 'status', return_value=status):
            state = run_batch(self.pool, self.pool.config_path, manifest, state_path, timeout=10, poll_interval=0)
            resumed = run_batch(self.pool, self.pool.config_path, manifest, state_path, timeout=10, poll_interval=0)
        self.assertEqual(state['result'], 'FAILED')
        self.assertEqual(state['jobs'][0]['phase'], 'DONE')
        self.assertEqual(resumed['result'], 'FAILED')
        self.assertEqual(mocked_submit.call_count, 1)

    def test_checked_consumer_rejects_infrastructure_without_report_fields(self):
        infrastructure = {'pool_job': 'failed', 'pool_host': 'windows', 'pool_outcome': 'INFRA_FAILED',
                          'pool_status': str(self.pool.root / 'results/failed/pool-status.json')}
        with patch.dict(os.environ, {'OPENRC_TESTPOOL_CONFIG': str(self.pool.config_path)}), \
             patch('tools.testqueue.pool_checked.Pool') as pool_type:
            pool = pool_type.return_value
            pool.snapshot.return_value = self.snapshot
            pool.submit.return_value = {'state': 'SUBMITTED', 'receipt': 'receipt.json'}
            pool.status.return_value = {'state': 'FINISHED'}
            pool.collect.return_value = infrastructure
            command = [sys.executable, '--headless', '--path', str(Path(self.temp.name) / 'app'),
                       '--script', 'res://tests/test_math3d.gd']
            with self.assertRaisesRegex(ValueError, 'Pool infrastructure failure'):
                checked(command, out_dir=self.pool.root, timeout=90, required=[], max_log_bytes=1024,
                        warnings_as_errors=False, label='test')


if __name__ == '__main__':
    unittest.main()
