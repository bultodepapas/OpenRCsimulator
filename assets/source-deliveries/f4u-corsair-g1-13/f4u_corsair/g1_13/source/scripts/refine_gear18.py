"""Run once on a g1.7 game source. Details stay in existing rigid moving meshes."""
import bpy,bmesh,math,json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;C=bpy.data.collections['EXPORT_aircraft']
assert not S.get('gear_detail_g18'),'Already refined; reopen the prior source to rebuild.'
S.frame_set(100);bpy.context.view_layer.update();closed={o.name:o.matrix_world.copy()for o in C.objects}

def material(name,color,rough,metal=0):
 m=bpy.data.materials.get(name)or bpy.data.materials.new(name);m.use_nodes=True
 bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal;m.diffuse_color=(*color,1)
 return m,bs
gear,bs=material('gear_finish',(.5,.5,.5),.5)
for label,file,cs in [('basecolor','basecolor.png','sRGB'),('orm','orm.png','Non-Color')]:
 im=bpy.data.images.load(str(P/'textures/gear'/file),check_existing=False);im.name='gear18_'+label;im.colorspace_settings.name=cs;im.pack()
 tex=gear.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;tex.name='gear_'+label
 if label=='basecolor':gear.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
 else:
  sep=gear.node_tree.nodes.new('ShaderNodeSeparateColor');sep.mode='RGB';gear.node_tree.links.new(tex.outputs['Color'],sep.inputs['Color']);gear.node_tree.links.new(sep.outputs['Green'],bs.inputs['Roughness']);gear.node_tree.links.new(sep.outputs['Blue'],bs.inputs['Metallic'])
interior,ibs=material('gear_inner_coat',(.50,.53,.47),.53,.025)

class Builder:
 def __init__(self):self.v=[];self.f=[];self.uv=[];self.smooth=[]
 def vert(self,p):self.v.append(tuple(p));return len(self.v)-1
 def face(self,ids,uv=None,smooth=True):
  self.f.append(tuple(ids));self.uv.append(uv or[(.5,.83)]*len(ids));self.smooth.append(smooth)
 def lathe(self,profile,n=48,style='rim',side=1,scale=1,width_scale=1,center=(0,0,0)):
  rings=[]
  for x,r in profile:rings.append([self.vert((center[0]+x*side*width_scale,center[1]+r*scale*math.cos(2*math.pi*i/n),center[2]+r*scale*math.sin(2*math.pi*i/n)))for i in range(n)])
  def uv(i,j):
   v=.02+.46*j/(len(profile)-1)if style=='tyre' else (.53+.23*max(0,min(1,(profile[j][1]-.017)/.043))if style=='rim'else{'metal':.83,'brake':.90,'rubber':.97}[style])
   return(i/n,v)
  for j in range(len(rings)):
   k=(j+1)%len(rings)
   for i in range(n):
    ids=[rings[j][i],rings[j][(i+1)%n],rings[k][(i+1)%n],rings[k][i]];tex=[uv(i,j),uv(i+1,j),uv(i+1,k),uv(i,k)]
    if side<0:ids.reverse();tex.reverse()
    self.face(ids,tex)
 def prism(self,polygon,xs,style='rim',side=1,scale=1,width_scale=1):
  cy=sum(p[0]for p in polygon)/len(polygon);cz=sum(p[1]for p in polygon)/len(polygon);rings=[]
  for x,shrink in xs:rings.append([self.vert((x*side*width_scale,(cy+(y-cy)*shrink)*scale,(cz+(z-cz)*shrink)*scale))for y,z in polygon])
  uv=[(.5,.67)]*len(polygon)
  for j in range(len(rings)-1):
   for i in range(len(polygon)):self.face([rings[j][i],rings[j][(i+1)%len(polygon)],rings[j+1][(i+1)%len(polygon)],rings[j+1][i]],[(.5,.67)]*4,False)
  self.face(rings[0][::-1],uv,False);self.face(rings[-1],uv,False)
 def cylinder(self,center,radius,depth,n=8,style='metal',axis=(1,0,0)):
  axis=Vector(axis).normalized();u=axis.orthogonal().normalized();v=axis.cross(u);rings=[]
  for d in (-depth/2,depth/2):rings.append([self.vert(Vector(center)+axis*d+radius*(math.cos(2*math.pi*i/n)*u+math.sin(2*math.pi*i/n)*v))for i in range(n)])
  uv=(.5,{'metal':.83,'brake':.90,'rubber':.97,'rim':.67}[style])
  for i in range(n):self.face([rings[0][i],rings[0][(i+1)%n],rings[1][(i+1)%n],rings[1][i]],[uv]*4,True)
  self.face(rings[0][::-1],[uv]*n,False);self.face(rings[1],[uv]*n,False)
 def mesh(self,name):
  used=sorted({i for f in self.f for i in f});remap={old:new for new,old in enumerate(used)}
  m=bpy.data.meshes.new(name);m.from_pydata([self.v[i]for i in used],[],[tuple(remap[i]for i in f)for f in self.f]);m.update();uv=m.uv_layers.new(name='UVMap')
  for p,tex,smooth in zip(m.polygons,self.uv,self.smooth):
   p.use_smooth=smooth
   for l,t in zip(p.loop_indices,tex):uv.data[l].uv=t
  bm=bmesh.new();bm.from_mesh(m);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(m);bm.free();m.update();return m

profile=[(-.019,.057),(-.0225,.064),(-.023,.075),(-.022,.083),(-.017,.090),(-.012,.0934),(-.0108,.0936),(-.010,.0925),(-.0092,.0938),(-.0058,.094),(-.005,.0926),(-.0042,.0941),(-.0008,.09415),(0,.0927),(.0008,.09415),(.0042,.0941),(.005,.0926),(.0058,.094),(.0092,.0938),(.010,.0925),(.0108,.0936),(.012,.0934),(.017,.090),(.022,.083),(.023,.075),(.0225,.064),(.019,.057)]
report={'wheels':{},'doors':{}}
for role in ['left','right','tail']:
 o=bpy.data.objects['gear_wheel_'+role];assert o.parent.name=='gear_spin_'+role
 b=Builder();tail=role=='tail';scale=.03889/.09415 if tail else 1;ws=.56 if tail else 1;side=-1 if role=='left'else 1
 b.lathe(profile,32 if tail else 64,'tyre',scale=scale,width_scale=ws)
 b.lathe([(-.020,.052),(-.0215,.058),(-.0185,.060),(.0185,.060),(.0215,.058),(.020,.052)],32 if tail else 48,'rim',scale=scale,width_scale=ws)
 count=6 if tail else 8
 for i in range(count):
  a=2*math.pi*i/count
  polygon=[(r*math.cos(a+da),r*math.sin(a+da))for r,da in[(.017,-.25),(.054,-.09),(.054,.09),(.017,.25)]]
  b.prism(polygon,[(-.018,.88),(-.0168,1),(.0168,1),(.018,.88)],scale=scale,width_scale=ws)
 b.lathe([(-.020,.010),(-.020,.018),(-.014,.021),(.014,.021),(.020,.018),(.020,.010)],24 if tail else 32,'rim',scale=scale,width_scale=ws)
 # Inboard brake backing sits behind the open web, not in front of the outer rim.
 b.lathe([(-.010,.019),(-.010,.050),(-.006,.050),(-.006,.019)],24 if tail else 32,'brake',side=side,scale=scale,width_scale=ws)
 for face in (-1,1):
  b.lathe([(.018,.001),(.018,.012),(.022,.012),(.023,.009),(.023,.001)],16 if tail else 24,'metal',side=face,scale=scale,width_scale=ws)
  for i in range(count):
   a=2*math.pi*i/count;b.cylinder((face*.019*ws,.030*scale*math.cos(a),.030*scale*math.sin(a)),.0017*scale,.0020*ws,6,'metal')
 if not tail:
  a=1.1;b.cylinder((side*.019,.050*math.cos(a),.050*math.sin(a)),.00145,.007,8,'brake',axis=(side,0,0))
  b.cylinder((side*.023,.050*math.cos(a),.050*math.sin(a)),.00165,.0014,8,'rubber')
 old=o.data;o.data=b.mesh(o.name+'_mesh');o.data.materials.append(gear)
 if old.users==0:bpy.data.meshes.remove(old)
 o['g1_8_detail']='revolved tyre, recessed grooves, open wheel web, painted rim, hub caps, hex bolts, inboard brake backing'
 report['wheels'][o.name]={'triangles':sum(len(p.vertices)-2 for p in o.data.polygons),'radius_m':.09415*scale,'half_width_m':.0237*ws,'web_count':count}

# Thin stiffening beads follow the actual inner skin, sampled in closed-wing coordinates.
for role in ['left','right']:
 sign=-1 if role=='left'else 1
 for kind,cx,stations,length in [('front',.421,[-.10,-.17],.060),('inner',.361,[-.20,-.28,-.36],.054),('outer',.457,[-.20,-.28,-.36],.054)]:
  o=bpy.data.objects[f'gear_door_{kind}_mesh_{role}'];M=closed[o.name];inv=M.inverted();m=o.data;m.calc_loop_triangles()
  inner_faces=[p.index for p in m.polygons if (M.to_3x3()@p.normal).z>.15]
  inner_tris=[t for t in m.loop_triangles if t.polygon_index in inner_faces]
  verts=[M@v.co for v in m.vertices];bvh=BVHTree.FromPolygons(verts,[list(t.vertices)for t in inner_tris],all_triangles=True)
  idx=len(m.materials);m.materials.append(interior)
  for i in inner_faces:m.polygons[i].material_index=idx
  extra=Builder();raised=[]
  def surface(x,y):
   hit,norm,face,dist=bvh.ray_cast(Vector((x,y,.5)),Vector((0,0,-1)),1.0)
   return hit if hit is not None else None
  for cy in stations:
   rings=[];ok=True
   for t in range(7):
    px=sign*(cx-length/2+length*t/6)/.9;row=[]
    for dy,h in [(-.0035,0),(-.0020,.00065),(.0020,.00065),(.0035,0)]:
     hit=surface(px,cy/.9+dy)
     if hit is None:ok=False;break
     point=hit+Vector((0,0,h+.000035));row.append(extra.vert(inv@point));raised.append(list(point))
    if not ok:break
    rings.append(row)
   if ok:
    for j in range(6):
     for k in range(3):extra.face([rings[j][k],rings[j+1][k],rings[j+1][k+1],rings[j][k+1]],smooth=False)
    extra.face(rings[0],smooth=False);extra.face(rings[-1][::-1],smooth=False)
   for dx in (-length*.40,length*.40):
    hit=surface(sign*(cx+dx)/.9,cy/.9)
    if hit is not None:
     p=hit+Vector((0,0,.00078));axis=inv.to_3x3()@Vector((0,0,1));extra.cylinder(inv@p,.00115,.00030,8,'rim',axis)
  # Append geometry and UVs without replacing original vertices, faces or outer paint.
  em=extra.mesh('temporary_door_detail');em.materials.append(interior)
  temp=bpy.data.objects.new('temporary_door_detail',em);C.objects.link(temp);temp.matrix_world=o.matrix_world
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);temp.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.join()
  o['g1_8_detail']='painted inner skin, thin sampled stiffening beads and seated rivet heads'
  report['doors'][o.name]={'original_inner_polygons':len(inner_faces),'rib_height_m':.00065,'rivet_head_top_m':.00093,'detail_vertices':len({i for f in extra.f for i in f}),'detail_triangles':sum(len(f)-2 for f in extra.f)}
# Existing well liners and near-vertical cut walls get a coherent interior finish.
o=bpy.data.objects['wing_center_fixed'];m=o.data;idx=len(m.materials);m.materials.append(interior);well_count=0
for p in m.polygons:
 c=p.center;wall=(.346<abs(c.x)<.562 and -.482<c.y<-.030 and c.z<-.145 and abs(p.normal.z)<.70)
 if m.materials[p.material_index].name=='cockpit'or wall:p.material_index=idx;well_count+=1
report['well_inner_finish_polygons']=well_count
S['gear_detail_g18']=True;S.frame_set(0);bpy.context.view_layer.update()
meta=json.loads((P/'metadata.json').read_text());meta['revision']='g1.8';meta['base_revision']='g1.7';meta['revision_scope']='Gear appearance: wheels, coated open rims, tyre grooves, inner-door reinforcement and material detail. Existing pivots and sampled motion retained.';meta['gear_detail_g1_8']=report
meta['paint_finish']['gear_atlas']='textures/gear/basecolor.png and orm.png; 2048 square, shared across all liveries'
(P/'metadata.json').write_text(json.dumps(meta,indent=2));(P/'previews/gear-build.json').write_text(json.dumps(report,indent=2))
if 'PAINT_G1_7_README'in bpy.data.texts:bpy.data.texts.remove(bpy.data.texts['PAINT_G1_7_README'])
t=bpy.data.texts.get('GEAR_G1_8_README')or bpy.data.texts.new('GEAR_G1_8_README');t.clear();t.write('g1.8: interior de compuertas, neumáticos y rines. Mismos pivotes y acción GearRetract. Frame 0 abajo; exportación frame 100. Nuevos refuerzos unidos a cada compuerta, rines y neumáticos unidos a gear_wheel_*; texturas empacadas. Geometría de detalle interpretada a partir de las fotos, no plano de fabricación.')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'))
print('GEAR18_REFINED',json.dumps(report),flush=True)
