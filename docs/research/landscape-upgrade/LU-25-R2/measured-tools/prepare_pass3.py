from pathlib import Path
import shutil,os,json,hashlib,subprocess
r=Path.cwd();w=r/'tmp/perf-pass3-20261019';w.mkdir(exist_ok=True)
for name in ['base','profile']:
 app=w/name/'app';shutil.copytree(r/'app',app,ignore=lambda path,names:[n for n in names if n in ('assets','.godot')])
 for p in ['assets','.godot']:os.symlink(r/'app'/p,app/p,target_is_directory=True)
 for p in ['assets','research','tools']:os.symlink(r/p,app.parent/p,target_is_directory=True)
files={p.relative_to(w/'base/app').as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for d in ['sim','physics','data','input','app_state','scenery','environment','landscapes'] for p in (w/'base/app'/d).rglob('*') if p.is_file() and p.suffix in ('.gd','.json')}
(w/'source-hashes.json').write_text(json.dumps(files,indent=2))
s=(r/'tmp/perf-pass2-20261019/instrument.py').read_text().replace('tmp/perf-pass2-20261019','tmp/perf-pass3-20261019')
s=s.replace("prof='''extends RefCounted", "selected['physics/ground_terrain.gd'] = ['sample_validated', '_sample_microrelief_validated', 'is_valid_surface_table', 'amplitude_for_rolling_factor']\nselected['physics/ground_wheels.gd'] += ['frame', 'coefficients', 'anchor_step', 'compressions']\nselected['physics/lake_surface.gd'] += ['sample_terrain_validated']\nprof='''extends RefCounted")
(w/'instrument.py').write_text(s);subprocess.run(['python',str(w/'instrument.py')],check=True)
