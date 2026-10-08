#!/usr/bin/env python3
"""Run F6b defect injections only on disposable copies."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT/'research/radio-latency'
MUTATIONS = {
    'missing_frame_quantization': ('radius = 1+rs+rp', 'radius = rs+rp'),
    'ignore_cadence_bounds': ("for f in (fps['min'], fps['max'])", "for f in (fps['value'], fps['value'])"),
    'p95_uses_maximum': ('return s[(95*len(s)+99)//100-1]', 'return s[-1]'),
    'nineteen_trials_accepted': ("'minimum_20_trials_met': n >= 20", "'minimum_20_trials_met': n >= 19"),
}


def run(target):
    return subprocess.run([sys.executable, 'test_reduce.py'], cwd=target,
                          capture_output=True, text=True, timeout=60)


def main():
    results = []
    with tempfile.TemporaryDirectory(prefix='openrc-f6b-') as tmp:
        target = Path(tmp)/'latency'
        shutil.copytree(SOURCE, target, ignore=shutil.ignore_patterns('__pycache__'))
        control = run(target)
        if control.returncode:
            raise RuntimeError(control.stdout+control.stderr)
        results.append({'case': 'control', 'exit_code': 0})
        original = (target/'reduce.py').read_text()
        for name, (before, after) in MUTATIONS.items():
            if original.count(before) != 1:
                raise RuntimeError(f'{name}: nonunique mutation anchor')
            (target/'reduce.py').write_text(original.replace(before, after))
            shutil.rmtree(target/'__pycache__', ignore_errors=True)
            result = run(target)
            assertions = [line for line in result.stderr.splitlines() if line.startswith('FAIL:')]
            if result.returncode == 0 or not assertions or 'ERROR:' in result.stderr:
                raise RuntimeError(f'{name}: expected assertion failure\n{result.stderr}')
            results.append({'case': name, 'exit_code': result.returncode, 'assertions': assertions})
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
