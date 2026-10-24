import bpy,sys,json,math
from pathlib import Path
P=Path(__file__).resolve().parents[2]
if '--runtime'in sys.argv:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(P/'export/aircraft_spectrum.glb'))
exec(compile((P/'source/scripts/preview.py').read_text().split('for name,loc in')[0],str(P/'source/scripts/preview.py'),'exec'))
S.cycles.samples=24;S.render.resolution_x=1400;S.render.resolution_y=1000
S.view_settings.view_transform='Standard';S.view_settings.look='None';S.view_settings.exposure=-1.0
area('spectrum_belly_light',(0,1,-3),160,3)
prefix='spectrum12_runtime_'if '--runtime'in sys.argv else 'spectrum12_'
views={
 'hero':((3,4,2.25),(0,-.52,-.02),3.30,100),
 'opposite':((-3,4,2.25),(0,-.52,-.02),3.30,100),
 'top':((0,-.52,6),(0,-.52,0),3.15,100),
 'bottom':((0,-.52,-6),(0,-.52,-.03),3.15,100),
 'belly':((2.7,4,-3),(0,-.5,-.05),3.30,100),
 'right':((6,-.52,.18),(0,-.52,-.01),2.60,100),
 'left':((-6,-.52,.18),(0,-.52,-.01),2.60,100),
 'gear':((3,4,1.8),(0,-.50,-.1),3.30,0),
 'cowl':((1.8,2.2,.9),(0,.10,0),.95,100),
 'motion50':((2.7,4,-3),(0,-.5,-.1),3.30,50)}
names=['hero','top','bottom']
if '--only'in sys.argv:names=sys.argv[sys.argv.index('--only')+1].split(',')
for name in names:
 loc,t,scale,frame=views[name];S.frame_set(frame);target=Vector(t)*K;d.ortho_scale=scale*K;render(prefix+name,loc)
print('SPECTRUM12_VIEWS_DONE',flush=True)
