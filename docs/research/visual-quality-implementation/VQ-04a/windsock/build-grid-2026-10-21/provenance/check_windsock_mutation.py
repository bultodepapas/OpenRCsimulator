from pathlib import Path
import subprocess,sys,json
repo=Path.cwd();root=Path('D:/OpenRCsimulator-scratch/windsock-grid-20261021-8b808672')
s=(root/'provenance/windsock-original.gd').read_text();a='\tarrays[Mesh.ARRAY_TEX_UV] = uvs';assert s.count(a)==1
s=s.replace(a,'\tuvs[1] += Vector2(0.0, 0.001)\n'+a,1)
p=root/'provenance/windsock-mutant-uv.gd';p.write_text(s,encoding='utf-8')
cmd=[sys.executable,str(repo/'tools/godot/run_checked.py'),'--out-dir',str(root/'checks'),'--label','expected-uv-mutation','--timeout','90','--',str(repo/'.tools/Godot_v4.7.2-stable_win64.exe'),'--headless','--path',str(repo/'app'),'--audio-driver','Dummy','--script',str(repo/'tools/ground/compare_windsock_optimization.gd'),'--','--baseline='+str(p),'--out='+str(root/'runs/expected-uv-mutation.json')]
r=subprocess.run(cmd,capture_output=True,text=True);print(r.stdout[-1500:],r.stderr[-800:])
d=json.loads((root/'runs/expected-uv-mutation.json').read_text());assert r.returncode!=0 and not d['passed'] and d['checks']['mismatches']>0
assert any(m['field']=='static_mesh.array_bytes' and m['context']['array']==4 for m in d['mismatches'])
print('PASS: disposable UV mutation rejected by static mesh byte comparison')
