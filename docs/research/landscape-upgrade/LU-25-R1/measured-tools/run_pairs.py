from pathlib import Path
import json,statistics,subprocess
r=Path('tmp/perf-20261019-work').resolve();d=json.loads((r/'lake-final-stik.json').read_text()); g=[100*(1-b/a) for a,b in zip(d['baseline_batch_usec'],d['candidate_batch_usec'])]; print('Stik final:',statistics.median(d['baseline_tick_usec']),statistics.median(d['candidate_tick_usec']),'paired gain',statistics.median(g),'wins',sum(x>0 for x in g),'of',len(g),flush=True)
godot=Path('.tools/Godot_v4.7.2-stable_win64_console.exe').resolve()
for aid,case in [('p51d-mustang-120','trim'),('turbo-lumber-evolution','trim'),('jensen-das-ugly-stik-60','runway'),('p51d-mustang-120','maneuver')]:
 name='lake-final-'+aid+'-'+case
 cmd=[str(godot),'--headless','--path',str(r/'profile/app'),'--audio-driver','Dummy','--script',str(r/'paired_lake.gd'),'--','--reference=res://sim/flight_session.gd','--candidate=res://sim/flight_session.gd','--output='+str(r/(name+'.json')),'--aircraft='+aid,'--case='+case,'--warmup=2400','--samples=14400']
 p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=240)
 (r/(name+'.log')).write_text(p.stdout)
 print(name, 'exit',p.returncode, p.stdout[-250:],flush=True)
 if p.returncode or 'SCRIPT ERROR:' in p.stdout or '\nERROR:' in p.stdout: raise SystemExit(1)
