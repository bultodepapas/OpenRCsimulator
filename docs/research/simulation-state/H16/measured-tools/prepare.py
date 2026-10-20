from pathlib import Path
import hashlib, json, os, shutil, subprocess
r = Path.cwd()
w = r / 'tmp/perf-pass2-20261019'
for name in ['base', 'profile']:
    app = w / name / 'app'
    shutil.copytree(r / 'app', app, ignore=lambda path, names: [n for n in names if n in ('assets', '.godot')])
    for part in ['assets', '.godot']:
        os.symlink(r / 'app' / part, app / part, target_is_directory=True)
    for part in ['assets', 'research', 'tools']:
        os.symlink(r / part, app.parent / part, target_is_directory=True)
files = {p.relative_to(w/'base/app').as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
         for parent in ['sim', 'physics', 'data', 'input', 'app_state', 'scenery', 'environment', 'landscapes']
         for p in (w/'base/app'/parent).rglob('*') if p.is_file() and p.suffix in ('.gd', '.json')}
(w / 'source-hashes.json').write_text(json.dumps(files, indent=2))
source = (r / 'tmp/perf-20261019-work/instrument.py').read_text()
source = source.replace("tmp/perf-20261019-work/profile/app", "tmp/perf-pass2-20261019/profile/app")
marker = "prof='''extends RefCounted"
extra = "selected['sim/flight_session.gd'] += ['wheel_count', 'wheel_index', 'anchor_count', 'gear_is_retractable', 'glow_is_active', 'shaft_is_coupled', 'battery_is_dynamic', 'battery_is_pack', '_rotor_index', 'current_landing_gear', 'downwash_index', 'turbine_is_continuous', '_liquid_index']\n"
source = source.replace(marker, extra + marker)
(w / 'instrument.py').write_text(source)
subprocess.run(['python', str(w / 'instrument.py')], check=True)
print('Current source frozen:', len(files), 'files')
