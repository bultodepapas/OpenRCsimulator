from pathlib import Path
import json, shutil, subprocess
r = Path.cwd()
w = r / 'tmp/perf-20261019-work'
app = w / 'profile/app'
for path in ['tests/test_lake_definition_cache.gd', 'tests/fixtures/lake_definition_reference.gd']:
    shutil.copyfile(r / 'app' / path, app / path)
leaf = app / 'physics/lake_surface.gd'
original = leaf.read_bytes()
try:
    text = leaf.read_text()
    assert text.count('lake == cached') == 1
    leaf.write_text(text.replace('lake == cached', 'str(lake.get("identity")) == str(cached.get("identity"))'))
    result = subprocess.run([str(r / '.tools/Godot_v4.7.2-stable_win64.exe'), '--headless',
        '--path', str(app), '--audio-driver', 'Dummy', '--script', 'res://tests/test_lake_definition_cache.gd'],
        capture_output=True, text=True, timeout=30)
    log = result.stdout + result.stderr
    (w / 'verification/identity-only-mutation.log').write_text(log)
    failures = [line for line in log.splitlines() if line.startswith('FAIL ')]
    assert result.returncode == 1 and len(failures) > 10 and 'ERROR:' not in log
    (w / 'verification/mutation.json').write_text(json.dumps({'mutation': 'identity label instead of full value equality',
        'exit_code': result.returncode, 'rejected': True, 'failing_assertions': len(failures)}, indent=2))
    print('Intentional identity-only defect rejected:', len(failures), 'failing assertions')
finally:
    leaf.write_bytes(original)
