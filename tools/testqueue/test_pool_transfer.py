"""Remote archive transfer failures are proved nondispatched and retry on the bound host (TQ-05-F0.3)."""
from __future__ import annotations

import contextlib
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tools.testqueue import collection, pool as pool_module, pool_mcp
from tools.testqueue.common import write_json
from tools.testqueue.pool_batch import run_batch

OPTION_VALUES = ('BatchMode=yes', 'StrictHostKeyChecking=yes', 'ServerAliveInterval=15', 'ServerAliveCountMax=4')
CREATION_FLAGS = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
STAGE_TIMEOUTS = {'mkdir': 30, 'hash_check': 180, 'scp': 1800, 'verify': 180, 'publish': 30}
PASS = {'state': 'FINISHED', 'outcome': 'PASSED', 'cleanup': 'CONFIRMED', 'evidence': 'COMPLETE'}


class TransferDeferralTests(unittest.TestCase):
    SCRIPT = 'res://tests/test_fixture.gd'

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='openrc-transfer-deferral-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        config = self.root / 'config.json'
        config.write_text(json.dumps({'state_root': str(self.root / 'pool'), 'hosts': []}))
        self.pool = pool_module.Pool(config)
        self.snapshot = self.root / 'snapshot'
        source = self.snapshot / 'source/app'
        source.mkdir(parents=True)
        content = b'verified frozen input\n'
        (source / 'test.gd').write_bytes(content)
        self.manifest = {'source_digest': 'a' * 64, 'source_root': str(self.root / 'developer'), 'files': {
            'app/test.gd': {'size': len(content), 'sha256': hashlib.sha256(content).hexdigest()}}}
        (self.snapshot / 'manifest.json').write_text(json.dumps(self.manifest))
        self.pool.hosts.extend([
            {'id': name, 'ssh': name, 'python': 'python3', 'agent': '/agent.py', 'root': '/remote/' + name,
             'engine': '/engine', 'engine_sha256': 'b' * 64} for name in ('remote', 'second')])
        self.selected = 'remote'
        self.planned = []

    @staticmethod
    def accepted(host, action, request):
        return {'request_id': request['request_id'], 'payload_sha256': pool_module.request_digest(request),
                'state': 'STARTING'}

    @staticmethod
    def stage_of(argv):
        command = argv[-1]
        if argv[0] == 'scp':
            return 'scp'
        if 'mkdir' in command:
            return 'mkdir'
        if 'os.replace' in command:
            return 'publish'
        return 'verify' if '.pending' in command else 'hash_check'

    def transport(self, faults=None):
        """Fake ssh/scp: record calls, raise queued exceptions per stage, remember publication."""
        faults, calls, published = faults or {}, [], []

        def run(argv, **kwargs):
            calls.append((argv, kwargs))
            stage = self.stage_of(argv)
            if faults.get(stage):
                raise faults[stage].pop(0)
            if stage == 'publish':
                published.append(True)
            code = 1 if stage == 'hash_check' and not published else 0
            result = subprocess.CompletedProcess(argv, code, b'', b'')
            if kwargs.get('check'):
                result.check_returncode()
            return result
        return run, calls

    @contextlib.contextmanager
    def fleet(self, run):
        def plan(job, observations):
            self.planned.append([item['id'] for item in observations])
            return {'selected': self.selected}
        def probe(host_id=None):
            return [{'id': name, 'online': True, 'busy': False} for name in ('remote', 'second')
                    if host_id is None or name == host_id]
        with patch.object(self.pool, '_preflight', return_value=(self.manifest, {}, {})), \
                patch.object(self.pool, 'probe', side_effect=probe), \
                patch.object(pool_module, 'plan', side_effect=plan), \
                patch.object(pool_module, 'verify_archive'), \
                patch.object(self.pool, 'remote', side_effect=self.accepted) as remote, \
                patch.object(pool_module.subprocess, 'run', side_effect=run):
            yield remote

    def receipt(self, identifier='sameid'):
        return json.loads((self.pool.root / 'jobs' / (identifier + '.json')).read_text(encoding='utf-8'))

    def submit(self, identifier='sameid', **kwargs):
        return self.pool.submit(self.snapshot, self.SCRIPT, request_id=identifier, **kwargs)

    def assert_options(self, argv, connect_timeout=8):
        for value in OPTION_VALUES + (f'ConnectTimeout={connect_timeout}',):
            self.assertIn(value, argv)
            self.assertEqual(argv[argv.index(value) - 1], '-o', value)

    def test_scp_timeout_defers_without_dispatch_and_does_not_reserve_the_host(self):
        run, _ = self.transport({'scp': [subprocess.TimeoutExpired('scp', 1800)]})
        with self.fleet(run) as remote:
            with self.assertRaises(pool_module.SubmissionDeferred) as caught:
                self.submit()
            remote.assert_not_called()  # the agent's run action was never reached
        self.assertEqual(caught.exception.reason_code, 'TRANSFER_DEFERRED')
        receipt = self.receipt()
        self.assertEqual((receipt['state'], receipt['host']), ('TRANSFER_DEFERRED', 'remote'))
        self.assertNotIn('request', receipt)
        transfer = receipt['transfer']
        self.assertEqual((transfer['attempts'], transfer['stage'], transfer['code']), (1, 'scp', 'TRANSFER_TIMEOUT'))
        self.assertIn('1800', receipt['error'])
        busy = {item['id']: item['busy'] for item in self.pool._reserve(
            [{'id': 'remote', 'busy': False}, {'id': 'second', 'busy': False}])}
        self.assertEqual(busy, {'remote': False, 'second': False})
        with patch.object(self.pool, 'remote') as remote:
            for observe in (self.pool.status, self.pool.recover):
                status = observe('sameid')
                self.assertEqual((status['state'], status['reason_code']), ('WAITING', 'TRANSFER_DEFERRED'))
                self.assertEqual(status['pool_host'], 'remote')
            remote.assert_not_called()
        self.assertEqual(self.receipt()['state'], 'TRANSFER_DEFERRED')  # observation changed nothing

    def test_only_deferred_transfers_release_the_reservation(self):
        for state, reserved in (('PREPARING', True), ('SUBMISSION_UNCONFIRMED', True), ('TRANSFER_DEFERRED', False)):
            with self.subTest(state=state):
                write_json(self.pool.root / 'jobs' / 'held.json',
                           {'request_id': 'held', 'host': 'remote', 'state': state, 'created': 1.0})
                self.assertEqual(self.pool._reserve([{'id': 'remote', 'busy': False}])[0]['busy'], reserved)

    def test_every_pre_run_failure_is_typed_and_nondispatched(self):
        cases = [
            ('mkdir', subprocess.CalledProcessError(255, 'ssh', stderr=b'Permission denied (publickey).'),
             'TRANSFER_FAILED', 'Permission denied'),
            ('hash_check', subprocess.TimeoutExpired('ssh', 180), 'TRANSFER_TIMEOUT', '180'),
            ('scp', subprocess.CalledProcessError(1, 'scp'), 'TRANSFER_FAILED', 'exit status 1'),
            ('scp', FileNotFoundError('scp'), 'TRANSFER_FAILED', 'FileNotFoundError'),
            ('verify', subprocess.CalledProcessError(1, 'ssh', stderr=b'No space left on device'),
             'TRANSFER_FAILED', 'No space left'),
            ('publish', subprocess.TimeoutExpired('ssh', 30), 'TRANSFER_TIMEOUT', '30'),
        ]
        for index, (stage, error, code, text) in enumerate(cases):
            with self.subTest(stage=stage, code=code):
                run, _ = self.transport({stage: [error]})
                identifier = f'case{index}'
                with self.fleet(run) as remote:
                    with self.assertRaises(pool_module.SubmissionDeferred):
                        self.submit(identifier)
                    remote.assert_not_called()
                receipt = self.receipt(identifier)
                self.assertEqual(receipt['state'], 'TRANSFER_DEFERRED')
                self.assertEqual((receipt['transfer']['stage'], receipt['transfer']['code']), (stage, code))
                self.assertIn(text, receipt['transfer']['error'])
                self.assertNotIn('request', receipt)

    def test_retry_of_the_same_id_retransfers_on_the_bound_host_and_submits_once(self):
        run, calls = self.transport({'scp': [subprocess.TimeoutExpired('scp', 1800)]})
        with self.fleet(run) as remote:
            with self.assertRaises(pool_module.SubmissionDeferred):
                self.submit()
            first, first_plans = self.receipt(), len(self.planned)
            self.assertEqual(self.planned[0], ['remote', 'second'])  # the first placement was open
            result = self.submit()
            self.assertTrue(self.planned[first_plans:])
            self.assertTrue(all(ids == ['remote'] for ids in self.planned[first_plans:]))  # bound host only
            self.assertEqual(result['state'], 'SUBMITTED')
            self.assertEqual(remote.call_count, 1)
            self.assertEqual((remote.call_args.args[0]['id'], remote.call_args.args[1]), ('remote', 'run'))
            self.assertEqual(remote.call_args.args[2]['request_id'], 'sameid')
            self.assertEqual(self.submit()['state'], 'SUBMITTED')  # idempotent: no further transfer or run
            self.assertEqual(remote.call_count, 1)
        stages = [self.stage_of(argv) for argv, _ in calls]
        self.assertEqual(stages.count('scp'), 2)
        self.assertEqual(stages.count('publish'), 1)
        receipt = self.receipt()
        self.assertEqual((receipt['state'], receipt['host']), ('SUBMITTED', 'remote'))
        self.assertEqual(receipt['created'], first['created'])
        self.assertEqual(receipt['transfer']['attempts'], 1)  # history of the earlier failure is kept
        self.assertNotIn('error', receipt)
        self.assertEqual(receipt['request']['archive']['path'].rsplit('/', 2)[0], '/remote/remote')

    def test_retry_with_changed_inputs_is_refused_and_transfers_nothing(self):
        run, calls = self.transport({'scp': [subprocess.TimeoutExpired('scp', 1800)]})
        with self.fleet(run) as remote:
            with self.assertRaises(pool_module.SubmissionDeferred):
                self.submit()
            seen = len(calls)
            with self.assertRaisesRegex(ValueError, 'different inputs'):
                self.pool.submit(self.snapshot, 'res://tests/other.gd', request_id='sameid')
            with self.assertRaisesRegex(ValueError, 'different inputs'):
                self.submit(platform='linux')
            moved = {**self.manifest, 'source_digest': 'c' * 64}
            with patch.object(self.pool, '_preflight', return_value=(moved, {}, {})), \
                    self.assertRaises(pool_module.SubmissionRejected):
                self.submit()
            self.assertEqual(len(calls), seen)
            remote.assert_not_called()
        self.assertEqual(self.receipt()['state'], 'TRANSFER_DEFERRED')

    def test_bound_host_without_capacity_keeps_waiting_without_a_transfer(self):
        run, calls = self.transport({'scp': [subprocess.TimeoutExpired('scp', 1800)]})
        with self.fleet(run):
            with self.assertRaises(pool_module.SubmissionDeferred):
                self.submit()
            seen, self.selected = len(calls), None
            self.assertEqual(self.submit()['state'], 'WAITING')
        self.assertEqual(len(calls), seen)
        self.assertEqual(self.receipt()['state'], 'TRANSFER_DEFERRED')

    def test_every_ssh_and_scp_call_uses_the_shared_options_and_keeps_timeouts(self):
        run, calls = self.transport()
        with self.fleet(run):
            self.submit()
        self.assertEqual([self.stage_of(argv) for argv, _ in calls],
                         ['mkdir', 'hash_check', 'scp', 'verify', 'publish'])
        for argv, kwargs in calls:
            stage = self.stage_of(argv)
            self.assertIn(argv[0], ('ssh', 'scp'))
            self.assert_options(argv)
            self.assertEqual(kwargs['creationflags'], CREATION_FLAGS)
            self.assertEqual(kwargs['timeout'], STAGE_TIMEOUTS[stage])
            if argv[0] == 'ssh':
                self.assertEqual((argv[1], argv[-2]), ('-T', 'remote'))
            else:
                self.assertTrue(argv[-1].startswith('remote:/remote/remote/incoming/'))

    def test_agent_and_artifact_calls_use_the_same_options(self):
        response = SimpleNamespace(returncode=0, stdout='{"ok":true,"result":{"state":"RUNNING"}}', stderr='')
        with patch.object(pool_module.subprocess, 'run', return_value=response) as call:
            self.pool.remote(self.pool.hosts[0], 'status', {'request_id': 'id1'})
        argv = call.call_args.args[0]
        self.assertEqual(argv[:2], ['ssh', '-T'])
        self.assert_options(argv, 8)
        payload = b'verified-data'
        expected = {'size': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}

        def copy(command, **options):
            options['stdout'].write(payload)
            return SimpleNamespace(returncode=0)
        with patch.object(pool_module.subprocess, 'run', side_effect=copy) as call:
            collection._copy_remote(pool_module, self.pool.hosts[0], '/remote/root', 'result',
                                    self.root / 'artifact', expected)
        self.assert_options(call.call_args.args[0], 10)

    def run_batch(self, timeout):
        batch = self.root / 'batch.json'
        if not batch.exists():
            write_json(batch, {'snapshot': str(self.snapshot), 'jobs': [{'script': self.SCRIPT}]})
        return run_batch(self.pool, self.pool.config_path, batch, self.root / 'batch-state.json',
                         timeout=timeout, poll_interval=0.005)

    def test_batch_retries_the_same_id_with_backoff_and_submits_once(self):
        run, _ = self.transport({'scp': [subprocess.TimeoutExpired('scp', 1800)]})
        report = lambda identifier: {'pool_job': identifier, 'pool_outcome': 'PASSED',
                                     'collection_format': collection.FORMAT, 'diagnostic_only': False}
        with self.fleet(run) as remote, \
                patch.object(self.pool, 'status', return_value=PASS), \
                patch.object(self.pool, 'collect', side_effect=report), \
                patch.object(self.pool, 'verify_collection', side_effect=lambda identifier, result: result), \
                patch('tools.testqueue.pool_batch.RETRY_INITIAL_SECONDS', 0.01):
            result = self.run_batch(timeout=5)
        row = result['jobs'][0]
        self.assertEqual(result['result'], 'PASSED')
        self.assertEqual(row['submission_attempts'], 2)
        self.assertIn('TRANSFER_TIMEOUT', row['first_error'])
        self.assertEqual(remote.call_count, 1)
        self.assertEqual(self.receipt(row['request_id'])['state'], 'SUBMITTED')

    def test_crash_after_deferral_resumes_as_retry_wait_and_summarizes_as_queued(self):
        run, _ = self.transport({'scp': [subprocess.TimeoutExpired('scp', 1800)]})
        original = self.pool.submit

        def defer_then_crash(*args, **kwargs):
            try:
                original(*args, **kwargs)
            except pool_module.SubmissionDeferred:
                raise SystemExit('crash before the batch recorded the deferral') from None
        with self.fleet(run), patch.object(self.pool, 'submit', side_effect=defer_then_crash):
            with self.assertRaises(SystemExit):
                self.run_batch(timeout=1)
        saved = json.loads((self.root / 'batch-state.json').read_text())
        self.assertEqual(saved['jobs'][0]['phase'], 'SUBMITTING')
        with self.fleet(run) as remote, patch('tools.testqueue.pool_batch.RETRY_INITIAL_SECONDS', 30):
            state = self.run_batch(timeout=1)
            remote.assert_not_called()
        row = state['jobs'][0]
        self.assertEqual(row['phase'], 'RETRY_WAIT')  # not BLOCKED, not TRACKING
        self.assertEqual(row['status']['reason_code'], 'TRANSFER_DEFERRED')
        summary = pool_mcp.summarize({'result': state['result'], 'jobs': state['jobs'],
                                      'supervisor_active': True, 'supervisor': {'state': 'WAITING'}})
        self.assertEqual((summary['queued'], summary['blocked']), (1, 0))
        self.assertEqual(summary['waiting'], {'TRANSFER_DEFERRED': 1})
        self.assertTrue(summary['next_action'].startswith('poll sim_test_status; waiting: TRANSFER_DEFERRED=1'))


if __name__ == '__main__':
    unittest.main()
