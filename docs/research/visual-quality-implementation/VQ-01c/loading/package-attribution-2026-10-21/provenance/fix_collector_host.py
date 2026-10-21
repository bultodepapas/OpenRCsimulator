from pathlib import Path
import hashlib,json,shutil
root=Path('D:/OpenRCsimulator-scratch/graphics-export-20261021-2463af65')
app=root/'snapshot/app'
project=app/'project.godot'
old=project.read_bytes()
(root/'provenance/collector-no-main-scene.godot').write_bytes(old)
(root/'provenance/collector-setup-failure.json').write_text(json.dumps({'reason':'Release template requires a main scene even with custom SceneTree','executable_sha256':hashlib.sha256((root/'collector/OpenRC Simulator.exe').read_bytes()).hexdigest(),'project_sha256':hashlib.sha256(old).hexdigest()},indent=2)+'\n')
text=old.decode()
assert 'run/main_scene=' not in text
project.write_text(text.replace('run/main_loop_type="PackLoadingProbe"','run/main_scene="res://package_probe_host.tscn"\nrun/main_loop_type="PackLoadingProbe"'),encoding='utf-8')
(app/'package_probe_host.tscn').write_text('[gd_scene format=3]\n\n[node name="PackageProbeHost" type="Node"]\n',encoding='utf-8')
shutil.copy2(__file__,root/'provenance/fix_collector_host.py')
