import json, subprocess
from pathlib import Path
root=Path(r'C:\DEVELOPMENT\OpenRCsimulator')
godot=root/'.tools'/'Godot_v4.7.2-stable_win64.exe'; project=root/'tmp'/'tree-continuation-assets'/'oak-native-preview-project'
source=root/'tmp'/'tree-continuation-assets'/'gltf-khr-test'/'oak_lod0.gltf'; out=root/'tmp'/'tree-continuation-assets'/'gltf-khr-test'/'godot-report'
cmd=[str(godot),'--path',str(project),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--script','res://oak_source_gallery_materialinspect.gd','--','--source='+source.as_posix(),'--out='+out.as_posix(),'--capture=off']
p=subprocess.run(cmd,cwd=root,capture_output=True,text=True,timeout=180)
print(json.dumps({'argv':cmd,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr},indent=2))
raise SystemExit(p.returncode)