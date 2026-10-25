"""Author migration from accepted g2.1. Saved packed sources are the portable delivery.
Blender 5.2.2 --background --python adapt_liveries.py -- scarlet ...
Requires ../g2_1 and work/g22/source_inventory.json only when rebuilding from scratch.
"""
import bpy,json,sys,hashlib,math
from pathlib import Path
import numpy as np
P=Path(__file__).resolve().parents[2];R=P.parent;sys.path.insert(0,str(Path(__file__).parent))
from export_livery import export
inventory=json.loads((R/'work/g22/source_inventory.json').read_text())
catalog={l['id']:l for l in json.loads((P/'liveries.json').read_text())}
ids=sys.argv[sys.argv.index('--')+1:]if '--'in sys.argv else list(catalog)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def digest_scene():
 col=bpy.data.collections['EXPORT_aircraft'];result={}
 for o in col.objects:
  r={'parent':o.parent.name if o.parent else None,'section':o.get('openrc_section')}
  if o.type=='MESH':
   me=o.data;h=hashlib.sha256()
   for elems,attr,width,dtype in [(me.vertices,'co',3,np.float32),(me.loops,'vertex_index',1,np.int32),(me.polygons,'loop_start',1,np.int32),(me.polygons,'loop_total',1,np.int32),(me.polygons,'use_smooth',1,np.int32),(me.corner_normals,'vector',3,np.float32)]:
    a=np.empty(len(elems)*width,dtype=dtype);elems.foreach_get(attr,a);h.update(a.tobytes())
   r['geometry_normals']=h.hexdigest();r['uv']={}
   for uv in me.uv_layers:
    a=np.empty(len(uv.data)*2,np.float32);uv.data.foreach_get('uv',a);r['uv'][uv.name]=hashlib.sha256(a.tobytes()).hexdigest()
  result[o.name]=r
 h=hashlib.sha256()
 for f in range(101):
  bpy.context.scene.frame_set(f);bpy.context.view_layer.update()
  for o in sorted(col.objects,key=lambda o:o.name):h.update(np.asarray(o.matrix_world,dtype=np.float32).tobytes())
 bpy.context.scene.frame_set(0)
 return {'nodes':result,'poses_101':h.hexdigest()}
def bs(mat):return next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
def linear(c):
 c=c/255;return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4
def load(path,label,space='Non-Color'):
 im=bpy.data.images.load(str(path),check_existing=False);im.name=label;im.colorspace_settings.name=space;im.pack();im.filepath=bpy.path.relpath(str(path),start=str(P/'source'));return im
def replace_image(old,new):
 for mat in bpy.data.materials:
  if not mat.use_nodes:continue
  for n in mat.node_tree.nodes:
   if n.type=='TEX_IMAGE'and n.image==old:n.image=new
def spinner_component(o):
 adj=[[]for _ in o.data.vertices]
 for e in o.data.edges:a,b=e.vertices;adj[a].append(b);adj[b].append(a)
 seed=max(o.data.vertices,key=lambda v:(o.matrix_world@v.co).y).index;todo=[seed];found={seed}
 while todo:
  for b in adj[todo.pop()]:
   if b not in found:found.add(b);todo.append(b)
 assert min((o.matrix_world@o.data.vertices[i].co).y for i in found)>.469
 return found
bpy.ops.wm.open_mainfile(filepath=str(R/'g2_1/source/aircraft_game.blend'));baseline=digest_scene()
(P/'checks/accepted_geometry_signature.json').write_text(json.dumps(baseline,indent=2))
for lid in ids:
 bpy.ops.wm.open_mainfile(filepath=str(R/'g2_1/source/aircraft_game.blend'));S=bpy.context.scene;S.frame_set(0);D=P/'textures/liveries'/lid;T=D/'runtime'
 info=json.loads((D/'adaptation.json').read_text())if (D/'adaptation.json').exists()else {'normal_strength':.65}
 source_name={'midnight':'aircraft_game.blend','scarlet':'aircraft_super57.blend','three_tone':'aircraft_game.blend'}.get(lid,'aircraft_'+lid+'.blend')
 legacy=inventory['g1_24/'+source_name]['materials'];rotor=bpy.data.objects['propeller_rotor']
 oldbase=bpy.data.images['g2_Naval308_basecolor'];oldorm=bpy.data.images['g2_Naval308_orm']
 base=load(T/'basecolor.png',lid+'_basecolor','sRGB');orm=load(T/'orm.png',lid+'_orm')
 replace_image(oldbase,base);replace_image(oldorm,orm)
 if lid!='midnight':
  normal=load(T/'normal.png',lid+'_surface_normal')
  for mat in bpy.data.materials:
   if not mat.name.startswith('paint_'):continue
   for n in mat.node_tree.nodes:
    if n.type=='TEX_IMAGE'and n.image and n.image.name=='g2_R59_normal':n.image=normal
    if n.type=='NORMAL_MAP':n.inputs['Strength'].default_value=info['normal_strength']
   shader=bs(mat);shader.inputs['Coat Weight'].default_value=0 if lid in ['chrome','p40','japan','luftwaffe','italy','three_tone']else .28
  # Colors are established finish palettes; baked mechanical normals/AO stay g2.1.
  coat=bs(bpy.data.materials['gear_inner_coat']);coat.inputs['Base Color'].default_value=tuple(linear(c)for c in info['interior_srgb'])+(1,)
  coat.inputs['Metallic'].default_value=.4 if lid=='chrome'else .07;coat.inputs['Roughness'].default_value=.48
  blade=bpy.data.materials['naval_blade_paint'];shader=bs(blade)
  prop=load(D/'propeller_basecolor.png',lid+'_propeller_basecolor','sRGB');replace_image(bpy.data.images['naval_propeller_basecolor'],prop)
  old_blade=next((v for k,v in legacy.items()if 'blade_paint'in k),None)
  if old_blade:
   for attr in ['Metallic','Roughness']:
    if attr in old_blade['inputs']:shader.inputs[attr].default_value=old_blade['inputs'][attr]
  if lid=='chrome':
   for link in list(shader.inputs['Base Color'].links):blade.node_tree.links.remove(link)
   shader.inputs['Base Color'].default_value=(.73,.76,.78,1)
  if (D/'gear/basecolor.png').exists():
   replace_image(bpy.data.images['gear18_basecolor'],load(D/'gear/basecolor.png',lid+'_gear_basecolor','sRGB'))
  sp=next((v for k,v in legacy.items()if 'spinner_paint'in k),None)
  if sp:
   sm=bpy.data.materials['alloy'].copy();sm.name='livery_spinner_paint';ss=bs(sm)
   for attr in ['Base Color','Metallic','Roughness','Coat Weight','Coat Roughness']:
    if attr in sp['inputs']:ss.inputs[attr].default_value=sp['inputs'][attr]
   component=spinner_component(rotor);rotor.data.materials.append(sm);index=len(rotor.data.materials)-1
   for p in rotor.data.polygons:
    if all(v in component for v in p.vertices):p.material_index=index
  if lid=='chrome':
   # Existing geometry at the exhaust remains dark under the mirror finish.
   es=bs(bpy.data.materials['engine_dark']);es.inputs['Base Color'].default_value=(.035,.027,.021,1);es.inputs['Roughness'].default_value=.61
  if lid=='carbon':
   ims={key:load(T/(key+'.png'),'carbon_'+key,'sRGB'if key=='emission'else 'Non-Color')for key in ['emission','anisotropy_strength','anisotropy_rotation']}
   for mat in bpy.data.materials:
    if not mat.name.startswith('paint_'):continue
    shader=bs(mat);ns=mat.node_tree.nodes;lk=mat.node_tree.links;shader.inputs['Coat Weight'].default_value=1;shader.inputs['Coat Roughness'].default_value=.18;shader.inputs['Emission Strength'].default_value=.08
    for key,socket in [('emission','Emission Color'),('anisotropy_strength','Anisotropic'),('anisotropy_rotation','Anisotropic Rotation')]:
     tx=ns.new('ShaderNodeTexImage');tx.image=ims[key];lk.new(tx.outputs['Color'],shader.inputs[socket])
 # Rebind every remaining shared dependency inside this delivery, then remove unused images.
 for im in bpy.data.images:
  if im.name=='g2_R59_normal':im.filepath='//../textures/shared/normal.png'
  if im.name=='naval_propeller_basecolor':im.filepath='//../textures/shared/propeller_basecolor.png'
  if im.name=='gear18_basecolor':im.filepath='//../textures/gear/basecolor.png'
  if im.name=='gear18_orm':im.filepath='//../textures/gear/orm.png'
 used={n.image for mat in bpy.data.materials if mat.use_nodes for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'and n.image and any(s.is_linked for s in n.outputs)}
 for mat in bpy.data.materials:
  if mat.use_nodes:
   for n in list(mat.node_tree.nodes):
    if n.type=='TEX_IMAGE'and n.image and n.image not in used:mat.node_tree.nodes.remove(n)
 for im in list(bpy.data.images):
  if im not in used:bpy.data.images.remove(im)
  elif not im.packed_file:im.pack()
 S['revision']='g2.2';S['g2_revision']='g2.2';S['livery_id']=lid;S['livery_name']=catalog[lid]['name']
 for t in list(bpy.data.texts):bpy.data.texts.remove(t)
 t=bpy.data.texts.new('READ_ME_g2_2');t.write('F4U Corsair g2.2 / '+catalog[lid]['name']+'\nAccepted g2.1 geometry and motion preserved. Frame 0 down; export 100 stowed.\nAll runtime images packed. Re-export with source/scripts/export_livery.py.\n')
 assert digest_scene()==baseline,'Geometry, UV, normals, hierarchy or motion changed'
 filename='aircraft_game'if lid=='midnight'else 'aircraft_'+lid
 native=P/'source'/(filename+'.blend');glb=P/'export'/('aircraft.glb'if lid=='midnight'else filename+'.glb')
 bpy.context.preferences.filepaths.save_version=0;S.frame_set(0);bpy.ops.wm.save_as_mainfile(filepath=str(native),compress=True)
 bpy.ops.wm.open_mainfile(filepath=str(native));assert digest_scene()==baseline
 g=export(glb);tris=sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes']for p in m['primitives']);surfs=sum(len(m['primitives'])for m in g['meshes'])
 assert tris==337664 and len(g['nodes'])==82 and surfs<=70 and len(g['materials'])<=16 and glb.stat().st_size<=30000000
 row={'id':lid,'name':catalog[lid]['name'],'blend':str(native.relative_to(P)).replace('\\','/'),'glb':str(glb.relative_to(P)).replace('\\','/'),'blend_sha256':sha(native),'glb_sha256':sha(glb),'glb_bytes':glb.stat().st_size,'triangles':tris,'nodes':len(g['nodes']),'surfaces':surfs,'materials':len(g['materials']),'images':len(g['images']),'geometry_normals_UVs_identical_to_g21':True,'all_82_nodes_101_poses_identical':True,'all_images_packed':all(i.packed_file for i in bpy.data.images),'normal_strength':info['normal_strength']}
 (P/'checks'/('adaptation_'+lid+'.json')).write_text(json.dumps(row,indent=2));print('LIVERY_COMPLETE',json.dumps(row),flush=True)
