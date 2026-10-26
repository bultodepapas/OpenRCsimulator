from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
source = root / 'app/sim/flight_session.gd'
pins = json.loads((out/'source-hashes.json').read_text())
assert hashlib.sha256(source.read_bytes()).hexdigest() == pins['before'], 'shared Session changed; review first'
draft = (out/'flight_session.gd').read_bytes()
assert hashlib.sha256(draft).hexdigest() == pins['draft']
draft = draft.replace(b'## Historical configuration routes retain their established ordering.', b'## Pending weather selection uses the same guarded closure without a tick.\n## Shaft configuration retains its historical ordering pending migration.')
test = (out/'test_weather_publication.gd').read_text()
test = test.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp-weather-publication/flight_session.gd','res://sim/flight_session.gd')
old = '\tvar expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp-weather-publication/baseline.json"))'
assert test.count(old)==1
expected = json.loads((out/'baseline.json').read_text())
test = test.replace(old, '\t# Complete 25-endpoint traces captured before GP-14h; see its evidence cohort.\n\tvar expected: Dictionary = '+json.dumps(expected, sort_keys=True))
dest = root/'app/tests/test_weather_publication.gd'
assert not dest.exists()
source.write_bytes(draft)
dest.write_bytes(test.encode())
report = {'before':pins['before'], 'after':{str(p.relative_to(root)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,dest]}}
(out/'promotion.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
