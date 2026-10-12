"""P51-17 bounded engine runner. Engine errors fail even when Godot exits zero."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', required=True, type=Path)
    p.add_argument('--app', required=True, type=Path)
    p.add_argument('--probe', choices=['envelope', 'ground'], required=True)
    p.add_argument('--hz', type=int, choices=[240, 480], default=240)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    script = Path(__file__).resolve().with_name(a.probe + '_probe.gd')
    out = a.output.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        raise SystemExit('Use a fresh output path; evidence must not be silently overwritten.')
    command = [str(a.godot.resolve()), '--headless', '--path', str(a.app.resolve()),
               '--audio-driver', 'Dummy', '--script', str(script), '--',
               f'--hz={a.hz}', f'--output={out}']
    files = [Path(__file__).resolve(), script, a.app / 'data/aircraft/p51d_mustang_120.json',
             script.parents[2] / 'extra-300/ex06/envelope_probe.gd',
             a.app / 'tests/p51_envelope_base.gd']
    before = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
    started = time.monotonic()
    result = subprocess.run(command, capture_output=True, text=True, timeout=300)
    log = result.stdout + result.stderr
    out.with_suffix('.log').write_text(log, encoding='utf-8', newline='\n')
    after = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
    out.with_suffix('.identity.json').write_text(json.dumps({
        'command': command, 'exit_code': result.returncode,
        'elapsed_seconds': time.monotonic() - started,
        'sha256': before, 'unchanged_during_run': before == after,
    }, indent=2) + '\n', encoding='utf-8')
    if result.returncode or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M):
        raise SystemExit(f'Engine failed; see {out.with_suffix(".log")}')
    if before != after:
        raise SystemExit('Probe inputs changed during execution; freeze and rerun.')
    data = json.loads(out.read_text())
    if data.get('errors') or not data.get('cases'):
        raise SystemExit(f'Probe failed: {data.get("errors", "no cases")}')
    if data.get('aircraft_id') != 'p51d-mustang-120':
        raise SystemExit('Wrong aircraft identity in report')
    if a.probe == 'envelope':
        if data.get('physics_hz') != a.hz or len(data['cases']) != 34:
            raise SystemExit('Incomplete airborne matrix or wrong tick rate')
        for case in data['cases']:
            f = case.get('flight', {})
            if not case.get('available') or case.get('simulation_fault') or not f.get('trace_continuous') \
                    or f.get('nonfinite_scalar_count') != 0 or f.get('rows', 0) != f.get('expected_rows', -1):
                raise SystemExit('Invalid airborne case: ' + case.get('id', '?'))
    elif data.get('tick_hz') != a.hz or not data.get('numerics_ok') or not data.get('completed') \
            or not data.get('cases_completed') or len(data['cases']) != 5:
        raise SystemExit('Ground fixture/lifecycle/numerical verification failed')
    print(f'{len(data["cases"])} cases, {a.hz} Hz, {time.monotonic()-started:.1f}s: {out}')


if __name__ == '__main__':
    main()
