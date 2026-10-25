"""Editable racing-service details. Photo-informed labels, interpreted panel hardware.
No added mesh geometry. Pixel footprint filtering respects the 2048 game atlas.
"""
import numpy as np
from PIL import Image,ImageDraw,ImageFont

def coverage(g,d,offset=0.):
 part=g['part'];fwidth=np.zeros_like(d)
 for axis in (0,1):
  values=[]
  for step in (-1,1):
   valid=(np.roll(part,step,axis)==part)&(part>=0)
   values.append(np.where(valid,np.abs(d-np.roll(d,step,axis)),0))
  fwidth+=np.maximum(*values)*.5
 fwidth=np.clip(fwidth,.0007,.007)
 return np.clip(.5+(d+offset)/(2*fwidth),0,1)

def race_details(g):
 x,y,z,nx,nz=[g[k]for k in ['x','y','z','nx','nz']]
 group,band,ramp,stamp=[g[k]for k in ['group','band','ramp','stamp']]
 out=np.zeros((g['N'],g['N'],4),np.uint8);rough=g['rough']
 body=g['fuselage'];cowl=group(('cowl',));wing=group(('wing_center_fixed','wing_left_fixed','wing_right_fixed'));top=nz>.65
 def over(color,a):
  a=np.clip(a,0,1)*g['covered'];old=out[:,:,3].astype(np.float32)/255
  alpha=a+old*(1-a)
  rgb=np.asarray(color)*a[...,None]+out[:,:,:3]*old[...,None]*(1-a[...,None])
  out[:,:,:3]=np.clip(rgb/np.maximum(alpha[...,None],1e-8),0,255).astype(np.uint8)
  out[:,:,3]=(alpha*255).round().astype(np.uint8)
 def text_bitmap(text,size=120):
  font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',size);box=font.getbbox(text)
  im=Image.new('RGBA',(box[2]-box[0]+12,box[3]-box[1]+12));d=ImageDraw.Draw(im)
  d.text((6-box[0],6-box[1]),text,font=font,fill=(34,25,24,238))
  return np.asarray(im)
 # The registration and EXPERIMENTAL appear in the supplied race-aircraft photos.
 u=np.where(x<0,(-.38-y)/.19,(y+.57)/.19)
 stamp(out,text_bitmap('EXPERIMENTAL'),u,(.124-z)/.018,body&(abs(nx)>.6))
 u=(.375-z)/.135;v=np.where(x>0,(-1.335-y)/.021,(y+1.356)/.021)
 stamp(out,text_bitmap('N5588N'),u,v,g['vertical']&(abs(nx)>.65))
 # Subtle paired lines and painted Dzus heads at the two removable cowl rings.
 angle=np.arctan2(z,x);arc=angle*.15
 periodic=lambda v,p:abs((v+p/2)%p-p/2)
 line=np.minimum(abs(y-.103),abs(y-.278))
 metal_head=1-ramp(.0018,.0036,np.sqrt(line**2+periodic(arc,.042)**2))
 over((192,184,163),metal_head*cowl*.40)
 slots=(1-ramp(.0006,.0013,line))*(1-ramp(.0014,.0026,periodic(arc,.042)))
 over((23,20,19),slots*cowl*.65)
 # Edge on one small service plate on each cowl cheek. Layout is an interpretation.
 dy=abs(y-.182);dz=abs(z-.074)
 q=np.maximum(dy-.025,dz-.018);plate=(q<0)&cowl&(abs(nx)>.65)
 edge=(1-ramp(.0007,.0020,abs(q)))*cowl*(abs(nx)>.65)
 over((52,29,26),edge*.42)
 corner=np.sqrt((dy-.020)**2+(dz-.013)**2)
 over((204,197,174),(1-ramp(.0009,.0024,corner))*plate*.68)
 over((38,27,24),plate*(abs(y-.182)<.009)*band(.0725,.0755,z,.0005)*.7)
 rough+=plate*.025+metal_head*cowl*.05
 # Wing inspection screws: a dark slot and a narrow painted rim.
 panels=np.zeros_like(x);screws=np.zeros_like(x)
 for xc in (.665,.825):
  dx=abs(abs(x)-xc);dy=abs(y+.17)
  dist=np.sqrt((dx-.037)**2+(dy-.046)**2)
  rim=band(.0012,.0031,dist,.00065)*wing*top
  over((187,173,153),rim*.28)
  slot=(1-ramp(.0006,.0012,abs(dx-.037)))*(1-ramp(.0015,.0025,abs(dy-.046)))*wing*top
  over((44,30,29),slot*.68)
  screws=np.maximum(screws,slot)
  panels=np.maximum(panels,(dx<.044)&(dy<.054))
 rough+=screws*.035+panels*wing*top*.012
 # Fuel cap: rim, recessed handle and a restrained buffed area around it.
 cap=np.sqrt(x*x+(y+.235)**2);capmask=body&(z>.05)&(abs(nx)<.7)
 over((201,194,176),band(.011,.014,cap,.0008)*capmask*.50)
 over((28,23,22),band(.003,.007,abs(x),.0007)*band(-.237,-.233,y,.0007)*capmask*.5)
 polish=np.exp(-(cap/.028)**4)*capmask;rough-=polish*.024
 # Recess dirt is restrained and localized. It does not draw highlights into paint.
 dirt=cowl*band(.095,.12,y,.006)*np.exp(-((z+.08)/.03)**2)
 over((55,35,24),dirt*.11);rough+=dirt*.04
 frame=group(('canopy_frame',));rough+=frame*.06
 # Underside: maintained racing finish, with service marks tied to each part.
 # These are visual interpretations, not measured factory access-panel locations.
 # Body corner normals in this inherited asset face inward; position identifies
 # its ventral skin without changing the mesh, shading normals or lettering axes.
 lower=nz<-.55;belly=body&(z<-.02)&(abs(nx)<.8);underwing=wing&lower
 def rounded_panel(cx,cy,hx,hy,r,mask,alpha=.40):
  dx=abs(x-cx);dy=abs(y-cy)
  qx=dx-hx+r;qy=dy-hy+r
  dist=np.sqrt(np.maximum(qx,0)**2+np.maximum(qy,0)**2)+np.minimum(np.maximum(qx,qy),0)-r
  stroke=coverage(g,dist,.0008)-coverage(g,dist,-.0008)
  over((47,31,27),stroke*mask*alpha)
  rough[:]+=mask*(dist<0)*.025
  return dx,dy,dist
 # A rounded ventral service cover and four recessed, painted fastener heads.
 dx,dy,dist=rounded_panel(0,-.825,.047,.088,.013,belly,.60)
 fast=np.sqrt((dx-.031)**2+(dy-.065)**2)
 over((202,183,161),band(.0015,.0032,fast,.0008)*belly*.45)
 over((39,28,25),(1-ramp(.0005,.0013,abs(dx-.031)))*(1-ramp(.0015,.0030,abs(dy-.065)))*belly*.74)
 latch=band(-.830,-.820,y,.0015)*band(-.012,.012,x,.0015)*belly
 over((48,32,28),latch*.55);rough[:]+=latch*.045
 # Existing underwing access panels receive the same fasteners as their upper faces.
 for xc in (.665,.825):
  dx=abs(abs(x)-xc);dy=abs(y+.17)
  rdist=np.sqrt((dx-.037)**2+(dy-.046)**2)
  over((196,180,159),band(.0012,.0031,rdist,.00065)*underwing*.28)
  slot=(1-ramp(.0006,.0012,abs(dx-.037)))*(1-ramp(.0015,.0025,abs(dy-.046)))*underwing
  over((42,29,26),slot*.64);rough[:]+=slot*.03
 # Small circular service covers below each inner wing, clear of the retracting doors.
 disk=np.sqrt((abs(x)-.57)**2+(y+.305)**2)
 over((44,30,27),band(.0125,.0145,disk,.001)*underwing*.48)
 over((53,35,28),band(-.306,-.304,y,.0008)*band(.561,.579,abs(x),.0008)*underwing*.55)
 rough[:]+=(disk<.015)*underwing*.045
 # Interior coating is distinct from exterior lacquer. Fastener rows follow the doors.
 inner=g['doors']&g['inside'];over((199,203,189),inner*.90)
 rough[inner]=.52+grain_field(x,y,z,amplitude=.012)[inner]
 for prefixes,cx,cy,hx,hy in [
  (('gear_door_front_',),.421,-.142,.061,.079),
  (('gear_door_inner_',),.361,-.284,.034,.112),
  (('gear_door_outer_',),.457,-.284,.034,.112),
  (('gear_door_tail_',),.018,-1.410,.010,.080)]:
  mask=group(prefixes)&inner
  ax=abs(x);dx=abs(ax-cx);dy=abs(y-cy)
  # Narrow painted reinforcement fields; no baked lighting or invented extrusion.
  rim=(1-ramp(.001,.003,abs(dx-hx)))*band(0,hy,dy,.005)
  end=(1-ramp(.001,.003,abs(dy-hy)))*band(0,hx,dx,.004)
  over((133,145,127),np.maximum(rim,end)*mask*.45)
  edge=np.minimum(abs(dx-hx),abs(dy-hy))
  along=np.where(abs(dx-hx)<abs(dy-hy),y-cy,ax-cx)
  bolt=np.sqrt(edge*edge+periodic(along,.032)**2)
  extent=(dx<hx+.004)&(dy<hy+.004)
  over((76,84,75),(1-ramp(.0009,.0020,bolt))*mask*extent*.65)
  rough[:]+=mask*np.maximum(rim,end)*.07
 # Mild oil/exhaust discoloration only behind the lower engine, elongated aft.
 tail_length=np.clip((.035-y)/.63,0,1)
 streak_mask=belly*band(-.59,.025,y,.045)*np.exp(-((abs(x)-(.042+.014*tail_length))/(.009+.018*tail_length))**2)
 over((62,43,30),streak_mask*.13*(1-.45*tail_length));rough[:]+=streak_mask*.065
 # The aft belly remains clean; edge wear stays around service closures only.
 over((77,49,37),np.exp(-((dist/.004)**2))*belly*.035)
 # Micro variation in the clear paint response, kept below visible color mottling.
 grain=np.sin(x*481+y*317+z*283)*np.cos(x*241-y*557)
 rough+=g['covered']*(~g['inside'])*grain*.006
 g['detail_stats']['g1_7_racing_details']={'layer_pixels':int((out[:,:,3]>0).sum()),'photo_labels':['EXPERIMENTAL','N5588N on tail'],'underside':['ventral service cover','underwing painted fasteners and round covers','separate satin interior door coating','door perimeter details','localized lower engine residue'],'interior_door_pixels':int(inner.sum()),'interpretation':'service-plate, interior reinforcement paint and fastener positions are visual details, not a measured engineering layout'}
 return out

def grain_field(x,y,z,amplitude=.006):
 return amplitude*np.sin(x*481+y*317+z*283)*np.cos(x*241-y*557)
