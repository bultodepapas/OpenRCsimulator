"""Blender paint binding checks; optional --baseline path verifies unchanged geometry and UVs."""
import bpy,json,sys,struct,hashlib
from pathlib import Path
P=Path(__file__).resolve().parents[2];checks={};errors=[]
def check(name,ok,detail=None):
 checks[name]={'passed':bool(ok),'detail':detail}
 if not ok:errors.append(name)
def geometry_hash():
 h=hashlib.sha256()
 for o in sorted((o for o in bpy.data.objects if o.type=='MESH'),key=lambda o:o.name):
  h.update(o.name.encode())
  for v in o.data.vertices:h.update(struct.pack('<3f',*v.co))
  for p in o.data.polygons:h.update(struct.pack('<I',len(p.vertices)));h.update(struct.pack('<'+'I'*len(p.vertices),*p.vertices))
  for uv in o.data.uv_layers['UVMap'].data:h.update(struct.pack('<2f',*uv.uv))
 return h.hexdigest()
current_hash=geometry_hash()
def rig_hash():
 h=hashlib.sha256();col=bpy.data.collections['EXPORT_aircraft']
 objects=sorted(col.objects,key=lambda o:o.name)
 for o in objects:
  h.update(json.dumps([o.name,o.parent.name if o.parent else None,o.get('openrc_section')]).encode())
 for f in range(101):
  bpy.context.scene.frame_set(f);bpy.context.view_layer.update()
  for o in objects:
   for row in o.matrix_world:h.update(struct.pack('<4f',*row))
 return h.hexdigest()
current_rig=rig_hash()
for name in ['paint_body','paint_wing','paint_wing_tip','paint_tail']:
 m=bpy.data.materials[name];n=m.node_tree.nodes;bs=next(x for x in n if x.type=='BSDF_PRINCIPLED')
 check(name+'_color',n['paint_basecolor'].image.name=='g1_default_basecolor'and n['paint_basecolor'].image.colorspace_settings.name=='sRGB')
 check(name+'_finish',n['paint_orm'].image.name=='g1_default_orm'and n['paint_orm'].image.colorspace_settings.name=='Non-Color'and bs.inputs['Roughness'].is_linked and bs.inputs['Metallic'].is_linked)
for lid in ['midnight','three_tone','scarlet']:
 for file in ['basecolor.png','orm.png','roughness.png','markings.png','paint_design.png','service_finish.png','insignia.png','weathering.png','fasteners.png','service_stencils.png','localized_wear.png']:
  b=(P/'textures/liveries'/lid/file).read_bytes();check(lid+'/'+file,b[:8]==b'\x89PNG\r\n\x1a\n'and struct.unpack_from('>II',b,16)==(2048,2048))
b=(P/'export/aircraft.glb').read_bytes();g=json.loads(b[20:20+struct.unpack_from('<I',b,12)[0]]);paint=[m for m in g['materials']if m['name'].startswith('paint_')];check('glb_standard_roughness',all('metallicRoughnessTexture'in m['pbrMetallicRoughness']for m in paint));check('glb_eight_images',len(g['images'])==8,len(g['images']));check('shared_color_image',len({g['textures'][m['pbrMetallicRoughness']['baseColorTexture']['index']]['source']for m in paint})==1);check('shared_finish_image',len({g['textures'][m['pbrMetallicRoughness']['metallicRoughnessTexture']['index']]['source']for m in paint})==1)
if '--baseline'in sys.argv:
 baseline=sys.argv[sys.argv.index('--baseline')+1];bpy.ops.wm.open_mainfile(filepath=baseline);check('geometry_and_uv_unchanged',geometry_hash()==current_hash,{'geometry_and_uv_sha256':current_hash});check('all_101_rig_poses_and_hierarchy_unchanged',rig_hash()==current_rig,{'rig_sha256':current_rig})
report={'passed':not errors,'errors':errors,'checks':checks};(P/'previews/paint-verification.json').write_text(json.dumps(report,indent=2));print('PAINT_VERIFICATION',report['passed'],errors,flush=True)
if errors:raise SystemExit(1)
