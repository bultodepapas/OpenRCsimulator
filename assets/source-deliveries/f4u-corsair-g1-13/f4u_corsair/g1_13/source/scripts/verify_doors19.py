import bpy,json,hashlib,struct,ast
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];B=P.parent/'g1_8';S=bpy.context.scene;checks={}
def check(n,v,d=None):checks[n]={'passed':bool(v),'detail':d}
tree=ast.parse((P/'source/scripts/verify_paints.py').read_text());exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name=='rig_hash'],type_ignores=[]),'rig_hash','exec'))
rig=rig_hash();targets={f'gear_door_{k}_mesh_{r}'for r in ['left','right']for k in ['front','inner','outer']}
def snapshot():
 result={}
 for o in bpy.data.collections['EXPORT_aircraft'].objects:
  if o.type!='MESH':continue
  m=o.data;result[o.name]={'v':[tuple(v.co)for v in m.vertices],'p':[tuple(p.vertices)for p in m.polygons],'uv':[tuple(l.uv)for l in m.uv_layers['UVMap'].data],'mats':[m.materials[p.material_index].name for p in m.polygons],'normal':[tuple(p.normal)for p in m.polygons]}
 return result
cur=snapshot()
for n in targets:
 m=bpy.data.objects[n].data;check(n+'_no_loose',len({i for p in m.polygons for i in p.vertices})==len(m.vertices));check(n+'_detail_uv',m.uv_layers.get('DoorInteriorUV')is not None)
check('interior_images_packed',all(bpy.data.images['interior19_'+n].packed_file and list(bpy.data.images['interior19_'+n].size)==[2048,2048]for n in ['basecolor','orm','normal']))
def bvh(o,faces=None):return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[list(p.vertices)for p in (o.data.polygons if faces is None else faces)])
build=json.loads((P/'previews/doors-build.json').read_text());rows=[]
for f in range(101):
 S.frame_set(f);bpy.context.view_layer.update();meshes={o.name:o for o in bpy.data.collections['EXPORT_aircraft'].objects if o.type=='MESH'};dyn={n:bvh(meshes[n])for n in targets|{'gear_wheel_left','gear_wheel_right','wing_center_fixed'}};hits=[]
 for n in sorted(targets):
  for other in ['wing_center_fixed','gear_wheel_left'if'left'in n else'gear_wheel_right']:
   c=len(dyn[n].overlap(dyn[other]))
   if c:hits.append([n,other,c])
  # Test just the new support plates against nearby gear parts and other doors.
  o=meshes[n];plate=bvh(o,list(o.data.polygons)[build[n]['original_polygons']:])
  for other,oo in meshes.items():
   if other==n or not other.startswith('gear_'):continue
   ob=dyn.get(other)or bvh(oo);c=len(plate.overlap(ob))
   if c:hits.append(['new_support:'+n,other,c])
 rows.append({'frame':f,'contacts':hits})
check('101_frames_without_surface_crossings',not any(r['contacts']for r in rows),[r for r in rows if r['contacts']])
(P/'previews/door-contact-audit.json').write_text(json.dumps({'passed':not any(r['contacts']for r in rows),'frames':rows,'method':'Discrete triangle-surface overlap at 101 integer frames. Full main doors vs well and wheels, plus new support plates vs other gear meshes. Does not certify positive/continuous clearance.'},indent=2))
for file,count in [('aircraft.glb',7),('aircraft_super57.glb',8)]:
 raw=(P/'export'/file).read_bytes();g=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]]);mat=next(m for m in g['materials']if m['name']=='gear_inner_coat');check(file+'_image_count',len(g['images'])==count,len(g['images']));check(file+'_normal_exported','normalTexture'in mat)
 pbr=mat['pbrMetallicRoughness'];check(file+'_interior_uv1',all(t.get('texCoord',0)==1 for t in [pbr['baseColorTexture'],pbr['metallicRoughnessTexture'],mat['normalTexture']]))
bpy.ops.wm.open_mainfile(filepath=str(B/'source/aircraft_game.blend'));prev=snapshot();check('all_101_poses_and_hierarchy_identical',rig_hash()==rig,rig);check('same_nodes',cur.keys()==prev.keys())
errors=[];normals=[]
for n,p in prev.items():
 c=cur[n]
 for field in ['v','p','uv','mats']:
  cc=c[field][:len(p[field])]if n in targets else c[field]
  if cc!=p[field]:errors.append(n+':'+field)
 if n in targets:
  dif=max((Vector(a)-Vector(b)).length for a,b in zip(p['normal'],c['normal']))
  if dif>1e-5:normals.append([n,dif])
check('all_original_geometry_uv0_material_assignments_preserved',not errors,errors);check('original_face_normals_preserved',not normals,normals)
out={'passed':all(c['passed']for c in checks.values()),'checks':checks};(P/'previews/doors-verification.json').write_text(json.dumps(out,indent=2));print('DOORS19_VERIFY',json.dumps(out),flush=True)
if not out['passed']:raise SystemExit(1)
