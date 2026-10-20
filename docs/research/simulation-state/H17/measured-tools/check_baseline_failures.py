from pathlib import Path
import subprocess,json
r=Path.cwd();w=r/'tmp/perf-pass4-20261019';out=w/'verification';engine=r/'.tools/Godot_v4.7.2-stable_win64.exe'
rows=[]
for name in ['test_wash_transport','test_p51_handling']:
 cmd=[str(engine),'--headless','--path',str(w/'base/app'),'--audio-driver','Dummy','--script','res://tests/'+name+'.gd']
 p=subprocess.run(cmd,capture_output=True,text=True,timeout=600);log=p.stdout+p.stderr
 (out/('baseline-'+name+'.log')).write_text(log,encoding='utf-8')
 actual=[s for s in log.splitlines() if 'FAIL' in s]
 integrated=[s for s in (out/(name+'.log')).read_text().splitlines() if 'FAIL' in s]
 assert p.returncode==1 and 'ERROR:' not in log and actual==integrated,(name,actual,integrated)
 rows.append({'test':name,'baseline_command':cmd,'failure_lines_match':True,'failures':actual})
 (out/'baseline-failures.json').write_text(json.dumps(rows,indent=2))
 print(name,'unchanged baseline failures:',len(actual),flush=True)
