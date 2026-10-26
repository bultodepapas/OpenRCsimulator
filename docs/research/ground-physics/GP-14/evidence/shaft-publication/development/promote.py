from pathlib import Path
import hashlib,json,difflib
root=Path(__file__).resolve().parents[2]
home=Path(__file__).resolve().parent
runtime=root/'app/sim/flight_session.gd'
test=root/'app/tests/test_shaft_publication.gd'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
expected=json.loads((home/'before.json').read_text())['sha256']
assert sha(runtime)==expected, 'Session changed since reviewed baseline'
assert not test.exists(), 'Test path already exists'
runtime.write_bytes((home/'flight_session.gd').read_bytes())
test.write_bytes((home/'test_shaft_publication.gd').read_bytes())
changes=''.join(difflib.unified_diff((home/'flight_session.before.gd').read_text().splitlines(True),runtime.read_text().splitlines(True),fromfile='a/app/sim/flight_session.gd',tofile='b/app/sim/flight_session.gd'))
(home/'promotion.patch').write_text(changes,newline='\n')
report={'format':'openrc-shaft-publication-promotion-v1','before':expected,
        'after':{'app/sim/flight_session.gd':sha(runtime),'app/tests/test_shaft_publication.gd':sha(test)},'staged_or_committed':False}
(home/'promotion.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
