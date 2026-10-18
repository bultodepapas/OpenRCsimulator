from pathlib import Path
import subprocess, json, hashlib, shutil
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tmp/tree-completion/final-lifecycle'
OUT.mkdir(exist_ok=False)
ENGINE=ROOT/'.tools/Godot_v4.7.2-stable_win64.exe'
APP=ROOT/'tmp/tree-completion/frozen-natural/candidate/app'
series=[]
for name,fixture in [('flight','tmp/tree-oak/fixtures/loading_probe.gd'),('rc-reset','tmp/tree-completion/rc_lifecycle_r2.gd')]:
    folder=OUT/name
    folder.mkdir()
    cmd=[str(ENGINE),'--path',str(APP),'--audio-driver','Dummy','--script',str(ROOT/fixture),'--','--cycles=20',f'--output={folder}/report.json']
    shutil.copy2(ROOT/fixture,folder/'fixture.gd')
    with (folder/'console.log').open('w') as log:
        p=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=600)
    row={'name':name,'command':cmd,'exit_code':p.returncode,'fixture_sha256':hashlib.sha256((ROOT/fixture).read_bytes()).hexdigest()}
    (folder/'command.json').write_text(json.dumps(row,indent=2)+'\n')
    assert not p.returncode and 'ERROR:' not in (folder/'console.log').read_text(), name
    report=json.loads((folder/'report.json').read_text())
    assert report['complete'] and len(report['cycles'])==20
    assert all(c['orphan_nodes']==0 for c in report['cycles'])
    if name=='rc-reset': assert all(c['paused_after_reset'] and c['reset_tick']==0 for c in report['cycles'])
    assert len(set(c['nodes_at_home'] for c in report['cycles']))==1
    assert len(set(c['nodes_in_flight'] for c in report['cycles']))==1
    series.append(row)
    print(name,'20 cycles complete',flush=True)
(OUT/'series.json').write_text(json.dumps(series,indent=2)+'\n')
DEST=ROOT/'docs/research/visual-quality-implementation/L6c/tree-completion/lifecycle-final'
shutil.copytree(OUT,DEST,dirs_exist_ok=True)
shutil.copy2(__file__,DEST/'run.py')
(DEST/'sha256.json').write_text(json.dumps({p.relative_to(DEST).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in DEST.rglob('*') if p.is_file()},indent=2)+'\n')
