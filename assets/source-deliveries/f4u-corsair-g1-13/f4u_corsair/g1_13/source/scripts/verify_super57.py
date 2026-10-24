"""Check the racing source and the two runtime variants without changing the asset."""
import bpy,struct,json,hashlib,sys,ast
from pathlib import Path
P=Path(__file__).resolve().parents[2];checks={}
def check(name,ok,detail=None):checks[name]={'passed':bool(ok),'detail':detail}
check('source_frame_zero',bpy.context.scene.frame_current==0)
# Reuse the exact geometry/UV and 101-pose hashing functions from the main check.
tree=ast.parse((P/'source/scripts/verify_paints.py').read_text())
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in {'geometry_hash','rig_hash'}],type_ignores=[]),'hash_helpers','exec'))
mesh_hash=geometry_hash();pose_hash=rig_hash()
for label,cs in [('basecolor','sRGB'),('orm','Non-Color')]:
 im=bpy.data.images['super57_'+label]
 check(label+'_packed',im.packed_file is not None and list(im.size)==[2048,2048] and im.colorspace_settings.name==cs)
 check(label+'_bound',all(m.node_tree.nodes['paint_'+label].image==im for m in bpy.data.materials if m.name.startswith('paint_')))
rotor=bpy.data.objects['propeller_rotor'];check('blade_image_packed',bpy.data.images.get('super57_propeller_basecolor') is not None and bpy.data.images['super57_propeller_basecolor'].packed_file is not None)
check('blade_image_resolution',list(bpy.data.images['super57_propeller_basecolor'].size)==[1024,256])
check('blade_uv_present',rotor.data.uv_layers.get('Super57BladeUV') is not None)
check('blade_material_isolated',sum(o.type=='MESH' and any(m and m.name=='super57_blade_paint' for m in o.data.materials)for o in bpy.data.objects)==1)
bpy.ops.wm.open_mainfile(filepath=str(P/'source/aircraft_game.blend'))
check('geometry_and_uv_match_default',geometry_hash()==mesh_hash,mesh_hash)
check('hierarchy_and_101_poses_match_default',rig_hash()==pose_hash,pose_hash)
def glb(path):
 raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+size]);return g,raw[28+size:]
A,Ab=glb(P/'export/aircraft.glb');B,Bb=glb(P/'export/aircraft_super57.glb')
check('runtime_nodes_identical',A['nodes']==B['nodes'])
check('runtime_images',len(B.get('images',[]))==8,len(B.get('images',[])))
check('runtime_material_budget',len(B['materials'])<=24,len(B['materials']))
check('runtime_surface_budget',sum(len(m['primitives'])for m in B['meshes'])<=60,sum(len(m['primitives'])for m in B['meshes']))
def accessor(g,buffer,index):
 a=g['accessors'][index];v=g['bufferViews'][a['bufferView']]
 components={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
 size=components*{5121:1,5123:2,5125:4,5126:4}[a['componentType']]
 start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
 return (a['count'],a['type'],a['componentType'],b''.join(buffer[start+i*stride:start+i*stride+size]for i in range(a['count'])))
same=True;blade_texture=False
for am,bm in zip(A['meshes'],B['meshes']):
 same &= am['name']==bm['name'] and len(am['primitives'])==len(bm['primitives'])
 for ap,bp in zip(am['primitives'],bm['primitives']):
  same &= accessor(A,Ab,ap['indices'])==accessor(B,Bb,bp['indices'])
  for key in ('POSITION','NORMAL','TEXCOORD_0'):
   same &= accessor(A,Ab,ap['attributes'][key])==accessor(B,Bb,bp['attributes'][key])
  if 'propeller' in am['name'] and B['materials'][bp['material']]['name']=='super57_blade_paint':
   blade_texture='baseColorTexture' in B['materials'][bp['material']]['pbrMetallicRoughness']
check('runtime_geometry_normals_uv_indices_identical',same)
check('runtime_baked_blade_texture',blade_texture)
report={'passed':all(c['passed']for c in checks.values()),'checks':checks}
(P/'previews/super57-verification.json').write_text(json.dumps(report,indent=2))
print('SUPER57_VERIFICATION',json.dumps(report),flush=True)
if not report['passed']:raise SystemExit(1)
