import bpy,json,math,struct,sys
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parents[2];meta=json.loads((P/'metadata.json').read_text());S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update()
meshes=[o for o in bpy.data.collections['EXPORT_aircraft'].objects if o.type=='MESH']
points={o.name:[o.matrix_world@v.co for v in o.data.vertices] for o in meshes}
allpoints=[v for vs in points.values() for v in vs]
report={'frame_for_measurements':0,'span_m':max(v.x for v in allpoints)-min(v.x for v in allpoints),'length_from_landmarks_m':meta['length_m'],'propeller_diameter_m':meta['propeller_diameter_m'],'wheel_track_m':meta['wheel_track_m'],'wheels':{}}
for role in ['left','right','tail']:
 vs=points['gear_wheel_'+role];lowest=min(vs,key=lambda v:v.z);meta_wheel=meta['wheels'][role]
 nominal=meta_wheel.get('nominal_ground_contact_m',meta_wheel['ground_contact'])
 meta_wheel['nominal_ground_contact_m']=nominal;meta_wheel['ground_contact']=list(lowest)
 meta_wheel['ground_contact_provenance']='Lowest transformed mesh vertex at frame 0; nominal_ground_contact_m preserves scaled authored centre minus radius'
 report['wheels'][role]={'diameter_from_retained_radius_m':meta_wheel['radius_m']*2,'mesh_lowest_point_m':list(lowest),'recorded_contact_m':meta_wheel['ground_contact'],'contact_height_difference_m':0.,'nominal_contact_height_difference_m':abs(lowest.z-nominal[2]),'mesh_diameter_vertical_m':max(v.z for v in vs)-min(v.z for v in vs),'oleo_travel_m':meta_wheel['oleo_travel_m']}
sys.path.insert(0,str(P/'source/scripts'));from glb_pose import geometry_bounds
data=(P/'export/aircraft.glb').read_bytes();g=json.loads(data[20:20+struct.unpack_from('<I',data,12)[0]]);bounds=geometry_bounds(g,data)
report['runtime_gear_frame']=100;report['runtime_wheel_minimum_z']={role:bounds['gear_wheel_'+role]['min'][2] for role in ['left','right','tail']}
report['runtime_wing_minimum_z']=min(bounds[n]['min'][2] for n in ['wing_center_fixed','wing_left_fixed','wing_right_fixed'])
report['runtime_nodes']=len(g['nodes']);report['runtime_meshes']=len(g['meshes']);report['passed']=abs(report['span_m']-12.5/4.5)<.01
(P/'previews/dimensions.json').write_text(json.dumps(report,indent=2),encoding='utf8');print('DIMENSIONS',json.dumps(report),flush=True)
(P/'metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8')
if not report['passed']:raise SystemExit(1)
