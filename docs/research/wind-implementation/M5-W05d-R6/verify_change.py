"""Sequential use of existing checked-runner and ORFL tools; no timing claims."""
from pathlib import Path
import csv
import json
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
WORK=Path(__file__).resolve().parent
ENGINE=ROOT/'.tools/Godot_v4.8-beta1_win64_console.exe'
tests=['test_spatial_gust_index','test_spatial_wind_field','test_spatial_wind_prepared',
       'test_spatial_stage_lean','test_spatial_wind_benchmark','test_spatial_weather_session','test_golden']
for name in tests:
 command=[sys.executable,str(ROOT/'tools/godot/run_checked.py'),'--timeout','300','--out-dir',str(WORK/'checks'),
     '--label',name,'--',str(ENGINE),'--headless','--path',str(WORK/'candidate/app'),
     '--script',f'res://tests/{name}.gd']
 run=subprocess.run(command,capture_output=True,text=True)
 if run.returncode: raise RuntimeError(run.stdout+run.stderr)
 print(name+': passed',flush=True)

out=WORK/'replay'
log=WORK/'extra-active-baseline.orfl'
for label,tree,verb in [('export','baseline','export'),('exact','baseline','replay'),('candidate','candidate','replay')]:
 command=[sys.executable,str(WORK/tree/'tools/flight_log/flight_log.py'),verb,str(log),'--out',str(out/label),'--godot',str(ENGINE)]
 if label=='candidate': command += ['--candidate',str(WORK/'candidate/app/data/aircraft/gp_extra_300s_60.json')]
 run=subprocess.run(command,capture_output=True,text=True)
 (WORK/f'replay-{label}.cli.log').write_text(run.stdout+run.stderr)
 if run.returncode: raise RuntimeError(run.stdout+run.stderr)
 print(label+': completed',flush=True)
def rows(p):
 with p.open(newline='',encoding='utf-8') as f: return list(csv.reader(f))
original=rows(out/'export/flight.csv')
assert original==rows(out/'exact/flight.csv')==rows(out/'candidate/flight.csv')
reports={label:json.loads((out/label/('export.json' if label=='export' else 'replay.json')).read_text()) for label in ['export','exact','candidate']}
assert all(x['status']=='ok' and x['complete'] for x in reports.values())
assert reports['exact']['solver_changed'] is False and reports['candidate']['solver_changed'] is True
command=[sys.executable,str(WORK/'candidate/tools/flight_log/flight_log.py'),'compare',str(out/'export/flight.csv'),str(out/'candidate/flight.csv'),'--out',str(out/'comparison.json')]
subprocess.run(command,check=True,capture_output=True)
(out/'parity.json').write_text(json.dumps({'all_csv_cells_equal':True,'rows':len(original)-1,'columns':len(original[0]),
    'complete':True,'exact_solver_changed':False,'candidate_solver_changed':True},indent=2)+'\n')
print(f'PASS: {len(original)-1} complete recorded rows retain identical CSV cells',flush=True)
