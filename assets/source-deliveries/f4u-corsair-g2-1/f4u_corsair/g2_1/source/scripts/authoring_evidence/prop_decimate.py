import bpy,bmesh,math,json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
W=Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(W.parent.parent/'g2_0/source/aircraft_game.blend'))
o=bpy.data.objects['propeller_rotor'];old=o.data
ref=BVHTree.FromPolygons([v.co for v in old.vertices],[list(p.vertices)for p in old.polygons])
bm=bmesh.new();bm.from_mesh(old);bm.normal_update();bm.verts.ensure_lookup_table();protected=set()
for f in bm.faces:
 if f.material_index>0:protected.update(v.index for v in f.verts)
for e in bm.edges:
 if len(e.link_faces)!=2:protected.update(v.index for v in e.verts);continue
 a,b=[f.normal for f in e.link_faces]
 mid=(e.verts[0].co+e.verts[1].co)*.5;delta=e.verts[1].co-e.verts[0].co
 for k in range(3):
  if a[k]*b[k]>0:continue
  direction=Vector([int(j==k)for j in range(3)]);side=direction.cross(delta)
  if side.length<1e-9:continue
  side.normalize();side*=.000015
  for sign in [-1,1]:
   hits=[ref.ray_cast(mid+side*off+direction*sign*2,-sign*direction,4)[0] is not None for off in [-1,1]]
   if hits[0]!=hits[1]:protected.update(v.index for v in e.verts)
bm.free()
protected.update(json.loads((W/'hub_envelope_protected.json').read_text()))
vgrp=o.vertex_groups.new(name='Reducible_hub_interior');vgrp.add([i for i in range(len(old.vertices))if i not in protected],1.,'REPLACE')
report=[]
for factor in [1,100,1000]:
 mod=o.modifiers.new('G21 hub budget','DECIMATE');mod.ratio=.46;mod.vertex_group=vgrp.name;mod.vertex_group_factor=factor;mod.use_collapse_triangulate=True
 dg=bpy.context.evaluated_depsgraph_get();ev=o.evaluated_get(dg);me=bpy.data.meshes.new_from_object(ev,depsgraph=dg);me.update();me.calc_loop_triangles()
 kd=KDTree(len(me.vertices))
 for v in me.vertices:kd.insert(v.co,v.index)
 kd.balance();protected_dev=max(kd.find(old.vertices[i].co)[2]for i in protected)*1000
 cv=BVHTree.FromPolygons([v.co for v in me.vertices],[list(t.vertices)for t in me.loop_triangles]);ds=[cv.find_nearest(v.co)[3]*1000 for v in old.vertices]+[ref.find_nearest(v.co)[3]*1000 for v in me.vertices];ds.sort()
 row={'factor':factor,'tris':len(me.loop_triangles),'protected':len(protected),'protected_max_displacement_mm':protected_dev,'max_mm':max(ds),'p95_mm':ds[int(.95*len(ds))]};report.append(row);print(row,flush=True)
 o.modifiers.remove(mod)
 if protected_dev<1e-4 and 12000<=len(me.loop_triangles)<=18000:
  me.name='propeller_rotor_g21';bpy.data.libraries.write(str(W/'rotor_decimated.blend'),{me},compress=True);break
(W/'prop_decimate.json').write_text(json.dumps(report,indent=2))
