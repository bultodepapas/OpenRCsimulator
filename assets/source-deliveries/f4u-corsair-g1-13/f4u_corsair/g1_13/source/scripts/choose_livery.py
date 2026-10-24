"""Run in Blender Text Editor. Choose an id below; changes stay in memory until saved.
The runtime package export remains the naval default. This script changes preview/editing materials.
"""
import bpy
from pathlib import Path
LIVERY='scarlet' # midnight / three_tone / scarlet
assert LIVERY in {'midnight','three_tone','scarlet'}
P=Path(bpy.data.filepath).resolve().parent.parent
for m in bpy.data.materials:
 if not m.name.startswith('paint_'):continue
 for n in m.node_tree.nodes:
  if n.name not in {'paint_basecolor','paint_orm'}:continue
  file='basecolor.png' if n.name=='paint_basecolor' else 'orm.png'
  im=bpy.data.images.load(str(P/'textures/liveries'/LIVERY/file),check_existing=True)
  im.colorspace_settings.name='sRGB' if file=='basecolor.png' else 'Non-Color';im.pack();n.image=im
print('Livery selected:',LIVERY)
