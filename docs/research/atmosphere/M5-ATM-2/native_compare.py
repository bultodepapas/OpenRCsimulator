#!/usr/bin/env python3
"""Compare source/exported Linux atmosphere rows with the independent oracle."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'app/tests'))
from check_atmosphere_trace import check

AIRCRAFT = ('jensen-das-ugly-stik-60', 'gp-extra-300s-60',
            'p51d-mustang-120', 'sebart-avanti-s-a200-p100rx')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    engine = subprocess.check_output([str(ROOT / 'app/get-godot.sh')], text=True).strip()
    binary = ROOT / 'dist/linux/openrc-simulator.x86_64'
    mixed = json.loads((Path(__file__).parent / 'hot-high.json').read_text())
    mixed.update(speed_mps=3.0, from_deg=270.0, gust_mps=1.0,
                 gust_up_mps=0.25, turbulence_rms_mps=[0.2, 0.15, 0.1])
    mixed_path = out / 'mixed-weather.json'
    mixed_path.write_text(json.dumps(mixed) + '\n')
    cases = [(aircraft, 'hot-high', ['--weather=hot-high']) for aircraft in AIRCRAFT]
    cases.append((AIRCRAFT[2], 'mixed', [f'--weather-file={mixed_path}']))
    reports = []
    for aircraft, weather, options in cases:
        numeric_rows = []
        for route, program, prefix in (
            ('source', engine, ['--path', str(ROOT / 'app')]),
            ('linux', str(binary), []),
        ):
            path = out / f'{aircraft}-{weather}-{route}.csv'
            command = [program, '--headless', '--audio-driver', 'Dummy', *prefix, '--',
                       *options, f'--aircraft={aircraft}', f'--trace={path}', '--t=3']
            result = subprocess.run(command, capture_output=True, text=True, timeout=45, cwd=out)
            log = result.stdout + result.stderr
            (out / f'{aircraft}-{weather}-{route}.log').write_text(log)
            if result.returncode or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M):
                raise RuntimeError(log)
            verified = check(path, 3)
            rows = '\n'.join(line for line in path.read_text().splitlines()
                             if not line.startswith('#')) + '\n'
            numeric_rows.append(rows)
            verified.update(aircraft=aircraft, route=route, weather=weather,
                            numeric_sha256=hashlib.sha256(rows.encode()).hexdigest())
            reports.append(verified)
        if numeric_rows[0] != numeric_rows[1]:
            raise RuntimeError(f'source/native row mismatch: {aircraft}/{weather}')
    args.report.write_text(json.dumps({'format': 'openrc-atmosphere-native-check v1',
                                      'godot': '4.7.2', 'duration_s': 3,
                                      'mixed_weather': mixed, 'reports': reports}, indent=2) + '\n')
    print('All four aircraft plus mixed OU: Linux/source rows match exactly, 721 samples each.')


if __name__ == '__main__':
    main()
