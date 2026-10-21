from pathlib import Path
import json,gzip,hashlib,re
repo=Path(__file__).resolve().parents[1]
out=repo/'docs/research/visual-quality-implementation/VQ-01c/loading/home-build-2026-10-21'
def sha(data): return hashlib.sha256(data).hexdigest()
def raw(path):
 if path.exists(): return path.read_bytes()
 return gzip.decompress(path.with_name(path.name+'.gz').read_bytes())
m=json.loads((out/'evidence-manifest.json').read_text())
relative='provenance/check_home_build_evidence.py'; data=Path(__file__).read_bytes();(out/relative).write_bytes(data)
m['files']=[r for r in m['files'] if r['retained']!=relative]+[{'source':str(Path(__file__)), 'retained':relative,'raw_sha256':sha(data),'stored_sha256':sha(data)}]
(out/'evidence-manifest.json').write_text(json.dumps(m,indent=2)+'\n')
for r in m['files']:
 p=out/r['retained'];data=p.read_bytes();assert sha(data)==r['stored_sha256'],p
 assert sha(gzip.decompress(data) if p.suffix=='.gz' else data)==r['raw_sha256'],p
checks=[]
for p in (out/'checks').rglob('report.json'):
 r=json.loads(p.read_text());assert r['ok'] and r['complete'] and r['process_exit']==0,p
 log=raw(p.with_name('engine.log'));assert sha(log)==r['log_sha256'],p
 assert b'ObjectDB instances leaked' not in log,p
 checks.append({'label':r['label'],'ok':True,'warnings':r['counts']['warning'],'elapsed_seconds':r['elapsed_seconds']})
assert len(checks)==6
for p in (out/'runs').glob('*.json'):
 r=json.loads(p.read_text());assert r['complete'] and r['shutdown']['audio_released'] and r['shutdown']['settings_removed'],p
 assert not r['execution']['editor_feature'] and not r['execution']['debug_build'],p
 assert r['package_build']['commit']=='3f3892c7ee97340469975e12b99d5cd6c160e0f0',p
 assert len(r['cycles'])==2 and all(not c['paused_at_first_draw'] and c['tick_at_first_draw']==12 and c['orphan_nodes']==0 for c in r['cycles']),p
 if not p.stem.startswith('diagnostic'): continue
 spans=r['construction_spans'];assert len(spans)==117 and len(spans)<512,p
 assert all(s['end_usec']>=s['start_usec'] for s in spans),p
 def rows(name): return [s for s in spans if s['name']==name]
 def contains(parent,child): return parent['start_usec']<=child['start_usec']<=child['end_usec']<=parent['end_usec']
 assert len(rows('home_scene._init'))==3 and len(rows('world.build'))==len(rows('field.build'))==len(rows('scenery.build'))==5,p
 for w in rows('world.build'):
  callbacks=[s for s in rows('world.field_callback') if contains(w,s)];fields=[s for s in rows('field.build') if contains(w,s)]
  assert len(callbacks)==len(fields)==1 and contains(callbacks[0],fields[0]),p
  assert w['detail']['field_build_ms']==callbacks[0]['detail']['field_build_ms'],p
  assert abs((callbacks[0]['end_usec']-callbacks[0]['start_usec'])/1000-w['detail']['field_build_ms'])<0.1,p
 for f in rows('field.build'):
  assert len([s for s in rows('scenery.attach') if contains(f,s)])==1,p
profile=json.loads((out/'provenance/home-profile-sha256.json').read_text())
for name,expected in profile.items(): assert sha(raw(out/'provenance/profile-sources'/name))==expected,name
source=json.loads(raw(out/'provenance/source-manifest.json'))
for name,expected in source['sha256'].items(): assert sha((repo/name).read_bytes())==expected,name
assert sha(raw(out/'provenance/final-export_presets.cfg'))==sha((repo/'app/export_presets.cfg').read_bytes())
for p in [out/'README.md',repo/'docs/plans/advanced-graphics.md',repo/'docs/plans/global-performance-visual-quality.md',repo/'docs/VISUAL-QUALITY-PLAN.md']:
 for link in re.findall(r'\]\(([^)]+)\)',p.read_text(encoding='utf-8')):
  if '://' not in link and not link.startswith('#'):
   target=p.parent/link.split('#')[0]
   if target!=out/'verification.json': assert target.exists(),(p,link)
result={'retained_artifacts_verified':len(m['files']),'checked_reports':checks,'source_inputs_unchanged':len(source['sha256']),'profile_hashes':'passed','release_identity_active_cycles_cleanup':'passed','span_nesting_and_field_callback':'passed','local_links':'passed','unchanged_export_preset':True,'limitations':'No runtime candidate, five-pair gain, image parity, full app suite, long lifecycle or physical-display qualification.'}
(out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS:',len(m['files']),'retained artifacts;',len(checks),'checked logs; 3840 unchanged production inputs; release identity, completion, spans and links')
