from pathlib import Path
import hashlib
import json
import shutil

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
review=HERE/'review-v1'
manifest=json.loads((review/'manifest.json').read_text())
final=json.loads((review/'final-integration.json').read_text())
assert hashlib.sha256((review/'manifest.json').read_bytes()).hexdigest()==final['review_manifest']['sha256']
assert final['sourcecheck']['unchanged_verified_files']==80
for item in manifest['main_prehashes']:
    assert hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()==item['sha256'],item['path']
old_paths={item['path'] for item in manifest['main_prehashes']}
for item in manifest['payload']:
    assert hashlib.sha256((ROOT/item['production']['path']).read_bytes()).hexdigest()==item['production']['sha256']
    if item['target'] not in old_paths:
        assert not (ROOT/item['target']).exists(),item['target']+' already exists'
before=HERE/'root-before'
assert not before.exists()
before.mkdir()
for item in manifest['main_prehashes']:
    shutil.copyfile(ROOT/item['path'],before/Path(item['path']).name)
for item in manifest['payload']:
    shutil.copyfile(ROOT/item['production']['path'],ROOT/item['target'])
receipt={'format':'openrc-integrated-contact-capacity-promotion-v1',
    'final_integration_sha256':hashlib.sha256((review/'final-integration.json').read_bytes()).hexdigest(),
    'files':{item['target']:item['production']['sha256'] for item in manifest['payload']},
    'source_projection':'exact reviewed production bytes; validated drafts differ only in import paths',
    'stock_activation':False}
(HERE/'root-promotion.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print(json.dumps(receipt,indent=2))
