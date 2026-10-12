"""Run an Extra research probe with bounded engine execution and evidence identity.

No physical thresholds are applied. Failure exits, engine errors, setup failures,
nonfinite results and incomplete airborne traces do fail this evidence runner.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--probe', choices=['envelope', 'ground'], required=True)
    parser.add_argument('--hz', type=int, choices=[240, 480], default=240)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    script = Path(__file__).resolve().with_name(args.probe + '_probe.gd')
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)  # A successful process must produce fresh evidence, never reuse an old report.
    command = [str(args.godot.resolve()), '--headless', '--path', str(args.app.resolve()),
               '--audio-driver', 'Dummy', '--script', str(script), '--',
               f'--hz={args.hz}', f'--output={output}']
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    log = result.stdout + result.stderr
    output.with_suffix('.log').write_text(log, encoding='utf-8', newline='\n')
    identity = {
        'command': command,
        'exit_code': result.returncode,
        'probe_sha256': hashlib.sha256(script.read_bytes()).hexdigest(),
        'aircraft_sha256': hashlib.sha256((args.app / 'data/aircraft/gp_extra_300s_60.json').read_bytes()).hexdigest(),
        'wheel_profiles_sha256': hashlib.sha256((args.app / 'data/ground/wheel_profiles.json').read_bytes()).hexdigest(),
    }
    output.with_suffix('.identity.json').write_text(json.dumps(identity, indent=2) + '\n', encoding='utf-8')
    if result.returncode or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M):
        raise SystemExit(f'Engine failed; see {output.with_suffix(".log")}')
    data = json.loads(output.read_text(encoding='utf-8'))
    if data.get('errors') or not data.get('cases'):
        raise SystemExit(f'Probe setup failed: {data.get("errors", "no cases")}')
    for case in data['cases']:
        if args.probe == 'envelope':
            if not case.get('available'):
                raise SystemExit(f'Unavailable case: {case}')
            flight = case['flight']
            if case['simulation_fault'] or flight['nonfinite_scalar_count'] or not flight['trace_continuous'] \
                    or flight['rows'] != flight['expected_rows']:
                raise SystemExit(f'Incomplete/nonfinite case: {case["id"]}')
        elif case.get('setup_error') or not case.get('metrics', {}).get('finite') \
                or case['metrics'].get('steps', 0) <= 0:
            raise SystemExit(f'Invalid ground case: {case}')
    description = 'complete finite flights' if args.probe == 'envelope' else 'finite ground outcomes (review crash/event fields)'
    print(f'{len(data["cases"])} {description} at {args.hz} Hz; {output}')


if __name__ == '__main__':
    main()
