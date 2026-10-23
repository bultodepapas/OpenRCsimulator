import bpy,json
from pathlib import Path
P=Path(__file__).resolve().parents[2];m=bpy.data.materials['gear_inner_coat'];nt=m.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
for n in list(nt.nodes):
 if n.type not in {'BSDF_PRINCIPLED','OUTPUT_MATERIAL'}:nt.nodes.remove(n)
uv=nt.nodes.new('ShaderNodeUVMap');uv.uv_map='DoorInteriorUV'
for label,cs in [('basecolor','sRGB'),('orm','Non-Color'),('normal','Non-Color')]:
 if bpy.data.images.get('interior19_'+label):bpy.data.images.remove(bpy.data.images['interior19_'+label])
 im=bpy.data.images.load(str(P/'textures/interiors'/f'{label}.png'),check_existing=False);im.name='interior19_'+label;im.colorspace_settings.name=cs;im.pack();t=nt.nodes.new('ShaderNodeTexImage');t.image=im;nt.links.new(uv.outputs['UV'],t.inputs['Vector'])
 if label=='basecolor':nt.links.new(t.outputs['Color'],bs.inputs['Base Color'])
 elif label=='orm':
  sep=nt.nodes.new('ShaderNodeSeparateColor');sep.mode='RGB';nt.links.new(t.outputs['Color'],sep.inputs['Color']);nt.links.new(sep.outputs['Green'],bs.inputs['Roughness']);nt.links.new(sep.outputs['Blue'],bs.inputs['Metallic'])
 else:
  normal=nt.nodes.new('ShaderNodeNormalMap');normal.uv_map='DoorInteriorUV';normal.inputs['Strength'].default_value=.65;nt.links.new(t.outputs['Color'],normal.inputs['Color']);nt.links.new(normal.outputs['Normal'],bs.inputs['Normal'])
meta=json.loads((P/'metadata.json').read_text());meta['revision']='g1.9';meta['base_revision']='g1.8';meta['revision_scope']='Main door interiors: shallow support plates, UV-aligned flange paint, fasteners, subtle local wear and PBR normal detail; exterior identity and mechanical motion retained.';meta['door_detail_g1_9']=json.loads((P/'previews/doors-build.json').read_text());meta['interior_atlas_g1_9']={'path':'textures/interiors','size':[2048,2048],'layers':4,'uv_set':'DoorInteriorUV','basecolor':'sRGB','orm':'Non-Color','normal':'Non-Color OpenGL tangent; strength 0.65','authenticity':'Interpretive game-model details based on supplied photographs.'};(P/'metadata.json').write_text(json.dumps(meta,indent=2))
bpy.context.scene.frame_set(0);bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('INTERIOR19_BOUND')
