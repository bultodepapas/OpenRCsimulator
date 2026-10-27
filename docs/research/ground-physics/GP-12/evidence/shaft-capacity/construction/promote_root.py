from pathlib import Path
import hashlib
import json
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
manifest_path = HERE / 'manifest.json'
assert sha(manifest_path) == '2d6ce78558d5051fec1b6d6721af0d7997223741acbdec208bc230daf9db5208'
manifest = json.loads(manifest_path.read_text())
for item in manifest['payloads']:
    source, target = HERE / 'production' / item['path'], ROOT / item['path']
    assert sha(source) == item['sha256'] and source.stat().st_size == item['bytes'], item['path']
    if item['prehash'] is None:
        assert not target.exists(), item['path']
    else:
        assert sha(target) == item['prehash'], 'Preserve concurrent edits: ' + item['path']
for item in manifest['payloads']:
    source, target = HERE / 'production' / item['path'], ROOT / item['path']
    if target.exists():
        backup = HERE / 'root-before' / item['path']
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(target, backup)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
receipt = {'format': 'openrc-shaft-capacity-promotion v1', 'files': {item['path']: sha(ROOT / item['path']) for item in manifest['payloads']}, 'scope': 'Stable fixed-source row binding and motor-off capture; powered startup remains refused'}
(HERE / 'root-promotion.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
