"""Render the ACTUAL runtime GLB in an empty Blender scene."""
import bpy
from pathlib import Path
P=Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(P/'export/aircraft.glb'))
setup=(P/'source/scripts/preview.py').read_text().split('for name,loc in')[0]
exec(compile(setup,str(P/'source/scripts/preview.py'),'exec'))
area('runtime_belly_fill',(0,1,-3),180,3)
for name,loc in [('runtime_three_quarter',(3,4,2.5)),('runtime_underside',(3,4,-2)),('runtime_side',(6,-.52,0))]:render(name,loc)
print('RUNTIME_PREVIEWS_DONE',flush=True)
