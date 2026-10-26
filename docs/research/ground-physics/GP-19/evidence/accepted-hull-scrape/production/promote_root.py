from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[2]
source = Path(__file__).resolve().parent / 'promotion'
manifest = json.loads((source / 'manifest.json').read_text())
sha = lambda raw: hashlib.sha256(raw).hexdigest()
paths = dict(manifest['payload_sha256'])
paths[manifest['fixture']['path']] = manifest['fixture']['sha256']
for rel, expected in paths.items():
    destination = root / rel
    destination.resolve().relative_to(root)
    assert rel.startswith('app/')
    assert sha((source / rel).read_bytes()) == expected, rel
    base = manifest['base_sha256'].get(rel)
    if base is None:
        assert not destination.exists(), f'new destination already exists: {rel}'
    else:
        assert sha(destination.read_bytes()) == base, f'base changed: {rel}'
# All source and destination guards pass before any write. Preserve unrelated paths.
for rel in paths:
    destination = root / rel
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes((source / rel).read_bytes())
attributes = root / '.gitattributes'
data = attributes.read_bytes()
line = b'/app/tests/fixtures/hull_friction_reference.bin -text'
if line not in data.splitlines():
    attributes.write_bytes(data.rstrip(b'\r\n') + b'\n' + line + b'\n')
for rel, expected in paths.items():
    assert sha((root / rel).read_bytes()) == expected, rel
receipt = dict(manifest)
receipt['manifest_sha256'] = sha((source/'manifest.json').read_bytes())
receipt['status'] = 'exact guarded payload installed; production checks pending'
(source.parent/'root-promotion.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'installed':len(paths),'manifest_sha256':receipt['manifest_sha256']}))
