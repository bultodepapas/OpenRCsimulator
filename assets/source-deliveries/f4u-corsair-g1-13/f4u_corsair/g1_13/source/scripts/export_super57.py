"""Export #57 racing edition. Run with aircraft_super57.blend for packed-image reexport."""
import bpy,json,hashlib,sys,math
from pathlib import Path
P=Path(__file__).resolve().parents[2]
for label,file,cs in [('basecolor','basecolor.png','sRGB'),('orm','orm.png','Non-Color')]:
 name='super57_'+label
 if '--refresh-paint' in sys.argv and name in bpy.data.images:bpy.data.images.remove(bpy.data.images[name])
 im=bpy.data.images.get(name)
 if im is None:
  im=bpy.data.images.load(str(P/'textures/liveries/scarlet'/file));im.name=name;im.colorspace_settings.name=cs;im.pack()
 for m in bpy.data.materials:
  if m.name.startswith('paint_'):
   for n in m.node_tree.nodes:
    if n.name=='paint_'+label:n.image=im
S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update()
# A separate blade material prevents the racing tips from changing tyres or hub.
# A small baked blade map gives clean tip boundaries on the existing low-poly mesh.
rotor=bpy.data.objects['propeller_rotor'];mesh=rotor.data
name='super57_propeller_basecolor'
if '--refresh-paint' in sys.argv and name in bpy.data.images:bpy.data.images.remove(bpy.data.images[name])
prop_image=bpy.data.images.get(name)
if prop_image is None:
 sys.path.insert(0,str(Path(__file__).resolve().parent))
 from prop57_strip import make_prop_texture
 path=P/'textures/liveries/scarlet/propeller_basecolor.png'
 make_prop_texture(rotor,path)
 prop_image=bpy.data.images.load(str(path));prop_image.name=name;prop_image.colorspace_settings.name='sRGB';prop_image.pack()
blade_mat=bpy.data.materials.get('super57_blade_paint')
if blade_mat is None:
 blade_mat=bpy.data.materials.new('super57_blade_paint');blade_mat.use_nodes=True
bs=next(n for n in blade_mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
bs.inputs['Metallic'].default_value=0.;bs.inputs['Roughness'].default_value=.34
for n in list(blade_mat.node_tree.nodes):
 if n.type not in {'BSDF_PRINCIPLED','OUTPUT_MATERIAL'}:blade_mat.node_tree.nodes.remove(n)
tex=blade_mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=prop_image
uvnode=blade_mat.node_tree.nodes.new('ShaderNodeUVMap');uvnode.uv_map='Super57BladeUV'
blade_mat.node_tree.links.new(uvnode.outputs['UV'],tex.inputs['Vector'])
blade_mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
for i,m in enumerate(mesh.materials):
 if m.name in {'rubber','super57_blade_paint'}:mesh.materials[i]=blade_mat
if mesh.color_attributes.get('Super57BladeColor'):mesh.color_attributes.remove(mesh.color_attributes['Super57BladeColor'])
S.frame_set(100);bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.collections['EXPORT_aircraft'].objects:o.hide_set(False);o.hide_render=False;o.select_set(True)
settings=json.loads((P/'metadata.json').read_text())['export_settings']
settings['filepath']=str(P/'export/aircraft_super57.glb')
bpy.ops.export_scene.gltf(**settings)
S.frame_set(0);bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT');bpy.data.objects['F4UCorsair'].select_set(True);bpy.context.view_layer.objects.active=bpy.data.objects['F4UCorsair']
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_super57.blend'))
print('SUPER57_EXPORTED',hashlib.sha256((P/'export/aircraft_super57.glb').read_bytes()).hexdigest(),flush=True)
