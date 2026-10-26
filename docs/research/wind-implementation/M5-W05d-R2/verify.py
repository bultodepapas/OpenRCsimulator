from pathlib import Path
import csv, hashlib, json, shutil, subprocess, sys

work = Path(__file__).resolve().parent
root = work.parents[1]
app = work/'candidate/app'
godot = root/'.tools/Godot_v4.8-beta1_win64_console.exe'
out = work/'verification'
out.mkdir(exist_ok=False)
shutil.copyfile(work/'test_spatial_wind_prepared.gd', app/'tests/test_spatial_wind_prepared.gd')
results = []
tests = ['test_spatial_wind_prepared', 'test_spatial_wind_field', 'test_balanced_thermal_field',
         'test_spatial_weather_session', 'test_spatial_thermal_response', 'test_spatial_weather_trace',
         'test_spatial_wind_contract', 'test_wind_field', 'test_wind_aircraft_flow',
         'test_spatial_aero_continuation', 'test_spatial_powered_stage', 'test_spatial_wash']
for test in tests:
    command = [sys.executable, str(root/'tools/godot/run_checked.py'), '--out-dir', str(out/'checks'),
               '--label', test, '--timeout', '180', '--', str(godot), '--headless', '--path', str(app),
               '--audio-driver', 'Dummy', '--script', 'res://tests/'+test+'.gd']
    if test == 'test_spatial_weather_trace':
        command += ['--', '--out='+str(out/'candidate-self-replay.orfl')]
    run = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace')
    results.append({'test': test, 'exit_code': run.returncode})
    (out/(test+'.log')).write_text(run.stdout+run.stderr, encoding='utf-8')
    (out/'checks-summary.json').write_text(json.dumps(results, indent=2)+'\n', encoding='utf-8')
    print(test+': '+str(run.returncode), flush=True)
    if run.returncode:
        raise SystemExit(run.stdout+run.stderr)

log = root/'docs/research/wind-implementation/M5-W05d-R1/flights/spatial-exact.orfl'
baseline_cli = work.parent/'wind-spatial-admission/candidate/tools/flight_log/flight_log.py'
candidate_cli = work/'candidate/tools/flight_log/flight_log.py'
commands = [
    [sys.executable, str(baseline_cli), 'export', str(log), '--out', str(out/'export'), '--godot', str(godot)],
    [sys.executable, str(baseline_cli), 'replay', str(log), '--out', str(out/'exact'), '--godot', str(godot)],
    [sys.executable, str(candidate_cli), 'replay', str(log), '--out', str(out/'candidate'), '--godot', str(godot),
     '--candidate', str(app/'data/aircraft/jensen_ugly_stik_60.json')],
]
for index, command in enumerate(commands):
    run = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace')
    (out/('replay-'+str(index)+'.log')).write_text(run.stdout+run.stderr, encoding='utf-8')
    if run.returncode:
        raise SystemExit(run.stdout+run.stderr)
    print('replay/export '+str(index)+': passed', flush=True)
baseline_rows = list(csv.DictReader((out/'export/flight.csv').open(newline='', encoding='utf-8')))
parity = []
for name, changed in [('exact', False), ('candidate', True)]:
    report = json.loads((out/name/'replay.json').read_text())
    assert report['complete'] and report['solver_changed'] == changed and report['status'] == 'ok', report
    current_rows = list(csv.DictReader((out/name/'flight.csv').open(newline='', encoding='utf-8')))
    assert baseline_rows == current_rows, name
    command = [sys.executable, str(candidate_cli), 'compare', str(out/'export/flight.csv'),
               str(out/name/'flight.csv'), '--out', str(out/(name+'-comparison.json'))]
    subprocess.run(command, check=True, capture_output=True)
    parity.append({'run': name, 'complete': True, 'solver_changed': changed,
                   'rows': len(current_rows), 'columns': len(current_rows[0]), 'all_csv_values_identical': True,
                   'baseline_solver_sha256': report['baseline_solver_sha256'],
                   'current_solver_sha256': report['current_solver_sha256']})
(out/'replay-parity.json').write_text(json.dumps(parity, indent=2)+'\n', encoding='utf-8')
print('All replay CSV values identical', flush=True)
