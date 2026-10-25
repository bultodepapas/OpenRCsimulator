"""Original naval restoration finish, inspired by photographs; no photographic pixels.

Design coordinates are the existing 1:5 paint space. Actual model remains 1:4.5.
All details project through the assembled rest pose, so colour crosses part joints.
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

def paint_design(g, colors):
 x,y,z,nz=g['x'],g['y'],g['z'],g['nz'];ramp=g['ramp'];group=g['group']
 upper=ramp(.25,.85,nz)
 # Slight sun lift above, deep blue below. Broad variation, no salt-and-pepper noise.
 wave=(np.sin(x*24+y*19+z*9)+.45*np.cos(x*49-y*33))*1.0
 colors[:]=(17,33,49)
 colors+=upper[...,None]*np.array([3.5,4,4.8])+wave[...,None]*.38
 fabric=group(('aileron_','elevator','rudder'))
 colors+=fabric[...,None]*np.array([1.5,2,2.6])
 return colors

def text_image(text, color=(229,231,219,245), condensed=False):
 fontfile=Path('C:/Windows/Fonts/arialbd.ttf')
 if not fontfile.exists():fontfile=Path('C:/Windows/Fonts/DejaVuSans-Bold.ttf')
 font=ImageFont.truetype(str(fontfile),100) if fontfile.exists() else ImageFont.load_default(size=100)
 lines=text.split('\n');tmp=Image.new('RGBA',(1600,400));d=ImageDraw.Draw(tmp)
 box=d.multiline_textbbox((0,0),text,font=font,spacing=8,align='center',stroke_width=0)
 im=Image.new('RGBA',(int(np.ceil(box[2]-box[0]+12)),int(np.ceil(box[3]-box[1]+12))))
 ImageDraw.Draw(im).multiline_text((6-box[0],6-box[1]),text,font=font,fill=color,spacing=8,align='center')
 return np.asarray(im)

def details(g):
 x,y,z,nx,nz=(g[k]for k in ('x','y','z','nx','nz'));N=g['N'];group=g['group'];ramp=g['ramp'];band=g['band'];stamp=g['stamp'];cov=g['covered'];rough=g['rough'];fus=g['fuselage'];wing=g['wing']
 top=wing&(nz>.58);bottom=wing&(nz<-.58);side=fus&(abs(nx)>.55)&(abs(x)>.042);ax=abs(x)
 layers={name:np.zeros((N,N,4),np.uint8)for name in ['Panel finish','Structural fasteners','Maintenance stencils','Naval identity','Airflow and service wear']}
 panels,fast,stencils,marks,wear=layers.values()
 def over(dst,color,a):
  a=np.clip(a*cov,0,1).astype(np.float32);old=dst[:,:,3].astype(np.float32)/255;out=a+old*(1-a)
  rgb=np.asarray(color,dtype=np.float32)*a[...,None]+dst[:,:,:3].astype(np.float32)*old[...,None]*(1-a[...,None])
  dst[:,:,:3]=np.clip(rgb/np.maximum(out[...,None],1e-8),0,255).astype(np.uint8);dst[:,:,3]=(out*255).round().astype(np.uint8)
 def periodic(v,p):return abs((v+p*.5)%p-p*.5)
 def line(v,width=.0012):return 1-ramp(width*.35,width*1.45,abs(v))
 def label(text,u,v,mask,color=(224,226,214,245),dst=None):stamp(stencils if dst is None else dst,text_image(text,color),u,v,mask&cov)
 def winglabel(text,u,v,mask,upper=True,color=(224,226,214,245),dst=None):
  # Mirrored geometry needs a handedness correction; text itself must not mirror.
  u=np.where((x<0)if upper else(x>0),1-u,u)
  label(text,u,v,mask,color,dst)
 def sidetext(text,front,width,upper,height,mask=side,dst=None,color=(231,231,218,255)):
  u=np.where(nx>0,(front-y)/width,(y-(front-width))/width)
  label(text,u,(upper-z)/height,mask,color,dst)
 def rounded_rect(a,b,half_a,half_b,r):
  qa=abs(a)-(half_a-r);qb=abs(b)-(half_b-r)
  return np.hypot(np.maximum(qa,0),np.maximum(qb,0))+np.minimum(np.maximum(qa,qb),0)-r

 # Coherent fictional identity, not a photographed aircraft's serial or squadron.
 sidetext('308',-.475,.195,.098,.105,dst=marks)
 sidetext('NAVY',-1.085,.225,.073,.055,dst=marks)
 sidetext('F4U CORSAIR',-1.105,.17,.009,.015,dst=marks,color=(192,200,195,240))
 tail=group(('fin_fixed','rudder'))
 over(marks,(226,228,217),tail*ramp(.430,.434,z))
 # Small matching identifiers on the outboard lower wing; no copied unit code.
 label('308',(ax-.97)/.20,(-.10-y)/.083,bottom&(x<0),dst=marks)

 # Longitudinal skin joints and lap rivets follow fuselage cross-sections.
 theta=np.arctan2(z-.015,x)
 rivets=np.zeros((N,N),np.float32);seams=np.zeros_like(rivets)
 for station in [-.045,-.295,-.655,-.775,-1.04,-1.265,-1.435]:
  valid=fus&(z<.135)
  seams=np.maximum(seams,line(y-station,.0008)*valid)
  dots=1-ramp(.00065,.0018,np.hypot(y-(station-.006),periodic(theta*.13,.017)))
  rivets=np.maximum(rivets,dots*valid)
 for angle in [-2.55,-.58,.42,2.72]:
  distance=np.angle(np.exp(1j*(theta-angle)))*.13
  dots=1-ramp(.0006,.00165,np.hypot(distance,periodic(y+.02,.018)))
  rivets=np.maximum(rivets,dots*side*band(-1.43,-.06,y)* (z<.12))
 over(panels,(8,18,27),seams*.32)
 over(fast,(120,139,147),rivets*.34)
 # Panel-to-panel reflectance differences are subtle and physically non-metallic.
 for lo,hi,amt in [(-.295,-.045,.065),(-.775,-.655,.09),(-1.265,-1.04,.07)]:
  m=band(lo+.003,hi-.003,y)*fus*ramp(-.06,.10,z)
  over(panels,(58,76,89),m*amt);rough+=m*.025

 # Access lids on rear fuselage and underside, with perimeter fasteners.
 access=np.zeros_like(rivets)
 for cy,cz,hw,hh in [(-1.335,-.018,.051,.028),(-1.117,-.063,.045,.022)]:
  d=rounded_rect(y-cy,z-cz,hw,hh,.009);m=side*band(-1.5,-.9,y)
  over(panels,(47,65,79),m*(1-ramp(-.001,.001,d))*.24)
  over(fast,(115,132,139),m*line(d,.0011)*.30)
  access=np.maximum(access,m*line(d,.0011))
  for sy in [-1,1]:
   for sz in [-1,1]:
    dot=1-ramp(.0007,.0017,np.hypot(y-(cy+sy*(hw-.009)),z-(cz+sz*(hh-.008))))
    over(fast,(174,180,171),dot*m*.55)
 sidetext('RUDDER\nACCESS',-1.29,.087,-.006,.023)
 sidetext('INSPECT',-1.078,.077,-.058,.012)
 # Circular lift access, with the tiny yellow witness mark seen on restored aircraft.
 rr=np.hypot(y+.24,z-.045);circ=side*line(rr-.010,.0011)
 over(fast,(163,177,178),circ*.55)
 sidetext('INSPECT',-.203,.073,.025,.012)
 over(stencils,(215,163,56),side*band(-.245,-.239,y,.0004)*band(.049,.053,z,.0004)*.85)

 # Two fastener tracks surround each wing access panel; spars/ribs stay subtle.
 fixed=group(('wing_left_fixed','wing_right_fixed'))
 for center in [.665,.825]:
  d=rounded_rect(ax-center,y+.17,.045,.055,.006)
  mask=fixed*(abs(nz)>.68)
  over(panels,(57,74,88),mask*(1-ramp(-.001,.001,d))*(.16 if center<.7 else .10))
  row=(line(abs(ax-center)-.038,.0013)*(1-ramp(.045,.049,abs(y+.17)))*line(periodic(y+.17,.018),.0014))
  row+=line(abs(y+.17)-.048,.0013)*(1-ramp(.030,.035,abs(ax-center)))*line(periodic(ax-center,.018),.0014)
  over(fast,(124,143,151),mask*row*.48)
  winglabel('ACCESS',(ax-center+.028)/.056,(-.158-y)/.012,top&fixed)
 for yy in [-.09,-.29]:
  dots=line(y-yy,.0011)*line(periodic(ax-.54,.019),.0014)*band(.56,1.15,ax)*fixed*(abs(nz)>.6)
  over(fast,(113,134,145),dots*.26)
 for xx in [.58,.73,.91,1.08]:
  seam=line(ax-xx,.0007)*band(-.28,-.095,y)*fixed*(abs(nz)>.67)
  over(panels,(8,18,29),seam*.22)
 # Tiny locking/service cues on the actual fixed upper fold covers.
 covers=group(('upper_fold_cover_',))
 # Keep the narrow cover clean: its UV density cannot resolve lettering reliably.
 # Broad root anti-slip patches; subdued worn edges, not silver rectangles.
 walk=g['walk'];edge=line(ax-.191,.0024)+line(ax-.289,.0024)
 grain=np.clip(np.sin(x*1919+y*1987)*np.sin(x*739-y*1171)-.15,0,1)
 over(wear,(124,130,120),walk*edge*grain*.36)
 scratches=(1-ramp(.00035,.001,periodic(y+.33,.017)))*ramp(.2,.8,np.sin(ax*1843+y*13))
 over(wear,(83,91,85),walk*scratches*.23)
 rough[walk]=.79+.035*np.sin(x[walk]*1043+y[walk]*673)
 # Service lettering on top and bottom surfaces, all separately removable.
 for s in [-1,1]:
  winglabel('NO STEP',(x*s-.31)/.13,(-.27-y)/.022,top&(x*s>0))
  winglabel('KEEP CLEAR',(x*s-.57)/.19,(-.315-y)/.016,bottom&(x*s>0),upper=False,color=(211,214,203,220))
  winglabel('FOLD LOCK',(x*s-.36)/.09,(-.095-y)/.012,top&(x*s>0),color=(204,213,206,220))
 label('FUEL',x/.08+.5,(-.170-y)/.020,fus&(nz>.65)&(z>.10)&(z<.17)&(y>-.23))
 label('DRAIN',x/.09+.5,(-.855-y)/.018,fus&(nz<-.65)&(z<-.055),color=(212,214,201,220))
 sidetext('OPEN',-.365,.057,.135,.013,mask=side&(nz<.7))
 # Canopy sill protective lip, kept restricted to paint, not glazing.
 sill=side*band(-.69,-.375,y,.005)*band(.117,.121,z,.0015)
 over(panels,(8,13,17),sill*.65)

 # Cowl radial fasteners and latches. Ring gets satin service abrasion at its lip.
 cowl=group(('cowl',));arc=np.arctan2(z,x)*.15
 for yy in [.108,.280]:
  dots=cowl*(1-ramp(.0010,.0025,np.hypot(y-yy,periodic(arc,.037))))
  over(fast,(167,176,173),dots*.55)
 for angle in [.55,2.59,3.65,5.78]:
  dist=np.angle(np.exp(1j*(np.arctan2(z,x)-angle)))*.15
  mask=cowl*band(.15,.26,y)*line(dist,.0009)
  over(panels,(6,15,23),mask*.42)
 lip=cowl*band(.309,.322,y,.002)*ramp(.3,.9,np.sin(arc*287+y*17))
 over(wear,(126,139,137),lip*.14);rough+=lip*.08
 # Exhaust: narrow soot origin below cowl, widening and fading aft. No black blanket.
 t=np.clip((.03-y)/.65,0,1);trail=side*band(-.68,.045,y,.035)
 plume=trail*np.exp(-((z-(-.083-.010*t))/(.013+.027*t))**2)*(1-t)**.7
 over(wear,(26,22,19),plume*.43);rough+=plume*.14
 over(wear,(87,68,44),plume*(1-ramp(.1,.44,t))*.10)
 belly=fus*(nz<-.6);aft=band(-1.20,-.50,y,.08)
 oily=belly*aft*np.exp(-(x/.028)**2)*.18
 over(wear,(12,14,14),oily);rough-=oily*.15
 # Trailing-edge fabric finish remains satin; no invented hardware over hinges.
 rough+=group(('aileron_','elevator','rudder'))*.025
 over(wear,(112,129,139),top*band(.55,1.18,ax)*np.exp(-((y+.020+.045*(ax-.55))/.004)**2)*grain*.10)
 # Service marks must not overprint the national emblem. Paint fasteners remain subtle.
 protection=g['insignia'][:,:,3].astype(np.float32)/255
 stencils[:,:,3]=(stencils[:,:,3]*(1-protection)).astype(np.uint8)
 fast[:,:,3]=(fast[:,:,3]*(1-protection*.85)).astype(np.uint8)
 g['naval_stats']={'design':'original naval 308, no real serial or squadron copied','reference_count':2,'layers':list(layers),'detail_pixels':{n:int((a[:,:,3]>0).sum())for n,a in layers.items()},'access_panel_pixels':int((access>.1).sum()),'rivet_pixels':int((rivets>.1).sum()),'exhaust_pixels':int((plume>.05).sum())}
 return layers
