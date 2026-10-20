from pathlib import Path
import subprocess, json, re, hashlib
r=Path.cwd(); w=r/'tmp/perf-pass3-20261019'; out=w/'verification'
engine=r/'.tools/Godot_v4.7.2-stable_win64.exe'
cmd=[str(engine),'--headless','--path',str(w/'base/app'),'--audio-driver','Dummy','--script','res://tests/test_golden.gd']
p=subprocess.run(cmd,capture_output=True,text=True,timeout=120)
log=p.stdout+p.stderr
(out/'baseline-golden.log').write_text(log,encoding='utf-8')
baseline_fail=[s for s in log.splitlines() if 'FAIL' in s]
assert len(baseline_fail)==4,baseline_fail
# Break coverage deliberately in a disposable candidate graph, leaving measured files intact.
mutation=w/'mutation'
for name in ['lake_surface','ground_terrain','hull_contact']:
    source=(w/'candidate/physics'/(name+'.gd')).read_text()
    source=source.replace((w/'candidate').as_posix(),mutation.as_posix())
    if name=='lake_surface':
        old='if _outside_expanded_polygon_aabb(lake.bank_ne_m, north, east, SAMPLE_EPSILON_M):'
        assert source.count(old)==1
        source=source.replace(old,'if true:')
    target=mutation/'physics'/(name+'.gd');target.parent.mkdir(parents=True,exist_ok=True);target.write_text(source)
test=(w/'test_lake_covered_sampling.gd').read_text().replace((w/'candidate').as_posix(),mutation.as_posix())
(mutation/'test.gd').write_text(test)
mutcmd=[str(engine),'--headless','--path',str(w/'base/app'),'--audio-driver','Dummy','--script',str(mutation/'test.gd')]
p=subprocess.run(mutcmd,capture_output=True,text=True,timeout=60)
mutlog=p.stdout+p.stderr
(out/'coverage-mutation.log').write_text(mutlog,encoding='utf-8')
assert p.returncode==1 and 'FAIL' in mutlog and 'ERROR:' not in mutlog
production={}
for name in ['lake_surface','ground_terrain','hull_contact']:
    path=r/'app/physics'/(name+'.gd')
    assert path.read_bytes()==(w/'intended/physics'/path.name).read_bytes()
    production[path.relative_to(r).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
for name,src,funcs in [('lake_covered_reference','lake_surface',['sample_terrain_validated']),('ground_terrain_covered_reference','ground_terrain',['sample','sample_validated']),('hull_contact_covered_reference','hull_contact',['prop_disc_depth'])]:
    original=(w/'base/app/physics'/(src+'.gd')).read_text()
    oracle=(r/'app/tests/fixtures'/(name+'.gd')).read_text()
    for func in funcs:
        pattern=r'static func '+func+r'\([\s\S]*?(?=\n\n|\Z)'
        assert re.search(pattern,original).group().rstrip()==re.search(pattern,oracle).group().rstrip(),func
result={'baseline_golden_command':cmd,'baseline_golden_failures':baseline_fail,'mutation_command':mutcmd,'mutation_rejected':True,'mutation_failures':sum('FAIL' in s for s in mutlog.splitlines()),'production_matches_measured_intended_source':production,'oracle_methods_match_baseline':True}
(out/'finish-checks.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
