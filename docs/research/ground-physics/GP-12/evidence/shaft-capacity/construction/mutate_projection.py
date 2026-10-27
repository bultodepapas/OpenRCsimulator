from pathlib import Path
import hashlib,json
task=Path(__file__).resolve().parent
p=task/'runtime-app/physics/aircraft_ground_electric.gd'
original=(task/'production/app/physics/aircraft_ground_electric.gd').read_bytes()
assert p.read_bytes()==original
s=original.decode()
a='return _evaluate(prepared, body, values, time_s, air, density, deflections, duty, enabled,\n\t\tprovider, gravity, brakes, downwash_cl, ground_up, trial_extension, NAN, NAN, false)'
b='var result := _evaluate(prepared, body, values, time_s, air, density, deflections, duty, enabled,\n\t\tprovider, gravity, brakes, downwash_cl, ground_up, trial_extension, NAN, NAN, false)\n\tif result.ok: result.loads[0] += 1.0\n\treturn result'
assert s.count(a)==1
p.write_text(s.replace(a,b))
(task/'mutation-source.json').write_text(json.dumps({'path':str(p),'before':hashlib.sha256(original).hexdigest(),'mutant':hashlib.sha256(p.read_bytes()).hexdigest(),'change':'disposable public evaluation force +1N; both res aliases mutate together; frozen original oracle must catch'},indent=2)+'\n')
