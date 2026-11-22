#!/usr/bin/env python3
"""Reconstruct and run the source-pinned R9 car audit in a NEW directory.

Requires the reviewed Git objects, official Linux x86-64 Godot 4.8-beta2,
Python 3 and NumPy (recorded version in evidence). Uses real source/resources
and the repository checked runner, retaining scheduling/admission settings.
Production source/data are never changed. Synthetic start/wall cases are
created inside explicitly labeled probes, not installed as stock content.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

REVIEWED_COMMIT = '77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b'
ENGINE_SHA256 = '34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564'
MANIFEST_SHA256 = '6dafccada76c78de8efde11d1805e2fcbfae2ee31b8dcbc24e70bfede35f71e2'
PROBES = (
    ('walls', 'ninth_pass_walls.gd', 'R9 WALL: 25 checks, 0 failed'),
    ('heading', 'ninth_pass_heading.gd', 'R9 HEADING: 7 checks, 0 failed'),
    ('nitro', 'ninth_pass_nitro.gd', 'R9 NITRO: 14 checks, 0 failed'),
    ('session', 'ninth_pass_session.gd', 'R9 SESSION: 39 checks, 0 failed'),
    ('baseline-data', 'tests/test_rcv_vehicle_data.gd', 'PASS: invalid axle brake fraction rejected: 0.85'),
    ('baseline-obstacles', 'tests/test_rcv_obstacle_contacts.gd', '0 failures'),
    ('baseline-nitro-session', 'tests/test_rcv_nitro_session.gd', '0 failed'),
)


def sha(data): return hashlib.sha256(data).hexdigest()


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo-root', type=Path, required=True)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    repo, engine, out = args.repo_root.resolve(), args.godot.resolve(), args.out.resolve()
    here = Path(__file__).resolve().parent
    if out.exists(): parser.error('--out must be new; previous evidence is never removed')
    if sha(engine.read_bytes()) != ENGINE_SHA256: parser.error('engine identity mismatch')
    manifest_path = here.parent/'ninth-pass-sources.json'
    if sha(manifest_path.read_bytes()) != MANIFEST_SHA256: parser.error('manifest identity mismatch')
    manifest = json.loads(manifest_path.read_text())
    assert manifest['reviewed_commit'] == REVIEWED_COMMIT and len(manifest['files']) == 172
    assert len({row['path'] for row in manifest['files']}) == 172

    def git_file(path): return subprocess.check_output(['git', 'show', REVIEWED_COMMIT+':'+path], cwd=repo)

    runner = repo/'tools/godot/run_checked.py'
    if runner.read_bytes() != git_file('tools/godot/run_checked.py'):
        raise RuntimeError('checked runner changed; use the reviewed source checkout')
    out.mkdir(parents=True)
    project = out/'project'
    project.mkdir()
    for row in manifest['files']:
        data = git_file(row['path'])
        assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest() == row['git_blob_sha1'], row['path']
        assert sha(data) == row['sha256'] and len(data) == row['bytes'], row['path']
        target = project/Path(row['path']).relative_to('app')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    (project/'project.godot').write_text(manifest['project_settings'])
    names = [name for _, name, _ in PROBES if not name.startswith('tests/')]
    for name in names: (project/name).write_bytes((here/name).read_bytes())
    for key, suffix in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        os.environ[key] = str(out/('user-'+suffix))
    # Preserve pool/testqueue environment. The checked runner owns admission.
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(repo))
    from tools.godot.run_checked import run_checked
    from tools.testqueue import common, pool
    import numpy
    support = {name: sha((repo/name).read_bytes()) for name in
               ['tools/godot/run_checked.py', 'tools/testqueue/common.py', 'tools/testqueue/pool.py']}
    evidence = {'format': 'openrc-a36-r9-evidence v1', 'reviewed_commit': REVIEWED_COMMIT,
        'engine_sha256': ENGINE_SHA256, 'engine_version': subprocess.check_output([str(engine), '--version'], text=True).strip(),
        'manifest_sha256': MANIFEST_SHA256, 'source_count': 172, 'execution_support_sha256': support,
        'python_version': sys.version, 'numpy_version': numpy.__version__, 'production_stubs': [],
        'backend': 'gdscript_reference explicitly selected in new probes; optional native artifact absent',
        'scope': 'Linux headless components and real sessions on declared synthetic fixtures; no rendering, native R9 probe, measured vehicle or ordinary-play trajectory claim',
        'host_admission': {'pool_config_present': Path(pool.default_config()).exists(), 'queue_enabled': common.enabled()},
        'probe_sha256': {name: sha((here/name).read_bytes()) for name in names+[Path(__file__).name, 'ninth_pass_oracles.py']},
        'checks': [], 'oracles': [], 'ok': False}
    path = out/'evidence.json'

    def checked(label, options, required):
        report = run_checked([str(engine), '--headless', '--path', str(project), '--audio-driver', 'Dummy']+options,
            out/'checks', timeout=90, warnings_as_errors=True, required=required, label='a36-r9-'+label)
        evidence['checks'].append({'label': label, 'report': report, 'engine_log': Path(report['log']).read_text()})
        dump(path, evidence)
        print(label+': '+report['reason'], flush=True)
        if not report['ok'] or report['counts'] != {'error': 0, 'warning': 0}:
            raise RuntimeError('checked invocation failed; inspect '+str(path))

    checked('import', ['--editor', '--import'], ['Godot Engine'])
    for label, filename, marker in PROBES:
        checked(label, ['--script', 'res://'+filename], [marker])
    result = subprocess.run([sys.executable, str(here/'ninth_pass_oracles.py'), '--evidence', str(path), '--project', str(project)],
        capture_output=True, text=True, check=False)
    evidence['oracles'].append({'command': 'ninth_pass_oracles.py --evidence <out>/evidence.json --project <out>/project',
        'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    dump(path, evidence)
    if result.returncode: raise RuntimeError('independent oracles failed; inspect '+str(path))
    for row in manifest['files']:
        assert sha((project/Path(row['path']).relative_to('app')).read_bytes()) == row['sha256'], row['path']
    for name in names: assert sha((project/name).read_bytes()) == evidence['probe_sha256'][name], name
    assert sha(engine.read_bytes()) == ENGINE_SHA256
    evidence['all_source_bytes_unchanged_after_execution'] = True
    evidence['ok'] = True
    dump(path, evidence)
    print('R9_REPRODUCTION_COMPLETE '+str(path), flush=True)


if __name__ == '__main__': main()
