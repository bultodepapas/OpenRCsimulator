"""Automatic placement of source-bound checked tests across local and SSH hosts."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import itertools
import json
import math
import os
import re
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import uuid

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import Singleton, rpc, state_root, write_json, submission_receipt
from tools.testqueue import pool_history
from tools.testqueue.pool_policy import DISK_RESERVE_BYTES, plan, platform_set
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


RUNTIME_FILES = ('remote_agent.py', 'processes.py', 'common.py')


def runtime_files(directory=None):
    """The agent runtime this coordinator runs, as LF bytes (what Git stores) (TQ-07-B4)."""
    directory = Path(directory) if directory else Path(__file__).resolve().parent
    return {name: (directory / name).read_bytes().replace(b'\r\n', b'\n') for name in RUNTIME_FILES}


def runtime_digest(files):
    """The same combined digest the agent reports for its own files."""
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}
    encoded = json.dumps(hashes, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False)
    return hashlib.sha256(encoded.encode('ascii')).hexdigest()


def outcome_is_failure(receipt):
    return ((receipt or {}).get('last_status') or {}).get('outcome') != 'PASSED'


def destination_of(host, identity=None):
    """The part of a host's configuration that decides where a request runs (TQ-07-A1).

    A receipt binds this instead of the whole configuration file, so adding a
    host or tuning another host's settings no longer orphans work in flight.
    The SSH alias may change only when the remote store's reported identity is
    bound; the remote root never may.
    """
    if host.get('local'):
        return {'host': host['id'], 'local': True}
    value = {'host': host['id'], 'local': False, 'root': host.get('root'), 'ssh': host.get('ssh')}
    if isinstance(identity, dict) and isinstance(identity.get('store_id'), str):
        value['identity'] = {'machine_id': identity.get('machine_id'), 'store_id': identity['store_id']}
    return value


def identity_matches(bound, observed):
    """Same job store, and the same machine whenever the binding knows it.

    A bound machine identity must be reported again: a clone that copied the
    store's random ``store_id`` but cannot name the machine is not accepted.
    """
    if not isinstance(bound, dict) or not isinstance(observed, dict):
        return False
    if not bound.get('store_id') or bound.get('store_id') != observed.get('store_id'):
        return False
    machine = bound.get('machine_id')
    return machine is None or machine == observed.get('machine_id')


class _ConfigSnapshot:
    """One immutable, validated reading of the configuration file."""

    __slots__ = ('config', 'hosts', 'data', 'digest')

    def __init__(self, data):
        config = json.loads(data)
        if not isinstance(config, dict) or not isinstance(config.get('hosts'), list):
            raise ValueError('configuration needs a hosts list')
        hosts = config['hosts']
        ids = [host['id'] for host in hosts]
        if len(ids) != len(set(ids)):
            raise ValueError('duplicate host ids')
        Path(config['state_root'])  # required
        self.config, self.hosts, self.data = config, hosts, data
        self.digest = hashlib.sha256(data).hexdigest()


class Pool:
    def __init__(self, config):
        self.config_path = Path(config).resolve()
        self._snapshot = _ConfigSnapshot(self.config_path.read_bytes())
        self._config_lock = threading.Lock()
        self.root = Path(self.config['state_root']).resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self._retain_config(self._snapshot)

    # Each attribute reads the current snapshot. A caller that needs two of them
    # to agree reads ``self._snapshot`` once (batch lanes run in threads).
    config = property(lambda self: self._snapshot.config)
    hosts = property(lambda self: self._snapshot.hosts)
    config_bytes = property(lambda self: self._snapshot.data)
    config_digest = property(lambda self: self._snapshot.digest)

    def _retain_config(self, snapshot):
        """Keep every configuration this pool has used, by digest, so an older
        receipt's destination can still be resolved after the file is edited."""
        try:
            history = self.root / 'config-history'
            history.mkdir(exist_ok=True)
            path = history / (snapshot.digest + '.json')
            if not path.exists():
                temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.pending')
                temporary.write_bytes(snapshot.data)
                temporary.replace(path)
        except OSError:
            pass  # advisory: resolution falls back to the backups beside the file

    def refresh_config(self):
        """Follow edits to the configuration file; a long-lived supervisor sees new hosts.

        The new reading is fully validated before it replaces the old one in a
        single assignment, so no thread ever sees a half-applied or rejected
        edit. An unreadable or invalid edit keeps the previous configuration
        and raises.
        """
        try:
            current = self.config_path.read_bytes()
        except OSError as error:
            raise ValueError(f'pool configuration is unreadable: {error}') from error
        if hashlib.sha256(current).hexdigest() == self._snapshot.digest:
            return False
        with self._config_lock:
            if hashlib.sha256(current).hexdigest() == self._snapshot.digest:
                return False
            try:
                snapshot = _ConfigSnapshot(current)
                if Path(snapshot.config['state_root']).resolve() != self.root:
                    raise ValueError('state_root cannot change under a running pool')
            except (ValueError, KeyError, TypeError) as error:
                raise ValueError(f'pool configuration edit is invalid; keeping the previous one: {error}') from error
            self._snapshot = snapshot
        self._retain_config(snapshot)
        return True

    def _retained_configs(self):
        """Digest -> bytes of every configuration that can still be read."""
        found = {}
        candidates = list((self.root / 'config-history').glob('*.json'))
        candidates += [path for path in self.config_path.parent.glob(self.config_path.name + '*') if path.is_file()]
        for path in candidates:
            try:
                data = path.read_bytes()
            except OSError:
                continue
            found.setdefault(hashlib.sha256(data).hexdigest(), data)
        return found

    def _bound_destination(self, receipt):
        """(destination, source): what the receipt was dispatched to, when known."""
        bound = receipt.get('destination')
        if isinstance(bound, dict):
            return bound, 'receipt'
        digest_bound = receipt.get('config_sha256')
        if not digest_bound:
            return None, 'unbound'
        snapshot = self._snapshot
        if digest_bound == snapshot.digest:
            data = snapshot.data
        else:
            data = self._retained_configs().get(digest_bound)
            if data is None:
                return None, 'unresolved'
        try:
            hosts = json.loads(data)['hosts']
            old = next(item for item in hosts if item['id'] == receipt['host'])
        except (ValueError, KeyError, TypeError, StopIteration):
            return None, 'unresolved'
        return destination_of(old), 'retained-config'

    @staticmethod
    def _compare_destination(bound, host):
        """Raise naming the first field that moved the request to a different place."""
        current = destination_of(host)
        if bool(bound.get('local')) != current['local']:
            field = 'local'
        elif current['local']:
            return
        elif bound.get('root') != current['root']:
            field = 'root'
        elif bound.get('ssh') != current['ssh'] and not isinstance(bound.get('identity'), dict):
            field = 'ssh'
        else:
            return
        raise ValueError(f"pool configuration changed for host {host['id']}: {field} differs from the "
                         'bound destination; restore it before recovery')

    def remote(self, host, action, payload, timeout=45):
        command = shlex.join([host['python'], host['agent'], action, '--root', host['root']])
        result = subprocess.run(ssh_command(host, command),
                                input=json.dumps(payload), capture_output=True, text=True, timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
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
                    value['busy_reason'] = 'an unmanaged simulator is running on this desktop (EXTERNAL_SIMULATOR)'
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
                busy_code = 'RUNNING_POOL_JOB'
                if admission.get('busy_code') in {'EXTERNAL_SIMULATOR', 'OCCUPANCY_UNKNOWN'}:
                    busy_code = admission['busy_code']
                value = {'platform': remote['host']['system'].lower(),
                         'online': remote['engine']['available'],
                         'busy': admission['busy'] or admission['quarantined'] or admission['enrolled'],
                         'free_disk_bytes': capacity['free_bytes'],
                         'free_memory_bytes': capacity['free_memory_bytes'],
                         'cores': capacity['cpu_count'], 'load': load[0] if isinstance(load, list) else (load or 0),
                         'capabilities': remote['capabilities'], 'engine': remote['engine'],
                         # Older agents report no identity; their receipts bind root and SSH alias only.
                         'identity': remote.get('identity') if isinstance(remote.get('identity'), dict) else None,
                         'features': [item for item in remote.get('features') or [] if isinstance(item, str)],
                         'description': remote.get('description') if isinstance(remote.get('description'), dict) else None,
                         'busy_code': ('QUARANTINED' if admission['quarantined'] else
                                       busy_code if admission['busy'] else
                                       'ENROLLED_HOST' if admission['enrolled'] else None)}
                if value['busy_code'] in {'EXTERNAL_SIMULATOR', 'OCCUPANCY_UNKNOWN'}:
                    value['busy_reason'] = f"{busy_code}: " + str(admission.get('busy_reason') or busy_code)[:200]
            if not host.get('local') and value['engine'].get('sha256') != host.get('engine_sha256'):
                raise ValueError('Remote engine differs from the configured verified pin')
            value.update(id=host['id'], local=host.get('local', False))
            value.setdefault('online', True)
            if not host.get('local'):
                description = value.get('description') or {}
                # TQ-07-B1: an archive the host already holds costs no transfer.
                incoming = set((description.get('caches') or {}).get('incoming_archives') or [])
                value['cached_inputs'] = sorted(source for source, archive in self._archive_digests().items()
                                                if archive in incoming)
                # TQ-07-B4: a host running another agent build is visible as drift.
                reported = (description.get('runtime') or {}).get('digest')
                value['runtime'] = ('current' if reported and reported == self.expected_runtime()
                                    else 'behind' if reported else 'unknown')
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

    _expected_runtime = None

    def expected_runtime(self):
        """Digest of the agent runtime this coordinator would deploy; None if unreadable."""
        if self._expected_runtime is None:
            try:
                self._expected_runtime = runtime_digest(runtime_files())
            except OSError:
                return None
        return self._expected_runtime

    def _archive_digests(self):
        """Source digest -> archive SHA-256, from sidecars written when archives were prepared."""
        found = {}
        for path in (self.root / 'archives').glob('*.tar.sha256'):
            try:
                value = path.read_text(encoding='ascii').strip()
            except OSError:
                continue
            if re.fullmatch(r'[0-9a-f]{64}', value):
                found[path.name[:-len('.tar.sha256')]] = value
        return found

    def _remember_archive_digest(self, source_digest, archive_digest):
        try:
            path = self.root / 'archives' / (source_digest + '.tar.sha256')
            if not path.exists():
                path.write_text(archive_digest + '\n', encoding='ascii')
        except OSError:
            pass  # advisory: only the transfer estimate depends on it

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

    def probe(self, host_id=None):
        if host_id is not None:
            host = next(host for host in self.hosts if host['id'] == host_id)
            return self._reserve([self.probe_host(host)])
        with ThreadPoolExecutor(max_workers=len(self.hosts) or 1) as executor:
            observations = list(executor.map(self.probe_host, self.hosts))
        return self._reserve(observations)

    CIRCUIT_FAILURES = 2
    CIRCUIT_RETRY_SECONDS = 600
    # Refusals caused by the host's state, not by the frozen source.
    _HOST_TRANSIENT = ('external godot', 'external simulator', 'external_simulator', 'insufficient disk', 'insufficient_disk',
                       'no space left', 'disk_unknown', 'quarantin', 'busy', 'gui_locked', 'desktop')

    @classmethod
    def _host_transient(cls, status):
        if status.get('reason_code') in {'EXTERNAL_SIMULATOR', 'WORKER_RESTART'}:
            return True
        text = ' '.join(str(status.get(key) or '') for key in ('error', 'reason', 'detail')).lower()
        return any(token in text for token in cls._HOST_TRANSIENT)

    @staticmethod
    def _terminal_time(receipt, path):
        """Coordinator observation time, with a stable fallback for old receipts."""
        observed = (receipt.get('terminal_observation') or {}).get('at')
        if type(observed) in (int, float) and math.isfinite(observed) and observed > 0:
            return observed
        modified = path.stat().st_mtime
        status = receipt['last_status']
        for key in ('finished_at', 'finished'):  # remote / local authority clocks
            stamp = status.get(key)
            if type(stamp) in (int, float) and math.isfinite(stamp) and stamp > 0:
                return min(stamp, modified)
        return modified

    def _remember_terminal(self, receipt, status, at):
        previous = receipt.get('terminal_observation') or {}
        if previous.get('outcome') == status.get('outcome') and previous.get('at'):
            at = previous['at']
        receipt['terminal_observation'] = {'at': at, 'outcome': status.get('outcome'),
                                           'cleanup': status.get('cleanup'), 'host_transient': self._host_transient(status)}

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
        trials = {}
        for path in (self.root / 'jobs').glob('*.json'):
            try:
                receipt = json.loads(path.read_text(encoding='utf-8'))
                last = receipt.get('last_status') or {}
                if receipt.get('source_digest') != source_digest:
                    continue
                terminal = receipt.get('terminal_observation') or {}
                if last.get('state') == 'FINISHED':
                    outcome, transient = last.get('outcome'), self._host_transient(last)
                elif terminal.get('cleanup') == 'CONFIRMED':
                    outcome, transient = terminal.get('outcome'), terminal.get('host_transient')
                else:
                    if receipt.get('circuit_trial') and receipt.get('state') != 'TRANSFER_DEFERRED':
                        trials[receipt['host']] = path.stem
                    continue
                if outcome == 'NOT_DISPATCHED':
                    continue
                if outcome == 'INFRA_FAILED' and transient:
                    continue  # the host refused for its own reasons; says nothing about this source (TQ-05-F0.4)
                finished.setdefault(receipt['host'], []).append((self._terminal_time(receipt, path), path.stem, outcome))
            except (OSError, ValueError, KeyError, TypeError, AttributeError):
                continue
        now = time.time()
        for observation in observations:
            recent = sorted(finished.get(observation['id'], []), reverse=True)[:self.CIRCUIT_FAILURES]
            trial = trials.get(observation['id'])
            if trial:
                reason = f'awaiting the terminal outcome of trial {trial}'
            elif len(recent) < self.CIRCUIT_FAILURES or any(outcome != 'INFRA_FAILED' for _, _, outcome in recent):
                continue
            elif now - recent[0][0] >= self.CIRCUIT_RETRY_SECONDS:
                observation['circuit_half_open'] = True
                continue
            else:
                reason = 'consecutive infrastructure failures: ' + ', '.join(stem for _, stem, _ in recent)
            observation.update(busy=True, busy_code='CIRCUIT_OPEN', busy_reason='CIRCUIT_OPEN: ' + reason)
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
                try:
                    os.utime(archive)  # reuse counts as recent for retention's age floor
                except OSError:
                    pass
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

    # A local submit that is still unconfirmed this long after dispatch is not
    # in flight: the authority answers or times out within its 30 s RPC step.
    LOCAL_FENCE_GRACE_SECONDS = 600

    def _fence_local_refusal(self, receipt, path, local):
        """Turn an unconfirmed local submission into proved nonexecution, or do nothing.

        A refusal reply alone cannot prove nonacceptance: a replay can fail
        validation after the original request was accepted. Only the local
        authority decides, through its durable tombstone: ``recover`` first,
        then ``cancel_submission``, which also fences a delayed original submit.
        Any doubt keeps ``SUBMISSION_UNCONFIRMED`` exactly as before. The caller
        holds the job lock. Releasing the host this way needs no operator: it is
        the same proof as ``reconcile`` for local receipts (2026-11-25 audit).
        """
        request = receipt.get('request')
        secret = request.get('request_secret') if isinstance(request, dict) else None
        if receipt.get('state') != 'SUBMISSION_UNCONFIRMED' or not isinstance(secret, str) or not secret:
            return None
        try:
            if rpc('recover', **local, request_id=receipt['request_id'], request_secret=secret) is not None:
                return None  # accepted: status observes the original job
            fenced = rpc('cancel_submission', **local, request_id=receipt['request_id'], request_secret=secret)
        except (OSError, ValueError, RuntimeError):
            return None
        if not isinstance(fenced, dict) or fenced.get('canceled') is not True or fenced.get('job'):
            return None  # accepted meanwhile and canceled through the normal path; status observes it
        refusal = receipt.get('error') or 'local submission unconfirmed after the grace period'
        receipt.update(state='CANCELED_BEFORE_DISPATCH',
                       reconciliation={'reconciled_at': time.time(), 'previous_state': 'SUBMISSION_UNCONFIRMED',
                                       'proof': 'local submission tombstone', 'automatic': True},
                       last_status={'state': 'FINISHED', 'outcome': 'NOT_DISPATCHED', 'cleanup': 'CONFIRMED',
                                    'evidence': 'INCOMPLETE', 'proof': 'durable local submission tombstone',
                                    'reason_code': 'LOCAL_SUBMIT_REFUSED', 'error': refusal})
        write_json(path, receipt)
        return receipt['last_status']

    def _local_fence_due(self, receipt):
        since = receipt.get('submitted_at', receipt.get('created'))
        return (type(since) in (int, float) and math.isfinite(since)
                and time.time() - since >= self.LOCAL_FENCE_GRACE_SECONDS)

    STALE_SWEEP_SECONDS = 60
    _stale_swept_at = None

    def _fence_stale_local_receipts(self):
        """Observe overdue unconfirmed local receipts so they cannot reserve the host forever.

        A blocked batch row is not observed again until its batch restarts, and
        ``_reserve`` keeps its host busy meanwhile: four refused local submits
        held the Windows host 23-61 h each between 14 and 25 November. Placement
        calls this before probing. Observation goes through the normal status
        path, so the tombstone rules above decide; a busy job lock is skipped.
        """
        now = time.monotonic()
        if self._stale_swept_at is not None and now - self._stale_swept_at < self.STALE_SWEEP_SECONDS:
            return
        self._stale_swept_at = now
        for path in (self.root / 'jobs').glob('*.json'):
            try:
                receipt = json.loads(path.read_text(encoding='utf-8'))
                due = (isinstance(receipt, dict) and receipt.get('state') == 'SUBMISSION_UNCONFIRMED'
                       and receipt.get('local_authority_root') and self._local_fence_due(receipt))
            except (OSError, ValueError):
                continue
            if not due or not path.stem.isalnum():
                continue
            try:
                guard = acquire_lock(self.root / (path.stem + '.lock'), timeout=1)
            except PoolLockTimeout:
                continue
            try:
                self._status_locked(path.stem)
            except Exception:  # advisory: the receipt keeps its conservative state
                pass
            finally:
                guard.close()

    _INSTALLER = (
        'import fcntl, hashlib, json, os, shutil, sys, time\n'
        'staging, runtime, root, expected, rollback = sys.argv[1], sys.argv[2], sys.argv[3], json.loads(sys.argv[4]), sys.argv[5] == "1"\n'
        'def out(value, code=0):\n'
        '    print(json.dumps(value)); sys.exit(code)\n'
        'lock = open(os.path.join(root, "pool.lock"), "a+b")\n'
        'try:\n'
        '    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)\n'
        'except OSError:\n'
        '    out({"ok": False, "error": "BUSY: the host lock is held"}, 1)\n'
        'jobs = os.path.join(root, "jobs")\n'
        'for name in (os.listdir(jobs) if os.path.isdir(jobs) else []):\n'
        '    path = os.path.join(jobs, name, "state.json")\n'
        '    try:\n'
        '        state = json.load(open(path)).get("state")\n'
        '    except Exception:\n'
        '        state = "UNREADABLE" if os.path.exists(path) else None\n'
        '    if state in ("STARTING", "RUNNING", "UNKNOWN", "UNREADABLE"):\n'
        '        out({"ok": False, "error": "BUSY: job " + name + " is " + state}, 1)\n'
        'if rollback:\n'
        '    restored = []\n'
        '    for name in expected:\n'
        '        previous = os.path.join(runtime, name + ".prev-deploy")\n'
        '        if os.path.exists(previous):\n'
        '            os.replace(previous, os.path.join(runtime, name)); restored.append(name)\n'
        '    out({"ok": True, "restored": restored})\n'
        'for name, sha in expected.items():\n'
        '    data = open(os.path.join(staging, name), "rb").read()\n'
        '    if hashlib.sha256(data).hexdigest() != sha:\n'
        '        out({"ok": False, "error": "staged " + name + " differs from the expected digest"}, 1)\n'
        'for name in expected:\n'
        '    current = os.path.join(runtime, name)\n'
        '    if os.path.exists(current):\n'
        '        shutil.copy2(current, current + ".prev-deploy")\n'
        '        shutil.copy2(current, current + ".prev-" + time.strftime("%Y%m%dT%H%M%S"))\n'
        '    os.replace(os.path.join(staging, name), current)\n'
        'fd = os.open(runtime, os.O_RDONLY); os.fsync(fd); os.close(fd)\n'
        'shutil.rmtree(staging, ignore_errors=True)\n'
        'out({"ok": True, "installed": sorted(expected)})\n')

    def deploy_runtime(self, host_id, *, execute=False):
        """Install this coordinator's agent runtime on one idle remote host (TQ-07-B4).

        Only bytes that Git already stores are installed. The swap happens under
        the host lock with no unfinished job, keeps the previous files, and is
        rolled back if the host does not then report the expected runtime.
        """
        host = self._remote_host(host_id)
        files = runtime_files()
        expected_digest = runtime_digest(files)
        for name, data in files.items():
            oid = subprocess.run(['git', '-C', str(REPO), 'hash-object', '--stdin'], input=data,
                                 capture_output=True, check=True).stdout.decode().strip()
            if subprocess.run(['git', '-C', str(REPO), 'cat-file', '-e', oid], capture_output=True).returncode != 0:
                raise ValueError(f'{name} is not committed; only committed agent bytes are deployed')
        probe = self.remote(host, 'probe', {'engine_path': None}, timeout=60)
        reported = ((probe.get('description') or {}).get('runtime') or {}).get('digest')
        report = {'host': host_id, 'expected': expected_digest, 'reported': reported,
                  'up_to_date': reported == expected_digest, 'execute': execute}
        if reported == expected_digest or not execute:
            return report
        admission = probe.get('admission') or {}
        if admission.get('busy') or admission.get('quarantined'):
            raise ValueError(f'{host_id} is not idle ({admission.get("busy_code") or "busy"}); deploy later')
        runtime = str(Path(host['agent']).parent).replace('\\', '/')
        staging = f"{runtime}/.staging-{uuid.uuid4().hex}"
        hashes = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}
        flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        buffer = tempfile.SpooledTemporaryFile()
        with tarfile.open(fileobj=buffer, mode='w') as bundle:
            for name, data in files.items():
                info = tarfile.TarInfo(name)
                info.size, info.mode = len(data), 0o644
                bundle.addfile(info, io.BytesIO(data))
        buffer.seek(0)
        subprocess.run(ssh_command(host, shlex.join(['mkdir', '-p', staging]) + ' && ' +
                                   shlex.join(['tar', '-x', '-C', staging])),
                       input=buffer.read(), capture_output=True, check=True, timeout=120, creationflags=flags)

        def install(rollback):
            command = shlex.join([host['python'], '-', staging, runtime, host['root'], json.dumps(hashes),
                                  '1' if rollback else '0'])
            result = subprocess.run(ssh_command(host, command), input=self._INSTALLER.encode(),
                                    capture_output=True, timeout=120, creationflags=flags)
            try:
                return json.loads(result.stdout.decode().strip().splitlines()[-1])
            except (ValueError, IndexError):
                return {'ok': False, 'error': (result.stderr.decode(errors='replace') or 'no reply')[-300:]}

        installed = install(False)
        report['install'] = installed
        if not installed.get('ok'):
            return report
        try:
            after = self.remote(host, 'probe', {'engine_path': None}, timeout=60)
            report['reported_after'] = ((after.get('description') or {}).get('runtime') or {}).get('digest')
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
            report['reported_after'] = None
            report['probe_error'] = str(error)[:200]
        report['up_to_date'] = report['reported_after'] == expected_digest
        if not report['up_to_date']:
            report['rollback'] = install(True)
        return report

    def recover_quarantined_hosts(self):
        """Ask each quarantined remote host to settle jobs its reboot proves ended (TQ-07-A9f).

        Read-only for hosts that are not quarantined or whose agent predates
        ``recover-boot``. Returns one line of outcome per remote host.
        """
        def one(host):
            try:
                probe = self.remote(host, 'probe', {'engine_path': None}, timeout=30)
            except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
                return host['id'], {'skipped': 'unreachable: ' + str(error)[:120]}
            if not (probe.get('admission') or {}).get('quarantined'):
                return host['id'], {'skipped': 'not quarantined'}
            if 'recover-boot' not in (probe.get('features') or []):
                return host['id'], {'skipped': 'agent predates recover-boot; redeploy it'}
            try:
                return host['id'], self.remote(host, 'recover-boot', {}, timeout=60)
            except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
                return host['id'], {'error': str(error)[:200]}

        remote_hosts = [host for host in self.hosts if not host.get('local')]
        if not remote_hosts:
            return {}
        with ThreadPoolExecutor(max_workers=len(remote_hosts)) as executor:
            return dict(executor.map(one, remote_hosts))

    SETTLE_SLOW_SECONDS = 5.0

    def settle_reserving_receipts(self, budget_seconds=45.0):
        """Observe every overdue receipt that reserves a host, once (TQ-07-A2).

        Run by the watchdog, so a receipt with no live batch still reaches the
        proofs in ``_status_locked``: an interrupted preparation becomes a
        deferral, a refused local submit or a fenced remote one is settled, and
        a job that did run is promoted back to SUBMITTED. Nothing is released
        without one of those proofs. A host whose observation is slow (likely
        unreachable) is skipped for the rest of this pass, and the pass stops
        starting new observations after ``budget_seconds``.
        """
        deadline = time.monotonic() + budget_seconds
        report = {'observed': 0, 'settled': [], 'skipped_hosts': []}
        slow = set()
        for path in sorted((self.root / 'jobs').glob('*.json')):
            if time.monotonic() >= deadline:
                report['deferred'] = True
                break
            try:
                receipt = json.loads(path.read_text(encoding='utf-8'))
            except (OSError, ValueError):
                continue
            if not isinstance(receipt, dict) or not path.stem.isalnum():
                continue
            state, host = receipt.get('state'), receipt.get('host')
            if state not in {'PREPARING', 'SUBMISSION_UNCONFIRMED'} or host in slow:
                continue
            if state == 'SUBMISSION_UNCONFIRMED' and not self._local_fence_due(receipt):
                continue
            try:
                guard = acquire_lock(self.root / (path.stem + '.lock'), timeout=1)
            except PoolLockTimeout:
                continue  # a submission or observation owns it right now
            started = time.monotonic()
            try:
                result = self._status_locked(path.stem)
            except Exception as error:  # advisory: the receipt keeps its conservative state
                result = {'state': 'UNKNOWN', 'error': str(error)[:200]}
            finally:
                guard.close()
            report['observed'] += 1
            if result.get('outcome') == 'NOT_DISPATCHED' or result.get('reason_code') == 'TRANSFER_DEFERRED' \
                    or result.get('state') not in {'UNKNOWN', 'SUBMISSION_UNCONFIRMED'}:
                report['settled'].append({'job': path.stem, 'host': host, 'state': result.get('state'),
                                          'reason_code': result.get('reason_code') or result.get('outcome')})
            elif time.monotonic() - started >= self.SETTLE_SLOW_SECONDS:
                slow.add(host)
        report['skipped_hosts'] = sorted(item for item in slow if isinstance(item, str))
        return report

    @staticmethod
    def _unproved_nonexecution(receipt):
        # Older coordinators treated any local submit ValueError as proof that
        # nothing ran, even on a replay after an accepted reply was lost.
        return receipt.get('state') == 'NOT_DISPATCHED'

    def _read_receipt_locked(self, path, *, allow_missing=False):
        try:
            receipt = json.loads(path.read_text())
        except FileNotFoundError:
            if allow_missing:
                return None
            raise
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
        # Promote only an identity-checked legacy terminal status. This record
        # is placement history; collection still uses fresh, verified evidence.
        previous = receipt.get('last_status') or {}
        if (receipt.get('state') == 'SUBMITTED' and isinstance(receipt.get('request'), dict)
                and previous.get('state') == 'FINISHED' and previous.get('cleanup') == 'CONFIRMED'
                and previous.get('request_id') == receipt['request'].get('request_id') == path.stem
                and 'cleanup' not in (receipt.get('terminal_observation') or {})):
            try:
                host, _ = self._destination(receipt)
                if host.get('local'):
                    self._verify_local_status(receipt, previous)
                else:
                    self._verify_remote_status(receipt, previous)
            except (KeyError, OSError, ValueError):
                pass
            else:
                self._remember_terminal(receipt, previous, self._terminal_time(receipt, path))
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
        if 'transfer_seconds' in receipt:
            result['transfer_seconds'] = receipt['transfer_seconds']
        if receipt.get('invalidated_nonexecution'):
            result['pool_recovery_version'] = 1
        return result

    @staticmethod
    def _missing_receipt(identifier):
        return {'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED', 'job': identifier,
                'reason_code': 'MISSING_RECEIPT',
                'error': f'Missing pool receipt jobs/{identifier}.json. Preserve the original batch and ID. '
                         'Restore the original receipt from verified evidence before recovery; dispatch is uncertain.'}

    @staticmethod
    def _deferred_status(receipt):
        """Queued, not blocked: the transfer failed before any dispatch and the same ID retries."""
        transfer = receipt.get('transfer') or {}
        return {'state': 'WAITING', 'reason_code': 'TRANSFER_DEFERRED', 'error': receipt.get('error'),
                'transfer_attempts': transfer.get('attempts'), 'dispatched': False}

    @staticmethod
    def _record_deferral(receipt, path, stage, code, text):
        """Durably record a proved nondispatch; the same ID retries on the same host."""
        previous = receipt.get('transfer')
        history = list(receipt.get('transfer_history') or [])
        if previous:
            history.append(previous)
        failure = {'attempts': (previous or {}).get('attempts', 0) + 1, 'stage': stage,
                   'code': code, 'error': text, 'at': time.time()}
        message = f"{code} at {stage} (attempt {failure['attempts']}): {text}"
        receipt.update(state='TRANSFER_DEFERRED', transfer=failure, transfer_history=history[-9:], error=message)
        write_json(path, receipt)
        return message, failure

    @classmethod
    def _defer_transfer(cls, receipt, path, error):
        message, failure = cls._record_deferral(receipt, path, error.stage, error.code, str(error))
        raise TransferDeferred(message, failure) from error

    PREPARATION_SETTLE_SECONDS = 3600

    def _preparation_settleable(self, receipt, path):
        """Prove that a PREPARING receipt was never dispatched. The caller holds its job lock.

        Every dispatch call is made only after SUBMISSION_UNCONFIRMED is durable.
        A receipt that binds a destination was written by a coordinator that
        holds this job lock from the PREPARING write until after dispatch, so
        holding the lock now proves nothing is in flight. The first coordinator
        released the lock right after writing PREPARING; for those receipts the
        proof is an age beyond any transfer timeout instead.
        """
        if isinstance(receipt.get('destination'), dict):
            return True
        try:
            age = time.time() - path.stat().st_mtime
        except OSError:
            return False
        return age >= self.PREPARATION_SETTLE_SECONDS

    def _remote_fence_due(self, receipt):
        """Only a never-confirmed submission bound to a known store may be fenced (TQ-07-A2).

        A receipt that was ever accepted, or whose store identity is unknown
        (older agents, legacy receipts), keeps the operator path: absence there
        could mean a store that was wiped after the job ran.
        """
        destination = receipt.get('destination')
        return (receipt.get('state') == 'SUBMISSION_UNCONFIRMED' and 'accepted' not in receipt
                and not receipt.get('terminal_observation')
                and isinstance(destination, dict) and isinstance(destination.get('identity'), dict)
                and self._local_fence_due(receipt))

    def _try_fence(self, host, identifier):
        """Ask the remote agent for a durable never-run tombstone; None when it cannot say."""
        try:
            result = self.remote(host, 'fence', {'request_id': identifier})
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError):
            return None  # transport failure, refusal or an agent that predates fence
        if not isinstance(result, dict) or result.get('request_id') != identifier:
            return None
        return result

    def _fence_remote(self, receipt, path, host, *, automatic=True):
        """Settle a remote submission the agent proves will never run. The caller holds the job lock."""
        identifier = receipt['request_id']
        result = self._try_fence(host, identifier)
        bound = (receipt.get('destination') or {}).get('identity')
        if (result is None or result.get('state') != 'FENCED'
                or not identity_matches(bound, result.get('identity'))):
            return None
        previous = receipt.get('state')
        receipt.update(state='CANCELED_BEFORE_DISPATCH',
                       reconciliation={'reconciled_at': time.time(), 'previous_state': previous,
                                       'proof': 'remote fence tombstone', 'automatic': automatic,
                                       'fence': {key: result.get(key) for key in ('state', 'identity', 'fenced_at')}},
                       last_status={'state': 'FINISHED', 'outcome': 'NOT_DISPATCHED', 'cleanup': 'CONFIRMED',
                                    'evidence': 'INCOMPLETE', 'proof': 'durable remote fence tombstone',
                                    'reason_code': 'REMOTE_FENCED',
                                    'error': receipt.get('error') or 'remote submission unconfirmed after the grace period'})
        write_json(path, receipt)
        return receipt['last_status']

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
        """Resolve the receipt's original host, or raise without touching the receipt.

        The receipt's own destination is compared with the host's current
        settings (TQ-07-A1); unrelated configuration edits are ignored. A legacy
        receipt is resolved from a retained configuration with the digest it
        bound. Without any binding it may be observed, never replayed.
        """
        self.refresh_config()
        host = next((item for item in self.hosts if item['id'] == receipt['host']), None)
        if host is None:
            raise ValueError('original pool host is no longer configured; restore the original destination')
        bound, _ = self._bound_destination(receipt)
        if bound is None:
            if replay:
                raise ValueError('legacy receipt has no destination binding; observation only, automatic replay refused')
        else:
            self._compare_destination(bound, host)
            if (not host.get('local') and bound.get('ssh') != host.get('ssh')
                    and not identity_matches(bound.get('identity'), self._observed_identity(host))):
                raise ValueError(f"pool configuration changed for host {host['id']}: the SSH alias now reaches a "
                                 'store whose identity was not proved to be the bound one')
        root = Path(receipt['local_authority_root']) if receipt.get('local_authority_root') else None
        return host, ({'root': root} if root is not None else {})

    def _observed_identity(self, host):
        """The store identity a remote host reports now, or None."""
        try:
            value = self.remote(host, 'probe', {'engine_path': None})
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError):
            return None
        identity = value.get('identity') if isinstance(value, dict) else None
        return identity if isinstance(identity, dict) else None

    def submit(self, snapshot, script, *, platform='any', require=(), timeout=90, host_id=None,
               request_id=None, settings=None, expected_manifest_sha256=None, rendering_driver=None,
               before_dispatch=None):
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
                                expected_manifest_sha256=expected_manifest_sha256,
                                rendering_driver=rendering_driver, before_dispatch=before_dispatch)
        finally:
            guard.close()

    @staticmethod
    def _submission_result(receipt, path):
        result = {'job': receipt['request_id'], 'receipt': str(path), 'state': receipt['state'],
                  'decision': receipt['decision']}
        return result

    def _preflight(self, snapshot, script, platform, require, timeout, host_id, settings, expected_manifest_sha256,
                   rendering_driver=None):
        try:
            platform_set(platform)  # 'any', one OS, or a list of OSes (TQ-07-D1)
        except ValueError:
            raise ValueError('invalid job platform') from None
        if host_id is not None and host_id not in {host['id'] for host in self.hosts}:
            raise ValueError('unknown configured host: ' + str(host_id))
        options = validate('checked', {'script': script, 'require': list(require), 'timeout': timeout,
                           'headless': True, 'workload': 'auto', 'settings': settings or {}})
        if scheduling('checked', options)['workload'] == 'performance':
            raise ValueError('Performance checks require a dedicated same-host campaign through the existing queue')
        if rendering_driver is not None:
            # TQ-06 GPU lane: the check renders on a remote host that advertises
            # the `graphics` capability. The import stays headless.
            if rendering_driver not in {'vulkan', 'opengl3'}:
                raise ValueError('rendering_driver must be vulkan or opengl3')
            if host_id is not None and next(h for h in self.hosts if h['id'] == host_id).get('local'):
                raise ValueError('graphics checks run only on remote hosts with a GPU lane')
            options.update(headless=False, workload='graphics', rendering_driver=rendering_driver)
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
        job = {'platform': platform, 'workload': 'graphics' if rendering_driver else 'headless',
               'source_bytes': sum(item['size'] for item in manifest['files'].values()),
               'cache_id': manifest['source_digest'], 'duration_key': script, 'estimated_seconds': timeout,
               'memory_bytes': 512 * 1024 * 1024, 'disk_bytes': IMPORT_CACHE_BYTES}
        return manifest, options, job

    def _submit(self, snapshot, script, *, platform, require, timeout, host_id, request_id, settings,
                expected_manifest_sha256=None, rendering_driver=None, before_dispatch=None):
        snapshot = Path(snapshot).resolve()
        identifier = request_id or uuid.uuid4().hex
        if not identifier.isalnum() or len(identifier) > 64:
            raise ValueError('invalid request id')
        inputs = {'snapshot': str(snapshot), 'script': script, 'platform': platform,
                  'require': list(require), 'timeout': timeout, 'host': host_id, 'settings': settings or {}}
        if expected_manifest_sha256 is not None:
            inputs['snapshot_manifest_sha256'] = expected_manifest_sha256
        if rendering_driver is not None:
            inputs['rendering_driver'] = rendering_driver  # absent for headless, so older receipts keep their identity
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
                                                    host_id, settings, expected_manifest_sha256, rendering_driver)
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
        self._fence_stale_local_receipts()
        try:
            while True:
                # SSH probes and remote engine hashing run before the global
                # dispatch lock; only local receipt reservation and planning
                # happen under it (plan section 7.6).
                probed_at = time.time()
                observations = self.probe(bound_host) if bound_host else self.probe()
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
                if host_id is None:
                    # Unpinned work avoids a host where this exact source keeps
                    # failing infrastructure; pinned work keeps its explicit host.
                    observations = self._circuit(observations, manifest['source_digest'])
                decision = plan(job, observations)
                if decision['selected'] is None:
                    waiting = {'state': 'WAITING', 'decision': decision, 'placement_job': job}
                    if bound_host is not None:
                        waiting['placement_host'] = bound_host
                    return waiting
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
                        self._remember_archive_digest(manifest['source_digest'], archive_digest)
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
                observed = next((item for item in observations if item['id'] == host['id']), {})
                receipt = {'request_id': identifier, 'host': host['id'], 'snapshot': str(snapshot),
                           'inputs': inputs,
                           'source_digest': manifest['source_digest'], 'options': options,
                           'decision': decision, 'state': 'PREPARING', 'created': time.time(),
                           'config_sha256': self.config_digest,
                           'destination': destination_of(host, observed.get('identity'))}
                if host.get('local'):
                    receipt['local_authority_root'] = str(state_root().resolve())
            if any(item['id'] == host['id'] and item.get('circuit_half_open') for item in observations):
                receipt['circuit_trial'] = True
            else:
                receipt.pop('circuit_trial', None)
            if before_dispatch is not None:
                before_dispatch()
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
                transfer_started = time.monotonic()
                try:
                    remote_archive = self._transfer_archive(host, archive, archive_digest, identifier)
                except TransferFailure as error:
                    self._defer_transfer(receipt, receipt_path, error)  # always raises TransferDeferred
                receipt['transfer_seconds'] = round(time.monotonic() - transfer_started, 3)
                receipt['request'] = {'request_id': identifier, 'preset': 'checked',
                                      'archive': {'path': remote_archive, 'sha256': archive_digest},
                                      'expected_engine_sha256': host['engine_sha256'],
                                      'engine_path': host['engine'], 'options': options}
            # Persist the exact destination and request before any possible execution.
            receipt['state'] = 'SUBMISSION_UNCONFIRMED'
            receipt['submitted_at'] = time.time()
            write_json(receipt_path, receipt)
            refused, busy, local = False, None, {}
            try:
                host, local = self._destination(receipt, replay=True)
                if host.get('local'):
                    try:
                        accepted = rpc('submit', **local, **receipt['request'])
                    except ValueError:
                        # An error reply from the authority (or a malformed reply),
                        # not a transport failure; recover-first decides acceptance.
                        refused = True
                        raise
                    self._verify_local_acceptance(accepted)
                else:
                    try:
                        accepted = self.remote(host, 'run', receipt['request'])
                    except RemoteRefusal as error:
                        # The agent answers an ID it already knows with its status and
                        # raises BUSY only from the host lock, before writing a job.
                        # This is the only run call for this ID, so nothing was accepted.
                        busy = error if error.code == 'BUSY' else None
                        raise
                    self._verify_remote_status(receipt, accepted)
                receipt['accepted'] = accepted
                receipt['state'] = 'SUBMITTED'
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                receipt['error'] = str(error)
                # The transport's exception type cannot establish nonacceptance.
                # In particular a replay may fail validation after the original
                # request was accepted. Keep its identity and original host.
            write_json(receipt_path, receipt)
            if busy is not None:
                # For example a storage sweep holding the host lock (2026-11-25 review).
                # Proved nondispatched: retry the same ID on the same host.
                self._defer_transfer(receipt, receipt_path, TransferFailure('run', 'HOST_BUSY', str(busy)))
            if refused:
                fenced = self._fence_local_refusal(receipt, receipt_path, local)
                if fenced is not None:
                    raise SubmissionRejected(f"local authority refused the request: {receipt['error']}",
                                             {'state': 'REJECTED', 'job': identifier, 'pool_host': receipt['host'],
                                              **{key: fenced[key] for key in ('reason_code', 'error', 'proof')}})
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
            receipt = self._read_receipt_locked(path, allow_missing=True)
            if receipt is None:
                return self._missing_receipt(identifier)
            if receipt.get('state') in self._RECONCILED:
                # Settled as never dispatched (tombstone or operator): recovery must
                # not replay it, which could start work an operator released.
                return self._public_status(receipt, identifier, receipt['last_status'])
            if (receipt.get('terminal_observation') or {}).get('cleanup') == 'CONFIRMED':
                # Once completion and teardown are witnessed, recovery can
                # observe the authority but a lost receipt there cannot replay.
                return self._status_locked(identifier)
            if receipt.get('state') in {'TRANSFER_DEFERRED', 'PREPARING'}:
                # Nondispatched (an interrupted preparation is settled as such under
                # this lock); only a repeated submit, which has the snapshot, resumes it.
                return self._status_locked(identifier)
            if 'request' not in receipt:
                receipt.update(state='SUBMISSION_UNCONFIRMED', last_status={'state': 'UNKNOWN',
                               'cleanup': 'UNCONFIRMED', 'error': 'Dispatch metadata is unavailable; preserve the original receipt and authority'})
                write_json(path, receipt)
                return self._public_status(receipt, identifier, receipt['last_status'])
            try:
                host, local = self._destination(receipt)
            except ValueError as error:
                return self._public_status(receipt, identifier, {'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED',
                                                                 'reason_code': 'DESTINATION_CHANGED', 'error': str(error)})
            refused = False
            try:
                if host.get('local'):
                    request = receipt['request']
                    result = rpc('recover', **local, request_id=identifier, request_secret=request['request_secret'])
                    if result is None:
                        # None is an observation, not a fence: the original
                        # submit may still be delayed. Only replay the SAME ID.
                        self._destination(receipt, replay=True)
                        try:
                            result = rpc('submit', **local, **request)
                        except ValueError:
                            refused = True
                            raise
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
                # Soon after submission a late original can still be accepted after
                # this refused replay; only an overdue one is settled by the tombstone.
                fenced = (self._fence_local_refusal(receipt, path, local)
                          if refused and self._local_fence_due(receipt) else None)
                return self._public_status(receipt, identifier, fenced or receipt['last_status'])
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
            if receipt.get('state') == 'PREPARING':
                return self._status_locked(identifier)  # proved nondispatched under this lock
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
                if 'accepted' not in receipt:
                    # TQ-07-A2: a never-confirmed submission to a store whose identity is
                    # bound is settled by the agent's durable tombstone, without an operator.
                    fenced = self._fence_remote(receipt, path, host, automatic=False)
                    if fenced is not None:
                        return self._public_status(receipt, identifier, fenced)
                if not operator_confirm:
                    raise ValueError('remote authority has no record of this request and could not fence it against '
                                     'this receipt\'s bound store; release requires --operator-confirm after checking '
                                     'no dispatch is in flight')
                # Leave a tombstone where the agent supports it, so a delayed original cannot start later.
                fence = self._try_fence(host, identifier)
                receipt.update(state='OPERATOR_RECONCILED_ABSENT',
                               reconciliation={**evidence, 'proof': 'remote NOT_FOUND + operator confirmation',
                                               **({'fence': {key: fence.get(key) for key in ('state', 'identity')}}
                                                  if fence else {})},
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

    RECLAIMABLE_FAILURES = frozenset({'TEST_FAILED', 'TIMED_OUT', 'INFRA_FAILED'})
    GC_REMOTE_TIMEOUT = 300

    @classmethod
    def _gc_candidate(cls, receipt, host_id):
        last = receipt.get('last_status') if isinstance(receipt, dict) else None
        if (not isinstance(last, dict) or receipt.get('host') != host_id or not isinstance(receipt.get('request'), dict)
                or (receipt.get('storage_gc') or {}).get('state') == 'RECLAIMED'
                or (last.get('storage_gc') or {}).get('state') == 'RECLAIMED'
                or last.get('state') != 'FINISHED' or last.get('cleanup') != 'CONFIRMED'):
            return False
        return (last.get('outcome') == 'PASSED' and last.get('evidence') == 'COMPLETE'
                or last.get('outcome') in cls.RECLAIMABLE_FAILURES)

    def _remember_storage_gc(self, identifier, result):
        guard = acquire_lock(self.root / (identifier + '.lock'))
        try:
            path = self.root / 'jobs' / (identifier + '.json')
            receipt = self._read_receipt_locked(path)
            receipt['storage_gc'] = {'state': 'RECLAIMED', 'at': time.time(),
                                     'logical_bytes_removed': result.get('logical_bytes_removed'),
                                     'retained_residue_files': (result.get('retained_residue') or {}).get('files')}
            write_json(path, receipt)
        finally:
            guard.close()

    AUTO_GC_INTERVAL_SECONDS = 1200
    AUTO_GC_BUDGET_SECONDS = 120
    GC_REFUSAL_SECONDS = 24 * 3600

    def _gc_memory_path(self, host_id):
        return self.root / 'retention' / f'gc-refusals-{host_id}.json'

    def _gc_memory(self, host_id):
        """Refusals remembered per host so a sweep does not repeat them (TQ-07-A4)."""
        try:
            value = json.loads(self._gc_memory_path(host_id).read_text(encoding='utf-8'))
        except (OSError, ValueError):
            value = {}
        if not isinstance(value, dict) or not isinstance(value.get('jobs'), dict):
            value = {'jobs': {}}
        return value

    def _save_gc_memory(self, host_id, memory):
        now = time.time()
        memory['jobs'] = {key: entry for key, entry in memory['jobs'].items()
                          if isinstance(entry, dict) and now - entry.get('at', 0) < self.GC_REFUSAL_SECONDS}
        try:
            self._gc_memory_path(host_id).parent.mkdir(exist_ok=True)
            write_json(self._gc_memory_path(host_id), memory)
        except OSError:
            pass  # advisory: the next sweep simply asks again

    @staticmethod
    def _agent_refuses_failures(text):
        # Agents before failure reclamation answer every failed job with this.
        return 'only a finished job with confirmed cleanup' in text or 'only a FINISHED/PASSED/COMPLETE/CONFIRMED' in text

    def reclaim_for_space(self, decision, budget_seconds=AUTO_GC_BUDGET_SECONDS):
        """Run ``gc`` on remote hosts that just refused placement for disk space.

        Called by the batch runner outside every pool lock, at most once per host
        per ``AUTO_GC_INTERVAL_SECONDS`` and by one process at a time. Each sweep
        starts no new job after ``budget_seconds``, so a placement lane is not held
        for long; a backlog continues on later sweeps. Before this, retention was
        manual: on 25 November finished failures held 24 GB of the linux host's
        25 GB queue store while 14 rows waited on disk. Returns the per-host
        reports of sweeps that ran.
        """
        if type(budget_seconds) not in (int, float) or not math.isfinite(budget_seconds) or budget_seconds < 1:
            return {}
        candidates = (decision or {}).get('candidates') if isinstance(decision, dict) else None
        hosts = sorted({item['host'] for item in candidates or [] if isinstance(item, dict)
                        and isinstance(item.get('host'), str)
                        and any(isinstance(reason, str) and reason.startswith('INSUFFICIENT_DISK')
                                for reason in item.get('reasons') or [])})
        directory = self.root / 'retention'
        reports = {}
        for host_id in hosts:
            if not host_id.replace('-', '').replace('_', '').isalnum():
                continue
            host = next((item for item in self.hosts if item['id'] == host_id), None)
            if host is None or host.get('local'):
                continue
            directory.mkdir(exist_ok=True)
            try:
                guard = acquire_lock(directory / f'auto-gc-{host_id}.lock', timeout=0)
            except PoolLockTimeout:
                continue  # another process is sweeping this host
            try:
                journal = directory / f'auto-gc-{host_id}.json'  # written only under this host's lock
                try:
                    last = json.loads(journal.read_text(encoding='utf-8'))
                except (OSError, ValueError):
                    last = {}
                last = last if isinstance(last, dict) else {}
                if type(last.get('at')) in (int, float) and time.time() - last['at'] < self.AUTO_GC_INTERVAL_SECONDS:
                    continue
                write_json(journal, {'host': host_id, 'at': time.time(), 'state': 'RUNNING'})
                try:
                    report = self.gc(host_id, execute=True, deadline=time.monotonic() + budget_seconds)
                    entry = {'state': 'DONE', **{key: report.get(key) for key in (
                        'candidates', 'reclaimed', 'deferred', 'logical_bytes_removed')},
                             'skipped': len(report.get('skipped') or []),
                             'skipped_sample': (report.get('skipped') or [])[:3]}
                except Exception as error:
                    entry = {'state': 'FAILED', 'error': str(error)[:300]}
                    report = entry
                write_json(journal, {'host': host_id, 'at': time.time(), **entry})
                reports[host_id] = report
            finally:
                guard.close()
        return reports

    def gc(self, host_id, *, execute=False, deadline=None):
        """Reclaim a remote host's reproducible copies of jobs whose evidence is collected here.

        ``deadline`` (monotonic) stops starting new jobs; the rest stay candidates
        for the next sweep. Failures, which hold the most bytes, go first.

        Without ``execute`` this only lists candidates. With it, each job is first
        collected (or its existing collection re-verified) on this coordinator;
        only then does the remote agent remove that job's reproducible inputs:
        the whole source and archive copies of a complete pass, or for a finished
        failure with confirmed cleanup only what it proves it can regenerate,
        keeping the run's residue. UNKNOWN and unconfirmed jobs are never candidates.
        """
        host = self._remote_host(host_id)
        candidates = []
        for path in sorted((self.root / 'jobs').glob('*.json')):
            try:
                receipt = json.loads(path.read_text(encoding='utf-8'))
            except (OSError, ValueError):
                continue
            if self._gc_candidate(receipt, host_id):
                candidates.append((path.stem, receipt))
        memory = self._gc_memory(host_id)
        now = time.time()
        failures_refused = now < memory.get('failures_refused_until', 0)
        held = {identifier for identifier, entry in memory['jobs'].items()
                if now - entry.get('at', 0) < self.GC_REFUSAL_SECONDS}
        failures = [item for item in candidates if item[1]['last_status'].get('outcome') != 'PASSED']
        passes = [item for item in candidates if item[1]['last_status'].get('outcome') == 'PASSED']
        if failures_refused:
            failures = []  # this host's agent cannot reclaim failures; do not ask per job (TQ-07-A4)
        failures = [item for item in failures if item[0] not in held]
        passes = [item for item in passes if item[0] not in held]
        # Failures hold the most bytes, but a sweep must also reach passes: a
        # backlog of refused failures used to consume every sweep's budget.
        order = [item for pair in itertools.zip_longest(failures, passes) for item in pair if item is not None]
        report = {'host': host_id, 'candidates': len(candidates), 'execute': execute,
                  'held_after_refusal': len(held), 'failures_refused_by_agent': failures_refused}
        if not execute:
            report['request_ids'] = [identifier for identifier, _ in order]
            return report
        reclaimed, skipped, total = [], [], 0
        for index, (identifier, receipt) in enumerate(order):
            if deadline is not None and time.monotonic() >= deadline:
                report['deferred'] = len(order) - index
                break
            if failures_refused and outcome_is_failure(receipt):
                continue  # the agent refused this class earlier in this sweep
            try:
                collected = self.collect(identifier)
                outcome = collected.get('pool_outcome')
                if outcome == 'PASSED':
                    if collected.get('diagnostic_only') is not False:
                        raise ValueError('collected evidence is not a complete pass')
                elif outcome not in self.RECLAIMABLE_FAILURES or outcome != receipt['last_status'].get('outcome'):
                    raise ValueError('collected evidence does not match the finished outcome')
                result = self.remote(host, 'gc', {'request_id': identifier, 'operator_confirm': True,
                                                  'payload_sha256': request_digest(receipt['request'])},
                                     timeout=self.GC_REMOTE_TIMEOUT)
                total += result.get('logical_bytes_removed', 0) or 0
                reclaimed.append(identifier)
                self._remember_storage_gc(identifier, result)
                memory['jobs'].pop(identifier, None)
            except Exception as error:  # one job's refusal never stops the sweep
                text = str(error)[:300]
                skipped.append({'request_id': identifier, 'error': text})
                memory['jobs'][identifier] = {'at': time.time(), 'error': text}
                if outcome_is_failure(receipt) and self._agent_refuses_failures(text):
                    memory['failures_refused_until'] = time.time() + self.GC_REFUSAL_SECONDS
                    report['failures_refused_by_agent'] = failures_refused = True
                    memory['jobs'].pop(identifier, None)  # a class refusal says nothing about this job
        self._save_gc_memory(host_id, memory)
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
        receipt = self._read_receipt_locked(path, allow_missing=True)
        if receipt is None:
            return self._missing_receipt(identifier)
        if receipt.get('state') in self._RECONCILED:
            return self._public_status(receipt, identifier, receipt['last_status'])
        if receipt.get('state') == 'TRANSFER_DEFERRED':
            return self._public_status(receipt, identifier, self._deferred_status(receipt))
        if receipt.get('state') == 'PREPARING':
            if not self._preparation_settleable(receipt, path):
                return self._public_status(receipt, identifier, {
                    'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED', 'reason_code': 'PREPARATION_IN_DOUBT',
                    'error': 'an older coordinator may still be preparing this request; it is settled after '
                             f'{self.PREPARATION_SETTLE_SECONDS} s without change'})
            self._record_deferral(receipt, path, 'preparation', 'COORDINATOR_INTERRUPTED',
                                  'the coordinator stopped before dispatch; no submit or run call was made')
            return self._public_status(receipt, identifier, self._deferred_status(receipt))
        if 'request' not in receipt:
            return self._public_status(receipt, identifier, {'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED',
                    'error': 'Preparation interrupted before durable dispatch request'})
        try:
            host, local = self._destination(receipt)
        except ValueError as error:
            # TQ-07-A1: a refused destination leaves the receipt exactly as it was;
            # demoting it would make its host look reserved.
            return self._public_status(receipt, identifier, {'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED',
                                                             'reason_code': 'DESTINATION_CHANGED', 'error': str(error)})
        try:
            if host.get('local'):
                request = receipt['request']
                recovered = rpc('recover', **local, request_id=identifier, request_secret=request['request_secret'])
                if recovered is not None:
                    self._verify_local_acceptance(recovered)
                elif self._local_fence_due(receipt):
                    fenced = self._fence_local_refusal(receipt, path, local)
                    if fenced is not None:
                        return self._public_status(receipt, identifier, fenced)
                result = (self._verify_local_status(receipt, rpc('status', **local, job=recovered['job']))
                          if recovered else {'state': 'SUBMISSION_UNCONFIRMED'})
            else:
                try:
                    observed = self.remote(host, 'status', {'request_id': identifier})
                except RemoteRefusal as error:
                    if error.code == 'NOT_FOUND' and self._remote_fence_due(receipt):
                        fenced = self._fence_remote(receipt, path, host)
                        if fenced is not None:
                            return self._public_status(receipt, identifier, fenced)
                    raise
                result = self._verify_remote_status(receipt, observed)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            result = {'state': 'UNKNOWN', 'cleanup': 'UNCONFIRMED', 'error': str(error)}
        if result.get('state') == 'FINISHED':
            previous = receipt.get('last_status') or {}
            outcome = result.get('outcome')
            stamp = receipt.get('terminal_observation')
            legacy = not stamp and previous.get('state') == 'FINISHED' and previous.get('outcome') == outcome
            observed = self._terminal_time(receipt, path) if legacy else time.time()
            self._remember_terminal(receipt, result, observed)
        elif result.get('state') in {'RUNNING', 'STARTING', 'ACCEPTED', 'QUEUED', 'DISPATCHING', 'CLEANING'}:
            receipt.pop('terminal_observation', None)
        receipt['last_status'] = result
        if result.get('state') in {'RUNNING', 'STARTING', 'FINISHED', 'ACCEPTED', 'QUEUED', 'DISPATCHING', 'CLEANING'}:
            receipt['state'] = 'SUBMITTED'
        elif result.get('state') in {'UNKNOWN', 'SUBMISSION_UNCONFIRMED', 'NOT_FOUND'}:
            if (receipt.get('terminal_observation') or {}).get('cleanup') != 'CONFIRMED':
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
    gc = sub.add_parser('gc', help='reclaim reproducible remote copies of collected finished jobs '
                                   '(dry run unless --execute)')
    gc.add_argument('--host', required=True)
    gc.add_argument('--execute', action='store_true')
    deploy = sub.add_parser('deploy', help="install this coordinator's committed agent runtime on an idle remote "
                                           'host (dry run unless --execute)')
    deploy.add_argument('--host', required=True)
    deploy.add_argument('--execute', action='store_true')
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
    elif args.command == 'deploy':
        value = pool.deploy_runtime(args.host, execute=args.execute)
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
