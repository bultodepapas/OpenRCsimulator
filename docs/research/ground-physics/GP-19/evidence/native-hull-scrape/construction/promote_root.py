from pathlib import Path
import hashlib
import json
import shutil

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
manifest=json.loads((HERE/'manifest.json').read_text())
for path,digest in manifest['base_sha256'].items():
    assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path+' changed'
for path,digest in manifest['draft_sha256'].items():
    assert hashlib.sha256((HERE/'draft'/Path(path).name).read_bytes()).hexdigest()==digest,path+' draft changed'
for path,digest in manifest['runtime_pins'].items():
    assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path+' runtime changed'
before=HERE/'before'
assert not before.exists()
before.mkdir()
for path in manifest['base_sha256']:
    shutil.copyfile(ROOT/path,before/Path(path).name)
    shutil.copyfile(HERE/'draft'/Path(path).name,ROOT/path)
# The tool fixture is still an external checked script, now inheriting installed probe.
fixture=(HERE/'draft/test_probe_fixtures.gd').read_text()
fixture=fixture.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-native/draft/gameplay_probe.gd',str(ROOT/'tools/audio/gameplay_probe.gd').replace('\\','/'))
(HERE/'test_installed_probe.gd').write_text(fixture,encoding='utf-8',newline='\n')
receipt={'format':'openrc-hull-native-tool-promotion-v1','manifest_sha256':hashlib.sha256((HERE/'manifest.json').read_bytes()).hexdigest(),
         'files':manifest['draft_sha256'],'runtime_unchanged':manifest['runtime_pins']}
(HERE/'promotion.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print(json.dumps(receipt,indent=2))
