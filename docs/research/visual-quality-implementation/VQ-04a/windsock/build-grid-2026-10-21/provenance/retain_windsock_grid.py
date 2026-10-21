from pathlib import Path
import json,hashlib,gzip,shutil,subprocess
repo=Path.cwd();root=Path('D:/OpenRCsimulator-scratch/windsock-grid-20261021-8b808672')
out=repo/'docs/research/visual-quality-implementation/VQ-04a/windsock/build-grid-2026-10-21';out.mkdir(parents=True,exist_ok=True)
def sha(b):return hashlib.sha256(b).hexdigest()
frozen=json.loads((root/'provenance/source-manifest.json').read_text())
changes={}
for label,base in [('production',repo),('snapshot',root/'snapshot')]:
 changes[label]=sorted(name for name,expected in frozen['sha256'].items() if sha((base/name).read_bytes())!=expected)
assert changes['production']==['app/render/windsock.gd','app/tests/test_windsock.gd','tools/ground/README.md','tools/ground/compare_windsock_optimization.gd'],changes
assert changes['snapshot']==['app/project.godot','app/render/windsock.gd'],changes
assert (repo/'app/render/windsock.gd').read_bytes()==(root/'provenance/windsock-candidate.gd').read_bytes()
(root/'provenance/source-verification.json').write_text(json.dumps({'frozen_head':frozen['head'],'tracked_inputs':len(frozen['sha256']),'changes':changes,'physics_aircraft_assets_unchanged':True},indent=2)+'\n')
artifacts={}
receipt=json.loads((repo/'app/native/ground_vehicle/build-receipt.json').read_text())
for variant in ['collector','diagnostic']:
 artifacts[variant]={}
 for name in ['OpenRC Simulator.exe','openrc_ground_vehicle.dll']:
  p=root/variant/name;artifacts[variant][name]={'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())}
 assert artifacts[variant]['openrc_ground_vehicle.dll']['sha256']==receipt['platforms']['windows']['binary_sha256']
(root/'provenance/artifact-identities.json').write_text(json.dumps(artifacts,indent=2)+'\n')
for name in ['project.godot','export_presets.cfg','package_loading_probe.gd','package_probe_host.tscn']:
 shutil.copy2(root/'snapshot/app'/name,root/'provenance'/name)
for name in ['wind_prepare_graphics_export','wind_prepare_export_collector','wind_run_graphics_export','wind_run_package_loading','run_wind_pairs','test_windsock_grid','reduce_windsock_grid','capture_windsock_grid','check_windsock_mutation','retain_windsock_grid']:
 shutil.copy2(repo/'tmp'/(name+'.py'),root/'provenance'/(name+'.py'))
for name in ['tools/ground/compare_windsock_optimization.gd','tools/ground/capture_windsock_motion.gd','app/tests/test_windsock.gd','tools/ground/README.md']:
 shutil.copy2(repo/name,root/'provenance'/Path(name).name)
patch=subprocess.check_output(['git','diff','--','app/render/windsock.gd','app/tests/test_windsock.gd','tools/ground/compare_windsock_optimization.gd'],cwd=repo)
(root/'provenance/implementation.patch').write_bytes(patch)
records=[]
def retain(p,relative):
 data=p.read_bytes();compressed=len(data)>60000;target=out/(relative+('.gz' if compressed else ''));target.parent.mkdir(parents=True,exist_ok=True)
 stored=gzip.compress(data,mtime=0) if compressed else data;target.write_bytes(stored)
 records.append({'source':str(p),'retained':target.relative_to(out).as_posix(),'raw_sha256':sha(data),'stored_sha256':sha(stored)})
for folder in ['provenance','checks','runs']:
 for p in sorted((root/folder).rglob('*')):
  if p.is_file():retain(p,p.relative_to(root).as_posix())
for variant in ['baseline','candidate']:retain(root/'captures'/variant/'capture.json','captures/'+variant+'-capture.json')
retain(root/'captures/candidate/direction-reversal-before-near.png','captures/verified-near.png')
(out/'evidence-manifest.json').write_text(json.dumps({'format':'openrc-windsock-grid-evidence-v1','files':records},indent=2)+'\n')
checks=[]
for p in (root/'checks').rglob('report.json'):
 r=json.loads(p.read_text());assert sha(p.with_name('engine.log').read_bytes())==r['log_sha256']
 if r['label']=='expected-uv-mutation':assert not r['ok'] and r['process_exit']==1 and r['counts']['error']==0
 else:assert r['ok'] and r['process_exit']==0,p
 checks.append({'label':r['label'],'ok':r['ok'],'expected_failure':r['label']=='expected-uv-mutation','warnings':r['counts']['warning']})
for record in records:
 p=out/record['retained'];data=p.read_bytes();assert sha(data)==record['stored_sha256']
 assert sha(gzip.decompress(data) if p.suffix=='.gz' else data)==record['raw_sha256']
loads=json.loads((root/'runs/loading-summary.json').read_text());assert [r['pair'] for r in loads['pairs'] if r['eligible']]==[2,3,4,5,7]
for variant in ['collector','diagnostic']:
 for n in range(1,8):
  r=json.loads((root/'runs'/f'{variant}-{n:02d}.json').read_text())
  assert r['complete'] and len(r['cycles'])==2 and not r['execution']['editor_feature'] and not r['execution']['debug_build']
  assert r['shutdown']['audio_released'] and r['shutdown']['settings_removed'] and all(c['orphan_nodes']==0 for c in r['cycles'])
  report=next(p for p in (root/'checks').rglob('report.json') if json.loads(p.read_text())['label']==f'{variant}-native-{n:02d}')
  assert b'ObjectDB instances leaked' not in report.with_name('engine.log').read_bytes()
result={'artifact_hashes_verified':len(records),'source_verification':changes,'checks':checks,'eligible_pairs':[2,3,4,5,7],'excluded_pairs':[1,6],'component_comparison_passed':json.loads((root/'runs/geometry-and-build.json').read_text())['passed'],'pixel_exact_native_images':18,'runtime_parses':True,'full_app_suite_run':False,'ordinary_export_qualification':False}
(out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS: retained',len(records),'artifacts;',len(checks),'checked reports; 5 active pairs; expected UV mutant rejected; only 3 executable/test changes plus tool instructions')
