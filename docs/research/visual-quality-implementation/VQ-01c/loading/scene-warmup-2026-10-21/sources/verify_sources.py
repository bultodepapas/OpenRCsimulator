from pathlib import Path
import json, hashlib, subprocess
root=Path(__file__).resolve().parent
repo=root.parents[1]
baseline=json.loads((root/'source-manifest.json').read_text())
differences={}
for label,base in [('production',repo),('load-control',root/'load-control'),('load-warmup',root/'load-warmup')]:
    changed=[]
    for name,expected in baseline['sha256'].items():
        p=base/name
        actual=hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else 'missing'
        if actual!=expected: changed.append(name)
    differences[label]=changed
assert differences['production']==[], differences['production']
assert differences['load-control']==[], differences['load-control']
assert differences['load-warmup']==['app/app_root.gd'], differences['load-warmup']
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
assert head==baseline['head']
identity=root/'warmup-trial-identity.json'
old=json.loads(identity.read_text())
old['patch_control_lf_sha256']=hashlib.sha256((root/'load-control/app/app_root.gd').read_text(encoding='utf-8').encode()).hexdigest()
old['control_sha256']=hashlib.sha256((root/'load-control/app/app_root.gd').read_bytes()).hexdigest()
old['candidate_sha256']=hashlib.sha256((root/'load-warmup/app/app_root.gd').read_bytes()).hexdigest()
identity.write_text(json.dumps(old,indent=2)+'\n')
report={'head':head,'tracked_inputs_checked_per_tree':len(baseline['sha256']),'differences':differences,'scope':'tracked app, assets/aircraft and tools; ignored import/native cache not qualified'}
(root/'source-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
