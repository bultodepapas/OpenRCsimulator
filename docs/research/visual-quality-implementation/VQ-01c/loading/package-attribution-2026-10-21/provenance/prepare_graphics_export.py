from pathlib import Path
import subprocess, hashlib, json, shutil
repo=Path(__file__).resolve().parents[1]
out=Path('D:/OpenRCsimulator-scratch/graphics-export-20261021-2463af65')
assert not out.exists(), out
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
status=subprocess.check_output(['git','status','--porcelain'],cwd=repo,text=True)
assert not status,status
files=subprocess.check_output(['git','ls-files','-z','--','app','assets/aircraft','tools'],cwd=repo).decode().split('\0')
hashes={}
for name in filter(None,files):
    source=repo/name
    if not source.is_file(): continue
    target=out/'snapshot'/name
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)
    hashes[name]=hashlib.sha256(source.read_bytes()).hexdigest()
for name in ('.godot','native'):
    shutil.copytree(repo/'app'/name,out/'snapshot/app'/name,dirs_exist_ok=True)
for name in ('release','diagnostic','checks','runs','provenance','empty-host'):
    (out/name).mkdir()
(out/'provenance/source-manifest.json').write_text(json.dumps({'head':head,'status':status,'sha256':hashes,'cache':'copied existing .godot and native trees; subsequent import is isolated'},indent=2)+'\n')
shutil.copy2(__file__,out/'provenance/prepare_graphics_export.py')
print(json.dumps({'snapshot':str(out),'tracked_inputs':len(hashes),'D_free_bytes':shutil.disk_usage(out).free}))
