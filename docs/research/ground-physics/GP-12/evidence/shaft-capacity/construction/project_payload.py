from pathlib import Path
import hashlib,json,difflib,shutil
root=Path(__file__).resolve().parents[2]; task=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
records=json.loads((task/'runtime-identities.json').read_text())
for row in records:assert sha(root/row['target'])==row['prehash'],row['target']
names=['contact_capacity.gd','aircraft_ground_step.gd','aircraft_ground_electric.gd']
out=task/'production';patch=[];manifest=[]
for row in records:
    dst=out/row['target'];dst.parent.mkdir(parents=True,exist_ok=True)
    text=(root/row['draft']).read_text()
    for name in names:text=text.replace((task/'candidate'/name).as_posix(),'res://physics/'+name)
    dst.write_text(text,newline='\n')
    manifest.append({'path':row['target'],'prehash':row['prehash'],'sha256':sha(dst),'bytes':dst.stat().st_size})
    patch+=list(difflib.unified_diff((root/row['target']).read_text().splitlines(True),text.splitlines(True),fromfile=row['target'],tofile=row['target']))
text=(task/'test_shaft_capacity.gd').read_text()
for name in names:text=text.replace((task/'candidate'/name).as_posix(),'res://physics/'+name)
target='app/tests/test_shaft_capacity.gd';dst=out/target;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_text(text,newline='\n')
manifest.append({'path':target,'prehash':None,'sha256':sha(dst),'bytes':dst.stat().st_size})
target='app/tests/fixtures/ground_contact_shaft_legacy.bin';dst=out/target;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(task/'ground_contact_shaft_legacy.bin',dst)
manifest.append({'path':target,'prehash':None,'sha256':sha(dst),'bytes':dst.stat().st_size})
for row in manifest:
    dst=task/'runtime-app'/Path(row['path']).relative_to('app');dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(out/row['path'],dst)
    if row['path'].endswith('.gd'):assert 'C:/DEVELOPMENT' not in (out/row['path']).read_text() and '/tmp/' not in (out/row['path']).read_text()
(task/'manifest.json').write_text(json.dumps({'scope':'detached stable finite-bearing row mapping; startup remains refused','payloads':manifest},indent=2)+'\n')
(task/'review-production.patch').write_text(''.join(patch))
print(json.dumps(manifest,indent=2))
