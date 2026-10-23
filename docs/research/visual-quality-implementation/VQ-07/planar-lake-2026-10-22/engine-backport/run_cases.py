"""Serial native diagnostics against an explicitly selected custom engine."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path.cwd()
BUILD = Path('D:/OpenRC-builds/godot-vq07-20261022')
PROJECT = BUILD / 'project'
PHASE = sys.argv[1]
assert PHASE in ('baseline', 'patched')
engine = next((BUILD / PHASE).glob('*.console.exe'))
assert subprocess.check_output(['git', '-C', str(PROJECT), 'rev-parse', 'HEAD'], text=True).strip().startswith('2830d895')
out = BUILD / 'runs' / PHASE
out.mkdir(parents=True, exist_ok=False)
fixture = PROJECT / 'docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/engine-lifetime'
cases = []


def project_identity():
    paths = subprocess.check_output(['git', '-C', str(PROJECT), 'ls-files', '-z', 'app']).decode().split('\0')
    return {name: hashlib.sha256((PROJECT / name).read_bytes()).hexdigest() for name in paths if name}


before = project_identity()
(out / 'app-before.json').write_text(json.dumps(before, indent=2) + '\n')


def run(label, profile, script, args, mode='', marker='minimal lifetime complete'):
    env = os.environ.copy()
    env['OPENRC_LAKE_REFLECTIONS'] = mode
    env['TEMP'] = env['TMP'] = str(BUILD / 'temp')
    command = [sys.executable, str(ROOT / 'tools/godot/run_checked.py'),
               '--out-dir', str(out / 'checks'), '--label', label, '--timeout', '120',
               '--require-text', marker, '--', sys.executable,
               str(PROJECT / 'tools/graphics/launch.py'), '--godot', str(engine),
               '--profile', profile, '--audio-driver', 'Dummy', '--resolution', '1920x1080',
               '--script', str(script), '--', *args]
    result = subprocess.run(command, env=env, cwd=ROOT)
    cases.append({'label': label, 'exit_code': result.returncode, 'command': command, 'lake_reflections': mode})
    (out / 'commands.json').write_text(json.dumps(cases, indent=2) + '\n')
    if result.returncode:
        raise SystemExit(result.returncode)


run('no-probe', 'high', fixture / 'minimal.gd', [])
run('one-probe', 'high', fixture / 'minimal.gd', ['--probe'])
run('four-worlds', 'high', fixture / 'once_cycles.gd', ['--probe', '--cycles=4'], marker='isolated worlds complete')
for profile, mode in [('high', ''), ('high', 'planar'), ('standard', 'planar')]:
    label = profile + '-' + (mode or 'probe')
    run(label, profile, Path(__file__).with_name('lake_parity.gd'),
        ['--out=' + str(out / label)], mode, marker='engine lake parity complete')
after = project_identity()
(out / 'app-after.json').write_text(json.dumps(after, indent=2) + '\n')
assert before == after, 'Tracked app bytes changed during native cases'
print('engine cases complete:', PHASE)
