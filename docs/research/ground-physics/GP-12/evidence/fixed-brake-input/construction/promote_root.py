from pathlib import Path
import hashlib
import json
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
manifest_path = HERE / 'promotion-manifest.json'
assert sha(manifest_path) == 'c1afa9ce0e2d82fdf15f40e5dd08d30eef2981e098ee1f95deed4b644478f97a'
manifest = json.loads(manifest_path.read_text())
for item in manifest['files']:
    source, target = HERE / 'payload' / item['path'], ROOT / item['path']
    assert sha(source) == item['payload_sha256'], item['path']
    if item['base_sha256'] is None:
        assert not target.exists(), item['path']
    else:
        assert sha(target) == item['base_sha256'], 'Preserve concurrent edits: ' + item['path']
for item in manifest['files']:
    source, target = HERE / 'payload' / item['path'], ROOT / item['path']
    if target.exists():
        backup = HERE / 'root-before' / item['path']
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(target, backup)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
receipt = {'format': 'openrc-fixed-brake-promotion v1', 'files': {item['path']: sha(ROOT / item['path']) for item in manifest['files']}, 'stock_data_changed': False, 'force_law_changed': False}
(HERE / 'root-promotion.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
