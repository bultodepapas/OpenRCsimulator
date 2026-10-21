from pathlib import Path
import hashlib,json,gzip,shutil,subprocess,os,difflib
repo=Path(__file__).resolve().parents[1]
root=Path('D:/OpenRCsimulator-scratch/graphics-export-20261021-2463af65')
out=repo/'docs/research/visual-quality-implementation/VQ-01c/loading/package-attribution-2026-10-21'
out.mkdir(parents=True,exist_ok=True)
def sha(data): return hashlib.sha256(data).hexdigest()
records=[]
def retain(source,relative):
    data=source.read_bytes(); target=out/relative
    target.parent.mkdir(parents=True,exist_ok=True)
    stored=gzip.compress(data,mtime=0) if target.suffix=='.gz' else data
    target.write_bytes(stored)
    assert (gzip.decompress(stored) if target.suffix=='.gz' else stored)==data
    records.append({'source':str(source),'retained':relative,'raw_sha256':sha(data),'stored_sha256':sha(stored)})
original=json.loads((root/'provenance/source-manifest.json').read_text())
differences={}
for label,base in [('production',repo),('diagnostic_snapshot',root/'snapshot')]:
    changed=[]
    for name,expected in original['sha256'].items():
        if sha((base/name).read_bytes())!=expected: changed.append(name)
    differences[label]=changed
assert differences['production']==[],differences
assert sorted(differences['diagnostic_snapshot'])==['app/app_root.gd','app/project.godot'],differences
(root/'provenance/source-verification.json').write_text(json.dumps({'tracked_inputs':len(original['sha256']),'differences':differences,'added_diagnostic_files':['app/package_loading_probe.gd','app/package_probe_host.tscn'],'scope':'tracked app/assets-aircraft/tools only; imported caches are private and uncontrolled'},indent=2)+'\n')
receipt=json.loads((root/'snapshot/app/native/ground_vehicle/build-receipt.json').read_text())
artifacts={}
for variant in ('release','collector','diagnostic','dependency'):
    rows={}
    for name in ('OpenRC Simulator.exe','openrc_ground_vehicle.dll'):
        p=root/variant/name
        rows[name]={'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())}
    assert rows['openrc_ground_vehicle.dll']['sha256']==receipt['platforms']['windows']['binary_sha256']
    artifacts[variant]=rows
for label,p in [('editor',repo/'.tools/Godot_v4.7.2-stable_win64.exe'),('release_template',Path(os.environ['APPDATA'])/'Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe')]:
    artifacts[label]={'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())}
(root/'provenance/artifact-identities.json').write_text(json.dumps(artifacts,indent=2)+'\n')
# Save exact as-run final files and complete delta after the setup repair.
for name in ('app_root.gd','project.godot','package_loading_probe.gd','package_probe_host.tscn','export_presets.cfg'):
    shutil.copy2(root/'snapshot/app'/name,root/'provenance'/('final-'+name))
project_original=(root/'provenance/project-original.godot').read_text()
project_final=(root/'snapshot/app/project.godot').read_text()
(root/'provenance/collector-final-project.patch').write_text(''.join(difflib.unified_diff(project_original.splitlines(True),project_final.splitlines(True),fromfile='original/app/project.godot',tofile='collector/app/project.godot')),encoding='utf-8')
scripts=('prepare_graphics_export.py','run_graphics_export.py','prepare_export_collector.py','fix_collector_host.py','instrument_export_scene_load.py','prepare_dependency_profile.py','run_package_loading.py','retain_package_loading.py')
for name in scripts: shutil.copy2(repo/'tmp'/name,root/'provenance'/name)
for p in sorted((root/'provenance').iterdir()):
    if p.is_file(): retain(p,'provenance/'+p.name+('.gz' if p.stat().st_size>150000 else ''))
retain(repo/'research/performance/loading_probe.gd','provenance/canonical-loading-probe.gd')
retain(root/'snapshot/app/native/ground_vehicle/build-receipt.json','provenance/native-build-receipt.json')
for p in sorted((root/'checks').rglob('*')):
    if p.is_file():
        relative='checks/'+str(p.relative_to(root/'checks')).replace('\\','/')
        retain(p,relative+('.gz' if p.stat().st_size>40000 else ''))
for p in sorted((root/'runs').iterdir()):
    if p.is_file(): retain(p,'runs/'+p.name+('.gz' if p.suffix=='.csv' else ''))
metrics=[]
for p in sorted((root/'runs').glob('*.json')):
    r=json.loads(p.read_text())
    metrics.append({'run':p.stem,'complete':r['complete'],'home_from_load_s':r['home_first_draw_from_load_usec']/1e6,'home_engine_elapsed_s':r['home_first_draw_engine_elapsed_usec']/1e6,'first_fly_s':r['cycles'][0]['fly_first_draw_usec']/1e6,'warm_fly_s':r['cycles'][1]['fly_first_draw_usec']/1e6,'first_paused':r['cycles'][0]['paused_at_first_draw'],'scene_spans':r['scene_spans']})
dependency=json.loads((root/'runs/dependency-01.json').read_text())
summary={'decision':'retain runtime; package load persists but single optional preloads do not establish required ROI','runs':metrics,'dependencies_order_dependent':sorted(dependency['dependency_spans'],key=lambda row:row['load_usec'],reverse=True),'dependency_sum_usec':sum(d['load_usec'] for d in dependency['dependency_spans']),'dependency_residual_scene_usec':dependency['scene_spans'][0]['load_usec']}
(out/'metrics.json').write_text(json.dumps(summary,indent=2)+'\n')
(out/'evidence-manifest.json').write_text(json.dumps({'format':'openrc-package-loading-evidence-v1','files':records},indent=2)+'\n')
print(f'Retained {len(records)} artifacts; source unchanged; 4 exported DLLs match receipt')
