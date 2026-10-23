"""Repeatable paint inspection under identical light; no studio content saved into asset."""
import bpy,sys
from pathlib import Path
P=Path(__file__).resolve().parents[2]
setup=(P/'source/scripts/preview.py').read_text().split('for name,loc in')[0]
exec(compile(setup,str(P/'source/scripts/preview.py'),'exec'))
S.cycles.samples=24
S.render.resolution_x=1200;S.render.resolution_y=900
area('paint_belly_fill',(0,1,-3),160,3)
liveries=['midnight','three_tone','scarlet']
if '--livery' in sys.argv:liveries=[sys.argv[sys.argv.index('--livery')+1]]
for lid in liveries:
 for m in bpy.data.materials:
  if not m.name.startswith('paint_'):continue
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE':
    file='orm.png' if n.name=='paint_orm' else 'basecolor.png'
    n.image=bpy.data.images.load(str(P/'textures/liveries'/lid/file),check_existing=True)
    n.image.colorspace_settings.name='Non-Color' if file=='orm.png' else 'sRGB'
 S.frame_set(100);target=Vector((0,-.52,-.02))*K;d.ortho_scale=3.3*K
 for suffix,loc in [('hero',(3,4,2.5)),('left',(-6,-.52,.25)),('right',(6,-.52,.25)),('top',(0,-.52,6)),('belly',(2,4,-3))]:render('paint_'+lid+'_'+suffix,loc)
 target=Vector((.30,-.20,-.045))*K;d.ortho_scale=1.02*K
 render('paint_'+lid+'_surface',(1.4,.5,1.3))
print('PAINT_VIEWS_DONE',flush=True)
