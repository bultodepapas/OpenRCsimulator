"""Original, game-resolution paint cues. Layout is interpretive, not a measured factory rivet chart.
All placement is in the existing normalized 1:5 design space; UVs and geometry are untouched.
"""
import numpy as np
from PIL import Image,ImageDraw,ImageFont

def add_details(g):
 x,y,z=g['x'],g['y'],g['z'];nx,nz=g['nx'],g['nz'];N=g['N'];lid=g['lid']
 ramp=g['ramp'];band=g['band'];group=g['group'];stamp=g['stamp']
 covered=g['covered'];body=g['body'];fuselage=g['fuselage'];wing=g['wing'];walk=g['walk'];rough=g['rough']
 fixedwing=group(('wing_center_fixed','wing_left_fixed','wing_right_fixed'))
 cowl=group(('cowl',));top=covered&(nz>.65)
 details=np.zeros((N,N,4),np.uint8);stencils=np.zeros_like(details);wear=np.zeros_like(details)
 strength=.70 if lid=='scarlet' else 1.
 def over(dst,color,opacity):
  a=np.clip(opacity,0,1)*covered;old=dst[:,:,3].astype(np.float32)/255
  out=a+old*(1-a);rgb=np.asarray(color)*a[...,None]+dst[:,:,:3].astype(np.float32)*old[...,None]*(1-a[...,None])
  dst[:,:,:3]=np.clip(rgb/np.maximum(out[...,None],1e-8),0,255).astype(np.uint8);dst[:,:,3]=(out*255).round().astype(np.uint8)
 def periodic_distance(v,pitch):return abs((v+pitch/2)%pitch-pitch/2)
 def dot(d,r):return 1-ramp(r*.45,r,d)
 # Paired rows flanking a few existing longitudinal stations. Not an overall grid.
 angle=np.arctan2(z,x);arc=angle*.14
 rowdistance=np.full_like(x,100)
 for station in (-.02,-.31,-1.02,-1.25):
  rowdistance=np.minimum(rowdistance,abs(abs(y-station)-.006))
 rd=np.sqrt(rowdistance**2+periodic_distance(arc,.014)**2)
 rivets=dot(rd,.0018)*fuselage*(z<.125)*(y> -1.38)
 # Larger removable-cowl fasteners, with a restrained light rim and dark central slot.
 cowlrow=np.minimum(abs(y-.102),abs(y-.278));ca=periodic_distance(angle*.15,.042)
 cd=np.sqrt(cowlrow*cowlrow+ca*ca)
 screw=dot(cd,.0027)*cowl
 ring=band(.0013,.0030,cd,.0005)*cowl
 over(details,(7,12,15),rivets*.22*strength+screw*.28*strength)
 over(details,(153,158,149),ring*.34*strength)
 slot=(1-ramp(.00035,.0009,cowlrow))*(1-ramp(.0013,.0022,ca))*cowl
 over(details,(16,18,20),slot*.44*strength)
 # Wing access panel outline + corner screws + occasional adjacent rivet runs.
 panel_lines=np.zeros_like(x);paneldots=np.zeros_like(x);panelinterior=np.zeros_like(x)
 for xc in (.665,.825):
  dx=abs(abs(x)-xc);dy=abs(y+.17);edge=np.minimum(abs(dx-.045),abs(dy-.055))
  inside=(dx<.047)&(dy<.057)
  panel_lines=np.maximum(panel_lines,(1-ramp(.0006,.0015,edge))*inside)
  panelinterior=np.maximum(panelinterior,(dx<.043)&(dy<.053))
  dd=np.sqrt((dx-.037)**2+(dy-.046)**2)
  paneldots=np.maximum(paneldots,dot(dd,.0027))
 wr=np.sqrt(periodic_distance(abs(x)-.56,.012)**2+(y+.34)**2)
 wingrivets=dot(wr,.0017)*fixedwing*(abs(x)>.56)*(abs(x)<1.13)*top
 panel_lines*=fixedwing*top;paneldots*=fixedwing*top;panelinterior*=fixedwing*top
 over(details,(142,151,155),panelinterior*.025*strength)
 over(details,(10,17,22),panel_lines*.28*strength+paneldots*.40*strength+wingrivets*.25*strength)
 rough+=panelinterior*.018+paneldots*.025
 # A painted fuel-access ring forward of the cockpit; intentionally a visual approximation.
 capdist=np.sqrt(x*x+(y+.235)**2)
 capbody=(fuselage&(z>.05)&(abs(nx)<.7)) if lid=='scarlet' else (body&top)
 over(details,(8,14,19),capbody*band(.013,.016,capdist,.0007)*.55)
 over(details,(152,159,158),capbody*band(.0105,.0120,capdist,.0005)*.34)
 over(details,(12,17,20),capbody*band(-.001,.001,y+.235,.0005)*(abs(x)<.008)*.5)
 # Original generic service stencils, no serial, unit badge or sponsor.
 ink=(222,223,209,218) if lid!='scarlet' else (72,26,27,224)
 # Simple block lettering survives the limited texel density better than thin font curves.
 glyphs={
  'N':['10001','11001','11001','10101','10011','10011','10001'],
  'O':['01110','10001','10001','10001','10001','10001','01110'],
  'S':['01111','10000','10000','01110','00001','00001','11110'],
  'T':['11111','00100','00100','00100','00100','00100','00100'],
  'E':['11111','10000','10000','11110','10000','10000','11111'],
  'P':['11110','10001','10001','11110','10000','10000','10000'],
  'F':['11111','10000','10000','11110','10000','10000','10000'],
  'U':['10001','10001','10001','10001','10001','10001','01110'],
  'L':['10000','10000','10000','10000','10000','10000','11111'],
  '>':['00000','01000','00100','00010','00100','01000','00000'],
  ' ':['00000']*7}
 def text_bitmap(text,color=ink):
  lines=text.split('\n');width=max(len(line)*6-1 for line in lines)+2;height=len(lines)*9
  im=Image.new('RGBA',(width*12,height*12));d=ImageDraw.Draw(im)
  for k,line in enumerate(lines):
   start=(width-(len(line)*6-1))/2
   for c,ch in enumerate(line):
    for j,row in enumerate(glyphs[ch]):
     for i,on in enumerate(row):
      if on=='1':d.rectangle(((start+c*6+i)*12,(k*9+j+1)*12,(start+c*6+i+1)*12-1,(k*9+j+2)*12-1),fill=color)
  return np.asarray(im)
 no_step=text_bitmap('NO\nSTEP');fuel=text_bitmap('FUEL')
 for side in (-1,1):
  # U uses signed x, so the words are readable on both wings in top view.
  stamp(stencils,no_step,(x-side*.24)/.115+.5,(-.075-y)/.065,top&fixedwing)
 stamp(stencils,fuel,x/.12+.5,(-.258-y)/.041,top&body)
 # Short, original opening indication under each side of the cockpit.
 open_label=text_bitmap('OPEN >')
 u=np.where(nx>0,(-.385-y)/.115,(y+.50)/.115)
 stamp(stencils,open_label,u,(.115-z)/.034,fuselage&(abs(nx)>.7)&(nz>-.15))
 # Worn anti-slip coating: elongated scratches and softened foot contact patches.
 grain=(np.sin(x*1547+y*1163)+np.sin(x*891-y*1867))*.5
 scratch=walk*np.maximum(np.sin(x*2103+y*137)-.85,0)/.15*np.maximum(np.sin(y*433+1.8)-.05,0)
 scuff=walk*np.exp(-((abs(x)-.24)/.040)**2)*np.exp(-((y+.31)/.09)**2)
 wear_strength=.28 if lid=='scarlet' else (.65 if lid=='midnight' else 1.)
 over(wear,(83,86,78),scuff*.24*wear_strength+scratch*.32*wear_strength)
 # Scuffed edges stay on the walkway boundary, never on arbitrary joints or flying surfaces.
 edge=np.minimum(abs(abs(x)-.19),abs(abs(x)-.29))
 chips=walk*(1-ramp(.0007,.0024,edge))*(grain>.38)
 over(wear,(141,144,126),chips*.40*wear_strength)
 rough-=scuff*.045*wear_strength;rough+=scratch*.04
 # Local airflow-aligned exhaust deposits; each scheme has a different maintenance level.
 trail=fuselage*band(-.58,.04,y,.04)*np.exp(-((z+.082+.027*(-y))/.026)**2)*(abs(nx)>.55)
 mottled=np.clip(.75+.15*np.sin(y*75+x*143)+.10*np.cos(y*193-z*71),.35,1.)
 over(wear,(61,47,35),trail*mottled*.17*wear_strength)
 rough+=trail*.06*wear_strength
 # Subtle paint-edge separation on the racer; uniform hue on the naval schemes.
 if lid=='scarlet':
  stencils[:]=0  # Reference racer has a clean finish; retain service cues in naval liveries.
 stats={'fastener_layer_pixels':int((details[:,:,3]>0).sum()),'stencil_pixels':int((stencils[:,:,3]>0).sum()),'localized_wear_pixels':int((wear[:,:,3]>0).sum()),'style':'interpreted visible detail at game-atlas resolution; not a measured rivet blueprint','race_wear_multiplier':wear_strength}
 return details,stencils,wear,stats
