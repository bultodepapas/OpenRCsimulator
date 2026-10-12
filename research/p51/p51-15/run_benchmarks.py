"""Alternating P-51 baseline/candidate timings; results are host observations, not CI gates."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', type=Path, required=True)
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=False)
    report = {'platform': platform.platform(), 'processor': platform.processor(),
              'order': ['baseline', 'candidate', 'candidate', 'baseline'], 'runs': []}
    ground = Path(__file__).resolve().with_name('bench_ground.gd')
    report['ground_script_sha256'] = hashlib.sha256(ground.read_bytes()).hexdigest()
    for index, label in enumerate(report['order']):
        app = getattr(a, label).resolve()
        for regime, script in [('trim_stalled_components', 'res://tests/bench_physics.gd'),
                               ('whole_ground_tick', str(ground))]:
            command = [str(a.godot.resolve()), '--headless', '--path', str(app),
                       '--audio-driver', 'Dummy', '--script', script]
            if regime == 'trim_stalled_components':
                command += ['--', '--aircraft=p51d-mustang-120']
            done = subprocess.run(command, capture_output=True, text=True, timeout=180)
            log = done.stdout + done.stderr
            log_name = f'{index}-{label}-{regime}.log'
            (a.out / log_name).write_text(log, encoding='utf-8')
            record = {'revision': label, 'regime': regime, 'command': command,
                      'exit': done.returncode, 'log': log_name,
                      'engine_errors': bool(re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M))}
            if regime == 'trim_stalled_components':
                for key, prefix in [('trim_us', 'physics'), ('stalled_us', 'stalled flight')]:
                    match = re.search(rf'^{prefix}: ([0-9.]+)', log, re.M)
                    if match:
                        record[key] = float(match.group(1))
            else:
                for line in log.splitlines():
                    if line.startswith('{'):
                        record['ground'] = json.loads(line)
            report['runs'].append(record)
            (a.out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps(record), flush=True)
            if record['exit'] or record['engine_errors']:
                raise SystemExit('Benchmark failed; inspect preserved log')


if __name__ == '__main__':
    main()
