"""Bidirectional sampled distance from full evaluated R59 to g2 main skins.
All low vertices and high vertices/triangle centres (stride <= 2) are evaluated.
"""
import bpy,json,math,statistics
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];W=P.parent/'work/rev4_B'
bpy.ops.wm.open_mainfile(filepath=str(P/'source/aircraft_game.blend'));bpy.context.scene.frame_set(0)
with bpy.data.libraries.load(str(W/'r59_sources.blend'),link=False) as(a,b):b.collections=['R59_BAKE']
c=b.collections[0];bpy.context.scene.collection.children.link(c)
names=['fuselage_core','cowl','wing_center_fixed','wing_left_fixed','wing_right_fixed','aileron_left','aileron_right']+[f'flap_{s}_{i}' for s in ['left','right'] for i in [1,2,3]]+['stabilizer_fixed','elevator','fin_fixed','rudder','canopy_glass','windshield_glass']
bake_only={r['source'] for r in json.loads((W/'extraction.json').read_text())['sources'] if r.get('bake_only')}
def data(objects):
 v=[];f=[]
 for o in objects:
  o.data.calc_loop_triangles();start=len(v)
  triangles=[t for t in o.data.loop_triangles if not(o.data.materials and o.data.materials[t.material_index] and o.data.materials[t.material_index].name=='detail_alloy')]
  used=sorted({i for t in triangles for i in t.vertices});remap={n:i+start for i,n in enumerate(used)};v.extend(o.matrix_world@o.data.vertices[i].co for i in used);f.extend(tuple(remap[i]for i in p.vertices)for p in triangles)
 return v,f
rows=[]
for name in names:
 lo=bpy.data.objects[name];sources=[o for o in c.objects if o['g2_target']==name and o['r59_source'] not in bake_only]
 lv,lf=data([lo]);hv,hf=data(sources);lb=BVHTree.FromPolygons(lv,lf);hb=BVHTree.FromPolygons(hv,hf)
 ds=[]
 for vs,bvh in [(lv,hb),(hv,lb)]:
  for v in vs:
   hit=bvh.find_nearest(v)
   if hit[0] is not None:ds.append(hit[3]*1000)
 for face in hf:
  p=sum((hv[i] for i in face),Vector())/len(face);hit=lb.find_nearest(p)
  if hit[0] is not None:ds.append(hit[3]*1000)
 ds.sort();rows.append({'node':name,'samples':len(ds),'sampled_max_mm':max(ds),'p95_mm':ds[int((len(ds)-1)*.95)],'median_mm':ds[len(ds)//2]})
 print('DEVIATION',name,round(rows[-1]['sampled_max_mm'],4),round(rows[-1]['p95_mm'],4),flush=True)
(P/'checks/deviation_R59.json').write_text(json.dumps({'method':'bidirectional nearest surface at every vertex plus R59 face centre; sampled maximum, not a certified continuous Hausdorff bound','units':'mm at 1:4.5 model scale','R13_baked_seams_excluded':True,'parts':rows},indent=2))
