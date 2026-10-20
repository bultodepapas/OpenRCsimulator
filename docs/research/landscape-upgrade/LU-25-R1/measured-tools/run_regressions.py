from pathlib import Path
import hashlib, json, subprocess, time

root = Path.cwd()
work = root / 'tmp/perf-20261019-work'
out = work / 'verification'
out.mkdir(exist_ok=True)
godot = root / '.tools/Godot_v4.7.2-stable_win64.exe'
tests = ['test_lake_definition_cache', 'test_lake_surface', 'test_lake_collision',
         'test_lake_ground_contact', 'test_lake_session', 'test_water_checkpoint',
         'test_landscape_checkpoint', 'test_landscape_collision_session',
         'test_landscape_collision_oracle', 'test_checkpoint', 'test_checkpoint_integrity',
         'test_simulation', 'test_sf_vehicle_model', 'test_heli_ground_session', 'test_golden']
ledger = []
for name in tests:
    command = [str(godot), '--headless', '--path', str(root / 'app'), '--audio-driver', 'Dummy',
               '--script', 'res://tests/' + name + '.gd']
    started = time.monotonic()
    result = subprocess.run(command, capture_output=True, text=True, timeout=360)
    log = result.stdout + result.stderr
    (out / (name + '.log')).write_text(log, encoding='utf-8')
    ok = result.returncode == 0 and 'ERROR:' not in log and 'FAIL' not in log
    entry = {'test': name, 'ok': ok, 'exit_code': result.returncode,
             'elapsed_seconds': round(time.monotonic()-started, 3),
             'test_sha256': hashlib.sha256((root / 'app/tests' / (name + '.gd')).read_bytes()).hexdigest()}
    ledger.append(entry)
    (out / 'results.json').write_text(json.dumps(ledger, indent=2))
    print(name, 'PASS' if ok else 'FAIL', entry['elapsed_seconds'], log[-160:].strip(), flush=True)
raise SystemExit(0 if all(e['ok'] for e in ledger) else 1)
