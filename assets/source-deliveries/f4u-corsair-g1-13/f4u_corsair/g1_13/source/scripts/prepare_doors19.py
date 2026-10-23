"""Apply once to g1.8. Keep the existing door skin, hinges and rigid rig."""
import bpy,bmesh,json,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;C=bpy.data.collections['EXPORT_aircraft']
assert not S.get('doors_detail_g19'),'Reopen the g1.8 source before regenerating.'
S.frame_set(100);bpy.context.view_layer.update();layout=[];report={}
inner=bpy.data.materials['gear_inner_coat']
names=[f'gear_door_{kind}_mesh_{role}'for role in ['left','right']for kind in ['front','inner','outer']]
for tile,name in enumerate(names):
 o=bpy.data.objects[name];M=o.matrix_world.copy();inv=M.inverted();m=o.data
 oldv=len(m.vertices);oldp=len(m.polygons);original=[tuple(v.co)for v in m.vertices]
 indices=[p.index for p in m.polygons if m.materials[p.material_index]==inner]
 world=[M@v.co for v in m.vertices];tri=[[int(i)for i in t.vertices]for t in m.loop_triangles if t.polygon_index in indices]
 m.calc_loop_triangles();tri=[list(t.vertices)for t in m.loop_triangles if t.polygon_index in indices]
 bvh=BVHTree.FromPolygons(world,tri,all_triangles=True)
 def hit(x,y):return bvh.ray_cast(Vector((x,y,.5)),Vector((0,0,-1)),1)[0]
 coords=[world[i]for p in m.polygons if p.index in indices for i in p.vertices]
 x0=min(v.x for v in coords);x1=max(v.x for v in coords);y0=min(v.y for v in coords);y1=max(v.y for v in coords)
 # Two shallow, chamfered support/doubler plates, set on the inner skin.
 pad_points=[];padverts=[];padfaces=[];s=-1 if 'left'in name else 1
 for yf in (.24,.74):
  px=x0+(x1-x0)*(.25 if 'inner'in name else .75)
  if 'left'in name:px=x0+x1-px
  py=y0+(y1-y0)*yf
  if 'front'in name:py=y0+(y1-y0)*(.34 if yf<.5 else .68)
  rings=[];valid=True
  for height,shrink in [(.00005,1),(.00085,1),(.0012,.78)]:
   ring=[]
   for dx,dy in [(-.0045,-.007),(.0045,-.007),(.0045,.007),(-.0045,.007)]:
    h=hit(px+dx*shrink,py+dy*shrink)
    if h is None:valid=False;break
    ring.append(tuple(inv@(h+Vector((0,0,height)))))
   rings.append(ring)
  if not valid:continue
  start=len(padverts);padverts.extend(v for r in rings for v in r)
  for j in range(2):
   for k in range(4):padfaces.append((start+4*j+k,start+4*j+(k+1)%4,start+4*(j+1)+(k+1)%4,start+4*(j+1)+k))
  padfaces.extend([(start+3,start+2,start+1,start),(start+8,start+9,start+10,start+11)])
  pad_points.append([px,py])
 # Append directly, retaining every original vertex, polygon and original UV loop.
 faces=[tuple(p.vertices)for p in m.polygons]+[tuple(oldv+i for i in f)for f in padfaces]
 mats=list(m.materials);inneridx=mats.index(inner);mi=[p.material_index for p in m.polygons]+[inneridx]*len(padfaces)
 sm=[p.use_smooth for p in m.polygons]+[False]*len(padfaces)
 uvs={layer.name:[tuple(l.uv)for l in layer.data]for layer in m.uv_layers}
 nm=bpy.data.meshes.new(name+'_g19_mesh');nm.from_pydata(original+padverts,[],faces);nm.update()
 for mat in mats:nm.materials.append(mat)
 for p,mat,smooth in zip(nm.polygons,mi,sm):p.material_index=mat;p.use_smooth=smooth
 for un,values in uvs.items():
  u=nm.uv_layers.new(name=un)
  for i,v in enumerate(values):u.data[i].uv=v
 o.data=nm
 if m.users==0:bpy.data.meshes.remove(m)
 # Dedicated second UV set: all exterior UV0 paint remains byte-identical.
 scale=min(476/(x1-x0),988/(y1-y0));tx=(tile%4)*512+256-(x0+x1)*scale/2;ty=(tile//4)*1024+512+(y0+y1)*scale/2
 def pixel(p):return [tx+p.x*scale,ty-p.y*scale]
 uv=nm.uv_layers.new(name='DoorInteriorUV');base=nm.uv_layers['UVMap']
 for i,l in enumerate(uv.data):l.uv=base.data[i].uv
 polygons=[]
 for p in nm.polygons:
  if nm.materials[p.material_index]!=inner:continue
  ps=[pixel(M@nm.vertices[i].co)for i in p.vertices];polygons.append(ps)
  for li,xy in zip(p.loop_indices,ps):uv.data[li].uv=(xy[0]/2048,1-xy[1]/2048)
 nm.uv_layers.active_index=0
 for u in nm.uv_layers:u.active_render=(u.name=='UVMap')
 layout.append({'name':name,'tile':tile,'scale':scale,'tx':tx,'ty':ty,'bounds':[x0,x1,y0,y1],'polygons':polygons,'pads':pad_points,'kind':name.split('_')[2],'role':'left'if'left'in name else'right'})
 report[name]={'original_vertices':oldv,'original_polygons':oldp,'new_support_plates':len(pad_points),'added_triangles':sum(len(f)-2 for f in padfaces),'max_plate_height_m':.0012}
 o['g1_9_detail']='Shallow chamfered inner doubler plates; dedicated paint UV on inward faces; original exterior untouched.'
# Well lining: project each surface on its dominant axis into a quiet shared finish tile.
o=bpy.data.objects['wing_center_fixed'];m=o.data;uv=m.uv_layers.new(name='DoorInteriorUV');base=m.uv_layers['UVMap']
for i,l in enumerate(uv.data):l.uv=base.data[i].uv
for p in m.polygons:
 if m.materials[p.material_index]!=inner:continue
 for li in p.loop_indices:
  v=m.vertices[m.loops[li].vertex_index].co
  # Well textures are subtle unmarked coating; no false panels across cut corners.
  x=3*512+48+((abs(v.x)-.34)/.25)*416;y=1024+48+((v.y+.49)/.5)*928
  x=max(3*512+24,min(2048-24,x));y=max(1024+24,min(2048-24,y));uv.data[li].uv=(x/2048,1-y/2048)
m.uv_layers.active_index=0
for u in m.uv_layers:u.active_render=(u.name=='UVMap')
S['doors_detail_g19']=True;S.frame_set(0)
(P/'textures/interiors').mkdir(exist_ok=True)
(P/'textures/interiors/layout.json').write_text(json.dumps(layout))
(P/'previews/doors-build.json').write_text(json.dumps(report,indent=2))
t=bpy.data.texts.get('DOORS_G1_9_README')or bpy.data.texts.new('DOORS_G1_9_README');t.write('g1.9: seis compuertas principales con asientos interiores biselados y atlas dedicado. UV0 exterior, posiciones originales y articulaciones conservadas. Pintura interpretada, no plano de fábrica.')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'))
print('DOORS19_PREPARED',json.dumps(report),flush=True)
