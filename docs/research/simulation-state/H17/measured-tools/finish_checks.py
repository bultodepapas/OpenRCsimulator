from pathlib import Path
import subprocess,json,re,hashlib
r=Path.cwd();w=r/'tmp/perf-pass4-20261019';out=w/'verification';out.mkdir(exist_ok=True)
engine=r/'.tools/Godot_v4.7.2-stable_win64.exe'
cmd=[str(engine),'--headless','--path',str(w/'base/app'),'--audio-driver','Dummy','--script','res://tests/test_golden.gd']
p=subprocess.run(cmd,capture_output=True,text=True,timeout=120);log=p.stdout+p.stderr
(out/'baseline-golden.log').write_text(log,encoding='utf-8')
failures=[line for line in log.splitlines() if 'FAIL' in line]
assert len(failures)==4 and p.returncode==1,log
prod=r/'app/physics/slipstream.gd';assert prod.read_bytes()==(w/'intended/physics/slipstream.gd').read_bytes()
original=(w/'base/app/physics/slipstream.gd').read_text()
oracle=(r/'app/tests/fixtures/segmented_slipstream_reference.gd').read_text()
for func in ['loads','_segmented_increment']:
 pattern=r'static func '+func+r'\([\s\S]*?(?=\n\n|\Z)'
 assert re.search(pattern,original).group().rstrip()==re.search(pattern,oracle).group().rstrip(),func
sources=json.loads((w/'source-hashes.json').read_text())
assert all(hashlib.sha256((w/'base/app'/rel).read_bytes()).hexdigest()==sha for rel,sha in sources.items())
result={'baseline_golden_command':cmd,'baseline_golden_failures':failures,'original_methods_match':True,'frozen_runtime_hashes_unchanged':len(sources),
 'production_matches_measured':{prod.relative_to(r).as_posix():hashlib.sha256(prod.read_bytes()).hexdigest()}}
(out/'finish-checks.json').write_text(json.dumps(result,indent=2))
print('Baseline golden: four expected failures; original oracle methods and measured production bytes verified.')
