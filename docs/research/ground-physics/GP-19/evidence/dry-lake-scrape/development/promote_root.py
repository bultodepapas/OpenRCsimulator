from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
source = out/'promotion'
m = json.loads((source/'manifest.json').read_text())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
for rel, digest in m['payload_sha256'].items():
    assert sha(root/rel)==m['base_sha256'][rel], rel
    assert sha(source/rel)==digest, rel
for rel in m['payload_sha256']:
    (root/rel).write_bytes((source/rel).read_bytes())
receipt = dict(m)
receipt['promotion_manifest_sha256'] = sha(source/'manifest.json')
receipt['status'] = 'four guarded payloads installed; production checks pending'
(out/'root-promotion.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'installed':4,'manifest_sha256':receipt['promotion_manifest_sha256']}))
