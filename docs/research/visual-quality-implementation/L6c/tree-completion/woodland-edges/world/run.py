from pathlib import Path
import subprocess, json, hashlib, gzip, shutil
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tmp/tree-completion/understory-world'
OUT.mkdir(exist_ok=False)
APP=ROOT/'tmp/tree-completion/frozen-understory/candidate/app'
ENGINE=ROOT/'.tools/Godot_v4.7.2-stable_win64.exe'
prior=json.loads((ROOT/'tmp/tree-completion/world-final/summary.json').read_text())
runs=[]
for case in ['trim','runway']:
    source=next(r for r in prior['runs'] if r['label']=='candidate' and r['case']==case)
    row={'case':case}
    for action in ['record','replay']:
        cmd=[s.replace(str(ROOT/'tmp/tree-completion/frozen/candidate/app'),str(APP)).replace(str(ROOT/'tmp/tree-completion/world-final'),str(OUT)) for s in source[action+'_command']]
        with (OUT/f'{case}-{action}.log').open('w') as log:
            p=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        assert p.returncode==0 and 'ERROR:' not in (OUT/f'{case}-{action}.log').read_text()
        row[action+'_command']=cmd
    row['record']=json.loads((OUT/f'candidate-{case}.json').read_text())
    row['replay']=json.loads((OUT/f'candidate-{case}-replay.json').read_text())
    row['same_world']=row['record']['world_identity']==source['record']['world_identity']
    row['csv_byte_equal']=(OUT/f'candidate-{case}.csv').read_bytes()==(ROOT/f'tmp/tree-completion/world-final/candidate-{case}.csv').read_bytes()
    assert row['same_world'] and row['csv_byte_equal'] and row['record']['complete']
    runs.append(row)
    print(case,'same world and identical sampled states',flush=True)
(OUT/'summary.json').write_text(json.dumps({'runs':runs},indent=2)+'\n')
DEST=ROOT/'docs/research/visual-quality-implementation/L6c/tree-completion/woodland-edges/world'
DEST.mkdir(parents=True,exist_ok=True)
for p in OUT.iterdir():
    if p.suffix in ['.orfl','.csv']:
        (DEST/(p.name+'.gz')).write_bytes(gzip.compress(p.read_bytes(),mtime=0))
    else: shutil.copy2(p,DEST/p.name)
shutil.copy2(__file__,DEST/'run.py')
(DEST/'sha256.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in DEST.iterdir() if p.is_file()},indent=2)+'\n')
