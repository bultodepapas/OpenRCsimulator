from pathlib import Path
import subprocess,sys,shutil,json,hashlib
repo=Path.cwd();root=Path('D:/OpenRCsimulator-scratch/windsock-grid-20261021-8b808672'); target=root/'snapshot/app/render/windsock.gd'
try:
 for variant,source in [('baseline','windsock-original.gd'),('candidate','windsock-candidate.gd')]:
  shutil.copy2(root/'provenance'/source,target)
  command=[sys.executable,str(repo/'tools/godot/run_checked.py'),'--out-dir',str(root/'checks'),'--label','capture-'+variant,'--timeout','90','--',str(repo/'.tools/Godot_v4.7.2-stable_win64.exe'),'--path',str(root/'snapshot/app'),'--windowed','--resolution','960x540','--rendering-driver','opengl3','--audio-driver','Dummy','--script',str(repo/'tools/ground/capture_windsock_motion.gd'),'--','--out='+str(root/'captures'/variant)]
  r=subprocess.run(command,capture_output=True,text=True);print(variant,r.stdout[-1400:],r.stderr[-500:],flush=True)
  if r.returncode:sys.exit(r.returncode)
finally:shutil.copy2(root/'provenance/windsock-candidate.gd',target)
images=[]
for p in sorted((root/'captures/baseline').glob('*.png')):
 q=root/'captures/candidate'/p.name
 images.append({'name':p.name,'baseline_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(q.read_bytes()).hexdigest(),'exact':p.read_bytes()==q.read_bytes()})
assert len(images)==18 and all(i['exact'] for i in images),images
(root/'runs/visual-parity.json').write_text(json.dumps({'images':images,'passed':True,'scope':'18 fixed motion/lighting views; same native Compatibility renderer; not whole field or pilot acceptance'},indent=2)+'\n')
print('PASS: 18/18 native images byte identical',flush=True)
