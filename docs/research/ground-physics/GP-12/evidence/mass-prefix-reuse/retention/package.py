from pathlib import Path
from datetime import datetime,timezone
import json,hashlib,shutil,subprocess
R=Path.cwd();H=R/'tmp/gp12-hotspot-review';D=R/'tmp/gp12-mass-prefix-draft'
E=R/'docs/research/ground-physics/GP-12/evidence/mass-prefix-reuse'
E.mkdir(parents=True,exist_ok=True)
origins=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def copy(p,rel):
 q=E/rel;q.parent.mkdir(parents=True,exist_ok=True)
 if not q.exists():shutil.copyfile(p,q)
 assert sha(p)==sha(q)
 origins.append({'origin':p.relative_to(R).as_posix(),'retained':q.relative_to(E).as_posix(),'sha256':sha(q),'bytes':q.stat().st_size})

for f in ['report.json','manifest.json','README.md','build.py']:
 copy(H/f,'hotspot/'+f)
for mode in ['plain','timed']:
 for p in sorted((H/mode).rglob('*.gd')):copy(p,'hotspot/source/'+mode+'/'+p.relative_to(H/mode).as_posix())
 for p in sorted((H/mode).glob('*.result.bin')):copy(p,'hotspot/results/'+mode+'/'+p.name)
 for p in sorted((H/mode).glob('*.timings.json')):copy(p,'hotspot/results/'+mode+'/'+p.name)
hot=json.loads((H/'report.json').read_text())
for row in hot['passing_checked_reports']:
 p=R/row['path'];assert sha(p)==row['sha256']
 for name in ['report.json','engine.log']:copy(p.parent/name,'hotspot/checks/'+p.parent.name+'/'+name)

review=json.loads((D/'report.json').read_text())
for f in ['report.json','manifest.json','README.md','build.py','review.patch','production-review.patch','promotion-manifest.json','test-payload-manifest.json','test_mass_prefix.gd','paired.gd','paired-results.json','capture_production_returns.gd','baseline-production-hashes.json','baseline-bounds-hashes.json','root-promotion.json']:
 copy(D/f,'optimization/'+f)
for p in sorted((D/'optimized').rglob('*.gd')):copy(p,'optimization/source/'+p.relative_to(D/'optimized').as_posix())
for mode in ['baseline','optimized','counted']:
 for pattern in ['*.result.bin','*.timings.json']:
  for p in sorted((D/mode).glob(pattern)):copy(p,'optimization/results/'+mode+'/'+p.name)
for name in ['physics/contact_assembly_resolution.gd','driver.gd','metrics.gd']:
 copy(D/'counted'/name,'optimization/count-instrument/'+name)
counts=[{'path':p.relative_to(D/'counted').as_posix(),'sha256':sha(p)}for p in sorted((D/'counted').rglob('*.gd'))]
(E/'optimization/count-instrument/source-identities.json').write_text(json.dumps(counts,indent=2)+'\n')
for row in review['passing_checked_reports']:
 p=R/row['path'];assert sha(p)==row['sha256']
 for name in ['report.json','engine.log']:copy(p.parent/name,'optimization/checks/'+p.parent.name+'/'+name)

promotion=json.loads((D/'root-promotion.json').read_text())
for x in promotion['payload']:
 p=R/x['draft'];assert sha(p)==x['sha256']
 copy(p,'production/source/'+x['target'])
 if x['main_prehash']:
  key=x['target'][4:];text=(H/'plain'/key).read_text().replace((H/'plain').as_posix()+'/', 'res://')
  variants=[text.encode('utf-8'),text.replace('\n','\r\n').encode('utf-8')]
  raw=next((v for v in variants if hashlib.sha256(v).hexdigest()==x['main_prehash']),None)
  assert raw is not None,key
  q=E/'production/source-before'/x['target'];q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(raw)
root_checks=[]
for p in sorted((D/'root-production').glob('*/report.json')):
 x=json.loads(p.read_text());assert x['ok'] and x['complete'] and x['warnings_as_errors'] and x['counts']=={'error':0,'warning':0}
 for name in ['report.json','engine.log']:copy(p.parent/name,'production/checks/'+p.parent.name+'/'+name)
 root_checks.append({'label':x['label'],'report':'production/checks/'+p.parent.name+'/report.json','required_text':x['required_text']})
assert len(root_checks)==6

for row in hot['assets']:
 p=R/row['path'];assert sha(p)==row['current_sha256']
 copy(p,'inputs/'+row['path'])
hm=json.loads((H/'manifest.json').read_text())
for row in hm['inputs']:
 p=Path(row['path']);assert sha(p)==row['sha256']
 copy(p,'inputs/states/'+p.name)
for name in ['ground_contact_default_outputs.bin']+['ground_contact_rest_'+x+'.bin' for x in ['nonzero','proposal','range','slip','work']]:
 copy(R/'app/tests/fixtures'/name,'inputs/app/tests/fixtures/'+name)

(E/'.gitattributes').write_text('# Exact captured source, state, return, report and log bytes.\n* -text whitespace=cr-at-eol\n*.log -whitespace\n')
(E/'origins.json').write_text(json.dumps({'format':'openrc-mass-prefix-retained-origins-v1','copies':origins},indent=2)+'\n')
report={'format':'openrc-gp12-mass-prefix-retained-v1','captured_utc':datetime.now(timezone.utc).isoformat(),'production_checks':858,'production_invocations':root_checks,'hotspot_invocations':len(hot['passing_checked_reports']),'optimization_passing_invocations':len(review['passing_checked_reports']),'hotspot_complete_result_equalities':4,'optimization_complete_result_equalities':4,'warmed_pairs':10,'production_payload':promotion['payload'],'source_before_reconstruction':'Literal imports restored from captured plain sources and original CRLF restored; each complete SHA256 exactly equals recorded main_prehash.','physical_or_realtime_qualification':False,'scope':'Fixed mass prefix computation reuse; no change to physical laws, objective, bounds arithmetic, state or receipt values. Actual resting tick remains about0.7s; shared-host bounded diagnostic, no real-time qualification.','later_scalar_capacity_or_QP_patch_included':False,'main_runtime_writes_by_packager':[],'checked_copy_count':len(origins)}
(E/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(E.relative_to(R),'copied',len(origins),'files',len(list(E.rglob('*'))))
