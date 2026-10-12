"""Refresh only final reviewed text files in the disposable Linux test checkout."""
import hashlib
import json
from pathlib import Path
import subprocess
import time

source = Path('/mnt/c/DEVELOPMENT/OpenRCsimulator')
target = Path('/var/tmp/openrc-lu21-final-20261012')
out = source / '.tools/landscape-lu16/regression-corrections'
out.mkdir(exist_ok=True)
files = [
    'app/render/field_projected_shadows.gd',
    'app/scenery/population.gd', 'app/scenery/scenery.gd',
    'app/tests/test_field_projected_shadows.gd',
    'app/tests/test_time_of_day_scenery_update.gd',
    'app/tests/test_landscape_gravel.gd',
    'app/tests/test_landscape_vegetation.gd',
]
sync = {}
for name in files:
    raw = (source / name).read_bytes()
    (target / name).write_bytes(raw.replace(b'\r\n', b'\n'))
    sync[name] = hashlib.sha256(raw).hexdigest()
(out / 'synced-source-sha256.json').write_text(json.dumps(sync, indent=2)+'\n')
tests = [
    'test_field_projected_shadows', 'test_landscape_gravel',
    'test_landscape_vegetation', 'test_replay_policy',
    'test_scenery_build', 'test_landscape_population_assets',
    'test_landscape_population', 'test_time_of_day_scenery_update',
    'test_time_of_day_render_update', 'test_world_field_lights',
    'test_landscape_checkpoint', 'test_landscape_runtime',
]
engine = target / '.tools/Godot_v4.7.2-stable_linux.x86_64'
rows = []
for name in tests:
    if not (target / ('app/tests/'+name+'.gd')).exists():
        print('Unavailable optional test', name, flush=True)
        continue
    cmd = [str(engine), '--headless', '--path', str(target / 'app'),
           '--audio-driver', 'Dummy', '--script', 'res://tests/'+name+'.gd']
    start = time.monotonic()
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
    log = p.stdout + p.stderr
    failed = p.returncode != 0 or any(x.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:')) for x in log.splitlines())
    (out / (name+'.log')).write_text(log)
    rows.append(dict(test=name+'.gd', exit=p.returncode, failed=failed,
                     seconds=time.monotonic()-start, command=cmd))
    (out / 'summary.json').write_text(json.dumps(rows, indent=2)+'\n')
    print(('FAIL ' if failed else 'PASS ')+name, flush=True)
raise SystemExit(int(any(r['failed'] for r in rows)))
