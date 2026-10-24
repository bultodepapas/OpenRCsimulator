import bpy,json,math,bmesh
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update();changes=[]
def tree(o):return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[list(p.vertices)for p in o.data.polygons])
wing=tree(bpy.data.objects['wing_center_fixed'])
for role in ('left','right'):
 for i in (1,2):
  o=bpy.data.objects[f'flap_{role}_{i}'];delta=Vector((0,-(.0005 if role=='left'else .0006),0))if i==1 else Vector((0,-.002,-.0011))
  if not o.get('g1_clearance_relief_applied',False):
   for v in o.data.vertices:v.co+=delta
   o['g1_clearance_relief_applied']=True;o.data.update()
  changes.append({'mesh':o.name,'relief_local_m':list(delta),'remaining_contact_pairs':len(tree(o).overlap(wing))})
# Report open boundary loops for inspection; do not fill intentional openings indiscriminately.
loops=[]
for name in ('wing_left_fixed','wing_right_fixed','wing_center_fixed','stabilizer_fixed','fin_fixed','cowl'):
 o=bpy.data.objects[name];bm=bmesh.new();bm.from_mesh(o.data);edges={e for e in bm.edges if e.is_boundary}
 while edges:
  seed=edges.pop();component={seed};todo=[seed]
  while todo:
   e=todo.pop()
   for v in e.verts:
    for e2 in v.link_edges:
     if e2 in edges:edges.remove(e2);component.add(e2);todo.append(e2)
  vs={v for e in component for v in e.verts};coords=[o.matrix_world@v.co for v in vs];lo=[min(v[k]for v in coords)for k in range(3)];hi=[max(v[k]for v in coords)for k in range(3)];loops.append({'mesh':name,'edges':len(component),'min':lo,'max':hi})
 bm.free()
(P/'previews/polish.json').write_text(json.dumps({'changes':changes,'open_boundaries':loops},indent=2));bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('POLISH',json.dumps(changes),flush=True)
