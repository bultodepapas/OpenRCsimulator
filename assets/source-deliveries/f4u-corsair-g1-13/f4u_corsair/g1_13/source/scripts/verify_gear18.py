import bpy,json,hashlib,struct,ast
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];B=P.parent/'g1_7';S=bpy.context.scene;C=bpy.data.collections['EXPORT_aircraft'];checks={}
def check(n,ok,detail=None):checks[n]={'passed':bool(ok),'detail':detail}
targets={o.name for o in bpy.data.objects if o.name.startswith('gear_wheel_')or(o.name.startswith('gear_door_')and'_mesh_'in o.name and'tail'not in o.name)}
def snapshot():
 S=bpy.context.scene;S.frame_set(100);bpy.context.view_layer.update();data={}
 for o in bpy.data.collections['EXPORT_aircraft'].objects:
  if o.type!='MESH':continue
  m=o.data;uv=m.uv_layers['UVMap']
  data[o.name]={'v':[tuple(v.co)for v in m.vertices],'p':[tuple(p.vertices)for p in m.polygons],'uv':[tuple(l.uv)for l in uv.data],'mat':[m.materials[p.material_index].name for p in m.polygons],'norm':[tuple(o.matrix_world.to_3x3()@p.normal)for p in m.polygons],'loops':[list(p.loop_indices)for p in m.polygons]}
 return data
tree=ast.parse((P/'source/scripts/verify_paints.py').read_text());exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name=='rig_hash'],type_ignores=[]),'hash_rig','exec'))
rig=rig_hash();current=snapshot()
for n in targets:
 o=bpy.data.objects[n];used={i for p in o.data.polygons for i in p.vertices};check(n+'_no_loose_vertices',len(used)==len(o.data.vertices),len(o.data.vertices)-len(used))
check('gear_images_packed',all(bpy.data.images[n].packed_file and list(bpy.data.images[n].size)==[2048,2048]for n in ['gear18_basecolor','gear18_orm']))
def bvh(o):return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[list(p.vertices)for p in o.data.polygons])
# Surface intersections on every integer frame, including both new tyre envelopes.
rows=[];static={n:bvh(bpy.data.objects[n])for n in ['fuselage_core','wing_center_fixed']}
for f in range(101):
 S.frame_set(f);bpy.context.view_layer.update();dynamic={n:bvh(bpy.data.objects[n])for n in targets};hits=[]
 for name,dt in dynamic.items():
  if name.startswith('gear_door_'):
   other=['wing_center_fixed','gear_wheel_left'if'left'in name else'gear_wheel_right']
  else:other=['fuselage_core']if'tail'in name else['wing_center_fixed']
  for n in other:
   ot=static[n]if n in static else dynamic[n];count=len(dt.overlap(ot))
   if count:hits.append({'a':name,'b':n,'surface_contacts':count})
 rows.append({'frame':f,'contacts':hits})
check('gear_surface_contacts',not any(r['contacts']for r in rows),[r for r in rows if r['contacts']])
contact={'method':'BVH triangle surface intersections at all 101 integer GearRetract frames. Does not prove positive clearance or continuous collision freedom. Deliberate tyre/rim and fastener/skin seating within each mesh is excluded.','samples':rows,'passed':not any(r['contacts']for r in rows)}
(P/'previews/gear-contact-audit.json').write_text(json.dumps(contact,indent=2))
bpy.ops.wm.open_mainfile(filepath=str(B/'source/aircraft_game.blend'));before=snapshot();check('same_object_names',set(before)==set(current));check('same_hierarchy_and_101_poses',rig_hash()==rig,rig)
unchanged=[];outside=[]
for n,d in before.items():
 c=current[n]
 if n not in targets:
  if d['v']!=c['v']or d['p']!=c['p']or d['uv']!=c['uv']:unchanged.append(n)
 elif n.startswith('gear_door_'):
  if max((Vector(v)-Vector(c['v'][i])).length for i,v in enumerate(d['v']))>1e-6:outside.append(n+' vertices')
  for i,ids in enumerate(d['p']):
   if d['norm'][i][2]>.15:continue
   if c['p'][i]!=ids or c['mat'][i]!=d['mat'][i]:outside.append(n+' faces');break
   if any((Vector(d['uv'][l])-Vector(c['uv'][l])).length>1e-6 for l in d['loops'][i]):outside.append(n+' exterior UV');break
check('unrelated_geometry_and_uv_unchanged',not unchanged,unchanged)
check('door_original_vertices_exterior_faces_uv_preserved',not outside,outside)
report={'passed':all(c['passed']for c in checks.values()),'checks':checks};(P/'previews/gear-verification.json').write_text(json.dumps(report,indent=2));print('GEAR18_VERIFY',json.dumps(report),flush=True)
if not report['passed']:raise SystemExit(1)
