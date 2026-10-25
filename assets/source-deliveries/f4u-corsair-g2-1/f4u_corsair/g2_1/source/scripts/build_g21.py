"""Integrate scoped g2.1 F1-F4 candidates. Never edits an accepted baseline."""
import bpy,json,math,hashlib,struct,shutil
from pathlib import Path
P=Path(__file__).resolve().parents[2];R=P.parent;W=R/'work/g21'
bpy.ops.wm.open_mainfile(filepath=str(R/'g2_0/source/aircraft_game.blend'))
S=bpy.context.scene;S.frame_set(0);col=bpy.data.collections['EXPORT_aircraft']
original={o.name:(o.parent.name if o.parent else None,o.get('openrc_section'),o.matrix_basis.copy())for o in col.objects}
with bpy.data.libraries.load(str(W/'rotor_decimated.blend'),link=False)as(a,b):b.meshes=['propeller_rotor_g21']
rotor=bpy.data.objects['propeller_rotor'];rotor.data=b.meshes[0]
for i,m in enumerate(rotor.data.materials):rotor.data.materials[i]=bpy.data.materials[m.name.split('.')[0]]
mesh=rotor.data
blade=bpy.data.materials.new('naval_blade_paint');blade.use_nodes=True;blade.use_backface_culling=True
bs=next(n for n in blade.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=.37
im=bpy.data.images.load(str(P/'textures/shared/propeller_basecolor.png'));im.name='naval_propeller_basecolor';im.colorspace_settings.name='sRGB';im.pack()
tex=blade.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;tex.extension='EXTEND'
uvnode=blade.node_tree.nodes.new('ShaderNodeUVMap');uvnode.uv_map='NavalBladeUV';blade.node_tree.links.new(uvnode.outputs['UV'],tex.inputs['Vector']);blade.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
uv=mesh.uv_layers.new(name='NavalBladeUV');centers=[math.pi/2+i*math.tau/3 for i in range(3)]
for loop in mesh.loops:
 co=rotor.matrix_world@mesh.vertices[loop.vertex_index].co
 angle=math.atan2(co.z,co.x);a=min(centers,key=lambda c:abs(math.atan2(math.sin(angle-c),math.cos(angle-c))))
 # Linear axial U, unlike radial U: yellow transition is a plane square to each blade.
 span=co.x*math.cos(a)+co.z*math.sin(a);chord=-co.x*math.sin(a)+co.z*math.cos(a)
 uv.data[loop.index].uv=(span*.9/.42,.5+chord*.9/.10)
for i,m in enumerate(mesh.materials):
 if m.name in ['rubber','blade_tip']:mesh.materials[i]=blade
# Collapse duplicate blade material slots without touching geometry.
for p in mesh.polygons:
 if p.material_index==2:p.material_index=1
mesh.materials.pop(index=2);mesh.uv_layers.active_index=0
with bpy.data.libraries.load(str(R/'work/g21_wheels/wheels.blend'),link=False)as(a,b):
 b.meshes=['F2_g1_24_gear_wheel_'+side+'_mesh' for side in ['left','right','tail']]
for side,data in zip(['left','right','tail'],b.meshes):bpy.data.objects['gear_wheel_'+side].data=data
# Optional library path is supplied only after its report is accepted by the author.
choice=json.loads((W/'glass_choice.json').read_text())
with bpy.data.libraries.load(choice['library'],link=False)as(a,b):b.meshes=choice['meshes']
for name,data in zip(choice['targets'],b.meshes):
 for i,m in enumerate(data.materials):data.materials[i]=bpy.data.materials[m.name.split('.')[0]]
 bpy.data.objects[name].data=data
used={m for o in col.objects if o.type=='MESH'for m in o.data.materials if m}
for m in list(bpy.data.materials):
 if m not in used:bpy.data.materials.remove(m)
for m in used:
 if m.name.startswith('gear_finish.'):m.name='gear_finish'
orm=bpy.data.images['g2_Naval308_orm'];orm.filepath=str(P/'textures/liveries/midnight/orm.png');orm.reload();orm.pack()
# Occlusion is the shared ORM red channel, explicitly sampled using the original atlas UV.
group=next(g for g in bpy.data.node_groups if g.name.startswith('glTF Material Output'))
for m in used:
 if not m.use_nodes:continue
 ns=m.node_tree.nodes;lk=m.node_tree.links
 occs=[n for n in ns if n.type=='GROUP' and n.node_tree and n.node_tree.name.startswith('glTF Material Output')]
 if m==blade:
  gt=ns.new('ShaderNodeGroup');gt.node_tree=group;occs=[gt]
 for gt in occs:
  at=ns.new('ShaderNodeTexImage');at.image=orm;at.label='AO: ORM red only'
  uvn=ns.new('ShaderNodeUVMap');uvn.uv_map='UVMap';lk.new(uvn.outputs['UV'],at.inputs['Vector'])
  sep=ns.new('ShaderNodeSeparateColor');lk.new(at.outputs['Color'],sep.inputs['Color']);lk.new(sep.outputs['Red'],gt.inputs['Occlusion'])
 for n in list(ns):
  if n.type=='TEX_IMAGE' and n.image and n.image.name=='g2_R59_ao':ns.remove(n)
used_images={n.image for m in used for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
for im in list(bpy.data.images):
 if im not in used_images:bpy.data.images.remove(im)
for im in used_images:
 if im.name.startswith('gear18_'):
  f=P/'textures/gear'/(im.name+'.png');f.parent.mkdir(exist_ok=True);shutil.copy2(R/'work/g21_wheels/textures'/f.name,f);im.filepath=str(f)
 elif im.name=='g2_Naval308_basecolor':im.filepath=str(P/'textures/liveries/midnight/basecolor.png')
 elif im.name=='g2_R59_normal':im.filepath=str(P/'textures/shared/normal.png')
 im.filepath=bpy.path.relpath(im.filepath,start=str(P/'source'));im.pack()
# Contract conservation is checked before every save.
assert len(col.objects)==82
for o in col.objects:
 par,tag,mat=original[o.name];assert par==(o.parent.name if o.parent else None) and tag==o.get('openrc_section')
 assert max(abs(a-b)for r,s in zip(o.matrix_basis,mat)for a,b in zip(r,s))<1e-8
S['revision']='g2.1';S['g2_revision']='g2.1';S.frame_set(0)
for t in list(bpy.data.texts):bpy.data.texts.remove(t)
t=bpy.data.texts.new('READ_ME_g2_1');t.write('F4U Corsair g2.1. Naval 308.\nOpen at frame 0. Export at frame 100.\nRe-export using source/scripts/export_g2.py in Blender 5.2.2. All runtime textures packed.\nF1: UV blade paint. F2: exact g1.24 wheels. F3: protected propeller and canopy outlines. F4: ORM red supplies AO.\n')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'),compress=True)
bpy.ops.wm.open_mainfile(filepath=str(P/'source/aircraft_game.blend'))
exec(compile((P/'source/scripts/export_g2.py').read_text(),str(P/'source/scripts/export_g2.py'),'exec'),{'__file__':str(P/'source/scripts/export_g2.py'),'__name__':'__main__'})
S=bpy.context.scene;col=bpy.data.collections['EXPORT_aircraft'];meta=json.loads((R/'g2_0/metadata.json').read_text())
meta.update(revision='g2.1',base_revision='g2.0; scoped F1-F4',request_revision='g2.1',runtime_export_frame=100)
meta['meshes']=[]
for o in col.objects:
 if o.type=='MESH':
  o.data.calc_loop_triangles();meta['meshes'].append({'node':o.name,'section':o['openrc_section'],'triangles':len(o.data.loop_triangles),'surfaces':len({p.material_index for p in o.data.polygons})})
raw=(P/'export/aircraft.glb').read_bytes();g=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
meta['triangle_count']=sum(m['triangles']for m in meta['meshes']);meta['surface_count']=sum(m['surfaces']for m in meta['meshes']);meta['material_count']=len(g['materials']);meta['runtime_image_count']=len(g['images']);meta['glb_bytes']=len(raw)
meta['glb_sha256']=hashlib.sha256(raw).hexdigest();meta['source_blend_sha256']=hashlib.sha256((P/'source/aircraft_game.blend').read_bytes()).hexdigest()
meta['surface_detail']['g2_1_changes']=['F1 identical linear blade UV paint on both faces; original g1 PNG','F2 exact g1.24 wheel meshes and gear atlas','F3 local protected hub reduction and silhouette-preserving canopy reduction','F4 shared ORM red channel AO; no standalone AO runtime image']
meta['surface_detail']['geometry_method']='g2.0 retained except local outline-constrained propeller hub reduction, canopy reduction and exact g1.24 wheels'
(P/'metadata.json').write_text(json.dumps(meta,indent=2))
assert 300000<=meta['triangle_count']<=350000 and meta['surface_count']<=70 and meta['material_count']<=16 and len(raw)<30000000
assert 'blade_tip'not in [m['name']for m in g['materials']]
print('G21_BUILT',meta['triangle_count'],meta['surface_count'],meta['material_count'],meta['runtime_image_count'],len(raw),flush=True)
