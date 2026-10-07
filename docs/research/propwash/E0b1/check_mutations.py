#!/usr/bin/env python3
"""E0b1: reject independent wake defects on temporary copies, never in the shared app."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
GODOT = subprocess.check_output([str(ROOT / 'app/get-godot.sh')], text=True).strip()
TEST = 'test_propeller_wake.gd'
MUTATIONS = {
    'missing factor two in pressure jump': ('2.0 * thrust / (rho * area)', 'thrust / (rho * area)'),
    'disc induction doubled': ('0.5 * (vs - u)', '(vs - u)'),
    'contraction removed': ('rs = R * M.sqrt_(ratio)', 'rs = R'),
    'shaft projection replaced by body x': ('M.dot(v_air, Propulsion.axis(prop))', 'v_air[0]'),
    'ideal wash factor ignored': ('dv = k_w * w', 'dv = w'),
}


def run(project: Path) -> subprocess.CompletedProcess:
    return subprocess.run([GODOT, '--headless', '--path', str(project), '--script',
                           f'res://tests/{TEST}'], text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=30)


with tempfile.TemporaryDirectory(prefix='openrc-e0b1-') as scratch:
    project = Path(scratch)
    (project / 'project.godot').write_text('config_version=5\n[physics]\ncommon/physics_ticks_per_second=240\n')
    shutil.copytree(ROOT / 'app/physics', project / 'physics')
    shutil.copytree(ROOT / 'app/data/aircraft', project / 'data/aircraft')
    (project / 'tests').mkdir()
    shutil.copy2(ROOT / 'app/tests' / TEST, project / 'tests' / TEST)
    target = project / 'physics/slipstream.gd'
    original = target.read_text()
    baseline = run(project)
    if baseline.returncode or 'ERROR:' in baseline.stdout or 'FAIL' in baseline.stdout:
        raise SystemExit('Baseline failed:\n' + baseline.stdout)
    print('Baseline: ' + baseline.stdout.strip().splitlines()[-1])
    for name, (old, new) in MUTATIONS.items():
        if original.count(old) != 1:
            raise SystemExit(f'{name}: expected one mutation site')
        target.write_text(original.replace(old, new))
        result = run(project)
        failures = [line for line in result.stdout.splitlines() if line.startswith('FAIL ')]
        if result.returncode != 1 or 'ERROR:' in result.stdout or not failures:
            raise SystemExit(f'{name}: not rejected by assertions:\n{result.stdout}')
        print(f'{name}: rejected ({len(failures)} failed checks)')
        for failure in failures:
            print('  ' + failure)
    target.write_text(original)
    restored = run(project)
    if restored.returncode or 'ERROR:' in restored.stdout or 'FAIL' in restored.stdout:
        raise SystemExit('Restored baseline failed:\n' + restored.stdout)
    print('Restored baseline: ' + restored.stdout.strip().splitlines()[-1])
