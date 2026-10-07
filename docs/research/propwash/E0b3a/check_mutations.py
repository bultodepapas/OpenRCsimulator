#!/usr/bin/env python3
"""E0b3a: alter scratch copies only; failures must come from assertions, not engine errors."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
GODOT = subprocess.check_output([str(ROOT / 'app/get-godot.sh')], text=True).strip()
TEST = 'res://tests/test_slipstream_downwash.gd'
MUTATIONS = [
    ('physics/dynamics.gd', 'Slipstream.loads(state, air, d, model, rpm, rho, downwash_cl)',
     'Slipstream.loads(state, air, d, model, rpm, rho)', 'session lag disconnected at Dynamics'),
    ('physics/slipstream.gd', 'else downwash_cl', 'else 0.0', 'held wing lift ignored'),
    ('physics/slipstream.gd', 'tail.free_slope if has_downwash else tail.lift_slope',
     'tail.lift_slope', 'old scalar tail slope restored'),
    ('physics/slipstream.gd', 'float(tail.elevator_tau) * control',
     'float(tail.control_effectiveness) * control', 'old scalar elevator law restored'),
    ('physics/aero.gd', 'slope = tail.free_slope\n\telse:',
     'slope = tail.lift_slope\n\telse:', 'old helper tail slope restored'),
]


def run(project):
    return subprocess.run([GODOT, '--headless', '--path', str(project), '--script', TEST],
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)


with tempfile.TemporaryDirectory(prefix='openrc-e0b3a-') as scratch:
    project = Path(scratch) / 'app'
    shutil.copytree(ROOT / 'app', project, ignore=shutil.ignore_patterns('.godot', 'captures'))
    baseline = run(project)
    if baseline.returncode or 'ERROR:' in baseline.stdout or 'FAIL ' in baseline.stdout:
        raise SystemExit('Baseline failed:\n' + baseline.stdout)
    print('Baseline: ' + baseline.stdout.strip().splitlines()[-1])
    for name, old, new, label in MUTATIONS:
        path = project / name
        original = path.read_text()
        if original.count(old) != 1:
            raise SystemExit('Mutation site changed: ' + label)
        path.write_text(original.replace(old, new))
        result = run(project)
        path.write_text(original)
        failures = [line for line in result.stdout.splitlines() if line.startswith('FAIL ')]
        if result.returncode != 1 or not failures or 'ERROR:' in result.stdout:
            raise SystemExit(label + ' was not caught by assertions:\n' + result.stdout)
        print(label + ': rejected')
        for failure in failures:
            print('  ' + failure)
    restored = run(project)
    if restored.returncode or 'ERROR:' in restored.stdout or 'FAIL ' in restored.stdout:
        raise SystemExit('Restored baseline failed:\n' + restored.stdout)
    print('Restored: ' + restored.stdout.strip().splitlines()[-1])
