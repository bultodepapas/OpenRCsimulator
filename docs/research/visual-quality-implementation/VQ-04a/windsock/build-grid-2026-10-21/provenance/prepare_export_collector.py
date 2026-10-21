from pathlib import Path
import shutil, difflib, hashlib, json
repo=Path(__file__).resolve().parents[1]
root=Path('D:/OpenRCsimulator-scratch/windsock-grid-20261021-8b808672')
app=root/'snapshot/app'
project=app/'project.godot'
before=project.read_text(encoding='utf-8')
assert 'run/main_scene="res://app_root.tscn"' in before
after=before.replace('run/main_scene="res://app_root.tscn"','run/main_scene="res://package_probe_host.tscn"\nrun/main_loop_type="PackLoadingProbe"')
(root/'provenance/project-original.godot').write_bytes(project.read_bytes())
project.write_text(after,encoding='utf-8')
original=(repo/'research/performance/loading_probe.gd').read_text(encoding='utf-8')
probe=original.replace('extends SceneTree','class_name PackLoadingProbe\nextends SceneTree',1)
probe=probe.replace('\tvar before_load := Time.get_ticks_usec()', '\tEngine.set_meta("package_scene_spans", [])\n\tvar before_load := Time.get_ticks_usec()',1)
probe=probe.replace('\treport["shutdown"] = await _cleanup()', '''	report["scene_spans"] = Engine.get_meta("package_scene_spans", [])
	report["package_build"] = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json")) if FileAccess.file_exists("res://build_info.json") else null
	report["execution"] = {"executable": OS.get_executable_path(), "editor_feature": OS.has_feature("editor"), "debug_build": OS.is_debug_build(), "project_path": ProjectSettings.globalize_path("res://")}
	report["shutdown"] = await _cleanup()''',1)
(app/'package_loading_probe.gd').write_text(probe,encoding='utf-8')
(app/'package_probe_host.tscn').write_text('[gd_scene format=3]\n\n[node name="PackageProbeHost" type="Node"]\n',encoding='utf-8')
(root/'provenance/collector.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='original/app/project.godot',tofile='collector/app/project.godot'))+''.join(difflib.unified_diff(original.splitlines(True),probe.splitlines(True),fromfile='research/performance/loading_probe.gd',tofile='collector/app/package_loading_probe.gd')),encoding='utf-8')
(root/'collector').mkdir()
shutil.copy2(__file__,root/'provenance/prepare_export_collector.py')
print('Prepared collector-only MainLoop in isolated snapshot')
