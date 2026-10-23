import bpy,sys,json
from pathlib import Path
P=Path(__file__).resolve().parents[2]
base=(P/'source/scripts/preview.py').read_text().split('for name,loc in')[0]
# preview.py derives its path from __file__; restore the release path after setup.
exec(compile(base,str(P/'source/scripts/preview.py'),'exec'))
P=Path(__file__).resolve().parents[2]
S.cycles.samples=24;S.render.resolution_x=1400;S.render.resolution_y=1000
area('naval_belly',(0,1,-3),160,3)
before='--before' in sys.argv;prefix='naval10_before_' if before else ('naval10_runtime_' if '--runtime' in sys.argv else 'naval10_')
names=['hero','side'] if before else ['hero','side','top','belly','wing','cowl','rear']
if '--only' in sys.argv:names=sys.argv[sys.argv.index('--only')+1].split(',')
views={
 'hero':((3,4,2.25),(0,-.52,-.02),3.30,100),
 'side':((6,-.52,.18),(0,-.52,-.01),2.60,100),
 'left':((-6,-.52,.18),(0,-.52,-.01),2.60,100),
 'top':((0,-.52,6),(0,-.52,0),3.15,100),
 'belly':((2.7,4,-3),(0,-.50,-.05),3.30,100),
 'wing':((1.5,.2,2.8),(.68,-.23,-.06),1.38,100),
 'cowl':((1.8,2.2,.9),(0,.10,.0),.92,100),
 'rear':((2,-1.05,.60),(0,-.94,.065),1.20,100),
 'gear':((2.7,4,-2),(0,-.5,-.08),3.30,0),
 'interior':((1.2,-1.3,-.85),(.41,-.24,-.25),.55,0)}
for name in names:
 loc,t,scale,frame=views[name];S.frame_set(frame);target=Vector(t)*K;d.ortho_scale=scale*K;render(prefix+name,loc)
print('NAVAL10_VIEWS_DONE',flush=True)
