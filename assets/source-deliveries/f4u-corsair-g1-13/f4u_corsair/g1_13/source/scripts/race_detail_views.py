"""Comparable current/baseline racing details. Does not save changes into the model."""
import bpy,sys,math,json
from pathlib import Path
from mathutils import Vector,Matrix
P=Path(__file__).resolve().parents[2]
setup=(P/'source/scripts/preview.py').read_text().split('for name,loc in')[0]
exec(compile(setup,str(P/'source/scripts/preview.py'),'exec'))
original_render=render
def render(name,loc):
 if '--only' in sys.argv and name!=prefix+sys.argv[sys.argv.index('--only')+1]:return
 original_render(name,loc)
S.cycles.samples=28;S.render.resolution_x=1300;S.render.resolution_y=950
try:S.view_settings.look='AgX - Medium High Contrast'
except TypeError:pass
area('belly_fill',(0,1,-3),80,3)
prefix='before17_' if '--before' in sys.argv else 'detail17_'
subset=sys.argv[sys.argv.index('--set')+1]if '--set' in sys.argv else 'all'
if subset in {'all','overview'}:
 target=Vector((0,-.52,-.02))*K;d.ortho_scale=3.3*K
 for name,loc in [('hero',(3,4,2.5)),('left',(-6,-.52,.25)),('right',(6,-.52,.25)),('top',(0,-.52,6))]:render(prefix+name,loc)
if subset in {'all','details'}:
 views=[('cowl',(0,.15,.03),.64,(1.8,1.0,.45)),('identity',(0,-.70,.08),1.05,(-4,-.70,.30)),('tail',(0,-1.36,.29),.53,(-3,-1.36,.32)),('tail_right',(0,-1.36,.29),.53,(3,-1.36,.32)),('prop',(0,.40,0),1.35,(.1,4,.03)),('wing',(.72,-.19,-.10),.64,(.72,-.19,3))]
 for name,t,scale,loc in views:
  target=Vector(t)*K;d.ortho_scale=scale*K;render(prefix+name,loc)
if subset in {'all','motion'}:
 target=Vector((.4,-.25,-.20))*K;d.ortho_scale=.95*K
 for frame in (0,50,100):S.frame_set(frame);render(prefix+'doors_'+str(frame),(1.3,.8,-1.1))
 S.frame_set(0)
 rest={a['node']:bpy.data.objects[a['node']].matrix_basis.copy()for a in json.loads((P/'metadata.json').read_text())['articulations']if a['node'].startswith('flap_')}
 for n,M in rest.items():bpy.data.objects[n].matrix_basis=M@Matrix.Rotation(math.radians(40),4,'X')
 target=Vector((0,-.52,-.02))*K;d.ortho_scale=3.3*K
 render(prefix+'flaps',(3,-3,1.6))
 for n,M in rest.items():bpy.data.objects[n].matrix_basis=M
if subset in {'all','underside'}:
 S.frame_set(100)
 area('underside_key',(-2,1,-4),210,4)
 views=[('underside',(0,-.52,-.02),3.3,(0,-.52,-6)),('underside_angle',(0,-.52,-.02),3.3,(-3,2,-3)),('belly',(0,-.78,-.06),.80,(-.2,-.78,-3)),('underwing',(.81,-.24,-.10),1.18,(.81,-.24,-4))]
 for name,t,scale,loc in views:
  target=Vector(t)*K;d.ortho_scale=scale*K;render(prefix+name,loc)
 S.frame_set(0)
 target=Vector((.40,-.25,-.20))*K;d.ortho_scale=1.02*K
 render(prefix+'door_inside',(-.1,-.8,-2.0))
print('RACE_DETAIL_VIEWS_DONE',prefix,subset,flush=True)
