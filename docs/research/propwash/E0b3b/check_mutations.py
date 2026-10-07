#!/usr/bin/env python3
"""E0b3b: alter scratch copies only; failures must come from assertions, not engine errors."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
GODOT = subprocess.check_output([str(ROOT / 'app/get-godot.sh')], text=True).strip()
TEST = 'res://tests/test_wash_profile.gd'
MUTATIONS = [
    ('physics/slipstream.gd', 'moments[1] / immersed', '0.0', 'discard scalar immersed centroid'),
    ('physics/slipstream.gd', '(1.0-t*t*(3.0-2.0*t))', '(1.0-t)', 'replace C1 radial taper by linear weight'),
    ('physics/slipstream.gd', 'return 1.0 - Aero._smoothstep((ratio - bounds[0]) / (bounds[1] - bounds[0]))',
     'return 1.0', 'remove reverse-flow cutoff'),
    ('physics/slipstream.gd', 'shift[2] = 0.0', 'shift[2] = 0.005', 'move horizontal pressure plane'),
    ('physics/aircraft_data.gd', 'absf(total - area) > 1e-8', 'absf(total - area) > 100.0', 'accept incorrect profile area'),
    ('physics/aircraft_data.gd', 'row[0] < previous or ', '', 'accept overlapping profile intervals'),
]


def run(project):
    return subprocess.run([GODOT, '--headless', '--path', str(project), '--script', TEST],
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)


with tempfile.TemporaryDirectory(prefix='openrc-e0b3b-') as scratch:
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
