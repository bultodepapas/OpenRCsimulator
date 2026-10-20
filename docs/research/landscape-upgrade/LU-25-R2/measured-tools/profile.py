from pathlib import Path
import subprocess,json,time,ctypes
r=Path.cwd();w=r/'tmp/perf-pass3-20261019';e=r/'.tools/Godot_v4.7.2-stable_win64.exe';k=ctypes.WinDLL('kernel32');f=k.SetProcessAffinityMask;f.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
ledger=[]
for label,aid,case in [('stik','jensen-das-ugly-stik-60','trim'),('p51','p51d-mustang-120','trim'),('runway','jensen-das-ugly-stik-60','runway')]:
 cmd=[str(e),'--headless','--path',str(w/'profile/app'),'--audio-driver','Dummy','--script','res://profile_probe.gd','--','--aircraft='+aid,'--case='+case,'--warmup-ticks=240','--sample-ticks=2400','--output='+str(w/('profile-'+label+'.json'))]
 p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);assert f(int(p._handle),16)
 log,_=p.communicate(timeout=300);(w/('profile-'+label+'.log')).write_text(log,encoding='utf-8');assert p.returncode==0 and 'ERROR:' not in log,log[-3000:]
 d=json.loads((w/('profile-'+label+'.json')).read_text());assert d['complete'];ledger.append({'label':label,'command':cmd})
 print(label,sorted([(round(v['self_usec']/2400,1),n,round(v['calls']/2400,1)) for n,v in d['profile'].items()],reverse=True)[:12],flush=True)
(w/'profile-commands.json').write_text(json.dumps(ledger,indent=2))
