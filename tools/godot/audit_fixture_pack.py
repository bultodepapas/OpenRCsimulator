"""Pack the qualified typed publication captures; refuses unreviewed differences."""
import argparse
import base64
import copy
import gzip
import hashlib
import json
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
    parser.add_argument('--requalify-v4-from', type=Path, help='preserve this verified prior fixture and admit the reviewed v4 identity')
    args = parser.parse_args()
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
