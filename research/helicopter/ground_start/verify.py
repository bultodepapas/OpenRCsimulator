"""HELI-20 regression evidence; logs and source hashes, no golden rewrites."""
import argparse, hashlib, json, platform, re, subprocess, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser(); p.add_argument('--godot',required=True); p.add_argument('--out',required=True); p.add_argument('--ui-only',action='store_true'); p.add_argument('--tests',nargs='+'); a=p.parse_args()
out=Path(a.out).resolve(); out.mkdir(parents=True,exist_ok=True)
godot=str(Path(a.godot).resolve())
names=['test_ui_home','test_ui_aircraft','test_ui_help','test_controls_reference','test_controller_flight_actions','test_field_loader','test_field_surfaces','test_ground_surfaces','test_ground_terrain']
if not a.ui_only: names=[x.stem for x in sorted((ROOT/'app/tests').glob('test_heli_*.gd'))]+names
if a.tests:
 names=a.tests
 if any(not re.fullmatch(r'test_[a-z0-9_]+',name) or not (ROOT/'app/tests'/f'{name}.gd').is_file() for name in names): p.error('tests must name existing test_*.gd scripts without extensions')
results=[]
for name in names:
 command=[godot,'--headless','--path',str(ROOT/'app'),'--script',f'res://tests/{name}.gd']
 started=time.perf_counter()
 try:
  r=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
  output=r.stdout+r.stderr; code=r.returncode
 except subprocess.TimeoutExpired as exc:
  output=str(exc.stdout or '')+str(exc.stderr or '')+'\nTIMEOUT'; code=-1
 (out/(name+'.log')).write_text(output,encoding='utf-8')
 ok=code==0 and not re.search(r'^(?:SCRIPT |SHADER )?ERROR:',output,re.M) and not re.search(r'^FAIL\b',output,re.M)
 counts=re.findall(r'(\d+) checks, (\d+) failed',output)
 result={'name':name,'exit_code':code,'ok':ok,'seconds':time.perf_counter()-started,'counts':counts,'log':name+'.log'}
 results.append(result); print(name, 'PASS' if ok else 'FAIL', counts, flush=True)
 (out/'verification.json').write_text(json.dumps({'platform':platform.platform(),'godot':subprocess.check_output([godot,'--version'],text=True).strip(),'results':results},indent=2),encoding='utf-8')
paths=list((ROOT/'app/physics/rotorcraft').glob('*.gd'))+[ROOT/'app/sim/helicopter_flight_session.gd',ROOT/'app/sim/rotorcraft_recorder.gd',ROOT/'app/helicopter_main.gd',ROOT/'app/data/fields/default.json',ROOT/'app/data/aircraft/xcell_60_research.json',ROOT/'app/data/aircraft/hx700_electric_3d_experimental.json']
(out/'source-sha256.json').write_text(json.dumps({x.relative_to(ROOT).as_posix():hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted(paths)},indent=2),encoding='utf-8')
raise SystemExit(0 if all(x['ok'] for x in results) else 1)
