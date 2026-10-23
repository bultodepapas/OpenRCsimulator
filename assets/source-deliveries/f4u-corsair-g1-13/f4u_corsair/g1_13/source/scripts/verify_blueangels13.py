"""Audit the fifth paint and compare all meshes, UV sets and 101 rig poses to g1.11."""
import bpy,json,sys,struct,hashlib,ast
from pathlib import Path
P=Path(__file__).resolve().parents[2];checks={};errors=[]
def check(k,ok,detail=None):
 checks[k]={'passed':bool(ok),'detail':detail}
 if not ok:errors.append(k)
tree=ast.parse((P/'source/scripts/verify_paints.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in {'geometry_hash','rig_hash'}:exec(compile(ast.Module(body=[node],type_ignores=[]),'paint_hashes','exec'))
def all_uv_hash():
 h=hashlib.sha256()
 for o in sorted((o for o in bpy.data.objects if o.type=='MESH'),key=lambda o:o.name):
  h.update(o.name.encode())
  for layer in o.data.uv_layers:
   h.update(layer.name.encode())
   for uv in layer.data:h.update(struct.pack('<2f',*uv.uv))
 return h.hexdigest()
geometry=geometry_hash();rig=rig_hash();uvs=all_uv_hash()
for name in ['paint_body','paint_wing','paint_wing_tip','paint_tail']:
 m=bpy.data.materials[name]
 for key,cs in [('basecolor','sRGB'),('orm','Non-Color')]:
  im=m.node_tree.nodes['paint_'+key].image
  check(name+'_'+key,im.name=='blueangels_'+key and im.colorspace_settings.name==cs and im.packed_file is not None and tuple(im.size)==(2048,2048))
bs=next(n for n in bpy.data.materials['gear_inner_coat'].node_tree.nodes if n.type=='BSDF_PRINCIPLED');im=bs.inputs['Base Color'].links[0].from_node.image
check('blueangels_interior_identity',im.name=='blueangels_interior_basecolor'and im.packed_file is not None)
im=bpy.data.images.get('naval_propeller_basecolor');check('propeller_texture_packed',im is not None and im.packed_file is not None and tuple(im.size)==(1024,256))
check('existing_blade_UV_used',any(n.type=='UVMAP'and n.uv_map=='NavalBladeUV'for n in bpy.data.materials['naval_blade_paint'].node_tree.nodes))
mesh=bpy.data.objects['propeller_rotor'].data;slot=[i for i,m in enumerate(mesh.materials)if m and m.name=='blueangels_spinner_paint']
vertices={i for p in mesh.polygons if p.material_index in slot for i in p.vertices}
check('spinner_component_only',len(vertices)==561,len(vertices))
check('spinner_material_only_on_propeller',all(o.name=='propeller_rotor'for o in bpy.data.objects if o.type=='MESH'and any(m and m.name=='blueangels_spinner_paint'for m in o.data.materials)))
def glb(path):
 raw=path.read_bytes();return json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
g=glb(P/'export/aircraft_blueangels.glb');old=glb(P/'export/aircraft.glb')
check('runtime_node_hierarchy_and_transforms_unchanged',g['nodes']==old['nodes'])
counts={'triangles':sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes']for p in m['primitives']),'surfaces':sum(len(m['primitives'])for m in g['meshes']),'materials':len(g['materials']),'images':len(g['images'])}
check('runtime_counts',counts=={'triangles':99729,'surfaces':58,'materials':14,'images':8},counts)
baseline=P.parent/'g1_12/source/aircraft_game.blend'
if '--baseline'in sys.argv:baseline=Path(sys.argv[sys.argv.index('--baseline')+1])
bpy.ops.wm.open_mainfile(filepath=str(baseline))
check('geometry_and_UV0_identical',geometry_hash()==geometry,geometry)
check('all_UV_layers_identical',all_uv_hash()==uvs,uvs)
check('all_101_poses_and_hierarchy_identical',rig_hash()==rig,rig)
report={'passed':not errors,'checks':checks,'errors':errors};(P/'previews/blueangels-paint-verification.json').write_text(json.dumps(report,indent=2));print('SPECTRUM_PAINT_VERIFY',report['passed'],errors,flush=True)
if errors:raise SystemExit(1)
