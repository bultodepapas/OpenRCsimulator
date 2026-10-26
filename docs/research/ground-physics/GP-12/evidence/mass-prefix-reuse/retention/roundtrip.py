from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,shutil,subprocess,uuid

ap=argparse.ArgumentParser()
ap.add_argument('--evidence',default='docs/research/ground-physics/GP-12/evidence/mass-prefix-reuse')
ap.add_argument('--out-receipt',required=True)
args=ap.parse_args()
R=Path.cwd();E=(R/args.evidence).resolve();receipt=(R/args.out_receipt).resolve()
assert not receipt.exists(),'Never overwrite a retained receipt'
base=R/'tmp'/('gp12-mass-prefix-roundtrip-'+uuid.uuid4().hex)
source=base/'fixture';clone=base/'clone';source.mkdir(parents=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(cmd,cwd=None):
 p=subprocess.run(cmd,cwd=cwd or R,capture_output=True,text=True)
 assert p.returncode==0,(cmd,p.stdout,p.stderr)
 return p.stdout.strip()

rel=E.relative_to(R)
paths=[p for p in sorted(E.rglob('*')) if p.is_file()]
before={p.relative_to(E).as_posix():sha(p)for p in paths}
for p in paths:
 q=source/rel/p.relative_to(E);q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
shutil.copyfile(R/'.gitattributes',source/'.gitattributes')
for name in ['summarize.py','run_checked.py']:
 q=source/'tools/godot'/name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(R/'tools/godot'/name,q)
run(['git','init','--quiet'],source)
run(['git','config','core.autocrlf','true'],source)
(source/'.git/info/attributes').write_text('/.gitattributes -text\n')
run(['git','add','--all'],source)
run(['git','-c','user.name=Evidence fixture','-c','user.email=evidence@example.invalid','commit','--quiet','-m','Disposable mass-prefix raw-byte transfer fixture'],source)
commit=run(['git','rev-parse','HEAD'],source)
run(['git','clone','--quiet','--no-hardlinks','--config','core.autocrlf=true',str(source),str(clone)])
(clone/'.git/info/attributes').write_text('/.gitattributes -text\n')
copied={p.relative_to(clone/rel).as_posix():sha(p)for p in sorted((clone/rel).rglob('*')) if p.is_file()}
mismatches=[k for k in sorted(set(before)|set(copied)) if before.get(k)!=copied.get(k)]
assert not mismatches,mismatches
assert sha(source/'.gitattributes')==sha(R/'.gitattributes')==sha(clone/'.gitattributes')
summaries=[]
for name in ['production/checks','hotspot/checks','optimization/checks']:
 cmd=['python','tools/godot/summarize.py',(rel/name).as_posix()]
 result=subprocess.run(cmd,cwd=clone,capture_output=True,text=True)
 assert result.returncode==0,(name,result.stdout,result.stderr)
 summaries.append({'collection':name,'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr})
after={p.relative_to(E).as_posix():sha(p)for p in sorted(E.rglob('*')) if p.is_file()}
assert before==after,'Source changed during transfer check'
data={'format':'openrc-mass-prefix-attributes-roundtrip-v1','ok':True,'complete':True,'created_utc':datetime.now(timezone.utc).isoformat(),'fixture':base.relative_to(R).as_posix(),'fixture_commit':commit,'core_autocrlf_source':run(['git','config','core.autocrlf'],source),'core_autocrlf_clone':run(['git','config','core.autocrlf'],clone),'fresh_clone':True,'no_hardlinks':True,'root_meta_only_info_attribute':'/.gitattributes -text in source and clone; no evidence-path overrides','actual_repository_staged_or_committed':False,'artifacts_compared':len(before),'sha256_mismatches':mismatches,'source_stable':True,'manifest_sha256':sha(E/'manifest.json'),'root_gitattributes_sha256':sha(R/'.gitattributes'),'cloned_summaries':summaries,'receipt_written_after_snapshot_excluded_from_itself':True}
receipt.parent.mkdir(parents=True,exist_ok=True);receipt.write_text(json.dumps(data,indent=2)+'\n')
print(json.dumps({'ok':True,'artifacts':len(before),'receipt':receipt.relative_to(R).as_posix(),'receipt_sha256':sha(receipt)},indent=2))
