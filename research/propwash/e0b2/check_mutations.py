#!/usr/bin/env python3
"""E0b2 freshness and geometry faults, isolated from the shared working tree."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import derive_geometry as D

SCRIPT = Path('research/propwash/e0b2/derive_geometry.py')
TEST = Path('research/propwash/e0b2/test_geometry.py')


def run(project, relative, *args):
    return subprocess.run(['python3', str(project / relative), *args], text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)


def expect(result, success, label):
    if (result.returncode == 0) != success:
        raise SystemExit(label + ': unexpected result\n' + result.stdout)
    print(label + (': passed' if success else ': rejected'))


with tempfile.TemporaryDirectory(prefix='openrc-e0b2-mutations-') as directory:
    root = Path(directory)
    for source in [D.GEOMETRY, D.RUNTIME_GEOMETRY, D.AIRCRAFT, D.REPORT, D.ROOT / SCRIPT, D.ROOT / TEST]:
        destination = root / source.relative_to(D.ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    expect(run(root, SCRIPT, '--check'), True, 'fresh baseline')
    mutations = [
        (D.AIRCRAFT, lambda d: d['propulsion']['propeller']['thrust_line_offset']['value'].__setitem__(0, 0), 'hub reset to CG'),
        (D.AIRCRAFT, lambda d: d['propulsion']['propeller']['thrust_line_offset'].__setitem__('source', 'changed'), 'hub provenance changed'),
        (D.REPORT, lambda d: d['pieces'][0]['area'].__setitem__('value', 1), 'stale footprint area'),
        (D.GEOMETRY, lambda d: d['equipment'].__setitem__('prop_z', -0.5), 'source/runtime disagreement'),
    ]
    for source, mutate, label in mutations:
        target = root / source.relative_to(D.ROOT)
        before = target.read_bytes()
        data = json.loads(before)
        mutate(data)
        target.write_text(json.dumps(data))
        changed = target.read_bytes()
        result = run(root, SCRIPT, '--check')
        expect(result, False, label)
        if 'Stale ' not in result.stdout and 'source/runtime differ' not in result.stdout:
            raise SystemExit('Unexpected failure: ' + result.stdout)
        if target.read_bytes() != changed:
            raise SystemExit('--check wrote to ' + str(target))
        target.write_bytes(before)
    target = root / SCRIPT
    before = target.read_text()
    for old, new, label in [
        ("point[1] - geometry['equipment']['shaft_y']", 'point[1]', 'vertical datum omitted'),
        ("tail['elevator_cutout_start'], False", "1.0, False", 'elevator notch omitted'),
        ("relieved(tail['fin_outline'], -gap)", "tail['fin_outline']", 'fin hinge relief omitted'),
    ]:
        if before.count(old) != 1:
            raise SystemExit('Mutation site changed: ' + label)
        target.write_text(before.replace(old, new))
        # Prevent Python timestamp/size bytecode reuse between independent mutations.
        shutil.rmtree(target.parent / '__pycache__', ignore_errors=True)
        result = run(root, TEST)
        expect(result, False, label)
        if 'FAIL:' not in result.stdout or 'ERROR:' in result.stdout:
            raise SystemExit('Not an assertion failure: ' + result.stdout)
    target.write_text(before)
    shutil.rmtree(target.parent / '__pycache__', ignore_errors=True)
    expect(run(root, SCRIPT, '--check'), True, 'restored freshness')
    expect(run(root, TEST), True, 'restored geometry tests')
