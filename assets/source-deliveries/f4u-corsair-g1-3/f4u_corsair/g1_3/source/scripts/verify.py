"""Mandatory checks. Blender --background source/aircraft_game.blend --python verify.py.
Disposable negative checks: append -- --remove-hinge or --invalid-tag.
"""
import bpy,json,math,re,sys,struct,hashlib
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(__file__).resolve().parents[2];meta=json.loads((P/'metadata.json').read_text());errors=[];checks={};valid={'core','wing_left','wing_right','wing_center','horizontal_tail','vertical_tail','engine','propeller','gear','canopy'}
def check(k,ok,detail=None):
 checks[k]={'passed':bool(ok),'detail':detail}
 if not ok:errors.append(k)
if '--remove-hinge'in sys.argv:bpy.data.objects.remove(bpy.data.objects['aileron_left_hinge'],do_unlink=True)
if '--invalid-tag'in sys.argv:bpy.data.objects['wing_right_fixed']['openrc_section']='bad_section'
scene=bpy.context.scene;scene.frame_set(0);bpy.context.view_layer.update();col=bpy.data.collections.get('EXPORT_aircraft');objects=list(col.objects)if col else[];root=bpy.data.objects.get('F4UCorsair');carriers={x['node']for x in meta['gear']['carriers']}
check('one_export_collection',col is not None and len(bpy.data.collections)==1)
check('root_identity',root is not None and max(abs(root.matrix_world[i][j]-(1 if i==j else 0))for i in range(4)for j in range(4))<1e-7)
check('metres',scene.unit_settings.scale_length==1)
check('unique_ascii_names',len({o.name for o in objects})==len(objects)and all(o.name.isascii()and not re.search(r'\.\d{3}$',o.name)for o in objects))
check('unit_node_scales',all(max(abs(v-1)for v in o.scale)<1e-6 and o.matrix_local.to_3x3().determinant()>0 for o in objects))
check('only_meshes_and_pivots',all(o.type in {'MESH','EMPTY'}for o in objects))
check('no_drivers_constraints',all(not o.constraints and(not o.animation_data or not o.animation_data.drivers)for o in objects))
check('section_tags',all(o.get('openrc_section')in valid for o in objects if o.name not in {'F4UCorsair','thrust_frame'}))
cross=[]
for o in objects:
 parent=o.parent
 while parent:
  if parent.get('openrc_section')and o.get('openrc_section')and parent['openrc_section']!=o['openrc_section']:cross.append([o.name,parent.name])
  parent=parent.parent
check('no_cross_section_ancestors',not cross,cross)
required={x['node']for x in meta['articulations']}|{'propeller_spin','thrust_frame'}|{f'gear_{kind}_{role}'for kind in ['compression','spin','wheel']for role in ['left','right','tail']}|{'gear_steer_tail'}|carriers
check('required_nodes',required.issubset({o.name for o in objects}),sorted(required-{o.name for o in objects}))
actions=list(bpy.data.actions);check('one_gear_action',len(actions)==1 and actions[0].name=='GearRetract')
animated={o.name for o in objects if o.animation_data and o.animation_data.action};check('only_listed_carriers_animated',animated==carriers,sorted(animated^carriers))
paths=[]
for a in actions:
 for layer in a.layers:
  for strip in layer.strips:
   if strip.type=='KEYFRAME':
    for bag in strip.channelbags:paths.extend(fc.data_path for fc in bag.fcurves)
check('rigid_animation_channels',bool(paths)and all(p in {'location','rotation_quaternion','rotation_euler'}for p in paths),sorted(set(paths)))
meshes=[o for o in objects if o.type=='MESH'];triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons)for o in meshes);surfaces=sum(len(set(p.material_index for p in o.data.polygons))for o in meshes);materials={m.name for o in meshes for m in o.data.materials if m};check('triangle_budget',60000<=triangles<=100000,triangles);check('hard_triangle_ceiling',triangles<=150000);check('surface_budget',surfaces<=60,surfaces);check('material_budget',len(materials)<=24,len(materials))
check('UVMap_on_painted_meshes',all('UVMap'in o.data.uv_layers for o in meshes if any(m and m.name.startswith('paint_')for m in o.data.materials)))
check('no_external_libraries',len(bpy.data.libraries)==0)
check('packed_runtime_images',all(im.packed_file is not None for im in bpy.data.images if im.source=='FILE'))
check('no_reference_images',all(not any(k in im.name.lower()for k in ['plano','reference','corsair_r11'])for im in bpy.data.images))
vv=[o.matrix_world@v.co for o in meshes for v in o.data.vertices];span=max(v.x for v in vv)-min(v.x for v in vv);check('span_2_778m',abs(span-12.5/4.5)<.01,span)
scene.frame_set(100);bpy.context.view_layer.update()
if 'nodes'in meta:
 mismatch=[]
 for o in objects:
  if o.name not in meta['nodes']:mismatch.append(o.name);continue
  M=Matrix(meta['nodes'][o.name]['rest_matrix_blender']);d=(M.translation-o.matrix_world.translation).length;angle=M.to_quaternion().rotation_difference(o.matrix_world.to_quaternion()).angle
  if d>.0001 or angle>math.radians(.01):mismatch.append([o.name,d,math.degrees(angle)])
 check('metadata_rest_transforms',not mismatch,mismatch)
reference=P/'source/scripts/gear-reference.json'
if reference.exists():
 ref=json.loads(reference.read_text());worst=0.;angular=0.
 for f in range(101):
  scene.frame_set(f);bpy.context.view_layer.update()
  for n,frames in ref.items():
   if n not in bpy.data.objects:continue
   M=Matrix(frames[f]);o=bpy.data.objects[n];worst=max(worst,(M.translation-o.location).length);angular=max(angular,M.to_quaternion().rotation_difference(o.rotation_quaternion).angle)
 check('sampled_gear_reproduction',worst<=.0001 and angular<=math.radians(.01),{'translation_m':worst,'angle_deg':math.degrees(angular)})
scene.frame_set(100);bpy.context.view_layer.update()
glbpath=P/'export/aircraft.glb'
if '--glb-path' in sys.argv:glbpath=Path(sys.argv[sys.argv.index('--glb-path')+1])
if glbpath.exists():
 data=glbpath.read_bytes();magic,version,total=struct.unpack_from('<4sII',data,0);length,kind=struct.unpack_from('<II',data,12);g=json.loads(data[20:20+length]);gn=g.get('nodes',[]);names=[n.get('name','')for n in gn];gmeshes=g.get('meshes',[]);gtri=sum(g['accessors'][p['indices']]['count']//3 for m in gmeshes for p in m['primitives']if p.get('mode',4)==4)
 check('glb_header',magic==b'glTF'and version==2 and total==len(data));check('glb_sha256',hashlib.sha256(data).hexdigest()==meta['glb_sha256']);check('glb_unique_ascii_names',len(names)==len(set(names))and all(n.isascii()for n in names));check('glb_required_nodes',required.issubset(set(names)),sorted(required-set(names)));check('glb_sections',all(n.get('extras',{}).get('openrc_section')in valid for n in gn if n.get('name')not in {'F4UCorsair','thrust_frame'}));check('glb_unit_scales',all(max(abs(v-1)for v in n.get('scale',[1,1,1]))<1e-6 for n in gn));check('glb_no_cameras_lights',not g.get('cameras')and not g.get('extensions',{}).get('KHR_lights_punctual'));check('glb_neutral_no_animations',not g.get('animations'));check('glb_embedded_images',all('bufferView'in im and 'uri'not in im for im in g.get('images',[])));check('glb_no_compression',not any(e in g.get('extensionsUsed',[])for e in ['KHR_draco_mesh_compression','EXT_meshopt_compression','KHR_mesh_quantization']));check('glb_counts',gtri==triangles and len(g.get('materials',[]))<=24,{'triangles':gtri,'surfaces':sum(len(m['primitives'])for m in gmeshes),'materials':len(g.get('materials',[])),'images':len(g.get('images',[]))})
 sys.path.insert(0,str(P/'source/scripts'));from glb_pose import compare,geometry_bounds
 pose=compare(g,objects);check('glb_matches_GearRetract_frame_100',pose['passed'],pose)
 bounds=geometry_bounds(g,data);glbspan=max(b['max'][0] for b in bounds.values())-min(b['min'][0] for b in bounds.values());check('glb_span_2_778m',abs(glbspan-12.5/4.5)<.01,glbspan)
else:check('glb_present',False)
result={'passed':not errors,'errors':errors,'checks':checks}
if any(k in sys.argv for k in ['--remove-hinge','--invalid-tag','--glb-path']):
 print('G1_NEGATIVE_TEST',json.dumps(result),flush=True)
else:(P/'verification.json').write_text(json.dumps(result,indent=2),encoding='utf8');print('G1_VERIFY',json.dumps({'passed':not errors,'errors':errors,'triangles':triangles,'surfaces':surfaces}),flush=True)
if errors:raise SystemExit(1)
