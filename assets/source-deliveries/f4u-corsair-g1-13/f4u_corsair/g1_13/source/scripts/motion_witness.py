import bpy,json,math
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update();checks={}
for name in ['propeller_spin','gear_spin_left','gear_spin_right','gear_spin_tail']:
 o=bpy.data.objects[name];rest=o.matrix_basis.copy();members=[m for m in o.children_recursive if m.type=='MESH'];before={m.name:[m.matrix_world@v.co for v in m.data.vertices]for m in members}
 for degrees in range(0,361,15):o.matrix_basis=rest@Matrix.Rotation(math.radians(degrees),4,'X');bpy.context.view_layer.update()
 error=max(((m.matrix_world@v.co)-old).length for m in members for v,old in zip(m.data.vertices,before[m.name]));o.matrix_basis=rest;bpy.context.view_layer.update();checks[name]={'full_revolution_return_error_m':error,'passed':error<1e-6}
for role in ['left','right','tail']:
 o=bpy.data.objects['gear_spin_'+role];axis=o.matrix_world.to_3x3()@Vector((1,0,0));bottom_velocity=axis.cross(Vector((0,0,-1)));checks['rolling_'+role]={'bottom_surface_motion_y':bottom_velocity.y,'passed':bottom_velocity.y<-.99}
o=bpy.data.objects['gear_steer_tail'];rest=o.matrix_basis.copy();signs=[]
for degrees in [-30,30]:
 o.matrix_basis=rest@Matrix.Rotation(math.radians(degrees),4,'Y');bpy.context.view_layer.update();ax=bpy.data.objects['gear_spin_tail'].matrix_world.to_3x3()@Vector((1,0,0));heading=ax.cross(Vector((0,0,1)));signs.append({'degrees':degrees,'heading_x':heading.x})
o.matrix_basis=rest;bpy.context.view_layer.update();checks['tail_steering']={'samples':signs,'passed':signs[0]['heading_x']<0 and signs[1]['heading_x']>0}
result={'passed':all(v['passed']for v in checks.values()),'checks':checks};(P/'previews/motion-witness.json').write_text(json.dumps(result,indent=2));print('MOTION',json.dumps(result),flush=True)
if not result['passed']:raise SystemExit(1)
