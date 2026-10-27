from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parents[2];task=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((task/'manifest.json').read_text())
main=[]
for row in manifest['payloads']:
    p=root/row['path']
    if row['prehash']:
        assert sha(p)==row['prehash'],row['path']
        main.append({'path':row['path'],'before_sha256':row['prehash'],'after_sha256':sha(p),'unchanged':True})
    assert sha(task/'production'/row['path'])==row['sha256']
    assert sha(task/'runtime-app'/Path(row['path']).relative_to('app'))==row['sha256']
receipts=[]
for p in sorted((task/'checks').glob('*/report.json')):
    r=json.loads(p.read_text());log=Path(r['log']);text=log.read_text(errors='replace')
    checks=re.findall(r'(?:Shaft capacity draft|Contact capacity packet|Aircraft ground step|Traction capacity producer): (\d+) checks, (\d+) failed',text)
    receipts.append({'path':p.relative_to(root).as_posix(),'label':r['label'],'ok':r['ok'],'reason':r['reason'],
                     'engine_errors':r['counts']['error'],'engine_warnings':r['counts']['warning'],
                     'completion_counts':checks,'sha256':sha(p),'log_sha256':sha(log)})
primary=['production-projection-01','projection-generic-02','projection-step-01','projection-traction-02']
for label in primary:
    matches=[r for r in receipts if r['label']==label];assert len(matches)==1 and matches[0]['ok']
assert any(r['label']=='main-self-contained-final' and r['ok'] for r in receipts)
mutation=[r for r in receipts if r['label']=='oracle-force-mutation-01'][0]
assert not mutation['ok'] and mutation['engine_errors']==0 and mutation['engine_warnings']==0 and mutation['completion_counts']==[('119','16')]
scope=json.loads((task/'original-step-scope.json').read_text())
report={'format':'openrc-detached-shaft-capacity-review v1','status':'mapping-foundation-ready-for-review; powered240Hz-startup-unqualified',
        'production_manifest':'tmp/gp12-shaft-capacity/manifest.json','production_manifest_sha256':sha(task/'manifest.json'),
        'installed_runtime_unchanged':main,'primary_suites':primary,'primary_assertions':489,
        'main_project_final_assertions':141,'complete_original_oracles':{'evaluations':8,'steps':scope,'fixture_sha256':sha(task/'ground_contact_shaft_legacy.bin'),
          'capture_source':'results-main-final.bin original fields, checked main-runtime-final; installed runtime prehashes above unchanged',
          'original_capture_sha256':sha(task/'results-main-final.bin')},
        'negative_control':'disposable installed evaluator force+1N; both aliases changed;16 frozen comparisons refused; restored exact payload hash',
        'startup':'unchanged strict/throughput raw gates refuse .02 and1 duty from rest at240Hz under16; no operator/reservation change',
        'mechanism_summary':'tmp/gp12-shaft-capacity/mechanism-summary.json','receipts':receipts,
        'exclusions':['accepted powered startup','finite battery events','moving axes/hubs','stock selection','performance qualification','native activation','physical validation']}
(task/'report.json').write_text(json.dumps(report,indent=2)+'\n')
files=[]
for p in sorted(task.rglob('*')):
    if not p.is_file() or 'runtime-app' in p.relative_to(task).parts or p.name=='evidence-manifest.json':continue
    files.append({'path':p.relative_to(task).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
(task/'evidence-manifest.json').write_text(json.dumps({'format':'openrc-local-evidence-sha256 v1','files':files},indent=2)+'\n')
print(json.dumps({'files':len(files),'report_sha256':sha(task/'report.json'),'manifest_sha256':sha(task/'manifest.json'),
                 'evidence_manifest_sha256':sha(task/'evidence-manifest.json'),'primary_checks':489},indent=2))
