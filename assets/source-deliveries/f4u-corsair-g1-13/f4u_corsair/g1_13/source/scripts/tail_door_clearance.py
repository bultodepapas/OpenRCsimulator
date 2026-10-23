import bpy,json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update();d=bpy.data.objects['gear_door_tail_mesh_right_1'];f=bpy.data.objects['fuselage_core']
def tree(o):return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[list(p.vertices)for p in o.data.polygons])
ft=tree(f);original=[v.co.copy()for v in d.data.vertices];center=sum(original,Vector())/len(original);history=[]
for step in range(26):
 factor=1-step*.001
 for v,co in zip(d.data.vertices,original):v.co=center+(co-center)*factor
 d.data.update();hits=[]
 for frame in range(0,101,5):
  S.frame_set(frame);bpy.context.view_layer.update();hits.append(len(tree(d).overlap(ft)))
 history.append({'factor':factor,'maximum_contacts':max(hits)})
 if not max(hits):break
if max(hits):
 for v,co in zip(d.data.vertices,original):v.co=co
 raise RuntimeError('No acceptable local relief found; source not saved')
S.frame_set(0);bpy.context.view_layer.update();(P/'previews/tail-door-relief.json').write_text(json.dumps({'node':d.name,'uniform_mesh_factor_about_centroid':factor,'maximum_vertex_displacement_m':max((v.co-co).length for v,co in zip(d.data.vertices,original)),'sweep_frames_step':5,'contacts':hits},indent=2));bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('TAIL_RELIEF',factor,flush=True)
