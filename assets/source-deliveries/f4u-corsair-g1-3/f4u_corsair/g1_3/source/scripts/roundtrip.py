import bpy,json,math
from pathlib import Path
from mathutils import Matrix
P=Path(__file__).resolve().parents[2];meta=json.loads((P/'metadata.json').read_text());bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(P/'export/aircraft.glb'));bpy.context.view_layer.update();errors=[];maxpos=0.;maxangle=0.
for name,spec in meta['nodes'].items():
 o=bpy.data.objects.get(name)
 if o is None:errors.append({'missing':name});continue
 M=Matrix(spec['rest_matrix_blender']);d=(M.translation-o.matrix_world.translation).length;angle=M.to_quaternion().rotation_difference(o.matrix_world.to_quaternion()).angle;angle=abs((angle+math.pi)%(2*math.pi)-math.pi);maxpos=max(maxpos,d);maxangle=max(maxangle,angle)
 if d>.0001 or angle>math.radians(.01):errors.append({'name':name,'distance_m':d,'angle_deg':math.degrees(angle)})
 if spec['section']and o.get('openrc_section')!=spec['section']:errors.append({'tag':name})
vs=[o.matrix_world@v.co for o in bpy.data.objects if o.type=='MESH'for v in o.data.vertices];span=max(v.x for v in vs)-min(v.x for v in vs)
if abs(span-12.5/4.5)>.01:errors.append({'span':span})
report={'passed':not errors,'span_m':span,'maximum_node_position_error_m':maxpos,'maximum_node_angle_error_deg':math.degrees(maxangle),'errors':errors};(P/'previews/roundtrip.json').write_text(json.dumps(report,indent=2));print('G1_ROUNDTRIP',json.dumps(report),flush=True)
if errors:raise SystemExit(1)
