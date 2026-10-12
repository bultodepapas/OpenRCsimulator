"""AV-16 bounded engine runner; immutable inputs, complete cases and engine errors checked."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def fingerprints(app, scripts):
    files = sorted(p for p in app.rglob('*') if p.is_file() and '.godot' not in p.parts
                   and p.suffix in {'.gd', '.json', '.tscn', '.tres', '.godot'})
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files + scripts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--probe', choices=['envelope', 'lifecycle', 'pitch_sweep'], required=True)
    parser.add_argument('--hz', type=int, choices=[240, 480], default=240)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    app, output = args.app.resolve(), args.output.resolve()
    script = Path(__file__).resolve().with_name(args.probe + '_probe.gd')
    scripts = list(dict.fromkeys([Path(__file__).resolve(), script, script.with_name('envelope_probe.gd'),
               script.parents[2] / 'extra-300/ex06/envelope_probe.gd',
               script.parents[2] / 'p51/p51-15/envelope_probe.gd']))
    if output.exists():
        raise SystemExit('Use a fresh evidence path; output exists.')
    output.parent.mkdir(parents=True, exist_ok=True)
    before = fingerprints(app, scripts)
    command = [str(args.godot.resolve()), '--headless', '--path', str(app),
               '--audio-driver', 'Dummy', '--script', str(script), '--',
               f'--hz={args.hz}', f'--output={output}']
    start = time.monotonic()
    try:
        run = subprocess.run(command, capture_output=True, text=True, encoding='utf-8',
                             errors='replace', timeout=300)
        log, code = run.stdout + run.stderr, run.returncode
    except subprocess.TimeoutExpired as error:
        log = (error.stdout or b'').decode(errors='replace') + (error.stderr or b'').decode(errors='replace')
        code = 124
    output.with_suffix('.log').write_text(log, encoding='utf-8')
    after = fingerprints(app, scripts)
    output.with_suffix('.identity.json').write_text(json.dumps({
        'command': command, 'exit_code': code, 'seconds': time.monotonic() - start,
        'sha256': before, 'unchanged_during_run': before == after,
    }, indent=2) + '\n', encoding='utf-8')
    if code or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M) or before != after:
        raise SystemExit('Engine failure or changed inputs; inspect the preserved log/identity.')
    data = json.loads(output.read_text(encoding='utf-8'))
    if data.get('aircraft_id') != 'sebart-avanti-s-a200-p100rx' or data.get('errors'):
        raise SystemExit('Wrong aircraft or probe errors: ' + str(data.get('errors')))
    if not data.get('cases'):
        raise SystemExit('Missing cases')
    if args.probe in ['envelope', 'pitch_sweep']:
        expected = 34 if args.probe == 'envelope' else 8
        if data.get('physics_hz') != args.hz or len(data['cases']) != expected:
            raise SystemExit('Incomplete flight matrix or wrong tick rate')
        for case in data['cases']:
            flight = case.get('flight', {})
            if not case.get('available') or not case.get('complete') or case.get('simulation_fault') or case.get('crash') \
                    or not flight.get('trace_continuous') or flight.get('nonfinite_scalar_count') != 0 \
                    or flight.get('rows', 0) != flight.get('expected_rows', -1):
                raise SystemExit('Incomplete or invalid flight: ' + case.get('id', '?'))
    else:
        expected_ids = {'engine_off_glide_reset', 'checkpoint_native_replay_240',
                        'crash_hold_restart', 'unsupported_ground_contract',
                        'rendered_adapter_differential_hinges'}
        if data.get('tick_hz') != args.hz or not data.get('completed') \
                or len(data['cases']) != 5 or {c.get('id') for c in data['cases']} != expected_ids \
                or any(not all(c.get(k) for k in ['available', 'complete', 'ok']) for c in data['cases']):
            raise SystemExit('Lifecycle incomplete or wrong tick rate')
    print(f'{args.probe}: {len(data["cases"])} cases, {args.hz} Hz, {time.monotonic()-start:.1f}s; {output}')


if __name__ == '__main__':
    main()
