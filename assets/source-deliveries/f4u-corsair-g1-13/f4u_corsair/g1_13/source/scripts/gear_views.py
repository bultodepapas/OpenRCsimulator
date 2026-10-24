import bpy,sys
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parents[2]
if '--runtime'in sys.argv:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(P/'export/aircraft_super57.glb'))
exec(compile((P/'source/scripts/preview.py').read_text().split('for name,loc in')[0],str(P/'source/scripts/preview.py'),'exec'))
S.cycles.samples=32;S.render.resolution_x=1300;S.render.resolution_y=1000
try:S.view_settings.look='AgX - Medium High Contrast'
except TypeError:pass
area('gear_softbox',(-1,1,-2),120,2);area('gear_rim',(2,-2,-1),90,2)
prefix='before18_'if '--before'in sys.argv else'gear18_'
if '--runtime'in sys.argv:
 target=Vector((0,-.52,-.02))*K;d.ortho_scale=3.3*K;render('gear18_runtime',(-3,2,-3))
else:
 S.frame_set(0)
 views=[('wheel_left',(-.431,-.061,-.437),.29,(-2,-.03,-.40)),('wheel_right',(.431,-.061,-.437),.29,(2,-.03,-.40)),('wheel_inside',(-.431,-.061,-.437),.30,(-.1,-.45,-.4)),('tail',(0,-1.412,-.144),.15,(-1,-1.35,-.11)),('doors',(.46,-.29,-.27),.62,(1,-.8,-.68))]
 for name,t,scale,loc in views:
  if '--compare'in sys.argv and name not in {'wheel_inside','doors'}:continue
  if '--only'in sys.argv and name!=sys.argv[sys.argv.index('--only')+1]:continue
  target=Vector(t);d.ortho_scale=scale;render(prefix+name,loc)
 if '--before'not in sys.argv and '--only'not in sys.argv:
  target=Vector((0,-.52,-.02))*K;d.ortho_scale=3.3*K;render('gear18_hero',(3,4,1.5))
  target=Vector((.4,-.25,-.20))*K;d.ortho_scale=.95*K
  for frame in (0,50,100):S.frame_set(frame);render('gear18_motion_'+str(frame),(1.3,.8,-1.1))
print('GEAR18_VIEWS_DONE',prefix,flush=True)
