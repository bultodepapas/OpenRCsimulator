from pathlib import Path
import subprocess,ctypes,json,statistics
r=Path.cwd();w=r/'tmp/perf-pass4-20261019';engine=r/'.tools/Godot_v4.7.2-stable_win64.exe'
cmd=[str(engine),'--headless','--path',str(w/'base/app'),'--audio-driver','Dummy','--script',str(w/'component.gd'),'--','--output='+str(w/'component.json')]
k=ctypes.WinDLL('kernel32',use_last_error=True);f=k.SetProcessAffinityMask;f.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
assert f(int(p._handle),16)
log,_=p.communicate(timeout=180);(w/'component.log').write_text(log)
assert p.returncode==0 and 'ERROR:' not in log and 'FAIL' not in log,log
d=json.loads((w/'component.json').read_text());assert d['complete']
rows=[]
for row in d['cases']:
 before=row['before_usec'];after=row['after_usec']
 rows.append({'label':row['label'],'before_usec_per_call':statistics.median(before)/d['iterations'],'after_usec_per_call':statistics.median(after)/d['iterations'],
  'paired_reduction_percent':statistics.median(100*(1-b/a) for a,b in zip(before,after))})
(w/'component-command.json').write_text(json.dumps({'command':cmd,'affinity_mask':16,'summary':rows},indent=2))
print(json.dumps(rows,indent=2))
