from pathlib import Path
import subprocess,sys,json,shutil
repo=Path(__file__).resolve().parents[1]
root=Path('D:/OpenRCsimulator-scratch/pacing-20261021-ffc2974d')
label=sys.argv[1]
variant=sys.argv[2] if len(sys.argv)>2 else 'release'
mode=sys.argv[3] if len(sys.argv)>3 else 'capped'
assert mode in ('capped','default','no-vsync')
folder=root/'runs'/(variant if mode=='capped' else variant+'-'+mode)
folder.mkdir(exist_ok=True)
out=folder/(label+'.json')
assert not out.exists(),out
args=[str(root/variant/'OpenRC Simulator.exe'),'--audio-driver','Dummy','--resolution','1280x720','--position','80,80','--max-fps',('0' if mode=='default' else '60'),'--','--frametimes='+out.as_posix(),'--warmup=10','--t=60']
if mode=='no-vsync': args.insert(1,'--disable-vsync')
if label.startswith('diagnostic'): args.append('--frame-diagnostics')
cmd=[sys.executable,str(repo/'tools/godot/run_checked.py'),'--out-dir',str(root/'checks'),'--label',variant+'-'+mode+'-'+label,'--timeout','110','--',*args]
p=subprocess.run(cmd,cwd=repo,capture_output=True,text=True)
print(p.stdout[-1800:]);print(p.stderr[-1000:])
reports=list((root/'checks').glob(variant+'-'+mode+'-'+label+'-*/engine.log'))
assert len(reports)==1,reports
shutil.copy2(reports[0],out.with_suffix('.log'))
raise SystemExit(p.returncode)
