#!/usr/bin/env python3
"""Run isolated circuit acceptance and verify its saved trace; no app files change."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def invoke(godot, script, arguments, environment, timeout=600):
    result = subprocess.run(
        [str(godot), '--headless', '--path', str(ROOT / 'app'), '--audio-driver', 'Dummy',
         '--script', str(script), '--', *arguments],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        env=environment, timeout=timeout)
    errors = any(line.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:'))
                 for line in result.stdout.splitlines())
    return result, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True, help='new evidence directory')
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    godot = args.godot or Path(subprocess.check_output([str(ROOT / 'app/get-godot.sh')], text=True).strip())
    with tempfile.TemporaryDirectory(prefix='openrc-circuit-') as temporary:
        scratch = Path(temporary)
        env = os.environ.copy()
        for key in ('DATA', 'CONFIG', 'CACHE'):
            env[f'XDG_{key}_HOME'] = str(scratch / key.lower())
        for script in HERE.glob('*.gd'):
            result = subprocess.run([str(godot), '--headless', '--path', str(ROOT / 'app'),
                                     '--check-only', '--script', str(script)],
                                    capture_output=True, text=True, env=env, timeout=60)
            if result.returncode or 'ERROR:' in result.stdout + result.stderr:
                raise RuntimeError(f'parse failure: {script.name}\n{result.stdout}{result.stderr}')
        result, errors = invoke(godot, HERE / 'run.gd',
                                [f'--report={out / "report.json"}', f'--trace={out / "circuit.csv"}'], env)
        (out / 'flight.log').write_text(result.stdout)
        if result.returncode or errors:
            raise RuntimeError(f'circuit verification failed: see {out / "flight.log"}')
        checked = subprocess.run([sys.executable, str(HERE / 'check_trace.py'),
                                  str(out / 'circuit.csv'), str(out / 'report.json'), '--self-test'],
                                 capture_output=True, text=True, timeout=60)
        (out / 'trace-check.json').write_text(checked.stdout)
        if checked.returncode:
            raise RuntimeError(checked.stderr)
        if args.mutations:
            mutations = [
                ('nonfinite-command', 'circuit_pilot.gd',
                 'throttle = clampf(throttle, 0.0, 1.0),', 'throttle = NAN,',
                 'FAIL 240Hz east continuous normal flight ticks and bounded commands'),
                ('state-rewrite', 'circuit_driver.gd',
                 '\t\tsession.commands = command',
                 '\t\tsession.sim.state[0] += 1.0\n\t\tsession.commands = command',
                 'FAIL 240Hz east continuous normal flight ticks and bounded commands'),
            ]
            proofs = []
            for name, filename, old, new, expected in mutations:
                folder = scratch / name
                folder.mkdir()
                for source in HERE.glob('*.gd'):
                    text = source.read_text()
                    if source.name == filename:
                        if text.count(old) != 1:
                            raise RuntimeError(f'mutation anchor changed: {name}')
                        text = text.replace(old, new)
                    (folder / source.name).write_text(text)
                changed, errors = invoke(godot, folder / 'run.gd', ['--quick', '--duration=3'], env)
                (out / f'{name}.log').write_text(changed.stdout)
                rejected = changed.returncode == 1 and not errors and expected in changed.stdout
                proofs.append(dict(mutation=name, rejected=rejected))
                if not rejected:
                    raise RuntimeError(f'mutation was not cleanly detected: {name}')
            (out / 'mutations.json').write_text(json.dumps(proofs, indent=2) + '\n')
    print(f'PASS: full circuit, trace integrity and requested mutations; evidence: {out}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
