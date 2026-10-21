from pathlib import Path
import subprocess,sys,os,json
repo=Path(__file__).resolve().parents[1]
root=Path('D:/OpenRCsimulator-scratch/pacing-20261021-ffc2974d')
variant=sys.argv[1]
assert variant in ('release','collector','diagnostic','dependency','updated')
env=os.environ.copy()
def git(*args): return subprocess.check_output(['git',*args],cwd=repo,text=True).strip()
env.update(OPENRC_BUILD_DESCRIBE=git('describe','--tags','--always')+('-'+variant if variant!='release' else ''),OPENRC_BUILD_COMMIT=git('rev-parse','HEAD'),OPENRC_BUILD_DIRTY='1' if variant!='release' else '0',OPENRC_BUILD_DATE=git('show','-s','--format=%cI','HEAD'))
(root/'provenance'/f'{variant}-build-environment.json').write_text(json.dumps({k:v for k,v in env.items() if k.startswith('OPENRC_BUILD_')},indent=2)+'\n')
command=[sys.executable,str(repo/'tools/godot/run_checked.py'),'--out-dir',str(root/'checks'),'--label',variant+'-export','--timeout','180','--',str(repo/'.tools/Godot_v4.7.2-stable_win64.exe'),'--headless','--path',str(root/'snapshot/app'),'--audio-driver','Dummy','--export-release','Windows',str(root/variant/'OpenRC Simulator.exe')]
result=subprocess.run(command,cwd=repo,env=env,capture_output=True,text=True)
print(result.stdout[-2000:]);print(result.stderr[-2000:])
raise SystemExit(result.returncode)
