from pathlib import Path
import hashlib,json,re,datetime,subprocess,difflib
root=Path.cwd();b=root/'tmp/gp12-capacity-production';review=b/'review-v1';review.mkdir(exist_ok=True)
def record(p):return {'path':p.relative_to(root).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
pre=json.loads((b/'main-prehashes.json').read_text())
for item in pre['sources']:assert record(root/item['path'])['sha256']==item['sha256']
mapping={'aircraft_ground_step.gd':'app/physics/aircraft_ground_step.gd','aircraft_ground_traction.gd':'app/physics/aircraft_ground_traction.gd','contact_capacity.gd':'app/physics/contact_capacity.gd','test_contact_capacity.gd':'app/tests/test_contact_capacity.gd','test_traction_capacity.gd':'app/tests/test_traction_capacity.gd'}
payload=[];patch=[]
for name,target in mapping.items():
    source=b/name;s=source.read_text();validation=review/'validation'/name;validation.parent.mkdir(exist_ok=True);validation.write_bytes(source.read_bytes())
    for module in ['aircraft_ground_step.gd','aircraft_ground_traction.gd','contact_capacity.gd']:
        s=s.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/'+module,'res://physics/'+module)
    dest=review/'production'/target;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(s)
    payload.append({'target':target,'production':record(dest),'validated':record(validation),'transform':'own import paths only'})
    old=(root/target).read_text()if(root/target).exists()else''
    patch.extend(difflib.unified_diff(old.splitlines(True),s.splitlines(True),fromfile=target if old else'/dev/null',tofile=target))
(review/'review.patch').write_text(''.join(patch))
checks=[]
for label,count in [('packet',78),('producer',78),('step',167),('traction',86)]:
    paths=list((b/'checks').glob('payload-'+label+'-*/report.json'));assert len(paths)==1
    p=paths[0];r=json.loads(p.read_text());assert r['ok']and r['complete']and r['warnings_as_errors']
    checks.append({'assertions':count,'report':record(p),'log':record(p.parent/'engine.log')})
paths={b/'full_owner.gd'};pending=list(paths)
imports=re.compile(r'(?:(?:preload|load)\(\s*|extends\s+)["\']([^"\']+\.gd)["\']')
while pending:
    p=pending.pop()
    for literal in imports.findall(p.read_text(encoding='utf-8-sig')):
        dep=root/'app'/literal[6:]if literal.startswith('res://')else Path(literal)
        if dep.exists()and dep not in paths:paths.add(dep);pending.append(dep)
frozen=review/'frozen';scripts=[]
for p in sorted(paths):
    text=p.read_text(encoding='utf-8-sig');original=record(p)
    for literal in imports.findall(text):
        dep=root/'app'/literal[6:]if literal.startswith('res://')else Path(literal)
        if dep in paths:text=text.replace('"'+literal+'"','"'+(frozen/dep.relative_to(root)).as_posix()+'"').replace("'"+literal+"'","'"+(frozen/dep.relative_to(root)).as_posix()+"'")
    registrations=re.findall(r'^class_name .+$',text,re.M);text=re.sub(r'^class_name .+\n','',text,flags=re.M)
    dest=frozen/p.relative_to(root);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(text)
    scripts.append({'original':original,'frozen':record(dest),'change':'import retargeting and duplicate global registration removal only','removed_registrations':registrations})
assets=[]
prior=json.loads((root/'docs/research/ground-physics/GP-12/evidence/unloaded-potential/identities.json').read_text())
for entry in prior['source']:
    p=root/entry['path']
    if p.is_file()and p.suffix!='.gd'and str(p).startswith(str(root/'app')):assets.append(record(p))
for name in ['ground_unloaded_gentle.bin','ground_unloaded_hard.bin']:assets.append(record(root/'app/tests/fixtures'/name))
for p in sorted((b/'retained-buffers').glob('*.bin')):assets.append(record(p))
manifest={'format':'openrc-shared-contact-capacity-production-draft-v1','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'dirty':subprocess.check_output(['git','status','--short'],text=True),'main_prehashes':pre['sources'],'payload':payload,'strict_focused_assertions':sum(x['assertions']for x in checks),'checks':checks,'frozen_scripts':scripts,'assets':assets,'formatting':record(b/'formatting.json'),'main_written':False,'long_tapes':'not yet run; frozen full_owner entrypoint prepared'}
(review/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'payload':[{'target':x['target'],'sha256':x['production']['sha256']}for x in payload],'strict_checks':manifest['strict_focused_assertions'],'scripts':len(scripts),'frozen_entrypoint':str(frozen/'tmp/gp12-capacity-production/full_owner.gd')},indent=2))
