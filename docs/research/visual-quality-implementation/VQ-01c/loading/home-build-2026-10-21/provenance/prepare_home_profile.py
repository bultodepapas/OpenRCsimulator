from pathlib import Path
import importlib.util, sys, json, difflib, hashlib, shutil
repo=Path(__file__).resolve().parents[1]
root=Path('D:/OpenRCsimulator-scratch/home-build-20261021-3f3892c7')
app=root/'snapshot/app'
spec=importlib.util.spec_from_file_location('old_profile',repo/'tmp/graphics-phase2-2026-10-21/make_loading_profile.py')
m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
selected={'home_scene._init','home_scene.show_aircraft','world.build','airplane_builder.build','field_loader.load_from','field.build','scenery.attach','scenery.build','scenery.load_from','near_grass.build','field_shadows.attach','airfield_lighting.build'}
originals={}
for f in m.FUNCTIONS:
    if f.span_name not in selected: continue
    p=app/f.path
    if f.path not in originals: originals[f.path]=m.read_text(p)
    value=m.transform_function(m.read_text(p),f)
    if 'const Phase2LoadingProfile' not in value: value=m.add_helper_preload(value,f.path)
    if f.span_name in ('world.build','scenery.build'):
        expr='{"field_build_ms": phase2_result.field_build_ms}' if f.span_name=='world.build' else 'phase2_result.get_meta("stats", {})'
        a=f'Phase2LoadingProfile.record("{f.span_name}", phase2_start_usec, Time.get_ticks_usec())'
        assert value.count(a)==1
        value=value.replace(a,a[:-1]+', '+expr+')',1)
    m.write_text(p,value)
helper=m.HELPER_SOURCE.replace('end_usec: int) -> void:', 'end_usec: int, detail: Dictionary = {}) -> void:').replace('"end_usec": end_usec}', '"end_usec": end_usec, "detail": detail.duplicate(true)}')
m.write_text(app/m.HELPER_NAME,helper)
# Contiguous field segments: each ends before collection overhead and starts after it.
p=app/'render/field.gd'; value=m.read_text(p); nl=m.line_ending(value)
start='static func _phase2_impl_build(field: Dictionary, lighting: Dictionary = {}, extra_grass_exclusions: Array = []) -> Node3D:'
value=value.replace(start,start+nl+'\tvar home_phase_start: int = Time.get_ticks_usec()',1)
for anchor,label in [('\tfor object_data: Dictionary in field.objects:', 'field.ground'), ('\tvar scenery_options := Scenery.options()', 'field.cues'), ('\tScenery.attach(result, field, lighting, lake)', 'field.lake_resolution'), ('\tvar lake_node := LakeWorld.attach', 'field.scenery'), ('\tvar scenery_node := result.get_node_or_null("Scenery")', 'field.lake_attach'), ('\tif LandscapeOptions.enabled() and field.get("id", "") == "default":','field.grass'), ('\tFieldProjectedShadows.attach(result, field, lighting)', 'field.landscape'), ('\treturn result','field.finalize')]:
    assert value.count(anchor)==1,(anchor,value.count(anchor))
    stamp='\tPhase2LoadingProfile.record("'+label+'", home_phase_start, Time.get_ticks_usec())'+nl+'\thome_phase_start = Time.get_ticks_usec()'+nl
    value=value.replace(anchor,stamp+anchor,1)
m.write_text(p,value)
# Exact callback clock already owned by World; surround it without moving work.
p=app/'render/world/world.gd'; value=m.read_text(p); nl=m.line_ending(value)
anchor='static func _phase2_impl_build(parent: Node, field: Dictionary, build_field := Callable(), conditions: Dictionary = {}, lighting: Dictionary = {}, night_options: Dictionary = {}) -> Dictionary:'
value=value.replace(anchor,anchor+nl+'\tvar home_world_start: int = Time.get_ticks_usec()',1)
anchor='\tvar t0 := Time.get_ticks_usec()'; assert value.count(anchor)==1
value=value.replace(anchor,'\tPhase2LoadingProfile.record("world.before_field", home_world_start, Time.get_ticks_usec())'+nl+anchor,1)
anchor='\tvar field_build_ms := (Time.get_ticks_usec() - t0) / 1000.0'; assert value.count(anchor)==1
value=value.replace(anchor,anchor+nl+'\tPhase2LoadingProfile.record("world.field_callback", t0, Time.get_ticks_usec(), {"field_build_ms": field_build_ms})',1)
m.write_text(p,value)
p=app/'package_loading_probe.gd'; originals['package_loading_probe.gd']=m.read_text(p)
m.write_text(p,m.patch_probe(originals['package_loading_probe.gd']))
patch=''; hashes={}
for name,before in originals.items():
    after=m.read_text(app/name)
    patch+=''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='control/app/'+name,tofile='diagnostic/app/'+name))
    target=root/'provenance/profile-sources'/name; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(app/name,target)
    hashes[name]=hashlib.sha256((app/name).read_bytes()).hexdigest()
shutil.copy2(app/m.HELPER_NAME,root/'provenance/profile-sources'/m.HELPER_NAME)
hashes[m.HELPER_NAME]=hashlib.sha256((app/m.HELPER_NAME).read_bytes()).hexdigest()
(root/'provenance/home-profile.patch').write_text(patch,encoding='utf-8')
(root/'provenance/home-profile-sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
shutil.copy2(__file__,root/'provenance'/Path(__file__).name)
print('Prepared bounded Home profile; '+str(len(hashes))+' diagnostic inputs')
