#!/usr/bin/env python3
"""CR-01c: reject render regressions on disposable copies of an imported candidate."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', required=True)
    p.add_argument('--candidate', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    mutations = [
        ('control', None, None),
        ('ignore-crossing', 'impact.crossing != null and impact.crossing.available', 'false'),
        ('use-contact-as-cg', 'position: PackedFloat64Array = impact.crossing.position_ned', 'position: PackedFloat64Array = impact.crossing.point_ned'),
        ('fallback-to-interpolation', 'return _pose_of(impact.detected_state)', 'return _pose_of(session.sim.interpolated(0.0))'),
    ]
    report = []
    with tempfile.TemporaryDirectory(prefix='openrc-cr01c-mutations-') as temp:
        app = Path(temp)/'app'
        shutil.copytree(args.candidate/'app', app)
        target = app/'main.gd'
        source = target.read_text()
        for name, old, new in mutations:
            if old is not None and source.count(old) != 1:
                raise RuntimeError('mutation target changed: '+name)
            target.write_text(source if old is None else source.replace(old, new))
            run = subprocess.run([args.godot, '--headless', '--path', str(app), '--audio-driver', 'Dummy',
                                  '--script', 'res://tests/test_crash_pose.gd'],
                                 capture_output=True, text=True, timeout=90,
                                 env=dict(os.environ, XDG_DATA_HOME=temp+'/user'))
            log = run.stdout+run.stderr
            failures = [line for line in log.splitlines() if line.startswith('FAIL ')]
            if 'ERROR:' in log or (name == 'control' and (run.returncode or failures)) or (name != 'control' and (run.returncode != 1 or not failures)):
                raise RuntimeError(name+' unexpected result:\n'+log)
            report.append(dict(name=name,exit_code=run.returncode,failures=failures))
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('Control passed; three rendering mutations rejected.')


if __name__ == '__main__':
    main()
