#!/usr/bin/env python3
"""Exercise a staged package marker through the fixed, isolated release route.

This is a functional check, not a promotion, timing, physical-radio, display or
audio-output measurement. It writes only new private case directories and
never writes the marker beside the source bundle.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import uuid
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

MODES = ('missing', 'malformed', 'candidate', 'reference')
PREFIX = 'PACKAGE_DEFAULT_PROBE '
CASE_PREFIX = 'openrc-package-default-probe-'
SELECTION = {'aircraft': 'jensen-das-ugly-stik-60', 'battery': 'ideal',
             'start': 'airborne', 'weather': 'calm', 'soft_hull': True,
             'trim_profile': 'production'}
SEED = '''[meta]
schema=1

[ui]
first_flight_hint_seen=true

[updates]
check=false

[flight]
aircraft="jensen-das-ugly-stik-60"
battery_mode="ideal"
start_choice="airborne"
weather_config={"format":"openrc-weather v1","speed_mps":0.0,"from_deg":0.0,"gust_mps":0.0,"gust_up_mps":0.0,"gust_duration_s":4.0,"gust_period_s":12.0,"gust_delay_s":2.0}
'''.encode('utf-8')
SHA = re.compile(r'[0-9a-f]{64}\Z')
MAX_JSON = 4 * 1024 * 1024


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_regular(path: Path, maximum: int = MAX_JSON) -> bytes:
    require(not path.is_symlink() and path.is_file(), 'missing or redirected file: ' + str(path))
    before = path.stat()
    require(0 < before.st_size <= maximum, 'empty or oversized file: ' + str(path))
    data = path.read_bytes()
    after = path.stat()
    require((before.st_size, before.st_mtime_ns, before.st_ino) ==
            (after.st_size, after.st_mtime_ns, after.st_ino) and len(data) == before.st_size,
            'file changed while reading: ' + str(path))
    return data


def object_from(data: bytes) -> dict[str, Any]:
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            require(key not in result, 'duplicate JSON key: ' + key)
            result[key] = value
        return result
    def invalid(value: str) -> None:
        raise ValueError('non-finite JSON number: ' + value)
    result = json.loads(data, object_pairs_hook=unique, parse_constant=invalid)
    require(isinstance(result, dict), 'JSON root must be an object')
    return result


def no_links(path: Path) -> None:
    """Reject every existing symlink or special path component, without resolving it."""
    require(path.is_absolute() and path == Path(os.path.normpath(path)), 'path must be absolute and normalized')
    current = Path(path.anchor)
    for name in path.parts[1:]:
        current = current / name
        info = current.lstat()
        require(not stat.S_ISLNK(info.st_mode) and (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)),
                'path contains a symlink or special file: ' + str(current))


def chosen_selection(marker: Any) -> dict[str, Any]:
    require(isinstance(marker, dict) and marker.get('format') == 'openrc-macos-native-package-default v2'
            and marker.get('scope') == 'package-macos-arm64' and isinstance(marker.get('allowed_selections'), list),
            'candidate marker is malformed')
    rows = [row for row in marker['allowed_selections'] if isinstance(row, dict)
            and all(type(row.get(key)) is type(value) and row[key] == value for key, value in SELECTION.items())]
    require(len(rows) == 1 and set(rows[0]) == set(SELECTION) | {'start_sha256'}
            and isinstance(rows[0].get('start_sha256'), str) and SHA.fullmatch(rows[0]['start_sha256']),
            'candidate does not contain one exact fixed Home selection')
    return rows[0]


def observed_fallback_selection(observation: Any) -> dict[str, Any]:
    """Take the first real Home selection, then require it unchanged in both cases."""
    require(isinstance(observation, dict) and isinstance(observation.get('phases'), list),
            'fallback observation has no lifecycle')
    flights = [row for row in observation['phases'] if isinstance(row, dict) and row.get('phase') == 'flight']
    require(len(flights) == 1 and isinstance(flights[0].get('selection'), dict),
            'fallback observation lacks one actual screened selection')
    return chosen_selection({'format': 'openrc-macos-native-package-default v2', 'scope': 'package-macos-arm64',
                             'allowed_selections': [flights[0]['selection']]})


def verify_observation(observation: Any, mode: str, *, executable: Path, task_home: Path, token_sha: str,
                       marker_sha: str, selection: dict[str, Any], reference: dict[str, Any],
                       native: dict[str, Any]) -> None:
    require(mode in MODES and isinstance(observation, dict) and observation.get('verdict') == 'pass'
            and observation.get('reason') == '' and observation.get('mode') == mode
            and type(observation.get('pid')) is int and observation['pid'] > 0,
            'fixed package probe did not report success')
    user_dir = task_home / 'Library/Application Support/Godot/app_userdata/OpenRC Simulator'
    require(observation.get('executable') == str(executable) and observation.get('profile_home') == str(task_home)
            and observation.get('user_directory') == str(user_dir) and observation.get('profile_token_sha256') == token_sha
            and observation.get('marker_sha256') == marker_sha
            and isinstance(observation.get('audio_driver'), str) and observation['audio_driver'] not in ('', 'Dummy'),
            'package route, isolated user directory, marker or active audio driver differs')
    identity = observation.get('package_identity')
    require(isinstance(identity, dict) and identity.get('ok') is True and identity.get('reason') == ''
            and all(identity.get(key) == native.get(key) for key in
                    ('kind', 'sha256', 'receipt_sha256', 'reference_receipt_sha256', 'manifest_sha256',
                     'library_sha256', 'descriptor_sha256'))
            and isinstance(identity.get('reference_identity'), dict) and identity['reference_identity'].get('ok') is True
            and all(identity['reference_identity'].get(key) == reference.get(key) for key in
                    ('kind', 'sha256', 'receipt_sha256', 'executable_sha256', 'pack_sha256', 'probe_sha256', 'architecture'))
            and identity.get('library_path') == str(executable.parents[2] / 'Contents/Frameworks/libopenrc_native_kernel.dylib')
            and identity.get('descriptor_path') == str(executable.parents[2] / 'Contents/Resources/openrc_native_kernel_macos.gdextension'),
            'probe did not inspect the exact cloned package')
    phases = observation.get('phases')
    expected = ['flight', 'menu_audio_retired'] if mode == 'reference' else [
        'home', 'flight', 'pause', 'restart', 'returned_home', 'reentry', 'menu_audio_retired']
    require(isinstance(phases, list) and all(isinstance(row, dict) for row in phases)
            and [row.get('phase') for row in phases] == expected, 'package Home lifecycle is incomplete')
    if mode != 'reference':
        require(phases[0].get('aircraft') == SELECTION['aircraft'] and phases[0].get('menu_audio') is True
                and phases[2].get('paused') is True, 'Home or pause did not enter the expected state')
    for row in phases:
        if row.get('phase') not in ('flight', 'restart', 'reentry'):
            continue
        backend = 'native' if mode == 'candidate' else 'gdscript_reference'
        status = row.get('status')
        require(row.get('backend') == backend and type(row.get('tick')) is int and row['tick'] > 0
                and row.get('soundscape_installed') is True and isinstance(status, dict)
                and isinstance(status.get('identity'), dict) and status['identity'].get('backend') == backend
                and status.get('requested') == ('gdscript_reference' if mode == 'reference' else 'native'),
                'flight backend or active simulation did not match the case')
        reason = status.get('reason')
        require(isinstance(reason, str) and (('qualification' in reason) if mode in ('missing', 'malformed')
                                            else reason == ''), 'unexpected backend refusal')
        if mode != 'reference':
            require(row.get('selection') == selection, 'automatic case used a different production selection')
        if mode == 'candidate':
            stats = row.get('native_stats')
            require(isinstance(stats, dict) and type(stats.get('context_calls')) is int and stats['context_calls'] >= 1
                    and type(stats.get('stage_calls')) is int and stats['stage_calls'] >= 4,
                    'candidate did not run native stage calls')
    audio = phases[-1].get('receipt')
    require(isinstance(audio, dict) and audio.get('complete') is True and audio.get('timed_out') is False
            and type(audio.get('pending_playbacks')) is int and audio['pending_playbacks'] == 0,
            'menu audio retirement did not complete')


def child_environment(task_home: Path, mode: str, marker_sha: str, token_sha: str) -> dict[str, str]:
    env = {name: value for name, value in os.environ.items()
           if not name.startswith(('OPENRC_', 'GODOT_', '__GODOT_', 'MTL_', 'METAL_', 'DYLD_', 'LD_', 'GIT_'))
           and name not in ('PYTHONPATH', 'PYTHONHOME', 'PYTHONSTARTUP')}
    # Inherited admission is verified by the existing checked runner. Never
    # invent an enrollment/context or change the parent process environment.
    for name in ('OPENRC_TESTQUEUE_ROOT', 'OPENRC_TESTQUEUE_CONTEXT'):
        if name in os.environ:
            env[name] = os.environ[name]
    env.update({'HOME': str(task_home), 'OPENRC_PACKAGE_DEFAULT_PROBE': '1',
                'OPENRC_PACKAGE_DEFAULT_PROBE_MODE': mode,
                'OPENRC_PACKAGE_DEFAULT_EXPECT_MARKER_SHA256': marker_sha,
                'OPENRC_PACKAGE_DEFAULT_PROFILE_TOKEN_SHA256': token_sha,
                'OPENRC_PACKAGE_DEFAULT_EXPECT_USER_DIR': str(task_home / 'Library/Application Support/Godot/app_userdata/OpenRC Simulator'),
                'PYTHONDONTWRITEBYTECODE': '1', 'PYTHONNOUSERSITE': '1'})
    return env


def checked_result(directory: Path, expected_command: list[str]) -> tuple[dict[str, Any], bytes, dict[str, Any]]:
    entries = list(directory.iterdir())
    require(len(entries) == 1 and entries[0].is_dir() and not entries[0].is_symlink(),
            'checked runner did not retain exactly one invocation')
    report_path, log_path = entries[0] / 'report.json', entries[0] / 'engine.log'
    report_data, log_data = read_regular(report_path), read_regular(log_path, 16 * 1024 * 1024)
    report = object_from(report_data)
    require(report.get('format') == 'openrc-godot-check v1' and report.get('complete') is True
            and report.get('ok') is True and report.get('process_exit') == 0 and report.get('reason') == 'passed'
            and report.get('warnings_as_errors') is True and report.get('command') == expected_command
            and report.get('report') == str(report_path) and report.get('log') == str(log_path)
            and report.get('log_sha256') == digest(log_data) and report.get('counts') == {'error': 0, 'warning': 0},
            'checked invocation, command or diagnostics failed')
    require(not re.search(rb'ObjectDB instances leaked|resources? still in use|Leaked instance', log_data, re.I),
            'checked log reports retained objects or resources')
    records = [line[len(PREFIX):] for line in log_data.decode('utf-8', errors='strict').splitlines()
               if line.startswith(PREFIX)]
    require(len(records) == 1, 'fixed probe must emit exactly one terminal result')
    return report, log_data, object_from(records[0].encode('utf-8'))


def write_new(path: Path, data: bytes) -> None:
    with path.open('xb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def _load_receipt_module() -> Any:
    path = ROOT / 'tools/release/macos_reference_receipt.py'
    spec = importlib.util.spec_from_file_location('package_default_reference_receipt', path)
    require(spec is not None and spec.loader is not None, 'cannot load package receipt reader')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _signature(bundle: Path) -> None:
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)], check=True,
                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)


def verify_home_proof(path: Path, executable: Path, candidate: Path, candidate_sha256: str) -> dict[str, Any]:
    """Reread the four raw checked cases; a summary alone is not evidence."""
    for value in (path, executable, candidate):
        no_links(value)
    proof_data, marker_data = read_regular(path), read_regular(candidate)
    require(SHA.fullmatch(candidate_sha256) is not None and digest(marker_data) == candidate_sha256,
            'candidate marker differs from its selected bytes')
    marker = object_from(marker_data)
    selection = chosen_selection(marker)
    proof = object_from(proof_data)
    receipts = _load_receipt_module()
    original_bundle = receipts.bundle_from_executable(executable)
    reference, native = receipts.verify(executable, 'arm64'), receipts.verify_native(executable, 'arm64')
    _signature(original_bundle)
    cases = proof.get('cases')
    require(proof.get('format') == 'openrc-package-default-home-proof v1' and proof.get('status') == 'passed'
            and proof.get('candidate_sha256') == candidate_sha256 and proof.get('selection') == selection
            and proof.get('reference') == reference and proof.get('native') == native
            and isinstance(cases, list) and len(cases) == len(MODES)
            and all(isinstance(row, dict) for row in cases)
            and [row.get('mode') for row in cases] == list(MODES), 'Home proof envelope differs')
    pids, capture_ids = set(), set()
    for mode, row in zip(MODES, cases):
        require(isinstance(row.get('case'), str), 'Home case location is missing')
        case = Path(row['case'])
        require(case.parent == path.parent and case.name.startswith(CASE_PREFIX)
                and re.fullmatch(r'[0-9a-f]{32}', case.name.removeprefix(CASE_PREFIX)) is not None,
                'Home case is outside the fixed private proof directory')
        no_links(case)
        task_home = case / 'private-home'
        user_dir = task_home / 'Library/Application Support/Godot/app_userdata/OpenRC Simulator'
        no_links(user_dir)
        token_sha = digest(read_regular(task_home / '.openrc-package-default-profile'))
        bundle = case / original_bundle.name
        clone_executable = bundle / executable.relative_to(original_bundle)
        no_links(clone_executable)
        expected_marker = b'{' if mode == 'malformed' else marker_data if mode in ('candidate', 'reference') else b''
        marker_path = bundle.with_name(bundle.name + '.openrc-native-default')
        require(not marker_path.is_symlink()
                and (not marker_path.exists() if mode == 'missing' else read_regular(marker_path) == expected_marker)
                and receipts.verify(clone_executable, 'arm64') == reference
                and receipts.verify_native(clone_executable, 'arm64') == native,
                'Home case marker or package differs')
        _signature(bundle)
        command = [str(clone_executable), '--rendering-method', 'forward_plus', '--rendering-driver', 'metal']
        if mode == 'reference':
            command += ['--', '--quick-flight', '--physics-backend=gdscript_reference']
        no_links(case / 'checked')
        checked, log, observation = checked_result(case / 'checked', command)
        verify_observation(observation, mode, executable=clone_executable, task_home=task_home,
                           token_sha=token_sha, marker_sha=digest(expected_marker) if expected_marker else '',
                           selection=selection, reference=reference, native=native)
        require(row.get('observation') == observation and row.get('pid') == observation['pid']
                and row.get('checked_report') == checked['report']
                and row.get('checked_sha256') == digest(read_regular(Path(checked['report'])))
                and row.get('engine_log_sha256') == digest(log), 'Home case was changed after capture')
        pid, capture = observation['pid'], checked.get('capture_id')
        require(pid not in pids and isinstance(capture, str) and capture and capture not in capture_ids,
                'Home cases reused a process or checked invocation')
        pids.add(pid)
        capture_ids.add(capture)
    require(read_regular(path) == proof_data and read_regular(candidate) == marker_data
            and receipts.verify(executable, 'arm64') == reference
            and receipts.verify_native(executable, 'arm64') == native, 'Home proof or original package changed')
    _signature(original_bundle)
    return {'sha256': digest(proof_data), 'selection': selection, 'cases': len(cases),
            'scope': 'four separate checked package processes; menu retirement and clean checked logs only'}


def run(args: argparse.Namespace) -> dict[str, Any]:
    from tools.testqueue.common import require_exclusive
    require(sys.platform == 'darwin' and not sys.flags.optimize, 'this functional probe requires unoptimized macOS Python')
    require_exclusive('rendered')
    executable, candidate, out = args.executable, args.candidate, args.out
    fallback_only = args.fallback_only
    require(type(fallback_only) is bool and
            ((fallback_only and candidate is None and args.candidate_sha256 is None) or
             (not fallback_only and candidate is not None and args.candidate_sha256 is not None)),
            'provide a candidate and its SHA, or select fallback-only without a candidate')
    no_links(executable)
    no_links(out.parent)
    require(not out.exists() and not out.is_symlink(), 'output must be a fresh directory')
    marker_data = b''
    selection = None
    modes = ('missing', 'malformed') if fallback_only else MODES
    if not fallback_only:
        no_links(candidate)
        marker_data = read_regular(candidate)
        require(SHA.fullmatch(args.candidate_sha256) is not None and digest(marker_data) == args.candidate_sha256,
                'candidate bytes differ from the independent pin')
        selection = chosen_selection(object_from(marker_data))
    receipts = _load_receipt_module()
    original_bundle = receipts.bundle_from_executable(executable)
    no_links(original_bundle)
    reference, native = receipts.verify(executable, 'arm64'), receipts.verify_native(executable, 'arm64')
    _signature(original_bundle)
    out.mkdir(mode=0o700)
    no_links(out)
    rows = []
    capture_ids = set()
    for mode in modes:
        case = out / (CASE_PREFIX + uuid.uuid4().hex)
        case.mkdir(mode=0o700)
        task_home = case / 'private-home'
        task_home.mkdir(mode=0o700)
        user_dir = task_home / 'Library/Application Support/Godot/app_userdata/OpenRC Simulator'
        user_dir.mkdir(parents=True, mode=0o700)
        no_links(user_dir)
        token = uuid.uuid4().hex.encode('ascii')
        write_new(task_home / '.openrc-package-default-profile', token)
        write_new(user_dir / 'settings.cfg', SEED)
        bundle = case / original_bundle.name
        # APFS clonefile copy avoids four full physical copies where supported;
        # cp failure is fatal and never falls back to an unverified source path.
        subprocess.run(['/bin/cp', '-cR', str(original_bundle), str(bundle)], check=True,
                       stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
        clone_executable = bundle / executable.relative_to(original_bundle)
        no_links(clone_executable)
        for suffix in (receipts.SUFFIX, receipts.NATIVE_SUFFIX):
            source = original_bundle.with_name(original_bundle.name + suffix)
            target = bundle.with_name(bundle.name + suffix)
            write_new(target, read_regular(source))
        marker_path = bundle.with_name(bundle.name + '.openrc-native-default')
        mode_marker = b'{' if mode == 'malformed' else marker_data if mode in ('candidate', 'reference') else b''
        if mode_marker:
            write_new(marker_path, mode_marker)
        mode_hash = digest(mode_marker) if mode_marker else ''
        require(receipts.verify(clone_executable, 'arm64') == reference
                and receipts.verify_native(clone_executable, 'arm64') == native,
                'cloned bundle differs from the independently checked package')
        _signature(bundle)
        command = [str(clone_executable), '--rendering-method', 'forward_plus', '--rendering-driver', 'metal']
        if mode == 'reference':
            command += ['--', '--quick-flight', '--physics-backend=gdscript_reference']
        checked_dir = case / 'checked'
        invocation = [sys.executable, '-B', str(ROOT / 'tools/godot/run_checked.py'), '--out-dir', str(checked_dir),
                      '--label', 'package-default-' + mode, '--timeout', '1200', '--warnings-as-errors',
                      '--require-text', PREFIX, '--', *command]
        with (case / 'runner.log').open('xb') as stream:
            result = subprocess.run(invocation, env=child_environment(task_home, mode, mode_hash, digest(token)),
                                    cwd=case, stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT)
        require(result.returncode == 0, 'checked package case failed: ' + mode)
        checked, log, observation = checked_result(checked_dir, command)
        capture = checked.get('capture_id')
        require(isinstance(capture, str) and capture and capture not in capture_ids,
                'checked package cases reused or omitted a capture ID')
        capture_ids.add(capture)
        if fallback_only and selection is None:
            selection = observed_fallback_selection(observation)
        verify_observation(observation, mode, executable=clone_executable, task_home=task_home,
                           token_sha=digest(token), marker_sha=mode_hash, selection=selection,
                           reference=reference, native=native)
        no_links(user_dir)
        require(not marker_path.is_symlink()
                and (not marker_path.exists() if mode == 'missing' else read_regular(marker_path) == mode_marker)
                and receipts.verify(clone_executable, 'arm64') == reference
                and receipts.verify_native(clone_executable, 'arm64') == native,
                'cloned marker or bundle changed during the case')
        _signature(bundle)
        rows.append({'mode': mode, 'case': str(case), 'pid': observation['pid'],
                     'checked_report': checked['report'], 'checked_sha256': digest(read_regular(Path(checked['report']))),
                     'engine_log_sha256': digest(log), 'observation': observation})
        write_new(case / 'case-receipt.json', (json.dumps(rows[-1], sort_keys=True, allow_nan=False) + '\n').encode())
    require(len({row['pid'] for row in rows}) == len(modes), 'process IDs are missing or reused')
    require((fallback_only or read_regular(candidate) == marker_data) and receipts.verify(executable, 'arm64') == reference
            and receipts.verify_native(executable, 'arm64') == native, 'original candidate or package changed')
    _signature(original_bundle)
    if fallback_only:
        return {'format': 'openrc-package-default-fallback-smoke v1', 'status': 'passed',
                'selection': selection, 'reference': reference, 'native': native, 'cases': rows,
                'scope': 'missing/malformed marker Home fallback only; not a candidate or promotion proof'}
    return {'format': 'openrc-package-default-home-proof v1', 'status': 'passed',
            'candidate_sha256': digest(marker_data), 'selection': selection, 'reference': reference, 'native': native,
            'cases': rows, 'scope': 'isolated rendered AppRoot lifecycle; no physical radio, scanout or performance proof'}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--candidate-sha256')
    parser.add_argument('--fallback-only', action='store_true', help='run missing/malformed Home fallback without a candidate')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    try:
        proof = run(args)
        output = args.out / ('fallback-smoke.json' if args.fallback_only else 'home-proof.json')
        write_new(output, (json.dumps(proof, sort_keys=True, indent=2, allow_nan=False) + '\n').encode())
        print(json.dumps({'status': 'passed', 'home_proof': str(output), 'sha256': digest(read_regular(output))}))
        return 0
    except (OSError, ValueError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print('package default Home probe refused: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
