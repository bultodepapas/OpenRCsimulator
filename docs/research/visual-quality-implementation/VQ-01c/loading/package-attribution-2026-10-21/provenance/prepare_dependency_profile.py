from pathlib import Path
import re,json,difflib,shutil
root=Path('D:/OpenRCsimulator-scratch/graphics-export-20261021-2463af65')
app=root/'snapshot/app'
main=(app/'main.gd').read_text(encoding='utf-8')
paths=list(dict.fromkeys(re.findall(r'preload\("([^"]+)"\)',main)))
assert 50<len(paths)<100
path=app/'app_root.gd';before=path.read_text(encoding='utf-8')
marker='\tvar load_begin: int = Time.get_ticks_usec()'
assert before.count(marker)==1
prefix='''	# Attribution only: sequential direct dependencies in source order.
	# Keep resources alive until main's own preloads take ownership.
	var dependency_keepalive: Array[Resource] = []
	if not Engine.has_meta("package_dependency_spans"):
		var dependency_spans: Array = []
		var dependency_paths: Array = PATHS
		for dependency_path: String in dependency_paths:
			var was_cached := ResourceLoader.has_cached(dependency_path)
			var dependency_begin: int = Time.get_ticks_usec()
			var resource: Resource = load(dependency_path)
			var dependency_end: int = Time.get_ticks_usec()
			dependency_keepalive.append(resource)
			dependency_spans.append({"path": dependency_path, "was_cached": was_cached,
				"load_usec": dependency_end - dependency_begin, "loaded": resource != null})
		Engine.set_meta("package_dependency_spans", dependency_spans)
'''.replace('PATHS',json.dumps(paths))
after=before.replace(marker,prefix+marker)
(root/'provenance/app_root-diagnostic.gd').write_bytes(path.read_bytes())
path.write_text(after,encoding='utf-8')
(root/'provenance/dependency-profile.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='diagnostic/app/app_root.gd',tofile='dependency/app/app_root.gd')),encoding='utf-8')
probe=app/'package_loading_probe.gd'
(root/'provenance/package_loading_probe-diagnostic.gd').write_bytes(probe.read_bytes())
text=probe.read_text(encoding='utf-8')
text=text.replace('\treport["scene_spans"] =', '\treport["dependency_spans"] = Engine.get_meta("package_dependency_spans", [])\n\treport["scene_spans"] =')
probe.write_text(text,encoding='utf-8')
(root/'provenance/direct-dependencies.json').write_text(json.dumps(paths,indent=2)+'\n')
(root/'dependency').mkdir()
shutil.copy2(__file__,root/'provenance/prepare_dependency_profile.py')
print(f'Prepared separate sequential profile of {len(paths)} direct preload paths')
