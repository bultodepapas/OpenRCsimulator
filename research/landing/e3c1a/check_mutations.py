#!/usr/bin/env python3
"""E3c1a: prove the landing checks reject defects, exclusively in disposable copies."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, default=ROOT / 'app')
parser.add_argument('--godot', type=Path, required=True)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
mutations = {
    'descent_without_flare': ('sim/landing_maneuver.gd',
        'var target_sink: float = minf(0.8, 0.15 + 0.35 * maxf(clearance, 0.0))',
        'var target_sink: float = 2.0', 1),
    'omit_contact_rotation': ('tests/landing_test_driver.gd',
        'M.cross(M.v3(s[10], s[11], s[12]), r)', 'M.v3(0.0, 0.0, 0.0)', 1),
    'bypass_crash_detector': ('tests/landing_test_driver.gd',
        'session._physics_process(dt)', 'pass # intentional mutation: crash detector bypassed', 2),
    'late_approach_runs_off_strip': ('sim/landing_maneuver.gd',
        'START_BEFORE_END: float = 94.0', 'START_BEFORE_END: float = 79.0', 1),
}
report = {}
with tempfile.TemporaryDirectory(prefix='openrc-e3c1a-mutations-') as tmp:
    app = Path(tmp) / 'app'
    shutil.copytree(args.app, app, ignore=shutil.ignore_patterns('.godot', 'captures'))
    sources = {path: (app / path).read_text() for path, *_ in mutations.values()}
    for name, change in [('control', None), *mutations.items()]:
        for path, source in sources.items():
            (app / path).write_text(source)
        if change:
            path, old, new, count = change
            source = sources[path]
            assert source.count(old) == count, f'{name}: mutation target changed'
            (app / path).write_text(source.replace(old, new))
        run = subprocess.run([str(args.godot.resolve()), '--headless', '--audio-driver', 'Dummy',
                              '--path', str(app), '--script', 'res://tests/test_landing_maneuver.gd',
                              '--', '--quick'], capture_output=True, text=True, timeout=60)
        log = run.stdout + run.stderr
        failures = [line for line in log.splitlines() if line.startswith('FAIL ')]
        engine_error = bool(re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M))
        completed = bool(re.search(r'^\d+ checks, \d+ failed$', log, re.M))
        accepted = completed and not engine_error and (
            run.returncode == 0 and not failures if name == 'control' else run.returncode == 1 and bool(failures))
        report[name] = dict(accepted=accepted, exit_code=run.returncode, engine_error=engine_error,
                            completed=completed, assertion_failures=failures)
rendered = json.dumps(report, indent=2) + '\n'
if args.output:
    args.output.write_text(rendered)
print(rendered, end='')
raise SystemExit(0 if all(v['accepted'] for v in report.values()) else 1)
