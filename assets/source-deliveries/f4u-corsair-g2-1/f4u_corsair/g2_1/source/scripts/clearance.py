import bpy,json,math
from pathlib import Path
from mathutils import Matrix
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];meta=json.loads((P/'metadata.json').read_text());S=bpy.context.scene;S.frame_set(0)
def tree(o):
 return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[list(p.vertices)for p in o.data.polygons],all_triangles=False,epsilon=0)
results=[]
for spec in meta['articulations']:
 n=spec['node']
 if not n.startswith(('aileron','flap','elevator','rudder')):continue
 o=bpy.data.objects[n];rest=o.matrix_basis.copy();moving=[bpy.data.objects[m]for m in spec['member_meshes']]
 if n.startswith('aileron'):fixed=['wing_'+('left'if'left'in n else'right')+'_fixed']
 elif n.startswith('flap'):fixed=['wing_center_fixed','wing_'+('left'if'left'in n else'right')+'_fixed']
 elif n.startswith('elevator'):fixed=['stabilizer_fixed','fuselage_core','fin_fixed']
 else:fixed=['fin_fixed','fuselage_core','stabilizer_fixed','elevator']
 fixedtrees={k:tree(bpy.data.objects[k])for k in fixed};samples=[]
 lo,hi=spec['checked_range_degrees']
 angles=sorted(set(range(lo,hi+1,5))|({1,2,3,4} if n.startswith('flap') else set()))
 for degree in angles:
  o.matrix_basis=rest@Matrix.Rotation(math.radians(degree),4,'X');bpy.context.view_layer.update();hits={}
  for m in moving:
   t=tree(m)
   for k,ft in fixedtrees.items():
    count=len(t.overlap(ft))
    if count:hits[m.name+' / '+k]=count
  samples.append({'degrees':degree,'triangle_contacts':hits})
 o.matrix_basis=rest;bpy.context.view_layer.update();results.append({'node':n,'samples':samples,'clear':all(not s['triangle_contacts']for s in samples)})
report={'method':'BVH triangle surface intersections, 5-degree samples plus flap 1,2,3,4 degrees; contact counts are not penetration-depth measurements. Not continuous collision detection.','all_clear':all(r['clear']for r in results),'controls':results}
(P/'previews/clearance.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
if not report['all_clear']:raise SystemExit(1)
