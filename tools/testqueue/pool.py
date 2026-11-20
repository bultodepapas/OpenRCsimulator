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
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import Singleton, rpc, state_root, write_json, submission_receipt
from tools.testqueue import pool_history
from tools.testqueue.pool_policy import DISK_RESERVE_BYTES, plan
from tools.testqueue.presets import validate, scheduling
from tools.testqueue.snapshots import capture, read_verified_file, verify


IMPORT_CACHE_BYTES = 2 * 1024 ** 3


class PoolLockTimeout(RuntimeError):
    """The requested pool lock was not acquired; another caller may own it."""


class SubmissionDeferred(RuntimeError):
    """This call did not dispatch. Only retry its original identity, never fail over."""

    reason_code = 'SUBMISSION_DEFERRED'
    detail = None


class TransferDeferred(SubmissionDeferred):
    """The archive transfer failed before the remote ``run`` action; nothing was dispatched (TQ-05-F0.3)."""

    reason_code = 'TRANSFER_DEFERRED'

    def __init__(self, message, detail):
        super().__init__(message)
        self.detail = detail


class TransferFailure(RuntimeError):
    """One transfer step failed. No request had reached the remote agent."""

    def __init__(self, stage, code, message):
        super().__init__(message)
        self.stage, self.code = stage, code


class ArchiveTemporaryUnresolved(RuntimeError):
    """A failed build left an owned temporary requiring inspection before retry."""


class SubmissionRejected(ValueError):
    """This call failed preflight; it is not a claim about earlier execution."""

    def __init__(self, message, status):
        super().__init__(message)
        self.status = status


class RemoteRefusal(RuntimeError):
    def __init__(self, message, code):
        super().__init__(message)
        self.code = code


def request_digest(request):
    """Match the standalone remote agent's canonical request identity."""
    encoded = json.dumps(request, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False)
    return hashlib.sha256(encoded.encode('ascii')).hexdigest()


def default_config():
    return os.environ.get('OPENRC_TESTPOOL_CONFIG', str(Path(os.environ.get('PROGRAMDATA', '/var/tmp')) / 'OpenRC/testpool/config.json'))


SSH_CONNECT_TIMEOUT = 8


def ssh_options(connect_timeout=SSH_CONNECT_TIMEOUT):
    """Non-interactive, fail-fast options shared by every ssh and scp call (TQ-05-F0.3)."""
    return ['-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
            '-o', f'ConnectTimeout={int(connect_timeout)}',
            '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=4']


def ssh_command(host, command, connect_timeout=SSH_CONNECT_TIMEOUT):
    return ['ssh', '-T', *ssh_options(connect_timeout), host['ssh'], command]


def scp_command(host, source, destination, connect_timeout=SSH_CONNECT_TIMEOUT):
    return ['scp', *ssh_options(connect_timeout), str(source), host['ssh'] + ':' + destination]


def _describe(error):
    if isinstance(error, subprocess.TimeoutExpired):
        text = f'timed out after {error.timeout:g} s'
    elif isinstance(error, subprocess.CalledProcessError):
        text = f'exit status {error.returncode}'
    else:
        text = f'{type(error).__name__}: {error}'
    stderr = getattr(error, 'stderr', None)
    if isinstance(stderr, bytes):
        stderr = stderr.decode('utf-8', 'replace')
    stderr = (stderr or '').strip()
    return f'{text}: {stderr[-300:]}' if stderr else text


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
                raise PoolLockTimeout('Timed out waiting for pool transaction lock')
            time.sleep(0.1)


def _plain_file(info):
    return (stat.S_ISREG(info.st_mode)
            and not getattr(info, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400))


def _discard_owned_archive_temporary(path, identity):
    """Only an invocation's unpublished temporary is disposable, never a sweep."""
    try:
        current = path.lstat()
    except FileNotFoundError:
        return
    if not _plain_file(current) or (current.st_dev, current.st_ino) != identity:
        raise ArchiveTemporaryUnresolved(f'Archive temporary identity changed; retained for inspection: {path}')
    try:
        path.unlink()
    except OSError as error:
        raise ArchiveTemporaryUnresolved(f'Unpublished archive temporary could not be removed: {path}: {error}') from error


class Pool:
    def __init__(self, config):
        self.config_path = Path(config).resolve()
        config_bytes = self.config_path.read_bytes()
        self.config = json.loads(config_bytes)
        self.config_digest = hashlib.sha256(config_bytes).hexdigest()
        self.root = Path(self.config['state_root']).resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.hosts = self.config['hosts']
        ids = [host['id'] for host in self.hosts]
        if len(ids) != len(set(ids)):
            raise ValueError('duplicate host ids')

    def remote(self, host, action, payload):
        command = shlex.join([host['python'], host['agent'], action, '--root', host['root']])
        result = subprocess.run(ssh_command(host, command),
                                input=json.dumps(payload), capture_output=True, text=True, timeout=45, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        try:
            response = json.loads(result.stdout)
        except ValueError as error:
            raise RuntimeError(result.stderr.strip() or 'remote agent returned no valid response') from error
        if not isinstance(response, dict):
            raise RuntimeError('remote agent returned an invalid response')
        if result.returncode or response.get('ok') is not True:
            message = response.get('error', 'remote agent refused request')
            if (response.get('ok') is False and response.get('protocol') == 1
                    and payload.get('request_id') is not None
                    and response.get('request_id') == payload['request_id']
                    and isinstance(response.get('code'), str)):
                raise RemoteRefusal(message, response['code'])
            raise RuntimeError(message)
        return response['result']

    @staticmethod
    def _verify_remote_status(receipt, result):
        if (not isinstance(result, dict) or result.get('request_id') != receipt['request']['request_id']
                or result.get('payload_sha256') != request_digest(receipt['request'])):
            raise ValueError('remote status does not prove the original request and input identity')
        return result

    @staticmethod
    def _verify_local_status(receipt, result):
        if not isinstance(result, dict):
            raise ValueError('local authority returned an invalid status')
        payload = result.get('payload') or {}
        manifest = payload.get('manifest') if isinstance(payload, dict) else None
        if manifest is None:
            manifest = {}
        if not isinstance(manifest, dict):
            raise ValueError('local authority returned an invalid snapshot identity')
        expected_source = receipt.get('source_digest') or receipt['request'].get('expected_source_digest')
        expected_manifest = receipt['request'].get('expected_manifest_digest')
        if (expected_source and manifest.get('source_digest') != expected_source
                or expected_manifest and manifest.get('manifest_digest') != expected_manifest
                or not expected_source and result.get('state') == 'FINISHED'):
            raise ValueError('local status does not prove the original snapshot identity')
        return result

    @staticmethod
    def _verify_local_acceptance(result):
        if not isinstance(result, dict) or not isinstance(result.get('job'), str) or not result['job']:
            raise ValueError('local authority returned an invalid acceptance')
        return result

    def probe_host(self, host):
        try:
            if host.get('local'):
                import psutil
                current = rpc('hosts')
                storage = current.get('storage')
                storage = storage if isinstance(storage, dict) else {}
                free_disk = storage.get('free_bytes') if storage.get('available') is True else None
                if type(free_disk) is not int or free_disk < 0:
                    free_disk = None
                external = (current.get('occupancy') or {}).get('external_simulators') is True
                queued = current.get('queued')
                value = {'platform': current['platform'], 'online': True,
                         'busy': (bool(current['claims']) or current['condition'] != 'READY'
                                  or bool(current['reservation']) or external
                                  or type(queued) is int and queued > 0),
                         'free_disk_bytes': free_disk, 'storage': storage,
                         'free_memory_bytes': psutil.virtual_memory().available,
                         'cores': os.cpu_count(), 'load': psutil.cpu_percent(interval=0.1) * (os.cpu_count() or 1) / 100,
                         'capabilities': ['headless'], 'engine': current['engine']}
                if external:
                    value['busy_reason'] = 'an unmanaged simulator is running on this desktop'
                # Typed cause for agents (TQ-05-F1.1); first match wins.
                value['busy_code'] = next((code for code, active in (
                    ('CONDITION_' + str(current['condition']), current['condition'] != 'READY'),
                    ('HUMAN_RESERVATION', bool(current['reservation'])),
                    ('EXTERNAL_SIMULATOR', external),
                    ('RUNNING_QUEUE_WORK', bool(current['claims'])),
                    ('QUEUED_LOCAL_WORK', type(queued) is int and queued > 0)) if active), None)
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
                         'capabilities': remote['capabilities'], 'engine': remote['engine'],
                         'busy_code': ('QUARANTINED' if admission['quarantined'] else
                                       'RUNNING_POOL_JOB' if admission['busy'] else
                                       'ENROLLED_HOST' if admission['enrolled'] else None)}
            if not host.get('local') and value['engine'].get('sha256') != host.get('engine_sha256'):
                raise ValueError('Remote engine differs from the configured verified pin')
            value.update(id=host['id'], local=host.get('local', False))
            value.setdefault('online', True)
            value.setdefault('cached_inputs', [])
            value.setdefault('durations', {})
            value['transfer_bytes_per_second'] = host.get('transfer_bytes_per_second', 10 * 1024 * 1024)
            history = self.history()
            if history:
                durations, sources, setup = pool_history.host_view(history, host['id'], 0 if host.get('local') else 5)
                value.update(durations=durations, duration_sources=sources, setup_seconds=setup)
            return value
        except (OSError, ValueError, RuntimeError, ImportError, subprocess.SubprocessError) as error:
            return {'id': host['id'], 'online': False, 'reason': str(error)}

    def history(self):
        """Advisory duration history; unreadable history never takes a host offline."""
        try:
            value = json.loads((self.root / 'history.json').read_text(encoding='utf-8'))
        except (OSError, ValueError, RecursionError):
            return {}
        return value if isinstance(value, dict) else {}

    def expected_seconds(self, script):
        """Fleet-best median duration of one script, or None when never measured."""
        return pool_history.expected_seconds(self.history(), script)

    def probe(self):
        with ThreadPoolExecutor(max_workers=len(self.hosts) or 1) as executor:
            observations = list(executor.map(self.probe_host, self.hosts))
        return self._reserve(observations)

    CIRCUIT_FAILURES = 2
    CIRCUIT_RETRY_SECONDS = 600
    # Refusals caused by the host's state, not by the frozen source.
    _HOST_TRANSIENT = ('external godot', 'external simulator', 'insufficient disk', 'insufficient_disk',
                       'no space left', 'disk_unknown', 'quarantin', 'busy', 'gui_locked', 'desktop')

    @classmethod
    def _host_transient(cls, status):
        text = ' '.join(str(status.get(key) or '') for key in ('error', 'reason', 'detail')).lower()
        return any(token in text for token in cls._HOST_TRANSIENT)

    def _circuit(self, observations, source_digest):
        """Open a per-host, per-source circuit after consecutive INFRA_FAILED results.

        The newest ``CIRCUIT_FAILURES`` observed finished attempts of this source
        on a host must all be infrastructure failures (for example an import
        that cannot load a platform extension). A different source digest, or a
        later non-infrastructure result, closes it. Refusals caused by the host's
        own state (external Godot, disk, quarantine) are not counted, and after
        ``CIRCUIT_RETRY_SECONDS`` one new attempt may run (TQ-05-F0.4). Nothing
        is retried or moved by the circuit itself.
        """
        finished = {}
        for path in (self.root / 'jobs').glob('*.json'):
            try:
                receipt = json.loads(path.read_text(encoding='utf-8'))
                last = receipt.get('last_status') or {}
                if receipt.get('source_digest') != source_digest or last.get('state') != 'FINISHED':
                    continue
                if last.get('outcome') == 'INFRA_FAILED' and self._host_transient(last):
                    continue  # the host refused for its own reasons; says nothing about this source (TQ-05-F0.4)
                finished.setdefault(receipt['host'], []).append((float(receipt.get('created', 0)), last.get('outcome'), path.stem))
            except (OSError, ValueError, KeyError, TypeError, AttributeError):
                continue
        now = time.time()
        for observation in observations:
            recent = sorted(finished.get(observation['id'], []), reverse=True)[:self.CIRCUIT_FAILURES]
            if recent and now - recent[0][0] >= self.CIRCUIT_RETRY_SECONDS:
                continue  # half-open: one new attempt may run; another failure closes it again
            if len(recent) == self.CIRCUIT_FAILURES and all(outcome == 'INFRA_FAILED' for _, outcome, _ in recent):
                observation['busy'] = True
                observation['busy_code'] = 'CIRCUIT_OPEN'
                observation['busy_reason'] = (f'CIRCUIT_OPEN: last {self.CIRCUIT_FAILURES} attempts of this source ended '
                                              f'INFRA_FAILED ({", ".join(stem[:8] for _, _, stem in recent)}); inspect them')
        return observations

    def _reserve(self, observations, since=None):
        """Mark hosts held by local receipts busy; cheap, local and idempotent.

        ``since`` also reserves every host that received a receipt at or after
        that time: the network probe ran without the dispatch lock, so a
        dispatch that landed meanwhile is not visible in its observation. An
        unreadable receipt cannot free a host; it is reported and skipped.
        """
        reserved, unreadable = {}, []
        for path in (self.root / 'jobs').glob('*.json'):
            try:
                receipt = json.loads(path.read_text(encoding='utf-8'))
                host = receipt['host']
                if not isinstance(host, str):
                    raise ValueError('receipt host is not a string')
                created = receipt.get('created')
                holds = (receipt.get('state') in {'PREPARING', 'SUBMISSION_UNCONFIRMED'}
                         or self._unproved_nonexecution(receipt)
                         or since is not None and type(created) in (int, float) and created >= since)
            except (OSError, ValueError, KeyError, TypeError, AttributeError):
                unreadable.append(path.stem)
                continue
            if holds:
                reserved.setdefault(host, f"receipt {path.stem} ({receipt.get('state')})")
        for observation in observations:
            if observation['id'] in reserved:
                observation['busy'] = True
                observation['busy_reason'] = reserved[observation['id']]
                observation['busy_code'] = 'RESERVED_BY_RECEIPT'
            if unreadable:
                observation['unreadable_receipts'] = sorted(unreadable)[:10]
        return observations

    SNAPSHOT_ATTEMPTS = 4
    SNAPSHOT_BACKOFF_SECONDS = 2.0

    def snapshot(self, source):
        """Freeze ``source``; retry a capture that saw files change (TQ-05-F0.2).

        Several agents edit the shared checkout, so "changed during snapshot" is
        routine. Each retry uses a fresh destination. Only this call's own
        incomplete destination is removed; other failures keep theirs for
        inspection and are raised at once.
        """
        parent = self.root / 'snapshots'
        parent.mkdir(exist_ok=True)
        for attempt in range(1, self.SNAPSHOT_ATTEMPTS + 1):
            target = parent / uuid.uuid4().hex
            try:
                capture(Path(source).resolve(), target, include_imports=False)
                return target
            except ValueError as error:
                transient = 'changed during snapshot' in str(error) or 'disappeared during snapshot' in str(error)
                if not transient or attempt == self.SNAPSHOT_ATTEMPTS:
                    raise
                from tools.testqueue.local_gc import safe_remove_tree
                if target.exists():
                    safe_remove_tree(target)
                time.sleep(self.SNAPSHOT_BACKOFF_SECONDS * attempt)

    def _prepare_archive(self, snapshot, manifest):
        """Publish a verified archive; discard only this call's failed build."""
        archive = self.root / 'archives' / (manifest['source_digest'] + '.tar')
        archive.parent.mkdir(exist_ok=True)
        parent_info = archive.parent.lstat()
        if (not stat.S_ISDIR(parent_info.st_mode)
                or getattr(parent_info, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400)):
            raise ValueError('Archive directory must not be a link or reparse point')
        guard = acquire_lock(archive.with_suffix('.lock'))
        try:
            try:
                existing = archive.lstat()
            except FileNotFoundError:
                existing = None
            if existing is not None:
                if not _plain_file(existing):
                    raise ValueError('Cached archive must be a regular file, not a link or reparse point')
                return archive
            # This is an advisory check on the actual archive volume, not a
            # reservation against concurrent writes. Failure cleanup remains
            # necessary even when the volume initially has enough space.
            self._require_archive_space(manifest, archive.parent)
            descriptor, name = tempfile.mkstemp(prefix=archive.stem + '.', suffix='.pending', dir=archive.parent)
            temporary = Path(name)
            identity = None
            try:
                with os.fdopen(descriptor, 'wb') as stream:
                    info = os.fstat(stream.fileno())
                    identity = (info.st_dev, info.st_ino)
                    with tarfile.open(fileobj=stream, mode='w') as bundle:
                        for member in sorted(manifest['files']):
                            bundle.add(snapshot / 'source' / member, arcname=member, recursive=False)
                    stream.flush()
                    os.fsync(stream.fileno())
                verify_archive(temporary, manifest)
                current = temporary.lstat()
                if not _plain_file(current) or (current.st_dev, current.st_ino) != identity:
                    raise RuntimeError('Archive temporary changed before publication')
                temporary.replace(archive)
            finally:
                if identity is not None:
                    _discard_owned_archive_temporary(temporary, identity)
                else:
                    raise ArchiveTemporaryUnresolved(f'Archive temporary ownership could not be verified: {temporary}')
            return archive
        finally:
            guard.close()

    @staticmethod
    def _require_archive_space(manifest, directory):
        source_bytes = sum(item['size'] for item in manifest['files'].values())
        if shutil.disk_usage(directory).free < source_bytes + DISK_RESERVE_BYTES:
            raise OSError('INSUFFICIENT_SPACE for pool archive and reserve')

    @staticmethod
    def _unproved_nonexecution(receipt):
        # Older coordinators treated any local submit ValueError as proof that
        # nothing ran, even on a replay after an accepted reply was lost.
        return receipt.get('state') == 'NOT_DISPATCHED'

    def _read_receipt_locked(self, path):
        receipt = json.loads(path.read_text())
        if not isinstance(receipt, dict):
            raise ValueError('invalid pool receipt; preserve original evidence')
        if self._unproved_nonexecution(receipt):
            receipt.setdefault('invalidated_nonexecution', {
                'state': receipt['state'], 'status': receipt.get('last_status'),
                'error': receipt.get('error'), 'invalidated_at': time.time()})
            receipt.update(state='SUBMISSION_UNCONFIRMED', last_status={
                'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED',
                'error': 'Legacy nonexecution result requires original-authority observation'})
            write_json(path, receipt)
        return receipt

    def needs_reobservation(self, identifier, status):
        """Inspect only local receipts; never replay or contact an authority."""
        if not isinstance(identifier, str) or not identifier.isalnum():
            raise ValueError('invalid job id')
        path = self.root / 'jobs' / (identifier + '.json')
        try:
            receipt = json.loads(path.read_text())
        except (OSError, ValueError):
            return True  # Preserve cached evidence, but it cannot certify execution.
        if not isinstance(receipt, dict):
            return True
        return (self._unproved_nonexecution(receipt)
                or bool(receipt.get('invalidated_nonexecution'))
                and status.get('pool_recovery_version') != 1)

    @staticmethod
    def _public_status(receipt, identifier, status):
        result = {**status, 'job': identifier, 'pool_host': receipt['host']}
        if receipt.get('invalidated_nonexecution'):
            result['pool_recovery_version'] = 1
        return result

    @staticmethod
    def _deferred_status(receipt):
        """Queued, not blocked: the transfer failed before any dispatch and the same ID retries."""
        transfer = receipt.get('transfer') or {}
        return {'state': 'WAITING', 'reason_code': 'TRANSFER_DEFERRED', 'error': receipt.get('error'),
                'transfer_attempts': transfer.get('attempts'), 'dispatched': False}

    @staticmethod
    def _defer_transfer(receipt, path, error):
        previous = receipt.get('transfer')
        history = list(receipt.get('transfer_history') or [])
        if previous:
            history.append(previous)
        failure = {'attempts': (previous or {}).get('attempts', 0) + 1, 'stage': error.stage,
                   'code': error.code, 'error': str(error), 'at': time.time()}
        message = f"{error.code} at {error.stage} (attempt {failure['attempts']}): {error}"
        receipt.update(state='TRANSFER_DEFERRED', transfer=failure, transfer_history=history[-9:], error=message)
        write_json(path, receipt)
        raise TransferDeferred(message, failure) from error

    def _transfer_archive(self, host, archive, archive_digest, identifier):
        """Place the verified archive on the bound remote host.

        Nothing here calls the remote agent's ``run`` action, so every failure is
        proved nondispatched. A killed upload leaves at most an unpublished
        ``.pending`` file that the digest check rejects and a retry overwrites.
        """
        flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        remote_archive = host['root'] + '/incoming/' + archive_digest + '.tar'
        verifier = ('import hashlib, pathlib, sys\n'
                    'checksum = hashlib.sha256()\n'
                    'with pathlib.Path(sys.argv[1]).open("rb") as stream:\n'
                    '    for block in iter(lambda: stream.read(1048576), b""):\n'
                    '        checksum.update(block)\n'
                    'sys.exit(0 if checksum.hexdigest() == sys.argv[2] else 1)\n')
        stage = 'mkdir'

        def run(name, argv, timeout, check=True, capture=True):
            nonlocal stage
            stage = name
            # scp spawns ssh; capturing its pipes can block after a timeout kill on Windows.
            return subprocess.run(argv, check=check, timeout=timeout, capture_output=capture, creationflags=flags)

        try:
            run('mkdir', ssh_command(host, shlex.join(['mkdir', '-p', host['root'] + '/incoming'])), 30)
            check = shlex.join([host['python'], '-c', verifier, remote_archive, archive_digest])
            present = run('hash_check', ssh_command(host, check), 180, check=False).returncode == 0
            if not present:
                upload = remote_archive + '.' + identifier + '.pending'
                run('scp', scp_command(host, archive, upload), 1800, capture=False)
                check = shlex.join([host['python'], '-c', verifier, upload, archive_digest])
                run('verify', ssh_command(host, check), 180)
                publish = shlex.join([host['python'], '-c', 'import os,sys; os.replace(sys.argv[1],sys.argv[2])',
                                      upload, remote_archive])
                run('publish', ssh_command(host, publish), 30)
        except subprocess.TimeoutExpired as error:
            raise TransferFailure(stage, 'TRANSFER_TIMEOUT', _describe(error)) from error
        except (OSError, subprocess.SubprocessError) as error:
            raise TransferFailure(stage, 'TRANSFER_FAILED', _describe(error)) from error
        return remote_archive

    def _destination(self, receipt, *, replay=False):
        bound = receipt.get('config_sha256')
        if digest(self.config_path) != self.config_digest or bound and self.config_digest != bound:
            raise ValueError('pool configuration changed; restore the original destination before recovery')
        if replay and not bound:
            raise ValueError('legacy receipt has no destination binding; observation only, automatic replay refused')
        host = next((item for item in self.hosts if item['id'] == receipt['host']), None)
        if host is None:
            raise ValueError('original pool host is no longer configured; restore the original destination')
        root = Path(receipt['local_authority_root']) if receipt.get('local_authority_root') else None
        return host, ({'root': root} if root is not None else {})

    def submit(self, snapshot, script, *, platform='any', require=(), timeout=90, host_id=None,
               request_id=None, settings=None, expected_manifest_sha256=None):
        identifier = request_id or uuid.uuid4().hex
        if not identifier.isalnum() or len(identifier) > 64:
            raise ValueError('invalid request id')
        try:
            guard = acquire_lock(self.root / (identifier + '.lock'))
        except PoolLockTimeout as error:
            raise SubmissionDeferred(str(error)) from error
        try:
            return self._submit(snapshot, script, platform=platform, require=require, timeout=timeout,
                                host_id=host_id, request_id=identifier, settings=settings,
                                expected_manifest_sha256=expected_manifest_sha256)
        finally:
            guard.close()

    @staticmethod
    def _submission_result(receipt, path):
        result = {'job': receipt['request_id'], 'receipt': str(path), 'state': receipt['state'],
                  'decision': receipt['decision']}
        return result

    def _preflight(self, snapshot, script, platform, require, timeout, host_id, settings, expected_manifest_sha256):
        if platform not in {'any', 'windows', 'darwin', 'linux'}:
            raise ValueError('invalid job platform')
        if host_id is not None and host_id not in {host['id'] for host in self.hosts}:
            raise ValueError('unknown configured host: ' + str(host_id))
        options = validate('checked', {'script': script, 'require': list(require), 'timeout': timeout,
                           'headless': True, 'workload': 'auto', 'settings': settings or {}})
        if scheduling('checked', options)['workload'] == 'performance':
            raise ValueError('Performance checks require a dedicated same-host campaign through the existing queue')
        if expected_manifest_sha256 is not None and digest(snapshot / 'manifest.json') != expected_manifest_sha256:
            raise ValueError('snapshot manifest changed')
        validation = verify(snapshot, include_manifest=True)
        if not validation.get('ok'):
            if validation.get('failure_kind') == 'IO':
                raise SubmissionDeferred(f'snapshot is temporarily unreadable: {validation}')
            raise ValueError(f'invalid snapshot: {validation}')
        if expected_manifest_sha256 is not None and validation['manifest_sha256'] != expected_manifest_sha256:
            raise ValueError('snapshot manifest changed during verification')
        manifest = validation['manifest']
        if 'app/get-godot.sh' in manifest['files']:
            import re
            pin = read_verified_file(snapshot, manifest, 'app/get-godot.sh').decode('utf-8')
            match = re.search(r'^ENGINE_VERSION=(\S+)', pin, re.MULTILINE)
            if not match or match[1] != self.config.get('engine_version'):
                raise ValueError('Frozen candidate engine pin differs from configured pool engine')
        # A checked attempt also writes Godot's import cache (.godot) inside its
        # workspace; 17 November: 403 MB and growing when a 2.5 GB-free Mac ran
        # out of space mid-import. Reserve it instead of discovering it.
        job = {'platform': platform, 'workload': 'headless',
               'source_bytes': sum(item['size'] for item in manifest['files'].values()),
               'cache_id': manifest['source_digest'], 'duration_key': script, 'estimated_seconds': timeout,
               'memory_bytes': 512 * 1024 * 1024, 'disk_bytes': IMPORT_CACHE_BYTES}
        return manifest, options, job

    def _submit(self, snapshot, script, *, platform, require, timeout, host_id, request_id, settings,
                expected_manifest_sha256=None):
        snapshot = Path(snapshot).resolve()
        identifier = request_id or uuid.uuid4().hex
        if not identifier.isalnum() or len(identifier) > 64:
            raise ValueError('invalid request id')
        inputs = {'snapshot': str(snapshot), 'script': script, 'platform': platform,
                  'require': list(require), 'timeout': timeout, 'host': host_id, 'settings': settings or {}}
        if expected_manifest_sha256 is not None:
            inputs['snapshot_manifest_sha256'] = expected_manifest_sha256
        receipt_path = self.root / 'jobs' / (identifier + '.json')
        resume = None
        if receipt_path.exists():
            receipt = self._read_receipt_locked(receipt_path)
            if receipt.get('inputs') != inputs:
                raise ValueError('request id already has different inputs')
            deferred = receipt.get('state') == 'TRANSFER_DEFERRED'
            self._destination(receipt, replay=deferred)
            if not deferred:
                return self._submission_result(receipt, receipt_path)
            resume = receipt  # proved nondispatched: re-enter the transfer on the bound host below
        try:
            manifest, options, job = self._preflight(snapshot, script, platform, require, timeout,
                                                    host_id, settings, expected_manifest_sha256)
            if resume is not None and resume.get('source_digest') != manifest['source_digest']:
                raise ValueError('snapshot differs from the one whose transfer was deferred')
        except OSError as error:
            raise SubmissionDeferred(f'preflight I/O unavailable: {error}') from error
        except (ValueError, KeyError, TypeError) as error:
            # Reject this invocation, without asserting global nonexecution or
            # fabricating cleanup. A lost earlier receipt is not proof that its
            # ID never ran. Only a fresh batch's known call history can finalize
            # its own invalid-input row from this returned preflight refusal.
            status = {'state': 'REJECTED', 'reason_code': 'INVALID_INPUT', 'error': str(error)}
            raise SubmissionRejected(str(error), status) from error
        guard = None
        archive = None
        archive_digest = None
        bound_host = resume['host'] if resume is not None else host_id
        try:
            while True:
                # SSH probes and remote engine hashing run before the global
                # dispatch lock; only local receipt reservation and planning
                # happen under it (plan section 7.6).
                probed_at = time.time()
                observations = self.probe()
                try:
                    guard = acquire_lock(self.root / 'dispatch.lock')
                except PoolLockTimeout as error:
                    raise SubmissionDeferred(str(error)) from error
                if receipt_path.exists():
                    receipt = self._read_receipt_locked(receipt_path)
                    if receipt.get('inputs') != inputs:
                        raise ValueError('request id already has different inputs')
                    deferred = resume is not None and receipt.get('state') == 'TRANSFER_DEFERRED'
                    self._destination(receipt, replay=deferred)
                    if not deferred:
                        return self._submission_result(receipt, receipt_path)
                    resume = receipt
                observations = self._reserve(observations, since=probed_at)
                if bound_host:
                    observations = [item for item in observations if item['id'] == bound_host]
                else:
                    # Unpinned work avoids a host where this exact source keeps
                    # failing infrastructure; pinned work keeps its explicit host.
                    observations = self._circuit(observations, manifest['source_digest'])
                decision = plan(job, observations)
                if decision['selected'] is None:
                    return {'state': 'WAITING', 'decision': decision}
                host = next(item for item in self.hosts if item['id'] == decision['selected'])
                if not host.get('local') and archive is None:
                    # Building inputs does not reserve an execution host. Other
                    # jobs may dispatch while this call holds only its request
                    # and archive locks; reselect under the dispatch lock after
                    # preparation, before publishing the destination receipt.
                    guard.close()
                    guard = None
                    try:
                        archive = self._prepare_archive(snapshot, manifest)
                        verify_archive(archive, manifest)
                        archive_digest = digest(archive)
                    except (OSError, PoolLockTimeout) as error:
                        # This invocation has not written a dispatch receipt or
                        # called an execution authority. The typed deferral is
                        # not evidence about a different historical submission.
                        raise SubmissionDeferred(f'Coordinator archive preparation unavailable: {error}') from error
                    except (ValueError, tarfile.TarError) as error:
                        raise RuntimeError(f'Archive requires inspection before retry: {error}') from error
                    continue
                break
            if resume is not None:
                receipt = resume
                receipt.pop('error', None)
                receipt.update(state='PREPARING', decision=decision)
            else:
                receipt = {'request_id': identifier, 'host': host['id'], 'snapshot': str(snapshot),
                           'inputs': inputs,
                           'source_digest': manifest['source_digest'], 'options': options,
                           'decision': decision, 'state': 'PREPARING', 'created': time.time(),
                           'config_sha256': self.config_digest}
                if host.get('local'):
                    receipt['local_authority_root'] = str(state_root().resolve())
            write_json(receipt_path, receipt)
            guard.close()
            guard = None
            if host.get('local'):
                import secrets
                request = {'request_id': identifier, 'request_secret': secrets.token_hex(32),
                           'preset': 'checked', 'snapshot': str(snapshot), 'source': manifest['source_root'],
                           'owner': 'automatic-pool', 'platform': 'windows', 'options': options,
                           'expected_source_digest': manifest['source_digest']}
                if manifest.get('manifest_digest') is not None:
                    request['expected_manifest_digest'] = manifest['manifest_digest']
                submission_receipt(self.root, request)
                receipt['request'] = request
            else:
                try:
                    remote_archive = self._transfer_archive(host, archive, archive_digest, identifier)
                except TransferFailure as error:
                    self._defer_transfer(receipt, receipt_path, error)  # always raises TransferDeferred
                receipt['request'] = {'request_id': identifier, 'preset': 'checked',
                                      'archive': {'path': remote_archive, 'sha256': archive_digest},
                                      'expected_engine_sha256': host['engine_sha256'],
                                      'engine_path': host['engine'], 'options': options}
            # Persist the exact destination and request before any possible execution.
            receipt['state'] = 'SUBMISSION_UNCONFIRMED'
            write_json(receipt_path, receipt)
            try:
                host, local = self._destination(receipt, replay=True)
                accepted = rpc('submit', **local, **receipt['request']) if host.get('local') else self.remote(host, 'run', receipt['request'])
                if not host.get('local'):
                    self._verify_remote_status(receipt, accepted)
                else:
                    self._verify_local_acceptance(accepted)
                receipt['accepted'] = accepted
                receipt['state'] = 'SUBMITTED'
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                receipt['error'] = str(error)
                # The transport's exception type cannot establish nonacceptance.
                # In particular a replay may fail validation after the original
                # request was accepted. Keep its identity and original host.
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
            receipt = self._read_receipt_locked(path)
            if receipt.get('state') == 'TRANSFER_DEFERRED':
                # Nondispatched; only a repeated submit (it needs the snapshot) can resume the transfer.
                return self._public_status(receipt, identifier, self._deferred_status(receipt))
            if 'request' not in receipt:
                receipt.update(state='SUBMISSION_UNCONFIRMED', last_status={'state': 'UNKNOWN',
                               'cleanup': 'UNCONFIRMED', 'error': 'Dispatch metadata is unavailable; preserve the original receipt and authority'})
                write_json(path, receipt)
                return self._public_status(receipt, identifier, receipt['last_status'])
            try:
                host, local = self._destination(receipt)
                if host.get('local'):
                    request = receipt['request']
                    result = rpc('recover', **local, request_id=identifier, request_secret=request['request_secret'])
                    if result is None:
                        # None is an observation, not a fence: the original
                        # submit may still be delayed. Only replay the SAME ID.
                        self._destination(receipt, replay=True)
                        result = rpc('submit', **local, **request)
                    self._verify_local_acceptance(result)
                else:
                    try:
                        result = self.remote(host, 'status', {'request_id': identifier})
                    except RemoteRefusal as error:
                        if error.code != 'NOT_FOUND':
                            raise
                        self._destination(receipt, replay=True)
                        result = self.remote(host, 'run', receipt['request'])
                    self._verify_remote_status(receipt, result)
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                receipt.update(state='SUBMISSION_UNCONFIRMED', error=str(error),
                               last_status={'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED', 'error': str(error)})
                write_json(path, receipt)
                return self._public_status(receipt, identifier, receipt['last_status'])
            receipt.update(state='SUBMITTED', accepted=result)
            write_json(path, receipt)
            # Recovery already owns this job's non-reentrant lock.
            return self._status_locked(identifier)
        finally:
            guard.close()

    _RECONCILABLE = {'NOT_DISPATCHED', 'SUBMISSION_UNCONFIRMED', 'PREPARING'}
    _RECONCILED = {'CANCELED_BEFORE_DISPATCH', 'OPERATOR_RECONCILED_ABSENT'}

    def reconcile(self, identifier, *, operator_confirm=False):
        """Release a host held by a receipt that never reached execution.

        Local receipts are fenced by the authority's durable submission tombstone:
        if the canceled request was never accepted, it can never run. Remote
        authorities have no tombstone, so absence of the request there releases
        the host only with an explicit operator confirmation. An accepted or
        observed request is never released here; use status/recover instead.
        """
        if not identifier.isalnum():
            raise ValueError('invalid job id')
        path = self.root / 'jobs' / (identifier + '.json')
        guard = acquire_lock(self.root / (identifier + '.lock'))
        try:
            receipt = self._read_receipt_locked(path)
            if receipt.get('state') in self._RECONCILED:
                return self._public_status(receipt, identifier, receipt['last_status'])
            if receipt.get('state') not in self._RECONCILABLE:
                raise ValueError(f"receipt state {receipt.get('state')} is not reconcilable; use status or recover")
            host, local = self._destination(receipt)
            evidence = {'reconciled_at': time.time(), 'previous_state': receipt.get('state')}
            if host.get('local'):
                request = receipt.get('request')
                if not isinstance(request, dict) or not request.get('request_secret'):
                    raise ValueError('local receipt has no request credential; nothing can fence it')
                fenced = rpc('cancel_submission', **local, request_id=identifier, request_secret=request['request_secret'])
                if fenced.get('job'):
                    raise ValueError(f"the local authority accepted this request as job {fenced['job']}; "
                                     'it was canceled through the normal path, observe it with status')
                receipt.update(state='CANCELED_BEFORE_DISPATCH', reconciliation={**evidence, 'proof': 'local submission tombstone'},
                               last_status={'state': 'FINISHED', 'outcome': 'NOT_DISPATCHED', 'cleanup': 'CONFIRMED',
                                            'evidence': 'INCOMPLETE', 'proof': 'durable local submission tombstone'})
            else:
                try:
                    observed = self.remote(host, 'status', {'request_id': identifier})
                except RemoteRefusal as error:
                    absent = error.code == 'NOT_FOUND'
                except RuntimeError as error:
                    absent = str(error).strip() == 'request not found'  # pre-protocol agents
                else:
                    raise ValueError(f"remote authority knows this request ({observed.get('state')}); use status/recover")
                if not absent:
                    raise ValueError('remote absence was not observed; nothing changed')
                if not operator_confirm:
                    raise ValueError('remote authority has no record of this request; a remote run has no tombstone, '
                                     'so release requires --operator-confirm after checking no dispatch is in flight')
                receipt.update(state='OPERATOR_RECONCILED_ABSENT',
                               reconciliation={**evidence, 'proof': 'remote NOT_FOUND + operator confirmation'},
                               last_status={'state': 'FINISHED', 'outcome': 'NOT_DISPATCHED', 'cleanup': 'UNCONFIRMED',
                                            'evidence': 'INCOMPLETE', 'proof': 'operator-confirmed remote absence'})
            write_json(path, receipt)
            return self._public_status(receipt, identifier, receipt['last_status'])
        finally:
            guard.close()

    def _remote_host(self, host_id):
        host = next((item for item in self.hosts if item['id'] == host_id), None)
        if host is None or host.get('local'):
            raise ValueError('expected a configured remote host id')
        return host

    def remote_reconcile(self, host_id, request_id):
        """Operator release of a remote UNKNOWN job; the remote agent checks the proof."""
        if not request_id.isalnum():
            raise ValueError('invalid job id')
        return self.remote(self._remote_host(host_id), 'reconcile',
                           {'request_id': request_id, 'operator_confirm': True})

    def gc(self, host_id, *, execute=False):
        """Reclaim a remote host's copies of PASSED jobs whose evidence is collected here.

        Without ``execute`` this only lists candidates. With it, each job is first
        collected (or its existing collection re-verified) on this coordinator;
        only then does the remote agent remove that job's extracted source and
        archive copies. Failed, incomplete and UNKNOWN jobs are never candidates.
        """
        host = self._remote_host(host_id)
        candidates = []
        for path in sorted((self.root / 'jobs').glob('*.json')):
            try:
                receipt = json.loads(path.read_text(encoding='utf-8'))
            except (OSError, ValueError):
                continue
            last = receipt.get('last_status') if isinstance(receipt, dict) else None
            if (not isinstance(last, dict) or receipt.get('host') != host_id or not isinstance(receipt.get('request'), dict)
                    or (last.get('state'), last.get('outcome'), last.get('evidence'), last.get('cleanup'))
                    != ('FINISHED', 'PASSED', 'COMPLETE', 'CONFIRMED')
                    or (last.get('storage_gc') or {}).get('state') == 'RECLAIMED'):
                continue
            candidates.append((path.stem, receipt))
        report = {'host': host_id, 'candidates': len(candidates), 'execute': execute}
        if not execute:
            report['request_ids'] = [identifier for identifier, _ in candidates]
            return report
        reclaimed, skipped, total = [], [], 0
        for identifier, receipt in candidates:
            try:
                collected = self.collect(identifier)
                if collected.get('pool_outcome') != 'PASSED' or collected.get('diagnostic_only') is not False:
                    raise ValueError('collected evidence is not a complete pass')
                result = self.remote(host, 'gc', {'request_id': identifier, 'operator_confirm': True,
                                                  'payload_sha256': request_digest(receipt['request'])})
                total += result.get('logical_bytes_removed', 0)
                reclaimed.append(identifier)
            except Exception as error:  # one job's refusal never stops the sweep
                skipped.append({'request_id': identifier, 'error': str(error)[:300]})
        try:
            incoming = self.remote(host, 'gc-incoming', {'operator_confirm': True})
        except Exception as error:
            incoming = {'error': str(error)[:300]}
        report.update(reclaimed=len(reclaimed), skipped=skipped, logical_bytes_removed=total, incoming=incoming)
        return report

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
        receipt = self._read_receipt_locked(path)
        if receipt.get('state') in self._RECONCILED:
            return self._public_status(receipt, identifier, receipt['last_status'])
        if receipt.get('state') == 'TRANSFER_DEFERRED':
            return self._public_status(receipt, identifier, self._deferred_status(receipt))
        if 'request' not in receipt:
            return self._public_status(receipt, identifier, {'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED',
                    'error': 'Preparation interrupted before durable dispatch request'})
        try:
            host, local = self._destination(receipt)
            if host.get('local'):
                request = receipt['request']
                recovered = rpc('recover', **local, request_id=identifier, request_secret=request['request_secret'])
                if recovered is not None:
                    self._verify_local_acceptance(recovered)
                result = (self._verify_local_status(receipt, rpc('status', **local, job=recovered['job']))
                          if recovered else {'state': 'SUBMISSION_UNCONFIRMED'})
            else:
                result = self._verify_remote_status(receipt, self.remote(host, 'status', {'request_id': identifier}))
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            result = {'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED', 'error': str(error)}
        receipt['last_status'] = result
        if result.get('state') in {'RUNNING', 'STARTING', 'FINISHED', 'ACCEPTED', 'QUEUED', 'DISPATCHING', 'CLEANING'}:
            receipt['state'] = 'SUBMITTED'
        elif result.get('state') in {'UNKNOWN', 'SUBMISSION_UNCONFIRMED', 'NOT_FOUND'}:
            receipt['state'] = 'SUBMISSION_UNCONFIRMED'
        write_json(path, receipt)
        return self._public_status(receipt, identifier, result)

    def collect(self, identifier, out_dir=None):
        from tools.testqueue.collection import collect
        return collect(self, identifier, out_dir=out_dir)

    def verify_collection(self, identifier, result):
        from tools.testqueue.collection import verify_collection
        return verify_collection(self, identifier, result)


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
    gc = sub.add_parser('gc', help='reclaim remote copies of collected PASSED jobs (dry run unless --execute)')
    gc.add_argument('--host', required=True)
    gc.add_argument('--execute', action='store_true')
    remote_reconcile = sub.add_parser('remote-reconcile', help='operator release of a remote UNKNOWN job with proof')
    remote_reconcile.add_argument('--host', required=True)
    remote_reconcile.add_argument('job')
    for name in ('status', 'wait', 'collect', 'recover', 'reconcile'):
        command = sub.add_parser(name)
        command.add_argument('job')
        if name == 'wait':
            command.add_argument('--timeout', type=float, default=600)
        if name == 'collect':
            command.add_argument('--out', type=Path)
        if name == 'reconcile':
            command.add_argument('--operator-confirm', action='store_true',
                                 help='release a remote receipt whose request the remote authority does not know')
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
        value = pool.collect(args.job, out_dir=args.out)
    elif args.command == 'recover':
        value = pool.recover(args.job)
    elif args.command == 'reconcile':
        value = pool.reconcile(args.job, operator_confirm=args.operator_confirm)
    elif args.command == 'gc':
        value = pool.gc(args.host, execute=args.execute)
    elif args.command == 'remote-reconcile':
        value = pool.remote_reconcile(args.host, args.job)
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
