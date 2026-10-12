"""Linux fresh-checkout app/test.sh, with recorded continuation after baseline failures.

Run inside the reviewed clone. Each process tree receives isolated Godot user data.
This does not turn a continued suite into an uninterrupted green app/test.sh.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', required=True, type=Path)
    p.add_argument('--out', required=True, type=Path)
    a = p.parse_args()
    a.root = a.root.resolve()
    a.out.mkdir(parents=True, exist_ok=False)
    app = a.root / 'app'
    godot = a.root / '.tools/Godot_v4.7.2-stable_linux.x86_64'
    records = []

    def run(name, command, timeout):
        index = len(records)
        env = os.environ.copy()
        for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
            env[key] = str(a.root / '.tools/user-data' / str(index) / key)
        start = time.monotonic()
        try:
            done = subprocess.run(command, cwd=a.root, env=env, capture_output=True, text=True, timeout=timeout)
            log, code = done.stdout + done.stderr, done.returncode
        except subprocess.TimeoutExpired as e:
            log = (e.stdout or b'').decode(errors='replace') + (e.stderr or b'').decode(errors='replace')
            code = 124
        (a.out / f'{index:03}.log').write_text(log)
        result = dict(name=name, exit=code, engine_errors=bool(re.search(r'^(SCRIPT |SHADER )?ERROR:', log, re.M)),
                      seconds=round(time.monotonic()-start, 2), log=f'{index:03}.log')
        records.append(result)
        (a.out / 'results.json').write_text(json.dumps(records, indent=2)+'\n')
        print(json.dumps(result), flush=True)
        return result, log

    initial, log = run('app/test.sh uninterrupted attempt', ['bash', str(app / 'test.sh')], 2400)
    if initial['exit'] == 0 and not initial['engine_errors']:
        return
    reached = re.findall(r'^== (test_\S+\.gd)$', log, re.M)
    after = reached[-1] if reached else ''
    for script in sorted((app / 'tests').glob('test_*.gd')):
        if script.name > after:
            run(script.name, [str(godot), '--headless', '--path', str(app), '--audio-driver', 'Dummy',
                             '--script', 'res://tests/' + script.name], 90)
    script = (app / 'test.sh').read_text()
    tail = script[script.index('echo "== H7:'):]
    blocks = re.split(r'(?=^echo "== )', tail, flags=re.M)
    header = f'''#!/usr/bin/env bash
set -euo pipefail
HERE='{app}'
GODOT='{godot}'
run() {{ timeout 60 "$GODOT" --headless --path "$HERE" --audio-driver Dummy "$@"; }}
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
'''
    for index, block in enumerate(blocks):
        if not block.strip():
            continue
        path = a.root / '.tools' / f'p51-tail-{index:02}.sh'
        path.write_text(header + block)
        run(block.splitlines()[0], ['bash', str(path)], 600)
    raise SystemExit(int(any(r['exit'] or r['engine_errors'] for r in records)))


if __name__ == '__main__':
    main()
