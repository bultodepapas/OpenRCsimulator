"""Restore this bounded recorded fixture into a NEW scratch directory only."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,sys,re

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--godot',type=Path,required=True)
    parser.add_argument('--mode',choices=['restore','reaction6','rest'],default='restore')
    args=parser.parse_args()
    evidence=Path(__file__).resolve().parent
    target=args.out.resolve()
    if target==evidence or evidence in target.parents or (target.exists()and any(target.iterdir())):
        raise SystemExit('Use a new empty scratch directory outside this evidence cohort.')
    identities=json.loads((evidence/'analysis/live-identities.json').read_text())
    godot=args.godot.resolve()
    if not godot.is_file()or hashlib.sha256(godot.read_bytes()).hexdigest()!=identities['engine']['sha256']:
        raise SystemExit('The supplied Godot executable does not match the recorded engine SHA-256.')
    target.mkdir(parents=True,exist_ok=True)
    replacements=[]
    old=b'C:/DEVELOPMENT/OpenRCsimulator/'
    new=(target.as_posix()+'/').encode()
    for source in (evidence/'source-run').rglob('*'):
        if not source.is_file():continue
        relative=source.relative_to(evidence/'source-run')
        destination=target/relative
        destination.parent.mkdir(parents=True,exist_ok=True)
        raw=source.read_bytes()
        relocated=raw.replace(old,new)if source.suffix=='.gd'else raw
        destination.write_bytes(relocated)
        replacements.append({'path':relative.as_posix(),'recorded_sha256':hashlib.sha256(raw).hexdigest(),
            'restored_sha256':hashlib.sha256(relocated).hexdigest(),'absolute_imports_relocated':raw!=relocated})
    for suffix in ['6s','10s']:
        shutil.copyfile(evidence/'rest'/('checkpoint-'+suffix+'.bin'),target/'tmp/gp12-local-reuse'/('checkpoint-'+suffix+'.bin'))
    # This retained subset is a physics fixture, not an application export.
    # Preserve its complete recorded physics section, omit unavailable UI/
    # translation/editor-plugin assets, and record this explicit isolation.
    original_project=(target/'app/project.godot').read_bytes()
    physics=re.search(rb'(?ms)^\[physics\]\r?\n.*?(?=^\[|\Z)',original_project)
    if physics is None:raise SystemExit('Recorded project has no physics section.')
    isolated_project=b'config_version=5\n\n[application]\nconfig/name="Recorded ground physics fixture"\n\n'+physics.group(0)
    (target/'app/project.godot').write_bytes(isolated_project)
    (target/'restoration.json').write_text(json.dumps({'scope':'Exact recorded source except declared absolute-import relocation; no physical arithmetic change.',
        'engine_sha256':identities['engine']['sha256'],'files':replacements,
        'project_isolation':{'scope':'UI/translation/editor assets omitted; captured physics section retained byte-for-byte.',
            'original_sha256':hashlib.sha256(original_project).hexdigest(),'isolated_sha256':hashlib.sha256(isolated_project).hexdigest(),
            'physics_section_sha256':hashlib.sha256(physics.group(0)).hexdigest()}},indent=2)+'\n')
    repository=next((p for p in evidence.parents if(p/'tools/godot/run_checked.py').is_file()),None)
    if repository is None:raise SystemExit('Run from a repository checkout containing tools/godot/run_checked.py.')
    command=[sys.executable,str(repository/'tools/godot/run_checked.py'),'--out-dir',str(target/'checks')]
    if args.mode=='restore':
        print('Restored',target,'; engine and source identities recorded in restoration.json.');return
    imported=subprocess.run(command+['--label','snapshot-import','--timeout','120','--',str(godot),'--headless','--path',str(target/'app'),'--audio-driver','Dummy','--import'])
    if imported.returncode:raise SystemExit(imported.returncode)
    if args.mode=='reaction6':
        tail=['--script',str(target/'tmp/gp12-reaction-trace/review.gd')]
        label='snapshot-reaction6';timeout='120';marker='Reaction checkpoint review: 45 checks, 0 failed'
    else:
        tail=['--script',str(target/'tmp/gp12-local-reuse/live_rest.gd'),'--','--only-rest']
        label='snapshot-original-rest';timeout='3600';marker='Aircraft ground composition: 15 checks, 1 failed'
    # Original rest intentionally retains its incomplete normal-only observable:
    # expect complete=true/exit1, then inspect separate corrected reaction proof.
    result=subprocess.run(command+['--label',label,'--timeout',timeout,'--require-text',marker,'--',str(godot),'--headless','--path',str(target/'app'),'--audio-driver','Dummy']+tail)
    raise SystemExit(result.returncode)

if __name__=='__main__':main()
