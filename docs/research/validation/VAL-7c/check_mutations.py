#!/usr/bin/env python3
"""Run VAL-7c mutations only in disposable copies; require a passing control."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT/'research/validation/rpm-step'
MUTATIONS = {
    'independent_endpoints_per_crossing': (
        "row = {'initial_rpm':", "row = {f'initial_rpm:{name}':"),
    'wrong_left_sample_sign': (
        'finite(-slope_inverse*(1-fraction)*ur)', 'finite(slope_inverse*(1-fraction)*ur)'),
    'lost_command_cancellation': (
        "(-1., rows['delay_s']), (-1., rows['tau_s']))",
        "(1., rows['delay_s']), (-1., rows['tau_s']))"),
    'missing_bracket_screen': ('if threshold_u > 0 and any(', 'if False and any('),
}


def run(target):
    return subprocess.run([sys.executable, '-m', 'unittest', 'test_reduce', 'test_uncertainty'],
                          cwd=target, capture_output=True, text=True, timeout=60)


def main():
    outcomes = []
    with tempfile.TemporaryDirectory(prefix='openrc-val7c-') as tmp:
        target = Path(tmp)/'rpm-step'
        shutil.copytree(SOURCE, target, ignore=shutil.ignore_patterns('__pycache__'))
        control = run(target)
        if control.returncode:
            raise RuntimeError(control.stdout+control.stderr)
        outcomes.append({'case': 'control', 'exit_code': 0, 'tests': 34})
        original = (target/'reduce.py').read_text()
        for name, (before, after) in MUTATIONS.items():
            if original.count(before) != 1:
                raise RuntimeError(f'{name}: mutation anchor not unique')
            (target/'reduce.py').write_text(original.replace(before, after))
            shutil.rmtree(target/'__pycache__', ignore_errors=True)
            result = run(target)
            if result.returncode == 0 or 'FAIL:' not in result.stderr or 'ERROR:' in result.stderr:
                raise RuntimeError(f'{name}: expected assertion rejection\n{result.stderr}')
            outcomes.append({'case': name, 'exit_code': result.returncode,
                             'assertions': [line for line in result.stderr.splitlines() if line.startswith('FAIL:')]})
    print(json.dumps(outcomes, indent=2))


if __name__ == '__main__':
    main()
