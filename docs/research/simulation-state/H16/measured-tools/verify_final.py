from pathlib import Path
import subprocess,json,time,hashlib
r=Path.cwd(); w=r/"tmp/perf-pass2-20261019"; e=r/".tools/Godot_v4.7.2-stable_win64.exe"
out=w/"verification"; ledger=[]
def run(name,app,script,args=(),check_only=False):
    cmd=[str(e),"--headless","--path",str(app),"--audio-driver","Dummy"]
    if check_only: cmd += ["--check-only"]
    cmd += ["--script",str(script)]
    if args: cmd += ["--",*args]
    t=time.monotonic(); q=subprocess.run(cmd,capture_output=True,text=True,timeout=300)
    log=q.stdout+q.stderr; (out/(name+".log")).write_text(log,encoding="utf-8")
    row={"name":name,"command":cmd,"exit_code":q.returncode,"engine_error":"ERROR:" in log,"seconds":time.monotonic()-t}
    ledger.append(row); print(name,row,log[-150:],flush=True)
    return q.returncode,log
for name in ["sim/flight_session.gd","tests/ground_stage_reference.gd","tests/test_ground_stage_queries.gd"]:
    code,log=run("parse-"+Path(name).stem,r/"app","res://"+name,check_only=True)
    assert code==0 and "ERROR:" not in log
code,log=run("public-probe-smoke",r/"app",r/"research/performance/session_pair_probe.gd",
    ["--reference=res://tests/ground_stage_reference.gd","--candidate=res://sim/flight_session.gd",
     "--aircraft=jensen-das-ugly-stik-60","--case=trim","--warmup=240","--samples=1200",
     "--output="+str(out/"public-probe-smoke.json")])
assert code==0 and "ERROR:" not in log
smoke=json.loads((out/"public-probe-smoke.json").read_text())
assert smoke["complete"] and smoke["completed_batches"]==10 and smoke["fingerprints"][0]==smoke["fingerprints"][1]
# Disposable mutation: a wrong offset must be caught by the original-method oracle.
s=(w/"flight_session_candidate.gd").read_text(); needle="var first_wheel: int = wheel_index()"
assert s.count(needle)==1
mutant=w/"flight_session_offset_mutation.gd"; mutant.write_text(s.replace(needle,needle+" + 1"))
test=(w/"test_ground_stage_queries.gd").read_text().replace('path_join("flight_session_candidate.gd")','path_join("flight_session_offset_mutation.gd")')
mutant_test=w/"test_offset_mutation.gd"; mutant_test.write_text(test)
code,log=run("offset-mutation",w/"base/app",mutant_test)
assert code==1 and "FAIL" in log and "ERROR:" not in log
code,log=run("baseline-golden",w/"base/app","res://tests/test_golden.gd")
current=(out/"test_golden.log").read_text()
a=[line for line in log.splitlines() if line.startswith("FAIL ")]
b=[line for line in current.splitlines() if line.startswith("FAIL ")]
assert code==1 and "ERROR:" not in log and len(a)==4 and a==b, (a,b)
(out/"final-checks.json").write_text(json.dumps({"checks":ledger,"golden_failure_lines_equal":True,"mutation_caught":True},indent=2))
print("Final checks PASS; four pre-existing golden failure lines exactly match frozen baseline",flush=True)
