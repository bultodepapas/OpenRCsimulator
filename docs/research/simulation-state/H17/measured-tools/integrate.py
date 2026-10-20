from pathlib import Path
import subprocess,json,hashlib
r=Path.cwd();w=r/'tmp/perf-pass4-20261019';out=w/'verification';out.mkdir(exist_ok=True)
engine=r/'.tools/Godot_v4.7.2-stable_win64.exe'
def run(name,script,check=False):
 cmd=[str(engine),'--headless','--path',str(w/'base/app'),'--audio-driver','Dummy','--script',str(script)]
 if check:cmd.append('--check-only')
 p=subprocess.run(cmd,capture_output=True,text=True,timeout=120);log=p.stdout+p.stderr
 (out/(name+'.log')).write_text(log,encoding='utf-8')
 assert p.returncode==0 and 'ERROR:' not in log and 'FAIL' not in log,(name,log)
 print(name,log[-700:].strip())
run('parse-oracle',w/'segmented_slipstream_reference.gd',True)
run('draft-parity',w/'test_segmented_slipstream_parity.gd')
# A disposable quadrature-point defect must be detected before trusting the oracle.
mut=w/'mutation';mut.mkdir(exist_ok=True)
s=(w/'candidate/physics/slipstream.gd').read_text()
old='var gauss_middle: float = 0.5 * (lo + hi)'
assert s.count(old)==1
(mut/'slipstream.gd').write_text(s.replace(old,old+' + 0.001'))
t=(w/'test_segmented_slipstream_parity.gd').read_text().replace((w/'candidate/physics/slipstream.gd').as_posix(),(mut/'slipstream.gd').as_posix())
(mut/'test.gd').write_text(t)
cmd=[str(engine),'--headless','--path',str(w/'base/app'),'--audio-driver','Dummy','--script',str(mut/'test.gd')]
p=subprocess.run(cmd,capture_output=True,text=True,timeout=120);log=p.stdout+p.stderr
(out/'quadrature-mutation.log').write_text(log,encoding='utf-8')
assert p.returncode==1 and 'FAIL' in log and 'ERROR:' not in log,log
(out/'mutation.json').write_text(json.dumps({'command':cmd,'exit_code':p.returncode,'rejected':True,'summary':[line for line in log.splitlines() if 'parity:' in line]},indent=2))
target=r/'app/physics/slipstream.gd'
assert target.read_bytes()==(w/'base/app/physics/slipstream.gd').read_bytes(),'Concurrent production edit'
for target_name in ['app/tests/test_segmented_slipstream_parity.gd','app/tests/fixtures/segmented_slipstream_reference.gd']:
 assert not (r/target_name).exists(),target_name
target.write_bytes((w/'intended/physics/slipstream.gd').read_bytes())
(r/'app/tests/fixtures/segmented_slipstream_reference.gd').write_bytes((w/'segmented_slipstream_reference.gd').read_bytes())
t=(w/'test_segmented_slipstream_parity.gd').read_text();t='## H17: exact segmented-slipstream parity against original method oracles.\n'+t[t.index('extends SceneTree'):]
t=t.replace('const BaseSlipstream = preload("res://physics/slipstream.gd")','const BaseSlipstream = preload("res://tests/fixtures/segmented_slipstream_reference.gd")')
t=t.replace((w/'candidate/physics/slipstream.gd').as_posix(),'res://physics/slipstream.gd').replace('candidate script loads from the requested absolute path','candidate script loads')
(r/'app/tests/test_segmented_slipstream_parity.gd').write_text(t)
print('Integrated measured slipstream method and portable original-method regression fixtures.')
