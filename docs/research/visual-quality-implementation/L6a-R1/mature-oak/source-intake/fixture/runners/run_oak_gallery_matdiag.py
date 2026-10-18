import json, subprocess
from pathlib import Path
root=Path(r'C:\DEVELOPMENT\OpenRCsimulator')
godot=root/'.tools'/'Godot_v4.7.2-stable_win64.exe'
project=root/'tmp'/'tree-continuation-assets'/'oak-native-preview-project'
source=root/'assets'/'landscape'/'vegetation'/'source'/'opengameart_oak_tree_lod_2026'/'gltf'/'lod0'/'oak_lod0.gltf'
for label,spec in [('rough1-spec0',0.0),('rough1-spec05',0.5)]:
 output=root/'tmp'/'tree-continuation-assets'/f'native-preview-oak-{label}-20261018'
 cmd=[str(godot),'--path',str(project),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--script','res://oak_source_gallery_matdiag.gd','--','--source='+source.as_posix(),'--out='+output.as_posix(),'--capture=on','--mat_diag='+label,'--specular='+str(spec),'--views=back,underside','--frame_height_m=14.0','--width=1280','--height=1280']
 p=subprocess.run(cmd,cwd=root,capture_output=True,text=True,timeout=180)
 print(json.dumps({'label':label,'argv':cmd,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr},indent=2))
 if p.returncode: raise SystemExit(p.returncode)