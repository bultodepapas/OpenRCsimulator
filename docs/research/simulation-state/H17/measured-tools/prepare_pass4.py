from pathlib import Path
import shutil,os,json,hashlib,subprocess
r=Path.cwd();w=r/'tmp/perf-pass4-20261019';w.mkdir(exist_ok=True)
for name in ['base','profile']:
 app=w/name/'app';shutil.copytree(r/'app',app,ignore=lambda path,names:[n for n in names if n in ('assets','.godot')])
 for p in ['assets','.godot']:os.symlink(r/'app'/p,app/p,target_is_directory=True)
 for p in ['assets','research','tools']:os.symlink(r/p,app.parent/p,target_is_directory=True)
files={p.relative_to(w/'base/app').as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for d in ['sim','physics','data','input','app_state','scenery','environment','landscapes'] for p in (w/'base/app'/d).rglob('*') if p.is_file() and p.suffix in ('.gd','.json')}
(w/'source-hashes.json').write_text(json.dumps(files,indent=2))
(w/'baseline-head.txt').write_text(subprocess.check_output(['git','rev-parse','HEAD'],text=True))
(w/'baseline-working.patch').write_bytes(subprocess.check_output(['git','diff','--binary','HEAD','--','app']))
for name in ['instrument.py','profile.py']:
 s=(r/'tmp/perf-pass3-20261019'/name).read_text().replace('perf-pass3-20261019','perf-pass4-20261019')
 (w/name).write_text(s)
subprocess.run(['python',str(w/'instrument.py')],check=True)
subprocess.run(['python',str(w/'profile.py')],check=True)
