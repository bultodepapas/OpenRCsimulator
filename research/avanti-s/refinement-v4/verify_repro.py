#!/usr/bin/env python3
"""Fresh local clone + current study sources; never copy ignored photos/caches."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('--captures',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    clone=Path(tempfile.mkdtemp(prefix='avanti-v4-clone-'))/'repo'
    subprocess.run(['git','clone','--quiet','--local',str(ROOT),str(clone)],check=True)
    for folder in ['av02','alignment','new-angles','user-profile']:
        shutil.copytree(ROOT/'research/avanti-s'/folder,clone/'research/avanti-s'/folder,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.godot','__pycache__'))
    assert not (clone/'references').exists()
    binary=ROOT/'.tools/Godot_v4.7.2-stable_linux.x86_64';project=clone/'research/avanti-s/av02'
    headless=[str(binary),'--headless','--path',str(project),'--script','res://verify.gd']
    def run(cmd, success=True):
        r=subprocess.run(cmd,text=True,capture_output=True,timeout=60)
        if success: assert r.returncode==0 and 'ERROR:' not in r.stdout+r.stderr,(r.stdout,r.stderr)
        return r
    run(headless+['--','--report='+str(clone/'checks.json')])
    results=[]
    common=['xvfb-run','-a',str(binary),'--path',str(project),'--audio-driver','Dummy','--rendering-driver','opengl3']
    for group,folder in [('original','alignment'),('additional','new-angles'),('profile','user-profile'),('inspector',None)]:
        output=clone/(group+'-renders')
        if folder:
            run(common+['--script','../alignment/render.gd','--','--compare-geometry',f'--fit=res://../{folder}/camera-fit.json',f'--picks=res://../{folder}/picks.json','--output-dir='+str(output)])
        else:run(common+['--script','res://inspect.gd','--','--output-dir='+str(output)])
        images=list(output.glob('*.png'));assert len(images)==({'original':3,'additional':3,'profile':1,'inspector':9}[group])
        for image in images:assert sha(image)==sha(a.captures/group/image.name),image
        results.append(dict(group=group,identical_pngs=len(images)))
    # Deliberately broken geometry only in the disposable clone.
    path=project/'geometry.json';original=path.read_text();d=json.loads(original)
    d['details']['fence_hinge_clearance_m']=-.04;path.write_text(json.dumps(d))
    mutation=run(headless,False)
    assert mutation.returncode==1 and 'Fence/aileron clearance' in mutation.stdout
    path.write_text(original)
    model=project/'model.gd';original_model=model.read_text()
    mutated=original_model.replace('data.loft.smooth_normals, false)', 'data.loft.smooth_normals, true)')
    assert mutated!=original_model;model.write_text(mutated)
    cap=run(headless,False)
    assert cap.returncode==1 and 'Fuselage cap blocks exhaust aperture' in cap.stdout
    model.write_text(original_model)
    paths=[str(f.relative_to(ROOT)) for f in (ROOT/'references/avanti-s/refinement-v4').rglob('*') if f.is_file()]
    ignored=subprocess.run(['git','check-ignore','--stdin'],input='\n'.join(paths)+'\n',cwd=ROOT,text=True,capture_output=True,check=True).stdout.splitlines()
    assert set(paths)==set(ignored)
    assert not subprocess.check_output(['git','ls-files','references/avanti-s/refinement-v4'],cwd=ROOT,text=True).strip()
    report=dict(geometry_sha256=sha(ROOT/'research/avanti-s/av02/geometry.json'),model_sha256=sha(ROOT/'research/avanti-s/av02/model.gd'),
                fresh_local_clone_with_current_source_overlay=True,references_absent=True,engine_external_to_clone=True,
                checks=json.loads((clone/'checks.json').read_text()),captures=results,
                fence_overlap_mutation_rejected=True,closed_exhaust_mutation_rejected=True,ignored_local_files=len(paths),
                app_suite_run=False,scope='Isolated Avanti visual study; no app integration or flight validation')
    a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
