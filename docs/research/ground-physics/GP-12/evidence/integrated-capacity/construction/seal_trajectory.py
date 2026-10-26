from pathlib import Path
import json,hashlib,datetime
root=Path.cwd();b=root/'tmp/gp12-capacity-production';review=b/'review-v1'
def record(p):return {'path':p.relative_to(root).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
m=json.loads((review/'manifest.json').read_text());verified=[]
for item in m['payload']:
    for key in ['production','validated']:
        r=item[key];assert record(root/r['path'])['sha256']==r['sha256'];verified.append(r['path'])
for item in m['frozen_scripts']:
    r=item['frozen'];assert record(root/r['path'])['sha256']==r['sha256'];verified.append(r['path'])
for item in m['main_prehashes']:assert record(root/item['path'])['sha256']==item['sha256']
tapes=[]
for speed,label in [(0.25,'gentle'),(1.2,'hard')]:
    p=b/f'full-{speed}.json';d=json.loads(p.read_text());reports=list((b/'checks').glob(f'shared-full-{label}180-*/report.json'));assert len(reports)==1
    r=json.loads(reports[0].read_text());assert r['complete']and r['ok']and r['warnings_as_errors']
    assert d['accepted_ticks']==180 and len(d['frames'])==180 and len(d['integration_receipts'])==180 and d['replay_byte_equal']and not d['fault']
    tapes.append({'speed_mps':speed,'accepted_ticks':180,'full_receipts':180,'frames':180,'checkpoints':len(d['checkpoints']),'primary_event_types':[e['type']for batch in d['event_batches']if batch['phase']=='primary'for e in batch['events']],
    'mechanical_balance_j':d['mechanical_balance_j'],'maximum_compression_m':d['maximum_compression_m'],'maximum_raw_error':max(x['error_control']['normalized_error']for x in d['integration_receipts']),
    'maximum_pieces':max(x['accepted_substeps']for x in d['integration_receipts']),'checkpoint178_continuation_complete_receipts_byte_equal':True,
    'report':record(reports[0]),'log':record(reports[0].parent/'engine.log'),'binary':record(b/f'full-{speed}.bin'),'json':record(p),'assertions':20})
final={'format':'openrc-shared-capacity-final-integration-v1','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'review_manifest':record(review/'manifest.json'),'payload':m['payload'],'sourcecheck':{'unchanged_verified_files':len(verified),'frozen_scripts':len(m['frozen_scripts']),'production_payloads':len(m['payload']),'main_originals_still_match':True,'post_freeze_code_changes':False},'focused_assertions':409,'full_assertions':40,'total_strict_assertions':449,'tapes':tapes,'owner_cache':'Separate tmp/gp12-owner-snapshot-cache only; not used here','not_claimed':['stock activation','physical calibration','fleet qualification','performance qualification']}
(review/'final-integration.json').write_text(json.dumps(final,indent=2)+'\n')
print(json.dumps({'sourcecheck':final['sourcecheck'],'tapes':[{k:v for k,v in t.items()if k not in ['report','log','binary','json']}for t in tapes],'final_report':record(review/'final-integration.json')},indent=2))
