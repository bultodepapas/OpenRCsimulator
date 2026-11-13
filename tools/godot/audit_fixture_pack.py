"""Pack the qualified typed publication captures; refuses unreviewed differences."""
import argparse
import base64
import copy
import gzip
import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path

if not __debug__:
    raise SystemExit('Fixture packing requires Python assertions; do not use -O or PYTHONOPTIMIZE')

ROOT = Path('.')
REFERENCE = '8ebb252acc341a5a1fc047e6bb931fabdb17b148'
CANDIDATE = '75299d6869f0b80f955574ddda8ba95f4b4915f4'
SCRIPTS = [
    'physics/aero.gd', 'physics/propulsion.gd', 'physics/math3d.gd',
    'physics/rigid_body.gd', 'physics/aircraft_data.gd', 'physics/wheel_profiles.gd',
    'physics/wind_config.gd', 'physics/electric_battery_step.gd', 'physics/electric_stop.gd',
    'physics/event_bracket.gd', 'sim/flight_session.gd', 'sim/electric_contact_step.gd',
    'sim/simulation.gd', 'sim/vehicle_model.gd',
]
DATA = [
    'data/aircraft/jensen_ugly_stik_60.json', 'data/aircraft/p51d_mustang_120.json',
    'data/fuels/openrc-fuel-registry.json', 'data/ground/wheel_profiles.json',
]
ENGINE2 = 'cafc17a192acf67903910a68aeb3c076c0907a4b'
ENGINE1 = '4d10419cacd6d3009976e8f9fd3abd970fd58018'
OVERLAYS = {
    'sim/flight_session.gd': '9b93be96e64e7c8ff425a177fb1590c9032d1de6b2bd6f536fb6a7d836a098cc',
    'sim/electric_contact_step.gd': 'ef6bf63bd3babd77e44b11deb4e06070885bbdc6c3a7a3913b8e315955213b76',
}

# The v4 requalification keeps the original family snapshots and allows only the
# declared aero-law identity change at each of the previously captured endpoints.
V4_PRIOR_FIXTURE = 'a57dc4c7a8b5687b59fcb4886b6a1235a22a32f96bc5e5cfe37b35a347001c4a'
V4_PRIOR_COMMIT = '630c8a5d7e3a89d22176b256bba47a38a56e3413'
V4_CANDIDATE = 'd1806cc26fd180d196a98370a01d06ad1592f5ba'
V4_OLD_LAW = 'section-plane-source-weighted-wake-velocity-v3'
V4_NEW_LAW = 'section-plane-source-weighted-wake-velocity-v4'
V4_SOURCE_PINS = {
    'physics/aero.gd': 'c0141d609c9e12866dba457c04a412a5609c0ca637222d2057e71771b522ebb8',
    'physics/aircraft_data.gd': 'ae2ced8856cdd9f1fd478db60e7b69f9e7d06465cf53c56be3dd158896a75358',
    'physics/wing_polar.gd': '0bac361ded5d5276464121c531dcd21f4b5168ee91d1656382821376d105cf56',
}
V4_PRIOR_WING_POLAR = '5ad827fb1726a935a49c3adb6691dd4a7f652996d5f11e053eaebe6752cf79ff'
V4_EVIDENCE = {
    ('windows', 'weather'): ('c4c77958e6918ebbb618765412f7019b5f60228e11eecd65d8e07dd8be4acf2f', '486dde6965fe8f8284dd502d3cde5ca4fe70e90590053cc9102e48b1a3d5bd18', '3216a78c4a16e601535617c0aa32299040c9e4df785b0ca707bcd01f4cc27ec2'),
    ('windows', 'shaft'): ('1f700c3de4a660093f378c84a9c23e5580414ded4fea3533a79b3339a3c001fc', 'b0b7a8c1962d42b763ece51e7fddcba7a3a06a6c9af941480e0d920930ab4440', '29ba854921941985f7894d8dcbad22e7c2d5e69bc5b40604ad58b243e49dcfc0'),
    ('linux', 'weather'): ('0a0784cf5bd1f51ad89f10bf0fd4d8ca73cb5f3778a638251dfa326b0589c11c', 'bdf1ca4517ab62bbedef15f9c577d7ee33e6550244ea92718199f8532c9a28ac', '3049057a2746e265aa616f7764c8027a7d35fe27fea6cb6ef3f8b215158c73f4'),
    ('linux', 'shaft'): ('d05ce2655fcf0a673ce7555ad09f58209dee88d83b26d86502cf0f9556ac6dac', '8fd77590d5ac162777f305530cfe0390fd51187c515f26304bdd0c28f7943456', '8d2c62e91d9477b207d8cd6527d8a3ee138654b94a0aa8b8d0ba27710a138705'),
}
V4_PAIRS_SHA256 = '097a50dd2111e6ce24fc7f171fa01b59c0b84c87e6126399c08c273a304c2fa0'

# The next rebind preserves the complete current pack. It admits only a changed
# Session source after both retained platform captures reproduce exactly.
SOURCE_REBIND_PRIOR = '842bfddfbbdd677114b9e4d9a9c74da5a06961c76c0a6e52a7bf3fb32cf5f86f'
SOURCE_REBIND_BASE = '676be5351357c981d6500b17569aa38615a0c8cb'
SOURCE_REBIND_SESSION = 'sim/flight_session.gd'
SOURCE_REBIND_ENGINES = {
    'Windows': '1a470886fc810b81a61e01bad7678e38989f1c94cf8e9733bfd1026224b3f42b',
    'Linux': '34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564',
}
SOURCE_REBIND_EXECUTABLES = {
    'Windows': '9d735a72c1a06bf42379829257b0bf966a6cf0ea507c6d8efa051bcfc8faccf2',
    'Linux': SOURCE_REBIND_ENGINES['Linux'],
}


def load(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def frames(case):
    result = [bytes.fromhex(value) for value in case['frames']]
    assert len(result) == 25 and all(result)
    assert digest(b''.join(result)) == case['sha256']
    return result


def values(diff, case, field):
    rows = [d for d in diff['differences'] if d['path'] == [case, 0, field]]
    assert len(rows) == 1 and rows[0]['left_type'] == rows[0]['right_type'] == 'String'
    return rows[0]['left_text'], rows[0]['right_text']


def pack(items):
    raw = b''.join(struct.pack('<I', len(item)) + item for item in items)
    compressed = gzip.compress(raw, compresslevel=9, mtime=0)
    assert gzip.decompress(compressed) == raw
    return base64.b64encode(compressed).decode('ascii')


def source_rebind_git_bytes(repo, commit, path, mode):
    blob = subprocess.check_output(['git', 'show', commit + ':app/' + path], cwd=repo)
    if mode == 'script-lf':
        return blob.replace(b'\r\n', b'\n')
    if mode != 'exact':
        raise ValueError('unsupported source pin mode: ' + path)
    attr = subprocess.check_output(['git', 'check-attr', '--source', commit, 'eol',
                                    '--', 'app/' + path], cwd=repo, text=True).strip().rsplit(': ', 1)[-1]
    if attr == 'crlf':
        if b'\r\n' in blob:
            raise ValueError('noncanonical Git blob: ' + path)
        blob = blob.replace(b'\n', b'\r\n')
    return blob


def source_rebind_git_normalized(repo, commit, path):
    blob = subprocess.check_output(['git', 'show', commit + ':' + path], cwd=repo)
    return blob.replace(b'\r\n', b'\n')


def _rebind_artifact(directory, relative):
    if not isinstance(relative, str) or not relative or '\\' in relative:
        raise ValueError('invalid rebind artifact path')
    path = Path(relative)
    if path.is_absolute() or any(part in ('', '.', '..') for part in path.parts):
        raise ValueError('invalid rebind artifact path')
    resolved = (directory / path).resolve()
    if not resolved.is_relative_to(directory.resolve()) or not resolved.is_file():
        raise ValueError('missing or escaped rebind artifact: ' + relative)
    return resolved.read_bytes()


def _rebind_hex(value, length=64):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{%d}' % length, value) is not None


def _rebind_command_path(value, platform):
    if not isinstance(value, str) or not value:
        raise ValueError('missing checked command path')
    value = value.replace('\\', '/')
    return value.casefold() if platform == 'Windows' else value


def source_rebind_tree(repo, commit):
    raw = subprocess.check_output(['git', 'ls-tree', '-rz', '--full-tree', commit, '--', 'app'], cwd=repo)
    tree = {}
    for row in raw.split(b'\0'):
        if not row:
            continue
        metadata, name = row.split(b'\t', 1)
        mode, kind, oid = metadata.decode('ascii').split()
        path = name.decode('utf-8')
        if (kind != 'blob' or mode not in ('100644', '100755') or not _rebind_hex(oid, 40)
                or not path.startswith('app/') or path in tree):
            raise ValueError('unsupported or duplicate committed app entry')
        tree[path] = {'git_blob': oid, 'mode': mode}
    if not tree:
        raise ValueError('committed app inventory is empty')
    return tree


def source_rebind_inventory(raw, commit, tree, pinned_bytes, pins, attributes_sha256):
    inventory = json.loads(raw)
    if (not isinstance(inventory, dict) or set(inventory) != {'format', 'commit', 'files', 'attributes_sha256'}
            or inventory['format'] != 'openrc-publication-source-inventory-v1' or inventory['commit'] != commit
            or inventory['attributes_sha256'] != attributes_sha256
            or not isinstance(inventory['files'], dict) or set(inventory['files']) != set(tree)):
        raise ValueError('source inventory does not cover the committed app')
    for path, entry in inventory['files'].items():
        if (not isinstance(entry, dict) or set(entry) != {'git_blob', 'mode', 'sha256', 'size'}
                or entry['git_blob'] != tree[path]['git_blob'] or entry['mode'] != tree[path]['mode']
                or not _rebind_hex(entry['sha256']) or type(entry['size']) is not int or entry['size'] < 0):
            raise ValueError('source inventory entry differs: ' + path)
    for path, expected in pinned_bytes.items():
        item = inventory['files'].get('app/' + path)
        if item is None:
            raise ValueError('source inventory omits pinned file: ' + path)
        allowed = [expected]
        if pins[path]['mode'] == 'script-lf':
            allowed.append(expected.replace(b'\n', b'\r\n'))
        if not any(item['sha256'] == digest(data) and item['size'] == len(data) for data in allowed):
            raise ValueError('source inventory does not match pinned bytes: ' + path)


def source_rebind_capture(raw, expected, platform, family, prior):
    if digest(raw) != expected:
        raise ValueError(f'{platform} {family}: retained capture differs')
    capture = json.loads(raw)
    cases = prior['families'][family][platform]
    if (capture.get('format') != f'ci-audit-{family}-capture-v1' or capture.get('os') != platform
            or capture.get('engine', {}).get('hash') != ENGINE2 or set(capture.get('cases', {})) != set(cases)):
        raise ValueError(f'{platform} {family}: capture identity or roster differs')
    for name, item in capture['cases'].items():
        fixture = cases[name]
        try:
            frames = [bytes.fromhex(value) for value in item['frames']]
            events = [bytes.fromhex(value) for value in item['events']]
            bytes.fromhex(item['configuration'])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f'{platform} {family} {name}: malformed typed capture') from error
        if (len(frames) != 25 or len(events) != 25 or not all(frames) or not all(events)
                or digest(b''.join(frames)) != item.get('sha256')
                or item['sha256'] != fixture['current_sha256']
                or digest(b''.join(events)) != fixture['events_sha256']):
            raise ValueError(f'{platform} {family} {name}: typed frames or events differ')


def source_rebind_report(raw, log, platform, family, run):
    report = json.loads(raw)
    if (report.get('format') != 'openrc-godot-check v1' or report.get('ok') is not True
            or report.get('complete') is not True or type(report.get('process_exit')) is not int
            or report.get('process_exit') != 0 or type(report.get('exit_code')) is not int
            or report.get('exit_code') != 0 or report.get('reason') != 'passed'
            or report.get('warnings_as_errors') is not True or report.get('counts') != {'error': 0, 'warning': 0}
            or report.get('missing_required_text') != [] or report.get('log_sha256') != digest(log)):
        raise ValueError(f'{platform} {family}: checked report is incomplete or failed')
    marker = f'CI_AUDIT_{family.upper()}_CAPTURE'
    count = 2 if family == 'shaft' else 4
    checks = 55 if family == 'shaft' else 109
    text = log.decode('utf-8', errors='strict')
    lines = [line.strip() for line in text.splitlines() if line.startswith(marker)]
    if len(lines) != 1 or lines[0] != f'{marker} checks={checks} failures=0 cases={count}':
        raise ValueError(f'{platform} {family}: missing or ambiguous positive marker')
    command = report.get('command')
    if (not isinstance(command, list) or not all(isinstance(part, str) for part in command)
            or not command or '--path' not in command or command.count('--path') != 1
            or '--script' not in command or command.count('--script') != 1):
        raise ValueError(f'{platform} {family}: checked command is invalid')
    path_index, script_index = command.index('--path'), command.index('--script')
    if (path_index + 1 >= len(command) or script_index + 1 >= len(command)
            or _rebind_command_path(command[0], platform) != _rebind_command_path(run.get('engine_path'), platform)
            or _rebind_command_path(command[path_index + 1], platform) != _rebind_command_path(run.get('project_path'), platform)
            or not command[script_index + 1].replace('\\', '/').endswith(f'audit_fixture_{family}_capture.gd')):
        raise ValueError(f'{platform} {family}: checked command does not identify the declared inputs')
    engine = _rebind_command_path(run.get('engine_path'), platform)
    executable = _rebind_command_path(run.get('engine_executable'), platform)
    expected_executable = engine.removesuffix('_console.exe') + '.exe' if platform == 'Windows' and engine.endswith('_console.exe') else engine
    if executable != expected_executable:
        raise ValueError(f'{platform} {family}: process executable differs from the checked engine')
    identity = report.get('capture_id')
    if not isinstance(identity, str) or not identity:
        raise ValueError(f'{platform} {family}: missing checked capture identity')
    return identity


def rebind_source(capture_dir, prior_fixture, output, receipt_path, candidate):
    """Preserve all typed frames while binding a reviewed Session-only source change."""
    repo = Path(__file__).resolve().parents[2]
    if not _rebind_hex(candidate, 40) or candidate == SOURCE_REBIND_BASE:
        raise ValueError('candidate must identify a distinct committed source')
    raw = prior_fixture.read_bytes().replace(b'\r\n', b'\n')
    if digest(raw) != SOURCE_REBIND_PRIOR:
        raise ValueError('prior fixture identity differs')
    prior = json.loads(raw)
    pins = prior.get('source_pins')
    if (prior.get('format') != 'openrc-publication-bridge-v1' or prior.get('current_engine') != ENGINE2
            or prior.get('candidate_commit') != SOURCE_REBIND_BASE or not isinstance(pins, dict) or len(pins) != 19
            or not _rebind_hex(pins.get(SOURCE_REBIND_SESSION, {}).get('sha256'))
            or prior.get('candidate_overlays', {}).get(SOURCE_REBIND_SESSION) != pins[SOURCE_REBIND_SESSION]['sha256']):
        raise ValueError('prior fixture source contract differs')
    old_pins, new_pins, old_bytes, new_bytes = {}, {}, {}, {}
    for path, pin in pins.items():
        if not isinstance(path, str) or not isinstance(pin, dict) or set(pin) != {'mode', 'sha256'} or not _rebind_hex(pin['sha256']):
            raise ValueError('invalid source pin')
        old = source_rebind_git_bytes(repo, SOURCE_REBIND_BASE, path, pin['mode'])
        new = source_rebind_git_bytes(repo, candidate, path, pin['mode'])
        current = (repo / 'app' / path).read_bytes()
        if pin['mode'] == 'script-lf':
            current = current.replace(b'\r\n', b'\n')
        if digest(old) != pin['sha256'] or current != new:
            raise ValueError('baseline or current committed source differs: ' + path)
        old_pins[path], new_pins[path] = digest(old), digest(new)
        old_bytes[path], new_bytes[path] = old, new
        if path != SOURCE_REBIND_SESSION and old != new:
            raise ValueError('unexpected source change: ' + path)
    if old_pins[SOURCE_REBIND_SESSION] == new_pins[SOURCE_REBIND_SESSION]:
        raise ValueError('Session source is unchanged')
    attributes = {role: digest(source_rebind_git_normalized(repo, commit, '.gitattributes')) for role, commit in
                  (('baseline', SOURCE_REBIND_BASE), ('candidate', candidate))}
    script_sha = {}
    for family in ('shaft', 'weather'):
        path = f'tools/godot/audit_fixture_{family}_capture.gd'
        old, new = (source_rebind_git_normalized(repo, commit, path) for commit in (SOURCE_REBIND_BASE, candidate))
        if old != new or (repo / path).read_bytes().replace(b'\r\n', b'\n') != new:
            raise ValueError('capture script changed: ' + path)
        script_sha[family] = digest(new)
    runner_path = 'tools/godot/run_checked.py'
    runner = source_rebind_git_normalized(repo, candidate, runner_path)
    if (repo / runner_path).read_bytes().replace(b'\r\n', b'\n') != runner:
        raise ValueError('checked runner differs from candidate commit')
    runner_sha = digest(runner)
    observations, manifests, capture_ids = {}, {}, set()
    trees = {role: source_rebind_tree(repo, commit) for role, commit in
             (('baseline', SOURCE_REBIND_BASE), ('candidate', candidate))}
    for platform in ('Windows', 'Linux'):
        directory = capture_dir / platform.lower()
        manifest_bytes = (directory / 'manifest.json').read_bytes()
        manifests[platform.lower()] = digest(manifest_bytes)
        manifest = json.loads(manifest_bytes)
        runs = manifest.get('runs')
        expected_runs = {f'{role}-{family}' for role in ('baseline', 'candidate') for family in ('shaft', 'weather')}
        if (manifest.get('format') != 'openrc-publication-rebind-capture-v1' or manifest.get('platform') != platform
                or manifest.get('mode_validation') != ('git-index-only-windows' if platform == 'Windows' else 'git-and-posix-executable')
                or not isinstance(runs, dict) or set(runs) != expected_runs):
            raise ValueError(platform + ': capture manifest differs')
        seen_files, inventories, projects = set(), {}, {}
        for name in sorted(expected_runs):
            role, family = name.split('-')
            run = runs[name]
            if not isinstance(run, dict):
                raise ValueError(platform + ': malformed run')
            before, after = run.get('before'), run.get('after')
            expected_pins = old_pins if role == 'baseline' else new_pins
            expected_commit = SOURCE_REBIND_BASE if role == 'baseline' else candidate
            composition = {'kind': 'baseline-commit-v1' if role == 'baseline' else 'candidate-commit-v1',
                           'base_commit': expected_commit, 'overlay_commit': None,
                           'overlay_paths': [], 'overlay_tree_ids': {}}
            if (run.get('commit') != expected_commit or run.get('composition') != composition
                    or not isinstance(before, dict) or before != after
                    or set(before) != {'engine_sha256', 'engine_executable_sha256', 'source_inventory_sha256',
                                       'source_pins', 'capture_script_sha256', 'checked_runner_sha256'}
                    or before.get('engine_sha256') != SOURCE_REBIND_ENGINES[platform]
                    or before.get('engine_executable_sha256') != SOURCE_REBIND_EXECUTABLES[platform]
                    or before.get('capture_script_sha256') != script_sha[family]
                    or before.get('checked_runner_sha256') != runner_sha
                    or run.get('capture_script_sha256') != script_sha[family]
                    or run.get('checked_runner_sha256') != runner_sha
                    or not isinstance(run.get('engine_executable'), str) or not run['engine_executable']
                    or before.get('source_pins') != expected_pins or not _rebind_hex(before.get('source_inventory_sha256'))):
                raise ValueError(platform + ' ' + name + ': source or engine observation differs')
            project = _rebind_command_path(run.get('project_path'), platform)
            if role in inventories and (inventories[role] != before['source_inventory_sha256'] or projects[role] != project):
                raise ValueError(platform + ' ' + role + ': project changed between captures')
            inventories[role], projects[role] = before['source_inventory_sha256'], project
            paths = [run.get(key) for key in ('capture', 'report', 'log', 'inventory_before', 'inventory_after')]
            prefix = platform.lower() + '/'
            if (any(not isinstance(path, str) or not path.startswith(prefix) or path in seen_files for path in paths)
                    or len(set(paths)) != len(paths)):
                raise ValueError(platform + ': capture evidence paths are reused or missing')
            seen_files.update(paths)
            capture, report, log, inventory_before, inventory_after = (_rebind_artifact(capture_dir, path) for path in paths)
            if (inventory_before != inventory_after or digest(inventory_before) != before['source_inventory_sha256']):
                raise ValueError(platform + ' ' + name + ': source inventory changed or differs from its hash')
            source_rebind_inventory(inventory_before, expected_commit, trees[role],
                                    old_bytes if role == 'baseline' else new_bytes, pins, attributes[role])
            if any(run.get(key + '_sha256') != digest(data) for key, data in
                   (('capture', capture), ('report', report), ('log', log))):
                raise ValueError(platform + ' ' + name + ': retained artifact identity differs')
            expected_hash = V4_EVIDENCE[(platform.lower(), family)][1]
            source_rebind_capture(capture, expected_hash, platform, family, prior)
            capture_id = source_rebind_report(report, log, platform, family, run)
            if capture_id in capture_ids:
                raise ValueError('checked capture identity was reused')
            capture_ids.add(capture_id)
            observations[platform.lower() + '-' + name] = {
                'capture_sha256': digest(capture), 'checked_report_sha256': digest(report),
                'engine_log_sha256': digest(log), 'capture_id': capture_id,
                'source_inventory_sha256': before['source_inventory_sha256'], 'composition': composition,
                'engine_sha256': before['engine_sha256'], 'engine_executable_sha256': before['engine_executable_sha256'],
                'project_path': run['project_path'], 'capture': run['capture'], 'report': run['report'], 'log': run['log'],
            }
        if projects['baseline'] == projects['candidate']:
            raise ValueError(platform + ': baseline and candidate projects must be separate')
    updated = copy.deepcopy(prior)
    updated['candidate_commit'] = candidate
    updated['candidate_overlays'][SOURCE_REBIND_SESSION] = new_pins[SOURCE_REBIND_SESSION]
    updated['source_pins'][SOURCE_REBIND_SESSION]['sha256'] = new_pins[SOURCE_REBIND_SESSION]
    data = (json.dumps(updated, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')
    result = {'format': 'openrc-publication-source-requalification-v1', 'baseline_commit': SOURCE_REBIND_BASE,
              'candidate_commit': candidate, 'prior_fixture_sha256': SOURCE_REBIND_PRIOR,
              'candidate_fixture_sha256': digest(data), 'source_pin_changes': {SOURCE_REBIND_SESSION:
                  {'before': old_pins[SOURCE_REBIND_SESSION], 'after': new_pins[SOURCE_REBIND_SESSION]}},
              'capture_manifests_sha256': manifests, 'captures': observations,
              'preserved': ['families', 'reference_commit', 'requalification'],
              'scope': 'Collector-verified complete historical app baseline and committed candidate; '
                       '25 typed endpoints and event frames per case, not physical or general equivalence.'}
    if (output.resolve() == receipt_path.resolve() or output.exists() or receipt_path.exists()
            or not output.parent.is_dir() or not receipt_path.parent.is_dir()
            or output.resolve().is_relative_to((repo / 'app').resolve())
            or receipt_path.resolve().is_relative_to((repo / 'app').resolve())):
        raise ValueError('outputs must be distinct fresh paths outside app')
    with output.open('xb') as file:
        file.write(data)
    with receipt_path.open('x', encoding='utf-8', newline='\n') as file:
        json.dump(result, file, indent=2, sort_keys=True)
        file.write('\n')
    print(output, 'bytes=', len(data), 'sha256=', digest(data), 'verified_captures=', len(observations))


def requalify_v4(capture_dir, prior_fixture, output):
    """Admit only the fully observed v3-to-v4 identity substitution, never new goldens."""
    repo = Path(__file__).resolve().parents[2]
    raw = prior_fixture.read_bytes().replace(b'\r\n', b'\n')
    assert digest(raw) == V4_PRIOR_FIXTURE
    prior = json.loads(raw)
    assert prior['format'] == 'openrc-publication-bridge-v1' and prior['current_engine'] == ENGINE2
    assert len(prior['source_pins']) == 18 and 'physics/wing_polar.gd' not in prior['source_pins']
    updated = copy.deepcopy(prior)
    source_pins = copy.deepcopy(prior['source_pins'])
    for path, sha in V4_SOURCE_PINS.items():
        source_pins[path] = {'sha256': sha, 'mode': 'script-lf'}
    for path, pin in source_pins.items():
        actual = (repo / 'app' / path).read_bytes()
        committed = subprocess.check_output(['git', 'show', V4_CANDIDATE + ':app/' + path], cwd=repo)
        if pin['mode'] == 'script-lf':
            actual = actual.replace(b'\r\n', b'\n')
            committed = committed.replace(b'\r\n', b'\n')
        else:
            assert pin['mode'] == 'exact', path
            # Git blobs use LF even when the reviewed checkout is pinned to CRLF.
            attr = subprocess.check_output(['git', 'check-attr', '--source', V4_CANDIDATE, 'eol',
                                            '--', 'app/' + path], cwd=repo, text=True).strip().rsplit(': ', 1)[-1]
            if attr == 'crlf':
                assert b'\r\n' not in committed, path
                committed = committed.replace(b'\n', b'\r\n')
        assert actual == committed and digest(actual) == pin['sha256'], path
    prior_wing = subprocess.check_output(['git', 'show', V4_PRIOR_COMMIT + ':app/physics/wing_polar.gd'], cwd=repo)
    assert digest(prior_wing.replace(b'\r\n', b'\n')) == V4_PRIOR_WING_POLAR
    for path in ('physics/aero.gd', 'physics/aircraft_data.gd'):
        historical = subprocess.check_output(['git', 'show', V4_PRIOR_COMMIT + ':app/' + path], cwd=repo)
        assert digest(historical.replace(b'\r\n', b'\n')) == prior['source_pins'][path]['sha256'], path

    pairs_raw = (capture_dir / 'v3-v4-config-pairs.json').read_bytes()
    assert digest(pairs_raw) == V4_PAIRS_SHA256
    pair_file = json.loads(pairs_raw)
    assert pair_file['format'] == 'v3-v4-config-pairs-v1' and len(pair_file['pairs']) == 12
    pairs = {entry['case']: entry for entry in pair_file['pairs']}
    assert len(pairs) == 12
    checked_pairs = set()
    for (host, family), (old_hash, new_hash, comparison_hash) in V4_EVIDENCE.items():
        retained = (capture_dir / f'retained-final-{host}-{family}-beta2.json').read_bytes()
        reproduced = (capture_dir / f'reconstructed2-{host}-{family}.json').read_bytes()
        candidate = (capture_dir / f'current-{host}-{family}.json').read_bytes()
        comparison = (capture_dir / f'compare-{host}-{family}.json').read_bytes()
        assert digest(retained) == digest(reproduced) == old_hash and retained == reproduced
        assert digest(candidate) == new_hash and digest(comparison) == comparison_hash
        old, new, diff = json.loads(retained), json.loads(candidate), json.loads(comparison)
        platform = 'Windows' if host == 'windows' else 'Linux'
        assert old['engine']['hash'] == new['engine']['hash'] == ENGINE2
        assert old['os'] == new['os'] == platform
        assert old['cases'].keys() == new['cases'].keys() == prior['families'][family][platform].keys()
        rows = diff['differences']
        assert diff['format'] == 'ci-audit-typed-diff-v1' and len(rows) == len(old['cases']) * 51
        for name, old_case in old['cases'].items():
            new_case = new['cases'][name]
            fixture = prior['families'][family][platform][name]
            assert len(frames(old_case)) == len(frames(new_case)) == 25
            assert old_case['sha256'] == fixture['current_sha256']
            assert old_case['events'] == new_case['events'] and len(old_case['events']) == 25
            assert digest(b''.join(bytes.fromhex(item) for item in old_case['events'])) == fixture['events_sha256']
            selected = [r for r in rows if r['path'][0] == name]
            assert len(selected) == 51
            config_rows = [r for r in selected if r['path'][1:] == ['configuration_fields', 'checkpoint']]
            assert len(config_rows) == 1
            old_config, new_config = config_rows[0]['left_text'], config_rows[0]['right_text']
            assert old_config == fixture['current_configuration'] and old_config != new_config
            expected_paths = {tuple([name, 'configuration_fields', 'checkpoint'])}
            expected_paths |= {(name, tick, key) for tick in range(25) for key in ('configuration', 'aero_loads_law')}
            assert {tuple(r['path']) for r in selected} == expected_paths
            for row in selected:
                assert row['left_type'] == row['right_type'] == 'String'
                if isinstance(row['path'][1], int):
                    expected = (old_config, new_config) if row['path'][2] == 'configuration' else (V4_OLD_LAW, V4_NEW_LAW)
                    assert (row['left_text'], row['right_text']) == expected
            pair_id = f'{host}/{family}/{name}'
            pair = pairs[pair_id]
            assert (pair['old_sha256'], pair['new_sha256']) == (old_config, new_config)
            old_bytes, new_bytes = bytes.fromhex(pair['old_bytes_hex']), bytes.fromhex(pair['new_bytes_hex'])
            old_law, new_law = V4_OLD_LAW.encode(), V4_NEW_LAW.encode()
            assert digest(old_bytes) == old_config and digest(new_bytes) == new_config
            assert old_bytes.count(old_law) == 1 and old_bytes.replace(old_law, new_law) == new_bytes
            checked_pairs.add(pair_id)
            updated_case = updated['families'][family][platform][name]
            updated_case['current_configuration'] = new_config
            updated_case['current_sha256'] = new_case['sha256']
            assert {k: v for k, v in updated_case.items() if k not in ('current_configuration', 'current_sha256')} == \
                {k: v for k, v in fixture.items() if k not in ('current_configuration', 'current_sha256')}
    assert checked_pairs == set(pairs)
    updated['candidate_commit'] = V4_CANDIDATE
    updated['source_pins'] = source_pins
    updated['requalification'] = {
        'prior_fixture_sha256': V4_PRIOR_FIXTURE, 'prior_source_commit': V4_PRIOR_COMMIT,
        'candidate_source_commit': V4_CANDIDATE, 'configuration_pairs_sha256': V4_PAIRS_SHA256,
        'scope': 'v3-to-v4 aero identity only; 25 endpoints and event tapes per case',
    }
    if output.exists():
        raise FileExistsError(output)
    data = (json.dumps(updated, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')
    with output.open('xb') as file:
        file.write(data)
    print(output, 'bytes=', len(data), 'sha256=', digest(data), 'preserved_cases=', len(checked_pairs))


def main():
    global ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-dir', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--requalify-v4-from', type=Path, help='preserve this verified prior fixture and admit the reviewed v4 identity')
    modes.add_argument('--rebind-source-from', type=Path, help='preserve the prior fixture after exact cross-platform source requalification')
    parser.add_argument('--rebind-candidate', help='full candidate commit SHA for the source rebind')
    parser.add_argument('--rebind-receipt', type=Path, help='fresh receipt path for the source rebind')
    args = parser.parse_args()
    if args.rebind_source_from is not None:
        if not args.rebind_candidate or args.rebind_receipt is None:
            parser.error('--rebind-source-from requires --rebind-candidate and --rebind-receipt')
        rebind_source(args.capture_dir.resolve(), args.rebind_source_from.resolve(), args.output,
                      args.rebind_receipt, args.rebind_candidate)
        return
    if args.rebind_candidate is not None or args.rebind_receipt is not None:
        parser.error('--rebind-candidate and --rebind-receipt require --rebind-source-from')
    if args.requalify_v4_from is not None:
        requalify_v4(args.capture_dir.resolve(), args.requalify_v4_from.resolve(), args.output)
        return
    ROOT = args.capture_dir.resolve()
    pins = {}
    for path in SCRIPTS:
        current = (ROOT / 'final-candidate/app' / path).read_bytes().replace(b'\r\n', b'\n')
        if path in OVERLAYS:
            assert digest(current) == OVERLAYS[path], path
        else:
            committed = subprocess.check_output(['git', 'show', CANDIDATE + ':app/' + path]).replace(b'\r\n', b'\n')
            assert current == committed, path
        assert current == (ROOT / 'final-linux/app' / path).read_bytes().replace(b'\r\n', b'\n'), path
        pins[path] = {'sha256': digest(current), 'mode': 'script-lf'}
    for path in DATA:
        current = (ROOT / 'final-candidate/app' / path).read_bytes()
        assert current == (ROOT / 'final-linux/app' / path).read_bytes(), path
        pins[path] = {'sha256': digest(current), 'mode': 'exact'}
    result = {'format': 'openrc-publication-bridge-v1', 'reference_commit': REFERENCE,
              'candidate_commit': CANDIDATE, 'candidate_overlays': OVERLAYS,
              'current_engine': ENGINE2, 'source_pins': pins, 'families': {}}
    for family in ('shaft', 'weather'):
        result['families'][family] = {}
        for platform, prefix in [('Windows', ''), ('Linux', 'linux-')]:
            ref = load(f'{prefix}baseline-{family}-beta2.json')
            candidate = load(f'{prefix}candidate-{family}-beta2.json')
            ref_events = load(f'{prefix}baseline-{family}-beta2-events.json')
            candidate_events = load(f'{prefix}candidate-{family}-beta2-events.json')
            final = load(f'final-{platform.lower()}-{family}-beta2.json')
            old = load(f'historical-{family}-beta1-crlf.json') if platform == 'Windows' else ref
            assert ref['engine']['hash'] == candidate['engine']['hash'] == ENGINE2
            assert old['engine']['hash'] == (ENGINE1 if platform == 'Windows' else ENGINE2)
            assert ref['os'] == candidate['os'] == old['os'] == platform
            assert ref['cases'].keys() == candidate['cases'].keys() == old['cases'].keys()
            diff = load(f'{prefix.lower() if prefix else "windows-"}{family}-diff.json')
            allowed = {'configuration', 'aero_loads_law'}
            for row in diff['differences']:
                p = row['path']
                assert (len(p) == 3 and isinstance(p[1], int) and p[2] in allowed) or \
                    (p[1] == 'configuration_fields' and (p[2:] == ['checkpoint'] or p[2:] == ['aircraft', 'data_sha256'])), p
            registry = load(f'windows-{family}-registry-diff.json') if platform == 'Windows' else None
            if platform == 'Windows':
                assert not load(f'windows-{family}-engine-diff.json')['differences']
                for row in registry['differences']:
                    p = row['path']
                    assert (len(p) == 3 and isinstance(p[1], int) and p[2] == 'configuration') or \
                        (p[1] == 'configuration_fields' and (p[2:] == ['checkpoint'] or p[2:] == ['aircraft', 'fuel_system', 'registry_sha256'])), p
            cases = {}
            for name in ref['cases']:
                old_frames, ref_frames, candidate_frames = frames(old['cases'][name]), frames(ref['cases'][name]), frames(candidate['cases'][name])
                assert ref_events['cases'][name]['sha256'] == ref['cases'][name]['sha256']
                assert candidate_events['cases'][name]['sha256'] == candidate['cases'][name]['sha256']
                event_frames = [bytes.fromhex(value) for value in ref_events['cases'][name]['events']]
                current_events = [bytes.fromhex(value) for value in candidate_events['cases'][name]['events']]
                assert len(event_frames) == len(current_events) == 25 and event_frames == current_events
                assert final['cases'][name]['frames'] == candidate_events['cases'][name]['frames']
                assert final['cases'][name]['events'] == candidate_events['cases'][name]['events']
                assert final['cases'][name]['configuration'] == candidate_events['cases'][name]['configuration']
                ref_config, current_config = values(diff, name, 'configuration')
                original_config = values(registry, name, 'configuration')[0] if registry else ref_config
                assert values(diff, name, 'aero_loads_law') == ('section-plane-source-weighted-wake-velocity-v2', 'section-plane-source-weighted-wake-velocity-v3')
                assert len(old_frames) == len(ref_frames) == len(candidate_frames) == 25
                cases[name] = {'frames_gzip_base64': pack(old_frames), 'original_sha256': old['cases'][name]['sha256'],
                               'events_gzip_base64': pack(event_frames), 'events_sha256': digest(b''.join(event_frames)),
                               'reference_sha256': ref['cases'][name]['sha256'], 'current_sha256': candidate['cases'][name]['sha256'],
                               'original_configuration': original_config, 'reference_configuration': ref_config,
                               'current_configuration': current_config}
            result['families'][family][platform] = cases
    output = args.output
    if output.exists():
        raise FileExistsError(output)
    data = (json.dumps(result, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')
    with output.open('xb') as file:
        file.write(data)
    print(output, 'bytes=', len(data), 'sha256=', digest(data))


if __name__ == '__main__':
    main()
