"""Macro views for the new paint details; no changes saved to source."""
import bpy,sys
from pathlib import Path
P=Path(__file__).resolve().parents[2]
setup=(P/'source/scripts/preview.py').read_text().split('for name,loc in')[0]
exec(compile(setup,str(P/'source/scripts/preview.py'),'exec'))
S.cycles.samples=32;S.render.resolution_x=1400;S.render.resolution_y=1000
for lid in ['midnight','three_tone','scarlet']:
 for m in bpy.data.materials:
  if not m.name.startswith('paint_'):continue
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE':
    file='orm.png'if n.name=='paint_orm'else'basecolor.png'
    n.image=bpy.data.images.load(str(P/'textures/liveries'/lid/file),check_existing=True)
    n.image.colorspace_settings.name='Non-Color'if file=='orm.png'else'sRGB'
 S.frame_set(100)
 target=Vector((.23,-.15,.02))*K;d.ortho_scale=.93*K
 render('detail_'+lid+'_root_aft',(1.1,-1.5,1.6))
 if '--rear-only' in sys.argv:continue
 render('detail_'+lid+'_root',(1.1,1.2,1.6))
 target=Vector((.73,-.18,-.10))*K;d.ortho_scale=.62*K
 render('detail_'+lid+'_wing',(.78,-.18,3))
 target=Vector((0,.10,.035))*K;d.ortho_scale=.66*K
 render('detail_'+lid+'_cowl',(1.6,1,1))
print('DETAIL_VIEWS_DONE',flush=True)
