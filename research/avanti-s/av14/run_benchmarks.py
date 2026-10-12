"""AV-17 same-host alternating measurements; host timings are not physical validation."""
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
    for index, label in enumerate(report['order']):
        app = getattr(a, label).resolve()
        command = [str(a.godot.resolve()), '--headless', '--path', str(app),
                   '--audio-driver', 'Dummy', '--script', 'res://tests/bench_physics.gd',
                   '--', '--aircraft=sebart-avanti-s-a200-p100rx']
        run = subprocess.run(command, capture_output=True, text=True, timeout=180)
        log = run.stdout + run.stderr
        name = f'{index}-{label}.log'
        (a.out / name).write_text(log, encoding='utf-8')
        record = {'revision': label, 'command': command, 'exit': run.returncode, 'log': name,
                  'engine_errors': bool(re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M)),
                  'data_sha256': hashlib.sha256((app / 'data/aircraft/sebart_avanti_s_a200.json').read_bytes()).hexdigest()}
        for key, prefix in [('trim_us', 'physics'), ('stalled_us', 'stalled flight')]:
            match = re.search(rf'^{prefix}: ([0-9.]+)', log, re.M)
            if not match:
                raise SystemExit('Missing benchmark output')
            record[key] = float(match.group(1))
        report['runs'].append(record)
        (a.out / 'results.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(record), flush=True)
        if record['exit'] or record['engine_errors']:
            raise SystemExit('Engine failure; inspect preserved log')


if __name__ == '__main__':
    main()
