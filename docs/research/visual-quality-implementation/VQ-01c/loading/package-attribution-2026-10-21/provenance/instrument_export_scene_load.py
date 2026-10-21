from pathlib import Path
import hashlib,json,difflib,shutil
root=Path('D:/OpenRCsimulator-scratch/graphics-export-20261021-2463af65')
path=root/'snapshot/app/app_root.gd'
raw=path.read_bytes(); before=path.read_text(encoding='utf-8')
old='\treturn load(route_path).instantiate()'
new='''	var load_begin: int = Time.get_ticks_usec()
	var packed: PackedScene = load(route_path)
	var load_end: int = Time.get_ticks_usec()
	var instance: Node = packed.instantiate()
	var instantiate_end: int = Time.get_ticks_usec()
	var spans: Array = Engine.get_meta("package_scene_spans", [])
	if spans.size() < 16:
		spans.append({"path": route_path, "load_start_usec": load_begin,
			"load_usec": load_end - load_begin, "instantiate_usec": instantiate_end - load_end})
		Engine.set_meta("package_scene_spans", spans)
	return instance'''
assert before.count(old)==1
after=before.replace(old,new)
(root/'provenance/app_root-original.gd').write_bytes(raw)
path.write_text(after,encoding='utf-8')
(root/'provenance/scene-load.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='control/app/app_root.gd',tofile='diagnostic/app/app_root.gd')),encoding='utf-8')
shutil.copy2(__file__,root/'provenance/instrument_export_scene_load.py')
print('Added only synchronous load/instantiate timings in scratch AppRoot')
