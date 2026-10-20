from pathlib import Path
import subprocess,json,time,shutil
r=Path.cwd();w=r/'tmp/perf-pass2-20261019';out=w/'verification';e=r/'.tools/Godot_v4.7.2-stable_win64.exe'
s=(w/'flight_session_candidate.gd').read_text();i=s.index('\nfunc ');s=s[:i]+'\nvar _ground_offset_mutation_armed := false\n'+s[i:]
s=s.replace('var first_wheel: int = wheel_index()', 'var first_wheel: int = wheel_index() + (1 if _ground_offset_mutation_armed else 0)')
(w/'flight_session_offset_mutation.gd').write_text(s)
test=(w/'test_ground_stage_queries.gd').read_text().replace('path_join("flight_session_candidate.gd")','path_join("flight_session_offset_mutation.gd")')
test=test.replace('\tvar initial_equal: bool =', '\tcandidate._ground_offset_mutation_armed = true\n\tvar initial_equal: bool =',1)
test=test.replace('\tcandidate.reset()','\tcandidate._ground_offset_mutation_armed = false\n\tcandidate.reset()\n\tcandidate._ground_offset_mutation_armed = true')
(w/'test_offset_mutation.gd').write_text(test)
ledger=[]
for name,script in [('armed-offset-mutation',str(w/'test_offset_mutation.gd')),('baseline-golden','res://tests/test_golden.gd')]:
 cmd=[str(e),'--headless','--path',str(w/'base/app'),'--audio-driver','Dummy','--script',script]
 t=time.monotonic();q=subprocess.run(cmd,capture_output=True,text=True,timeout=300);log=q.stdout+q.stderr
 (out/(name+'.log')).write_text(log,encoding='utf-8')
 ledger.append({'name':name,'command':cmd,'exit_code':q.returncode,'engine_error':'ERROR:' in log,'seconds':time.monotonic()-t})
 print(name,q.returncode,log[-350:],flush=True)
 assert q.returncode==1 and 'ERROR:' not in log
 if name=='armed-offset-mutation': assert 'FAIL' in log
 else:
  before=[x for x in log.splitlines() if x.startswith('FAIL ')]
  after=[x for x in (out/'test_golden.log').read_text().splitlines() if x.startswith('FAIL ')]
  assert len(before)==4 and before==after
(out/'final-checks.json').write_text(json.dumps({'checks':ledger,'golden_failure_lines_equal':True,'mutation_caught':True,'mutation_note':'Armed after valid setup and disarmed for reset to test direct stage behavior. The earlier always-on mutation also broke setup; that diagnostic log is retained separately.'},indent=2))
print('Exact golden baseline comparison and deliberate mutation checks PASS')
