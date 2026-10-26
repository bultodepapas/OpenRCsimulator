from pathlib import Path
import hashlib
import json
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
manifest = json.loads((HERE / 'promotion-manifest.json').read_text())
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
test = ROOT / 'app/tests/test_traction_capacity.gd'
assert sha(test) == manifest['main_test_prehash'], 'Preserve concurrent test changes'
for item in manifest['payload']:
    source = ROOT / item['path']
    assert sha(source) == item['sha256'] and source.stat().st_size == item['bytes'], item['path']
    destination = ROOT / item['target']
    assert item['target'] == 'app/tests/test_traction_capacity.gd' or not destination.exists(), item['target']
for item in manifest['payload']:
    destination = ROOT / item['target']
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / item['path'], destination)
receipt = {'format': 'openrc-oracle-promotion v1', 'files': {item['target']: sha(ROOT / item['target']) for item in manifest['payload']}, 'runtime_changed': False}
(HERE / 'root-promotion.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
