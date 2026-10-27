from pathlib import Path
import shutil,re,json,hashlib
root=Path(__file__).resolve().parents[2]
out=Path(__file__).resolve().parent/'runtime-app'
out.mkdir(exist_ok=True)
records=[]
for p in (root/'app').rglob('*'):
    rel=p.relative_to(root/'app')
    if not p.is_file() or rel.parts[0].startswith('.') or p.suffix not in ('.gd','.json','.bin'):continue
    if rel.parts[0] not in ('physics','sim','failures','tests','data'):continue
    dst=out/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dst)
    records.append({'path':rel.as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Detached shaft-capacity pure tests"\n[physics]\ncommon/physics_ticks_per_second=240\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
(out.parent/'project-source-identities.json').write_text(json.dumps(records,indent=2)+'\n')
print(len(records),'byte-exact source/data files; presentation autoload omitted explicitly')
