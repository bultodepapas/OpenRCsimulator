#!/usr/bin/env python3
"""Compare source and exported Linux coupled-shaft traces with independent readers."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'app/tests'))
from check_trimmed_flight import check as check_calm
from check_atmosphere_trace import check as check_air
from test_atmosphere_cli import MIXED_CONFIG


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    engine = subprocess.check_output([str(ROOT / 'app/get-godot.sh')], text=True).strip()
    mixed = out / 'mixed.json'
    mixed.write_text(json.dumps(MIXED_CONFIG) + '\n')
    reports = []
    for case, options in [('calm', []), ('hot-high', ['--weather=hot-high']),
                          ('mixed', ['--weather-file=' + str(mixed)])]:
        rows = []
        for route, binary, prefix in [('source', engine, ['--path', str(ROOT / 'app')]),
                                      ('linux', str(ROOT / 'dist/linux/openrc-simulator.x86_64'), [])]:
            path = out / f'{case}-{route}.csv'
            command = [binary, '--headless', '--audio-driver', 'Dummy', *prefix, '--',
                       '--aircraft=p51d-mustang-120', '--shaft-integrator=coupled-rk4',
                       *options, '--trace=' + str(path), '--t=3']
            result = subprocess.run(command, capture_output=True, text=True, timeout=45, cwd=out)
            log = result.stdout + result.stderr
            (out / f'{case}-{route}.log').write_text(log)
            if result.returncode or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M):
                raise RuntimeError(log)
            proof = {'trim_check': check_calm(path, 3, 240)} if case == 'calm' else check_air(path, 3)
            numeric = '\n'.join(line for line in path.read_text().splitlines() if not line.startswith('#')) + '\n'
            rows.append(numeric)
            reports.append({'case': case, 'route': route, 'proof': proof,
                            'numeric_sha256': hashlib.sha256(numeric.encode()).hexdigest()})
        if rows[0] != rows[1]:
            raise RuntimeError('Source/Linux mismatch: ' + case)
    payload = {'format': 'openrc-coupled-shaft-native-check v1', 'duration_s': 3,
               'aircraft': 'p51d-mustang-120', 'shaft_integrator': 'coupled-rk4', 'reports': reports}
    args.report.write_text(json.dumps(payload, indent=2) + '\n')
    print('Coupled P-51: source/Linux rows match exactly for calm, custom air and mixed OU; 721 samples per run.')


if __name__ == '__main__':
    main()
