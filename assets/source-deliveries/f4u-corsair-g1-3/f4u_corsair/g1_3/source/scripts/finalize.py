import bpy,json,math
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update()
def orient(name,M):
 o=bpy.data.objects[name];children={c:c.matrix_world.copy()for c in o.children};M.translation=o.matrix_world.translation;o.matrix_world=M;bpy.context.view_layer.update()
 for c,world in children.items():c.matrix_world=world
 bpy.context.view_layer.update()
for role in ('left','right','tail'):orient('gear_spin_'+role,Matrix.Rotation(math.pi,4,'Z'))
orient('gear_steer_tail',Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1))))
for role in ('left','right'):
 for i in (1,2):bpy.data.objects[f'flap_{role}_{i}']['g1_clearance_relief_applied']=True
meta=json.loads((P/'metadata.json').read_text());meta['gear']['positive_wheel_spin']='local +X points toward Blender -X when down: positive rotation rolls forward toward +Y';meta['gear']['positive_tail_steer']='local +Y points toward Blender -Z: positive angle steers nose toward pilot right';meta['closure_check']='Wing outer panels, tail and cowl have no boundary edges. Two submillimetre 2-edge remnants in center wing are recorded in previews/polish.json; no open section perimeter.'
meta['acceptance_status']='Technical validation in Blender; Godot integration is performed by receiving team.'
(P/'metadata.json').write_text(json.dumps(meta,indent=2));bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('FINALIZED',flush=True)
