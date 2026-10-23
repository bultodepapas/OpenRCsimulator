import bpy,sys
from pathlib import Path
P=Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(P/'export/aircraft.glb'))
sys.argv+=['--runtime','--only','hero']
exec(compile(Path(__file__).with_name('naval_views10.py').read_text(),str(Path(__file__).with_name('naval_views10.py')),'exec'))
