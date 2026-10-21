from pathlib import Path
import subprocess,sys
repo=Path.cwd();root=Path('D:/OpenRCsimulator-scratch/windsock-grid-20261021-8b808672')
for name in ['test_windsock','test_windsock_data','test_windsock_motion','test_windsock_shadow','test_flight_cue_shadows','test_field_projected_shadows','test_field_integration']:
 command=[sys.executable,str(repo/'tools/godot/run_checked.py'),'--out-dir',str(root/'checks'),'--label',name,'--timeout','90','--',str(repo/'.tools/Godot_v4.7.2-stable_win64.exe'),'--headless','--path',str(repo/'app'),'--audio-driver','Dummy','--script','res://tests/'+name+'.gd']
 r=subprocess.run(command,capture_output=True,text=True);print(name, 'PASS' if r.returncode==0 else 'FAIL',r.stdout[-1300:],r.stderr[-500:],flush=True)
 if r.returncode:sys.exit(r.returncode)
