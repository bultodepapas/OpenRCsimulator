from pathlib import Path
import subprocess,time,json,hashlib
r=Path.cwd();w=r/'tmp/perf-pass4-20261019';out=w/'verification';out.mkdir(exist_ok=True)
engine=r/'.tools/Godot_v4.7.2-stable_win64.exe'
tests=['test_segmented_slipstream_parity','test_slipstream_sidewash','test_slipstream_scalar',
 'test_slipstream_downwash','test_wash_transport','test_p51_handling','test_p51_ground',
 'test_p51_flaps','test_p51_retracts','test_checkpoint','test_golden']
rows=[]
for name in tests:
 cmd=[str(engine),'--headless','--path',str(r/'app'),'--audio-driver','Dummy','--script','res://tests/'+name+'.gd']
 start=time.monotonic();p=subprocess.run(cmd,capture_output=True,text=True,timeout=600)
 log=p.stdout+p.stderr;(out/(name+'.log')).write_text(log,encoding='utf-8')
 row={'test':name,'command':cmd,'exit_code':p.returncode,'ok':p.returncode==0 and 'ERROR:' not in log and 'FAIL' not in log,
  'seconds':time.monotonic()-start,'test_sha256':hashlib.sha256((r/'app/tests'/(name+'.gd')).read_bytes()).hexdigest()}
 rows.append(row);(out/'results.json').write_text(json.dumps(rows,indent=2))
 print(name,'PASS' if row['ok'] else 'FAIL',round(row['seconds'],1),log[-160:].strip(),flush=True)
raise SystemExit(0 if all(x['ok'] for x in rows) else 1)
