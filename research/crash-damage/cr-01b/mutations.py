#!/usr/bin/env python3
"""CR-01b sensitivity checks: mutate only a disposable copy, require semantic failures."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    cases = [
        ('control', None, None),
        ('omit-critical-intervals', 'boundaries.sort()', 'boundaries = PackedFloat64Array([0.0, 1.0])'),
        ('omit-shortest-sign', 'if dot < 0.0:', 'if false:'),
        ('reverse-pitch-cross-term', 'q[1]*q[3]-q[0]*q[2]', 'q[1]*q[3]+q[0]*q[2]'),
        ('omit-tie-tolerance', 'root.fraction < best - TIE_FRACTION', 'root.fraction < best'),
    ]
    results = []
    with tempfile.TemporaryDirectory(prefix='openrc-cr01b-mutations-') as temp:
        project = Path(temp)/'app'
        shutil.copytree(args.candidate/'app', project, ignore=shutil.ignore_patterns('.godot'))
        target = project/'physics/hull_crossing.gd'
        source = target.read_text()
        for name, before, after in cases:
            if before is not None and source.count(before) != 1:
                raise RuntimeError('mutation target changed: '+name)
            target.write_text(source if before is None else source.replace(before, after))
            run = subprocess.run([args.godot, '--headless', '--path', str(project),
                                  '--script', 'res://tests/test_hull_crossing.gd'],
                                 env=dict(os.environ, XDG_DATA_HOME=temp+'/user'),
                                 capture_output=True, text=True, timeout=60)
            log = run.stdout+run.stderr
            failures = [line for line in log.splitlines() if line.startswith('FAIL ')]
            if 'ERROR:' in log or (name == 'control' and (run.returncode or failures)) or (name != 'control' and (run.returncode != 1 or not failures)):
                raise RuntimeError(name+' unexpected result:\n'+log)
            results.append(dict(name=name, exit_code=run.returncode, failures=failures))
    args.output.write_text(json.dumps(results, indent=2)+'\n')
    print('Control passed; four semantic mutations rejected.')


if __name__ == '__main__':
    main()
