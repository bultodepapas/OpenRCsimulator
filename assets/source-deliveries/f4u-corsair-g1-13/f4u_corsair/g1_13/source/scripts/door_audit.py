import bpy,json
from pathlib import Path
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];S=bpy.context.scene
doors=[o for o in bpy.data.objects if o.type=='MESH'and o.name.startswith('gear_door_')];results=[]
def tree(o):return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[list(p.vertices)for p in o.data.polygons])
for f in range(0,101,5):
 S.frame_set(f);bpy.context.view_layer.update();hits=[]
 for d in doors:
  othernames=['fuselage_core']if 'tail'in d.name else['wing_center_fixed','gear_wheel_left'if'left'in d.name else'gear_wheel_right']
  dt=tree(d)
  for n in othernames:
   count=len(dt.overlap(tree(bpy.data.objects[n])))
   if count:hits.append({'door':d.name,'other':n,'triangle_contacts':count})
 results.append({'frame':f,'contacts':hits})
(P/'previews/door-audit.json').write_text(json.dumps({'method':'BVH surface contact candidates, includes seated seams. Not a penetration depth measurement.','samples':results},indent=2));print(json.dumps(results),flush=True)
