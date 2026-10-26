from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
DRAFT = HERE/'reader'
manifest = json.loads((DRAFT/'manifest.json').read_text())
destination = ROOT/manifest['source']
assert hashlib.sha256(destination.read_bytes()).hexdigest() == manifest['before_sha256'], 'production source changed'
assert hashlib.sha256((DRAFT/'flight_log_cli.gd').read_bytes()).hexdigest() == manifest['draft_sha256'], 'draft source changed'
test_path = ROOT/'app/tests/test_flight_log_inputs.gd'
fixture_path = ROOT/'app/tests/fixtures/flight_log_input_columns.json'
assert not test_path.exists() and not fixture_path.exists(), 'new destinations already exist'
test = (DRAFT/'test_flight_log_inputs_production.gd').read_text()
test = test.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp20-brake-input/reader/flight_log_cli.gd', 'res://tools/flight_log_cli.gd')
test = test.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp20-brake-input/reader/flight_log_input_columns.json', 'res://tests/fixtures/flight_log_input_columns.json')
assert 'tmp/gp20' not in test and 'Legacy' not in test
files = {
    destination: (DRAFT/'flight_log_cli.gd').read_bytes(),
    test_path: test.encode('utf-8'),
    fixture_path: (DRAFT/'flight_log_input_columns.json').read_bytes(),
}
for path, data in files.items():
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
receipt = {'format': 'openrc-input-roles-promotion v1', 'before_sha256': manifest['before_sha256'], 'files': {
    str(path.relative_to(ROOT)).replace('\\','/'): hashlib.sha256(data).hexdigest() for path,data in files.items()
}}
(HERE/'promotion.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print(json.dumps(receipt,indent=2))
