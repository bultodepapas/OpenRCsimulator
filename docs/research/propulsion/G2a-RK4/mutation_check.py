#!/usr/bin/env python3
"""Prove rotor/regression checks reject faults on an isolated application copy."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]


def run(engine, app, script, marker=None):
    result = subprocess.run([engine, '--headless', '--path', str(app), '--audio-driver', 'Dummy',
                             '--script', 'res://tests/' + script], capture_output=True, text=True, timeout=60)
    log = result.stdout + result.stderr
    if re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M):
        raise RuntimeError('Engine error invalidates mutation proof:\n' + log)
    failures = [line for line in log.splitlines() if line.startswith('FAIL ')]
    if marker is None:
        if result.returncode or failures:
            raise RuntimeError('Control copy failed:\n' + log)
    elif result.returncode == 0 or not any(marker in line for line in failures):
        raise RuntimeError('Mutation missed its intended assertion:\n' + log)
    return {'exit_code': result.returncode, 'failures': failures,
            'log_sha256': hashlib.sha256(log.encode()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    engine = subprocess.check_output([str(ROOT / 'app/get-godot.sh')], text=True).strip()
    targets = {'physics/rotor_coupling.gd', 'sim/flight_session.gd'}
    original = {path: (ROOT / 'app' / path).read_bytes() for path in targets}
    mutations = {
        'missing_body_acceleration': ('physics/rotor_coupling.gd',
            'var acceleration: float = (net_shaft_torque / rotor_inertia - M.dot(axis, unreacted)) / denominator',
            'var acceleration: float = net_shaft_torque / rotor_inertia',
            'test_rotor_coupling.gd', 'rotor-only absolute axial acceleration'),
        'reversed_reaction': ('physics/rotor_coupling.gd',
            'var reaction: PackedFloat64Array = M.scale(axis, -rotor_inertia * acceleration)',
            'var reaction: PackedFloat64Array = M.scale(axis, rotor_inertia * acceleration)',
            'test_rotor_coupling.gd', 'spin-up and spin-down'),
        'sampled_gyro': ('sim/flight_session.gd',
            'return Dynamics.rotor_momentum(aircraft.model, _coupled_rpm(values))',
            'return Dynamics.rotor_momentum(aircraft.model, sim.aux[AUX_RPM])',
            'test_shaft_refinement.gd', 'coupled-rk4 smooth full-session RPM refinement'),
    }
    reports = {}
    with tempfile.TemporaryDirectory(prefix='openrc-rotor-mutation-') as directory:
        app = Path(directory) / 'app'
        shutil.copytree(ROOT / 'app', app, ignore=shutil.ignore_patterns('captures', '__pycache__'))
        reports['control_rotor'] = run(engine, app, 'test_rotor_coupling.gd')
        reports['control_refinement'] = run(engine, app, 'test_shaft_refinement.gd')
        for name, (path, old, new, script, marker) in mutations.items():
            source = original[path].decode()
            if source.count(old) != 1:
                raise RuntimeError('Mutation target changed: ' + name)
            target = app / path
            target.write_text(source.replace(old, new))
            reports[name] = run(engine, app, script, marker)
            target.write_bytes(original[path])
    if any((ROOT / 'app' / path).read_bytes() != value for path, value in original.items()):
        raise RuntimeError('Live application changed during mutation proof')
    report = {'format': 'openrc-rotor-mutation-check v1', 'source_unchanged': True,
              'source_sha256': {path: hashlib.sha256(value).hexdigest() for path, value in original.items()},
              'results': reports}
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print('Three isolated physics mutations rejected; control copies passed; live source unchanged.')


if __name__ == '__main__':
    main()
