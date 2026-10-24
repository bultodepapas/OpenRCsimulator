import bpy,json,math,struct,hashlib
from pathlib import Path
P=Path(__file__).resolve().parents[2];meta=json.loads((P/'metadata.json').read_text());S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update()
for role in ['left','right','tail']:
 o=bpy.data.objects['gear_wheel_'+role];vs=[o.matrix_world@v.co for v in o.data.vertices];radius=max(math.hypot(v.co.y,v.co.z)for v in o.data.vertices);contact=min(vs,key=lambda v:v.z);centre=o.matrix_world.translation
 meta['wheels'][role]['radius_m']=radius;meta['wheels'][role]['ground_contact']=list(contact);meta['wheels'][role]['nominal_ground_contact_m']=[centre.x,centre.y,centre.z-radius];meta['wheels'][role]['ground_contact_provenance']='g1.9: lowest transformed current wheel vertex at frame 0; nominal point is axle centre minus current tyre radius.'
 meta['gear_detail_g1_8']['wheels'][o.name]['half_width_m']=max(abs(v.co.x)for v in o.data.vertices)
def stats(file):
 raw=(P/'export'/file).read_bytes();g=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
 return{'triangles':sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes']for p in m['primitives']),'surfaces':sum(len(m['primitives'])for m in g['meshes']),'materials':len(g['materials']),'images':len(g['images']),'sha256':hashlib.sha256(raw).hexdigest()}
navy=stats('aircraft.glb');race=stats('aircraft_super57.glb');meta['runtime_counts_g1_9']={'default':navy,'super57':race}
meta['additional_racing_delivery'].update({'material_count':race['materials'],'surface_count':race['surfaces'],'triangle_count':race['triangles'],'runtime_images':race['images'],'glb_sha256':race['sha256'],'blend_sha256':hashlib.sha256((P/'source/aircraft_super57.blend').read_bytes()).hexdigest()})
meta['paint_finish']['shared_uv_preserved']='Original airframe and exterior-door UVs preserved. Rebuilt wheels use a dedicated shared gear atlas.'
meta['paint_finish']['g1_9_details']='Eight shallow inner-door support plates, dedicated UV1 interior coating atlas, fasteners, perimeter finish and restrained wear. Existing exterior paint and 101-frame rig retained.'
(P/'metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8');print('GEAR_METADATA_UPDATED',navy,race)
