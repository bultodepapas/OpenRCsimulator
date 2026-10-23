"""One-time migration of a COPY of accepted g1.2 to request revision 3 (1:4.5)."""
import bpy, json, hashlib, struct
from pathlib import Path
from mathutils import Matrix, Vector
P=Path(__file__).resolve().parents[2]
K=10/9
meta=json.loads((P/'metadata.json').read_text())
assert abs(meta['scale_factor']-.2)<1e-9, 'Requires unscaled g1.2; refuses repeated scaling'
assert bpy.app.version[:3]==(5,2,2)
S=bpy.context.scene; col=bpy.data.collections['EXPORT_aircraft']; objects=list(col.objects)
meshes=[o for o in objects if o.type=='MESH']
assert all(not o.modifiers and not o.data.shape_keys for o in meshes)
def mesh_signature(o):
 h=hashlib.sha256()
 for p in o.data.polygons:h.update(struct.pack('<'+'I'*(len(p.vertices)+1),p.material_index,*p.vertices))
 for uv in o.data.uv_layers:
  h.update(uv.name.encode())
  for loop in uv.data:h.update(struct.pack('<2f',*loop.uv))
 h.update(json.dumps([m.name if m else None for m in o.data.materials]).encode())
 return h.hexdigest()
signatures={o.name:mesh_signature(o) for o in meshes}
coordinates={o.name:[v.co.copy() for v in o.data.vertices] for o in meshes}
hierarchy={o.name:(o.parent.name if o.parent else None,o.get('openrc_section')) for o in objects}
poses={}
for f in range(101):
 S.frame_set(f);bpy.context.view_layer.update();poses[f]={o.name:o.matrix_world.copy() for o in objects}
S.frame_set(0)
for data in {o.data for o in meshes}:data.transform(Matrix.Scale(K,4));data.update()
for o in objects:
 o.location*=K
 o.delta_location*=K
 M=o.matrix_parent_inverse.copy();M.translation*=K;o.matrix_parent_inverse=M
 if o.type=='EMPTY':o.empty_display_size*=K
location_keys=0
for action in bpy.data.actions:
 for layer in action.layers:
  for strip in layer.strips:
   if strip.type=='KEYFRAME':
    for bag in strip.channelbags:
     for curve in bag.fcurves:
      if curve.data_path=='location':
       for point in curve.keyframe_points:
        point.co.y*=K;point.handle_left.y*=K;point.handle_right.y*=K;location_keys+=1
       curve.update()
position_error=rotation_error=0.
for f in range(101):
 S.frame_set(f);bpy.context.view_layer.update()
 for o in objects:
  expected=poses[f][o.name];actual=o.matrix_world
  position_error=max(position_error,(actual.translation-expected.translation*K).length)
  rotation_error=max(rotation_error,max(abs(actual[i][j]-expected[i][j]) for i in range(3) for j in range(3)))
S.frame_set(0);bpy.context.view_layer.update()
vertex_error=max((v.co-old*K).length for o in meshes for v,old in zip(o.data.vertices,coordinates[o.name]))
assert position_error<1e-6 and rotation_error<1e-6 and vertex_error<1e-6
assert all(mesh_signature(o)==signatures[o.name] for o in meshes)
assert hierarchy=={o.name:(o.parent.name if o.parent else None,o.get('openrc_section')) for o in objects}
assert all(max(abs(x-1) for x in o.scale)<1e-6 for o in objects)

def vec(v):return [x*K for x in v]
def matrix(m):
 for i in range(3):m[i][3]*=K
 return m
for key,value in meta['landmarks_blender_m'].items():
 if key=='thrust_axis':continue
 if isinstance(value,dict):meta['landmarks_blender_m'][key]={k:vec(v) for k,v in value.items()}
 else:meta['landmarks_blender_m'][key]=vec(value)
for wheel in meta['wheels'].values():
 for k in ['center','ground_contact']:wheel[k]=vec(wheel[k])
 for k in ['radius_m','oleo_travel_m']:wheel[k]*=K
for key in ['span_m','length_m','propeller_diameter_m']:meta[key]*=K
for art in meta['articulations']:
 art['pivot']=vec(art['pivot']);art['rest_matrix_local']=matrix(art['rest_matrix_local'])
meta['scale_factor']=1/4.5;meta['revision']='g1.3';meta['request_revision']=3
meta['base_revision']='g1.2';meta['uniform_rescale_from_base']=K
meta['gear']['runtime_export_frame']=100;meta['gear']['landmark_frame']=0
meta['gear']['saved_editing_frame']=0;meta['wheel_track_m']=abs(meta['wheels']['right']['center'][0]-meta['wheels']['left']['center'][0])
meta['door_refinement']='Uniformly scaled accepted g1.2: 0.3888889 mm edge bevels; no geometry redesign'
meta['tail_door_relief']['maximum_vertex_displacement_m']*=K
meta['detail_notes']=[s.replace('0.5 mm','0.555556 mm').replace('0.6 mm','0.666667 mm').replace('2 mm','2.222222 mm').replace('1.1 mm','1.222222 mm') for s in meta['detail_notes']]
meta['revision_scope']='Request Revision 3: scale accepted g1.2 by 10/9; export frame 100. Materials, textures, UVs, topology, names, hierarchy and action rotations preserved. Separate from earlier paint-only g1.3.'
for n,spec in meta['nodes'].items():spec['rest_matrix_blender']=matrix(spec['rest_matrix_blender'])
(P/'metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8')
refpath=P/'source/scripts/gear-reference.json';ref=json.loads(refpath.read_text())
for frames in ref.values():
 for m in frames:matrix(m)
refpath.write_text(json.dumps(ref),encoding='utf8')
refpath=P/'source/scripts/reference-samples.json';ref=json.loads(refpath.read_text())
for name,(samples,count) in ref.items():ref[name]=[[vec(v) for v in samples],count]
refpath.write_text(json.dumps(ref),encoding='utf8')
report={'passed':True,'base':'g1.2','factor':K,'scale_factor':1/4.5,'sampled_frames':101,'node_count':len(objects),'mesh_count':len(meshes),'scaled_location_key_values':location_keys,'maximum_world_position_error_m':position_error,'maximum_rotation_matrix_component_error':rotation_error,'maximum_mesh_vertex_scale_error_m':vertex_error,'topology_uv_and_material_assignments_unchanged':True,'hierarchy_and_tags_unchanged':True,'all_node_scales_unit':True,'mesh_topology_uv_material_fingerprints':signatures}
(P/'previews/scale-verification.json').write_text(json.dumps(report,indent=2),encoding='utf8')
text=next(iter(bpy.data.texts),None) or bpy.data.texts.new('READ_ME_g1')
text.clear();text.write('F4U CORSAIR g1.3 / request Revision 3 / 1:4.5\nDerived by uniform 10/9 scaling of accepted g1.2.\nBlender +X right, +Y nose, +Z up. Root identity at D0.\nRe-export: blender -b source/aircraft_game.blend --disable-autoexec --python source/scripts/export.py\nExport sets GearRetract frame 100 (stowed). Source opens frame 0 for editing.\nControl pivots local +X: aileron_left/right_hinge, flap_left/right_1/2/3_hinge, elevator_hinge, rudder_hinge, propeller_spin.\nGear helpers gear_compression/spin/wheel_left/right/tail; gear_steer_tail local +Y.\nR59 is not required to re-export. See README and metadata.\n')
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_distance*=K
   area.spaces.active.region_3d.view_location*=K
bpy.ops.object.select_all(action='DESELECT');root=bpy.data.objects['F4UCorsair'];root.select_set(True);bpy.context.view_layer.objects.active=root
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'))
print('SCALE_REVISION3',json.dumps({k:v for k,v in report.items() if k!='mesh_topology_uv_material_fingerprints'}),flush=True)
