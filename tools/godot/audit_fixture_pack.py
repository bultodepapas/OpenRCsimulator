"""Pack the qualified typed publication captures; refuses unreviewed differences."""
import argparse
import base64
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


def main():
    global ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-dir', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
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
