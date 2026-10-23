"""Validate the Splash material assignment and preservation of the existing airframe."""
import bpy,json,sys,struct,hashlib,ast
from pathlib import Path
P=Path(__file__).resolve().parents[2];checks={};errors=[]
def check(k,ok,detail=None):
 checks[k]={'passed':bool(ok),'detail':detail}
 if not ok:errors.append(k)
tree=ast.parse((P/'source/scripts/verify_paints.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in {'geometry_hash','rig_hash'}:exec(compile(ast.Module(body=[node],type_ignores=[]),'paint_hashes','exec'))
geometry=geometry_hash();rig=rig_hash()
for name in ['paint_body','paint_wing','paint_wing_tip','paint_tail']:
 m=bpy.data.materials[name]
 for key,cs in [('basecolor','sRGB'),('orm','Non-Color')]:
  im=m.node_tree.nodes['paint_'+key].image
  check(name+'_'+key,im.name=='splash_'+key and im.colorspace_settings.name==cs and im.packed_file is not None and tuple(im.size)==(2048,2048))
bs=next(n for n in bpy.data.materials['gear_inner_coat'].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
im=bs.inputs['Base Color'].links[0].from_node.image
check('splash_interior_identity',im.name=='splash_interior_basecolor'and im.packed_file is not None)
mesh=bpy.data.objects['propeller_rotor'].data;slot=[i for i,m in enumerate(mesh.materials)if m and m.name=='splash_spinner_paint']
vertices={i for p in mesh.polygons if p.material_index in slot for i in p.vertices}
check('spinner_component_only',len(vertices)==561,len(vertices))
check('spinner_material_only_on_propeller',all(o.name=='propeller_rotor'for o in bpy.data.objects if o.type=='MESH'and any(m and m.name=='splash_spinner_paint'for m in o.data.materials)))
def glb(path):
 raw=path.read_bytes();return json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
g=glb(P/'export/aircraft_splash.glb');old=glb(P/'export/aircraft.glb')
check('runtime_node_hierarchy_and_transforms_unchanged',g['nodes']==old['nodes'])
counts={'triangles':sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes']for p in m['primitives']),'surfaces':sum(len(m['primitives'])for m in g['meshes']),'materials':len(g['materials']),'images':len(g['images'])}
check('runtime_counts',counts=={'triangles':99729,'surfaces':58,'materials':14,'images':8},counts)
baseline=P.parent/'g1_10/source/aircraft_game.blend'
if '--baseline'in sys.argv:baseline=Path(sys.argv[sys.argv.index('--baseline')+1])
bpy.ops.wm.open_mainfile(filepath=str(baseline))
check('geometry_and_UV0_identical',geometry_hash()==geometry,geometry)
check('all_101_poses_and_hierarchy_identical',rig_hash()==rig,rig)
report={'passed':not errors,'checks':checks,'errors':errors};(P/'previews/splash-paint-verification.json').write_text(json.dumps(report,indent=2));print('SPLASH_PAINT_VERIFY',report['passed'],errors,flush=True)
if errors:raise SystemExit(1)
