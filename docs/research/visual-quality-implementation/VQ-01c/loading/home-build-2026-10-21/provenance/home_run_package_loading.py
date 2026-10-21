from pathlib import Path
import sys,subprocess,json
repo=Path(__file__).resolve().parents[1]
root=Path('D:/OpenRCsimulator-scratch/home-build-20261021-3f3892c7')
variant,number=sys.argv[1:]
assert variant in ('collector','diagnostic','source','dependency') and number.isdecimal()
output=root/'runs'/f'{variant}-{number}.json'
if variant=='source':
    launch=[str(repo/'.tools/Godot_v4.7.2-stable_win64.exe'),'--path',str(root/'snapshot/app')]
else: launch=[str(root/variant/'OpenRC Simulator.exe')]
command=[sys.executable,str(repo/'tools/godot/run_checked.py'),'--out-dir',str(root/'checks'),'--label',f'{variant}-native-{number}','--require-text','loading probe: 2 Home/Fly cycles','--timeout','90','--',*launch,'--audio-driver','Dummy','--windowed','--resolution','1280x720','--screen','0','--position','80,80','--max-fps','60','--',f'--output={output}','--cycles=2']
result=subprocess.run(command,cwd=root/'empty-host',capture_output=True,text=True)
print(result.stdout[-1800:]);print(result.stderr[-800:])
if result.returncode: raise SystemExit(result.returncode)
data=json.loads(output.read_text())
assert data['complete'] and len(data['cycles'])==2
if variant!='source': assert not data['execution']['editor_feature'] and not data['execution']['debug_build']
print(json.dumps({key:data[key] for key in ('home_first_draw_from_load_usec','home_first_draw_engine_elapsed_usec','cycles','scene_spans','execution')},indent=2))
