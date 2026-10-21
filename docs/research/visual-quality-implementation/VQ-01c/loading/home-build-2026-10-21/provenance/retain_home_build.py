from pathlib import Path
import hashlib,json,gzip,shutil,subprocess,os
repo=Path(__file__).resolve().parents[1]
root=Path('D:/OpenRCsimulator-scratch/home-build-20261021-3f3892c7')
out=repo/'docs/research/visual-quality-implementation/VQ-01c/loading/home-build-2026-10-21'
out.mkdir(parents=True,exist_ok=True)
def sha(data): return hashlib.sha256(data).hexdigest()
manifest=json.loads((root/'provenance/source-manifest.json').read_text())
diffs={}
for label,base in [('production',repo),('diagnostic_snapshot',root/'snapshot')]:
 diffs[label]=[name for name,expected in manifest['sha256'].items() if sha((base/name).read_bytes())!=expected]
assert not diffs['production'],diffs
profile=json.loads((root/'provenance/home-profile-sha256.json').read_text())
expected=sorted(['app/'+p for p in profile if 'app/'+p in manifest['sha256']]+['app/project.godot'])
assert sorted(diffs['diagnostic_snapshot'])==expected,diffs
for name,expected_hash in profile.items(): assert sha((root/'snapshot/app'/name).read_bytes())==expected_hash,name
(root/'provenance/source-verification.json').write_text(json.dumps({'tracked_inputs':len(manifest['sha256']),'differences':diffs,'added_diagnostic_files':['app/package_loading_probe.gd','app/package_probe_host.tscn','app/phase2_loading_profile.gd'],'scope':'tracked app/assets-aircraft/tools; private copied import caches uncontrolled'},indent=2)+'\n')
receipt=json.loads((root/'snapshot/app/native/ground_vehicle/build-receipt.json').read_text())
artifacts={}
for variant in ['collector','diagnostic']:
 rows={}
 for name in ['OpenRC Simulator.exe','openrc_ground_vehicle.dll']:
  p=root/variant/name; rows[name]={'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())}
 assert rows['openrc_ground_vehicle.dll']['sha256']==receipt['platforms']['windows']['binary_sha256']
 artifacts[variant]=rows
for label,p in [('editor',repo/'.tools/Godot_v4.7.2-stable_win64.exe'),('release_template',Path(os.environ['APPDATA'])/'Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe')]:
 artifacts[label]={'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())}
(root/'provenance/artifact-identities.json').write_text(json.dumps(artifacts,indent=2)+'\n')
for name in ['project.godot','package_loading_probe.gd','package_probe_host.tscn','export_presets.cfg']:
 shutil.copy2(root/'snapshot/app'/name,root/'provenance'/('final-'+name))
for name in ['home_prepare_graphics_export.py','home_prepare_export_collector.py','home_run_graphics_export.py','home_run_package_loading.py','prepare_home_profile.py','retain_home_build.py']:
 shutil.copy2(repo/'tmp'/name,root/'provenance'/name)
p=root/'provenance/graphics-phase2-2026-10-21/make_loading_profile.py';p.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(repo/'tmp/graphics-phase2-2026-10-21/make_loading_profile.py',p)
shutil.copy2(repo/'research/performance/loading_probe.gd',root/'provenance/canonical-loading-probe.gd')
shutil.copy2(root/'snapshot/app/native/ground_vehicle/build-receipt.json',root/'provenance/native-build-receipt.json')
records=[]
for base in ['provenance','checks','runs']:
 for p in sorted((root/base).rglob('*')):
  if not p.is_file(): continue
  relative=p.relative_to(root).as_posix()+('.gz' if p.stat().st_size>40000 else '')
  data=p.read_bytes(); stored=gzip.compress(data,mtime=0) if relative.endswith('.gz') else data
  target=out/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(stored)
  records.append({'source':str(p),'retained':relative,'raw_sha256':sha(data),'stored_sha256':sha(stored)})
metrics=[]
for name in ['collector-01','diagnostic-01','diagnostic-02','collector-02']:
 r=json.loads((root/'runs'/(name+'.json')).read_text()); spans=r.get('construction_spans',[])
 row={'run':name,'complete':r['complete'],'home_from_load_s':r['home_first_draw_from_load_usec']/1e6,'home_engine_elapsed_s':r['home_first_draw_engine_elapsed_usec']/1e6,'home_sync_s':r['home_sync_usec']/1e6,'first_fly_s':r['cycles'][0]['fly_first_draw_usec']/1e6,'warm_fly_s':r['cycles'][1]['fly_first_draw_usec']/1e6,'combined_first_path_s':(r['home_first_draw_from_load_usec']+r['cycles'][0]['fly_first_draw_usec'])/1e6,'all_active':all(not c['paused_at_first_draw'] and c['tick_at_first_draw']==12 for c in r['cycles']),'span_count':len(spans)}
 if spans:
  home=next(s for s in spans if s['name']=='home_scene._init')
  first=[s for s in spans if home['start_usec']<=s['start_usec'] and s['end_usec']<=home['end_usec']]
  row['first_home_spans_ms']={s['name']:(s['end_usec']-s['start_usec'])/1000 for s in first if s['name'] not in ['scenery.load_from','field_loader.load_from']}
  row['all_builds_ms']={key:[(s['end_usec']-s['start_usec'])/1000 for s in spans if s['name']==key] for key in ['world.build','field.build','scenery.build','home_scene._init','home_scene.show_aircraft']}
  row['first_scenery_stats']=next(s['detail'] for s in first if s['name']=='scenery.build')
  row['first_field_build_ms']=next(s['detail']['field_build_ms'] for s in first if s['name']=='world.build')
 metrics.append(row)
(out/'metrics.json').write_text(json.dumps({'scope':'attribution only; nested spans are not additive; no speedup or parity claim','execution_order':[r['run'] for r in metrics],'runs':metrics},indent=2)+'\n')
(out/'evidence-manifest.json').write_text(json.dumps({'format':'openrc-home-build-evidence-v1','files':records},indent=2)+'\n')
print('Retained',len(records),'artifacts; frozen production inputs unchanged; native DLLs match receipt')
