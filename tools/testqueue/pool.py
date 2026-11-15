"""Automatic placement of source-bound checked tests across local and SSH hosts."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tarfile
import time
import uuid

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import Singleton, rpc, write_json, submission_receipt
from tools.testqueue.pool_policy import plan
from tools.testqueue.presets import validate, scheduling
from tools.testqueue.snapshots import capture, verify


def default_config():
    return os.environ.get('OPENRC_TESTPOOL_CONFIG', str(Path(os.environ.get('PROGRAMDATA', '/var/tmp')) / 'OpenRC/testpool/config.json'))


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def verify_archive(archive, manifest):
    with tarfile.open(archive) as bundle:
        members = bundle.getmembers()
        if len(members) != len(manifest['files']) or {item.name for item in members} != set(manifest['files']):
            raise ValueError('Archive member set differs from frozen snapshot')
        for member in members:
            expected = manifest['files'][member.name]
            if not member.isfile() or member.size != expected['size']:
                raise ValueError('Archive member differs from frozen snapshot')
            checksum = hashlib.sha256()
            with bundle.extractfile(member) as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    checksum.update(block)
            if checksum.hexdigest() != expected['sha256']:
                raise ValueError('Archive bytes differ from frozen snapshot: ' + member.name)


def acquire_lock(path, timeout=60):
    deadline = time.monotonic() + timeout
    while True:
        try:
            return Singleton(path)
        except (OSError, RuntimeError):
            if time.monotonic() >= deadline:
                raise RuntimeError('Timed out waiting for pool transaction lock')
            time.sleep(0.1)


class Pool:
    def __init__(self, config):
        self.config_path = Path(config).resolve()
        self.config = json.loads(self.config_path.read_text(encoding='utf-8'))
        self.root = Path(self.config['state_root']).resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.hosts = self.config['hosts']
        ids = [host['id'] for host in self.hosts]
        if len(ids) != len(set(ids)):
            raise ValueError('duplicate host ids')

    def remote(self, host, action, payload):
        command = shlex.join([host['python'], host['agent'], action, '--root', host['root']])
        result = subprocess.run(['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                                 '-o', 'ConnectTimeout=8', host['ssh'], command],
                                input=json.dumps(payload), capture_output=True, text=True, timeout=45)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        response = json.loads(result.stdout)
        if not response.get('ok'):
            raise RuntimeError(response.get('error', 'remote agent refused request'))
        return response['result']

    def probe_host(self, host):
        try:
            if host.get('local'):
                import psutil
                current = rpc('hosts')
                value = {'platform': current['platform'], 'online': True,
                         'busy': bool(current['claims']) or current['condition'] != 'READY' or bool(current['reservation']),
                         'free_disk_bytes': shutil.disk_usage(self.root).free,
                         'free_memory_bytes': psutil.virtual_memory().available,
                         'cores': os.cpu_count(), 'load': psutil.cpu_percent(interval=0.1) * (os.cpu_count() or 1) / 100,
                         'capabilities': ['headless'], 'engine': current['engine']}
            else:
                remote = self.remote(host, 'probe', {'engine_path': host['engine']})
                capacity, admission = remote['capacity'], remote['admission']
                load = capacity.get('load_average')
                value = {'platform': remote['host']['system'].lower(),
                         'online': remote['engine']['available'],
                         'busy': admission['busy'] or admission['quarantined'] or admission['enrolled'],
                         'free_disk_bytes': capacity['free_bytes'],
                         'free_memory_bytes': capacity['free_memory_bytes'],
                         'cores': capacity['cpu_count'], 'load': load[0] if isinstance(load, list) else (load or 0),
                         'capabilities': remote['capabilities'], 'engine': remote['engine']}
            if not host.get('local') and value['engine'].get('sha256') != host.get('engine_sha256'):
                raise ValueError('Remote engine differs from the configured verified pin')
            value.update(id=host['id'], local=host.get('local', False))
            value.setdefault('online', True)
            value.setdefault('cached_inputs', [])
            value.setdefault('durations', {})
            value['transfer_bytes_per_second'] = host.get('transfer_bytes_per_second', 10 * 1024 * 1024)
            history_path = self.root / 'history.json'
            if history_path.exists():
                history = json.loads(history_path.read_text()).get(host['id'], {})
                value['durations'] = {key: value for key, value in history.items() if key != '_setup_seconds'}
                value['setup_seconds'] = history.get('_setup_seconds', 0 if host.get('local') else 5)
            return value
        except (OSError, ValueError, RuntimeError, ImportError, subprocess.SubprocessError) as error:
            return {'id': host['id'], 'online': False, 'reason': str(error)}

    def probe(self):
        with ThreadPoolExecutor(max_workers=len(self.hosts) or 1) as executor:
            observations = list(executor.map(self.probe_host, self.hosts))
        reserved = set()
        for path in (self.root / 'jobs').glob('*.json'):
            receipt = json.loads(path.read_text())
            if receipt.get('state') in {'PREPARING', 'SUBMISSION_UNCONFIRMED'}:
                reserved.add(receipt['host'])
        for observation in observations:
            if observation['id'] in reserved:
                observation['busy'] = True
        return observations

    def snapshot(self, source):
        parent = self.root / 'snapshots'
        parent.mkdir(exist_ok=True)
        target = parent / uuid.uuid4().hex
        capture(Path(source).resolve(), target, include_imports=False)
        return target

    def submit(self, snapshot, script, *, platform='any', require=(), timeout=90, host_id=None, request_id=None, settings=None):
        identifier = request_id or uuid.uuid4().hex
        if not identifier.isalnum() or len(identifier) > 64:
            raise ValueError('invalid request id')
        guard = acquire_lock(self.root / (identifier + '.lock'))
        try:
            return self._submit(snapshot, script, platform=platform, require=require, timeout=timeout,
                                host_id=host_id, request_id=identifier, settings=settings)
        finally:
            guard.close()

    def _submit(self, snapshot, script, *, platform, require, timeout, host_id, request_id, settings):
        snapshot = Path(snapshot).resolve()
        identifier = request_id or uuid.uuid4().hex
        if not identifier.isalnum() or len(identifier) > 64:
            raise ValueError('invalid request id')
        inputs = {'snapshot': str(snapshot), 'script': script, 'platform': platform,
                  'require': list(require), 'timeout': timeout, 'host': host_id, 'settings': settings or {}}
        receipt_path = self.root / 'jobs' / (identifier + '.json')
        if receipt_path.exists():
            receipt = json.loads(receipt_path.read_text())
            if receipt.get('inputs') != inputs:
                raise ValueError('request id already has different inputs')
            return {'job': identifier, 'receipt': str(receipt_path), 'state': receipt['state'],
                    'decision': receipt['decision']}
        validation = verify(snapshot)
        if not validation.get('ok'):
            raise ValueError(f'invalid snapshot: {validation}')
        manifest = json.loads((snapshot / 'manifest.json').read_text())
        getter = snapshot / 'source/app/get-godot.sh'
        if getter.exists():
            import re
            match = re.search(r'^ENGINE_VERSION=(\S+)', getter.read_text(), re.MULTILINE)
            if not match or match[1] != self.config.get('engine_version'):
                raise ValueError('Frozen candidate engine pin differs from configured pool engine')
        options = validate('checked', {'script': script, 'require': list(require), 'timeout': timeout,
                                        'headless': True, 'workload': 'auto', 'settings': settings or {}})
        classification = scheduling('checked', options)
        if classification['workload'] == 'performance':
            raise ValueError('Performance checks require a dedicated same-host campaign through the existing queue')
        job = {'platform': platform, 'workload': 'headless',
               'source_bytes': sum(item['size'] for item in manifest['files'].values()),
               'cache_id': manifest['source_digest'], 'duration_key': script, 'estimated_seconds': timeout,
               'memory_bytes': 512 * 1024 * 1024}
        guard = acquire_lock(self.root / 'dispatch.lock')
        try:
            if receipt_path.exists():
                receipt = json.loads(receipt_path.read_text())
                if receipt.get('inputs') != inputs:
                    raise ValueError('request id already has different inputs')
                return {'job': identifier, 'receipt': str(receipt_path), 'state': receipt['state'],
                        'decision': receipt['decision']}
            observations = self.probe()
            if host_id:
                observations = [item for item in observations if item['id'] == host_id]
            decision = plan(job, observations)
            if decision['selected'] is None:
                return {'state': 'WAITING', 'decision': decision}
            host = next(item for item in self.hosts if item['id'] == decision['selected'])
            receipt = {'request_id': identifier, 'host': host['id'], 'snapshot': str(snapshot),
                       'inputs': inputs,
                       'source_digest': manifest['source_digest'], 'options': options,
                       'decision': decision, 'state': 'PREPARING', 'created': time.time()}
            write_json(receipt_path, receipt)
            guard.close()
            guard = None
            if host.get('local'):
                import secrets
                request = {'request_id': identifier, 'request_secret': secrets.token_hex(32),
                           'preset': 'checked', 'snapshot': str(snapshot), 'source': manifest['source_root'],
                           'owner': 'automatic-pool', 'platform': 'windows', 'options': options}
                submission_receipt(self.root, request)
                receipt['request'] = request
            else:
                archive = self.root / 'archives' / (manifest['source_digest'] + '.tar')
                archive.parent.mkdir(exist_ok=True)
                archive_guard = acquire_lock(archive.with_suffix('.lock'))
                try:
                    if not archive.exists():
                        temporary = archive.with_suffix('.pending')
                        with tarfile.open(temporary, 'w') as bundle:
                            for name in sorted(manifest['files']):
                                bundle.add(snapshot / 'source' / name, arcname=name, recursive=False)
                        verify_archive(temporary, manifest)
                        temporary.replace(archive)
                finally:
                    archive_guard.close()
                verify_archive(archive, manifest)
                archive_digest = digest(archive)
                remote_archive = host['root'] + '/incoming/' + archive_digest + '.tar'
                command = shlex.join(['mkdir', '-p', host['root'] + '/incoming'])
                subprocess.run(['ssh', '-T', host['ssh'], command], check=True, timeout=30)
                verifier = ('import hashlib, pathlib, sys\n'
                            'checksum = hashlib.sha256()\n'
                            'with pathlib.Path(sys.argv[1]).open("rb") as stream:\n'
                            '    for block in iter(lambda: stream.read(1048576), b""):\n'
                            '        checksum.update(block)\n'
                            'sys.exit(0 if checksum.hexdigest() == sys.argv[2] else 1)\n')
                check = shlex.join([host['python'], '-c', verifier, remote_archive, archive_digest])
                present = subprocess.run(['ssh', '-T', host['ssh'], check], timeout=180,
                                         capture_output=True).returncode == 0
                if not present:
                    upload = remote_archive + '.' + identifier + '.pending'
                    subprocess.run(['scp', str(archive), host['ssh'] + ':' + upload], check=True, timeout=1800)
                    check = shlex.join([host['python'], '-c', verifier, upload, archive_digest])
                    subprocess.run(['ssh', '-T', host['ssh'], check], check=True, timeout=180)
                    publish = shlex.join([host['python'], '-c', 'import os,sys; os.replace(sys.argv[1],sys.argv[2])', upload, remote_archive])
                    subprocess.run(['ssh', '-T', host['ssh'], publish], check=True, timeout=30)
                receipt['request'] = {'request_id': identifier, 'preset': 'checked',
                                      'archive': {'path': remote_archive, 'sha256': archive_digest},
                                      'expected_engine_sha256': host['engine_sha256'],
                                      'engine_path': host['engine'], 'options': options}
            # Persist the exact destination and request before any possible execution.
            receipt['state'] = 'SUBMISSION_UNCONFIRMED'
            write_json(receipt_path, receipt)
            try:
                accepted = rpc('submit', **receipt['request']) if host.get('local') else self.remote(host, 'run', receipt['request'])
                receipt['accepted'] = accepted
                receipt['state'] = 'SUBMITTED'
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                receipt['error'] = str(error)
                if host.get('local') and isinstance(error, ValueError):
                    receipt['state'] = 'NOT_DISPATCHED'
                    receipt['last_status'] = {'state': 'FINISHED', 'outcome': 'INFRA_FAILED',
                                              'cleanup': 'CONFIRMED', 'error': str(error)}
            write_json(receipt_path, receipt)
            return {'job': identifier, 'receipt': str(receipt_path), 'state': receipt['state'], 'decision': decision}
        finally:
            if guard is not None:
                guard.close()

    def recover(self, identifier):
        if not identifier.isalnum():
            raise ValueError('invalid job id')
        path = self.root / 'jobs' / (identifier + '.json')
        guard = acquire_lock(self.root / (identifier + '.lock'))
        try:
            receipt = json.loads(path.read_text())
            if 'request' not in receipt:
                receipt.update(state='NOT_DISPATCHED', last_status={'state': 'FINISHED', 'outcome': 'INFRA_FAILED',
                               'cleanup': 'CONFIRMED', 'error': 'Preparation ended before execution was submitted'})
                write_json(path, receipt)
                return {**receipt['last_status'], 'job': identifier, 'pool_host': receipt['host']}
            host = next(item for item in self.hosts if item['id'] == receipt['host'])
            try:
                result = rpc('submit', **receipt['request']) if host.get('local') else self.remote(host, 'run', receipt['request'])
            except (ValueError, FileNotFoundError) as error:
                if not host.get('local'):
                    raise
                receipt.update(state='NOT_DISPATCHED', last_status={'state': 'FINISHED', 'outcome': 'INFRA_FAILED',
                               'cleanup': 'CONFIRMED', 'error': str(error)})
                write_json(path, receipt)
                return {**receipt['last_status'], 'job': identifier, 'pool_host': host['id']}
            receipt.update(state='SUBMITTED', accepted=result)
            write_json(path, receipt)
            # Recovery already owns this job's non-reentrant lock.
            return self._status_locked(identifier)
        finally:
            guard.close()

    def status(self, identifier):
        if not identifier.isalnum():
            raise ValueError('invalid job id')
        guard = acquire_lock(self.root / (identifier + '.lock'))
        try:
            return self._status_locked(identifier)
        finally:
            guard.close()

    def _status_locked(self, identifier):
        """Observe and update a receipt while holding its per-job lock."""
        path = self.root / 'jobs' / (identifier + '.json')
        receipt = json.loads(path.read_text())
        if receipt.get('state') == 'NOT_DISPATCHED':
            return {**receipt['last_status'], 'job': identifier, 'pool_host': receipt['host']}
        if 'request' not in receipt:
            return {'job': identifier, 'host': receipt['host'], 'state': 'UNKNOWN',
                    'error': 'Preparation interrupted before durable dispatch request'}
        host = next(item for item in self.hosts if item['id'] == receipt['host'])
        try:
            if host.get('local'):
                request = receipt['request']
                recovered = rpc('recover', request_id=identifier, request_secret=request['request_secret'])
                result = rpc('status', job=recovered['job']) if recovered else {'state': 'SUBMISSION_UNCONFIRMED'}
            else:
                result = self.remote(host, 'status', {'request_id': identifier})
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            result = {'state': 'UNKNOWN', 'error': str(error)}
        receipt['last_status'] = result
        if result.get('state') in {'RUNNING', 'STARTING', 'FINISHED', 'ACCEPTED', 'QUEUED', 'DISPATCHING', 'CLEANING'}:
            receipt['state'] = 'SUBMITTED'
        write_json(path, receipt)
        return {**result, 'job': identifier, 'pool_host': host['id']}

    def collect(self, identifier, out_dir=None):
        status = self.status(identifier)
        if status.get('state') != 'FINISHED':
            raise ValueError('Collection requires a confirmed finished attempt')
        receipt = json.loads((self.root / 'jobs' / (identifier + '.json')).read_text())
        host = next(item for item in self.hosts if item['id'] == receipt['host'])
        destination = (Path(out_dir).resolve() if out_dir else self.root / 'results') / identifier
        destination.mkdir(parents=True, exist_ok=True)
        status_path = destination / 'pool-status.json'
        write_json(status_path, status)
        if host.get('local'):
            report = (status.get('runner_verdict') or {}).get('checked')
            if report:
                shutil.copyfile(report['log'], destination / 'engine.log')
        else:
            total = sum(item['size'] for item in status.get('artifacts', {}).values())
            if total > 128 * 1024 * 1024:
                raise ValueError('Artifact collection exceeds 128 MiB budget')
            for name, metadata in status.get('artifacts', {}).items():
                from tools.testqueue.snapshots import _relative
                _relative(name)
                if name.casefold() in {'pool-status.json', 'pool-infra-report.json'}:
                    raise ValueError('Remote artifact conflicts with saved pool evidence')
                target = destination / name
                target.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(['scp', host['ssh'] + ':' + status['output'] + '/' + name, str(target)],
                               check=True, timeout=120, capture_output=True)
                if target.stat().st_size != metadata['size'] or digest(target) != metadata['sha256']:
                    raise ValueError('Collected artifact digest mismatch: ' + name)
            report = status.get('checked')
            if report:
                remote_log = Path(report['log']).relative_to(status['output']).as_posix()
                shutil.copyfile(destination / remote_log, destination / 'engine.log')
        if not report:
            if status.get('outcome') != 'INFRA_FAILED':
                raise ValueError('Finished attempt has no checked report; infrastructure evidence retained')
            infrastructure_path = destination / 'pool-infra-report.json'
            infrastructure = {'pool_job': identifier, 'pool_host': host['id'],
                              'pool_outcome': 'INFRA_FAILED', 'pool_status': str(status_path),
                              'pool_report': str(infrastructure_path)}
            write_json(infrastructure_path, infrastructure)
            return infrastructure
        write_json(destination / 'original-report.json', report)
        if digest(destination / 'engine.log') != report['log_sha256']:
            raise ValueError('Checked log digest mismatch')
        local_report = {**report, 'log': str(destination / 'engine.log'),
                        'report': str(destination / 'report.json'), 'pool_host': host['id'],
                        'pool_job': identifier, 'pool_outcome': status['outcome']}
        write_json(destination / 'report.json', local_report)
        if status['outcome'] == 'PASSED':
            guard = Singleton(self.root / 'history.lock')
            try:
                history_path = self.root / 'history.json'
                history = json.loads(history_path.read_text()) if history_path.exists() else {}
                history.setdefault(host['id'], {})[receipt['options']['script']] = max(0.001, report['elapsed_seconds'])
                if 'import' in status:
                    history[host['id']]['_setup_seconds'] = max(0.001, status['import']['elapsed_seconds'])
                write_json(history_path, history)
            finally:
                guard.close()
        return local_report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default=default_config())
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('hosts')
    run = sub.add_parser('run')
    run.add_argument('--source', type=Path, default=REPO)
    run.add_argument('--script', action='append', required=True)
    run.add_argument('--platform', choices=['any', 'windows', 'darwin', 'linux'], default='any')
    run.add_argument('--require', action='append', default=[])
    run.add_argument('--timeout', type=float, default=90)
    run.add_argument('--wait-timeout', type=float, default=3600)
    snapshot = sub.add_parser('snapshot')
    snapshot.add_argument('--source', type=Path, default=REPO)
    submit = sub.add_parser('submit')
    submit.add_argument('--snapshot', required=True, type=Path)
    submit.add_argument('--script', required=True)
    submit.add_argument('--platform', choices=['any', 'windows', 'darwin', 'linux'], default='any')
    submit.add_argument('--host')
    submit.add_argument('--require', action='append', default=[])
    submit.add_argument('--timeout', type=float, default=90)
    for name in ('status', 'wait', 'collect', 'recover'):
        command = sub.add_parser(name)
        command.add_argument('job')
        if name == 'wait':
            command.add_argument('--timeout', type=float, default=600)
    args = parser.parse_args(argv)
    if not args.config:
        parser.error('--config or OPENRC_TESTPOOL_CONFIG is required')
    pool = Pool(args.config)
    if args.command == 'hosts':
        value = pool.probe()
    elif args.command == 'run':
        from tools.testqueue.pool_batch import run_batch
        snapshot_path = pool.snapshot(args.source)
        identifier = uuid.uuid4().hex
        manifest_path = pool.root / 'batches' / (identifier + '.json')
        state_path = pool.root / 'batches' / (identifier + '-state.json')
        write_json(manifest_path, {'snapshot': str(snapshot_path), 'jobs': [
            {'script': script, 'platform': args.platform, 'require': args.require, 'timeout': args.timeout}
            for script in args.script]})
        print('Batch manifest: ' + str(manifest_path), file=sys.stderr)
        print('Batch state: ' + str(state_path), file=sys.stderr)
        value = run_batch(pool, pool.config_path, manifest_path, state_path, timeout=args.wait_timeout)
    elif args.command == 'snapshot':
        value = {'snapshot': str(pool.snapshot(args.source))}
    elif args.command == 'submit':
        value = pool.submit(args.snapshot, args.script, platform=args.platform, require=args.require,
                            timeout=args.timeout, host_id=args.host)
    elif args.command == 'collect':
        value = pool.collect(args.job)
    elif args.command == 'recover':
        value = pool.recover(args.job)
    else:
        deadline = time.monotonic() + (args.timeout if args.command == 'wait' else 0)
        while True:
            value = pool.status(args.job)
            if value.get('state') in {'FINISHED', 'UNKNOWN', 'SUBMISSION_UNCONFIRMED', 'NOT_FOUND'} or time.monotonic() >= deadline:
                break
            time.sleep(2)
    print(json.dumps(value, indent=2))
    if args.command == 'submit' and value.get('state') == 'WAITING':
        return 3
    if args.command == 'wait':
        return 0 if value.get('outcome') == 'PASSED' else 1
    if args.command == 'run':
        return 0 if value.get('result') == 'PASSED' else 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
