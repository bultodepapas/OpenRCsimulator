import bpy,json
from pathlib import Path
P=Path(__file__).resolve().parents[2]
meta=json.loads((P/'metadata.json').read_text())
meta['revision']='g1.7';meta['base_revision']='g1.6 paint revision, scale 1:4.5'
meta['uniform_rescale_from_base']=1.0
meta['scale_history']['g1_6_to_g1_7']=1.0
meta['revision_scope']='Super Corsair #57/SOHIO photo-guided livery; user explicitly requested real identity. Existing F4U geometry, UVs and rig preserved.'
meta['liveries'][2]={'id':'scarlet','name':'Super Corsair 57 / SOHIO','description':'Photo-guided red/ivory fan, outlined 57, SOHIO, N5588N; adapted to existing F4U-1D-inspired geometry','default':False}
meta['paint_finish'].update({'g1_6_details':'Wider outlined fans, tapered interrupted stripe, scalloped nose apron, diamond, fin tip, light canopy frames, real identity requested by user. Clean racing finish.','paint_coordinate_space':'Original 1:5 design space sampled at world x0.9; exterior gear doors sampled at closed frame100, other surfaces at neutral frame0.','editable_layers':{'midnight':10,'three_tone':10,'scarlet':11},'g1_7_details':'Service plates, EXPERIMENTAL, fin registration, resolved thin-edge filtering and blade oval badges. Underside service cover, underwing fasteners, localized lower-engine residue, satin inner door coating and perimeter paint details.'})
meta['additional_racing_delivery']={'blend':'source/aircraft_super57.blend','glb':'export/aircraft_super57.glb','livery':'scarlet','geometry_conversion_to_F2G':False,'material_count':12,'surface_count':54,'triangle_count':90861,'runtime_images':3,'blade_paint':'Dedicated material and 1024x256 RGB blade atlas on additional Super57BladeUV; original UVMap and mesh preserved.','additional_blade_uv':True}
(P/'metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8')
for name in ['PAINT_G1_4_README','PAINT_G1_5_README','PAINT_G1_6_README']:
 if name in bpy.data.texts:bpy.data.texts.remove(bpy.data.texts[name])
for name,text in [('PAINT_CHOOSE_LIVERY.py',(P/'source/scripts/choose_livery.py').read_text()),('PAINT_G1_7_README','''Super Corsair #57 / SOHIO — g1.7
Decoración realizada según las cuatro fotos aportadas y la petición explícita de usar 57 y SOHIO.
Para abrir directamente la pintura de carreras: aircraft_super57.blend.
Exportación correspondiente: ../export/aircraft_super57.glb.
aircraft_game.blend / aircraft.glb conservan la librea naval predeterminada.
Geometría F4U existente a escala 1:4.5; no es una reconstrucción geométrica F2G.
Los mapas de carreras incluyen N5588N, el óvalo SOHIO y el 57 en una capa de marcas separada.
Once capas editables en ../textures/liveries/scarlet/source.ora.
Source frame0, GLB frame100. Los mecanismos y las UV permanecen sin cambios.
Para regenerar la entrega de carreras: source/scripts/export_super57.py.
El archivo de carreras tiene tres imágenes empacadas: color, acabado y detalles de hélice.
''')]:
 t=bpy.data.texts.get(name)or bpy.data.texts.new(name);t.clear();t.write(text)
for screen in bpy.data.screens:
 for a in screen.areas:
  if a.type=='VIEW_3D':a.spaces.active.shading.type='MATERIAL'
bpy.context.scene.frame_set(0)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'))
print('PAINT_FINALIZED')
