"""Photo-guided #57/SOHIO racing livery, explicitly requested 2026-10-22.
Digitally drawn artwork; no photograph pixels. Adapted to existing F4U game geometry.
Coordinates are the normalized 1:5 paint design space, not delivered physical units.
"""
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from super57_details import coverage

IVORY=(242,238,222)
EDGE=(43,24,24)

def design57(g,colors):
 x,y,z,nx,nz=[g[k] for k in ['x','y','z','nx','nz']]
 band,ramp,mix,group=[g[k] for k in ['band','ramp','mix','group']]
 # Wide fan sectors. The leading-edge area stays red; the same projection
 # crosses the center wing, fold covers, outer panels, controls and closed doors.
 theta=np.arctan2(-y-.018,np.maximum(abs(x)-.195,.0001))
 rays=np.zeros_like(x);edges=np.zeros_like(x)
 radius=np.maximum(np.sqrt((abs(x)-.195)**2+(y+.018)**2),.02)
 for lo,hi in [(.19,.38),(.54,.82),(1.03,1.31)]:
  distance=np.minimum(theta-lo,hi-theta)*radius
  rays=np.maximum(rays,coverage(g,distance))
  edges=np.maximum(edges,coverage(g,distance,.0023))
 surface=(g['wing']|g['doors'])*(~g['inside'])*(abs(x)>.20)
 colors=mix(colors,EDGE,surface*edges)
 colors=mix(colors,IVORY,surface*rays)
 ta=np.arctan2(-(y+1.31),np.maximum(abs(x)-.045,.0001))
 tail=group(('stabilizer','elevator'))*(abs(x)>.06)
 tr=np.zeros_like(x);te=np.zeros_like(x)
 radius=np.maximum(np.sqrt((abs(x)-.045)**2+(y+1.31)**2),.02)
 for lo,hi in [(.12,.41),(.60,.94),(1.15,1.52)]:
  distance=np.minimum(ta-lo,hi-ta)*radius
  tr=np.maximum(tr,coverage(g,distance));te=np.maximum(te,coverage(g,distance,.0021))
 colors=mix(colors,EDGE,tail*te);colors=mix(colors,IVORY,tail*tr)
 # Gently taper the fuselage stripe aft; leave a red field behind the number.
 aft=np.clip((y+1.50)/.50,0,1)
 half=.016*aft
 center=.008+.025*np.clip((-y-1.)/.50,0,1)
 stripe=band(center-half,center+half,z,.0007)*band(-1.51,.295,y,.001)
 stroke=band(center-half-.0018,center+half+.0018,z,.0007)*band(-1.51,.295,y,.001)
 side=g['body']*ramp(.35,.65,abs(nx))
 number_gap=1-band(-1.025,-.67,y,.006)
 colors=mix(colors,EDGE,side*stroke*number_gap)
 colors=mix(colors,IVORY,side*stripe*number_gap)
 # Scalloped nose apron: broad side cheeks flow into the narrow side stripe.
 # Angular dependence avoids a rectangular axial white ring.
 cowl=group(('cowl',));boundary=.292-.157*np.exp(-((z-.009)/.046)**2)
 white=coverage(g,y-boundary)*cowl
 border=coverage(g,y-boundary,.002)*cowl
 colors=mix(colors,EDGE,border);colors=mix(colors,IVORY,white)
 # White tip on the existing fin/rudder, replacing the earlier diagonal band.
 cap=coverage(g,z-.427)*g['vertical']
 colors=mix(colors,EDGE,g['vertical']*coverage(g,z-.427,.002))
 colors=mix(colors,IVORY,cap)
 # Reference canopy: light structural frames and a dark lower sill.
 frame=group(('canopy_frame',))
 colors=mix(colors,EDGE,frame)
 colors=mix(colors,IVORY,frame*ramp(.155,.160,z))
 return colors

def lettering(text,fontfile,size,color,stroke=0,outline=EDGE):
 font=ImageFont.truetype('C:/Windows/Fonts/'+fontfile,size)
 box=font.getbbox(text,stroke_width=stroke)
 im=Image.new('RGBA',(box[2]-box[0]+24,box[3]-box[1]+24))
 ImageDraw.Draw(im).text((12-box[0],12-box[1]),text,font=font,fill=(*color,255),stroke_width=stroke,stroke_fill=(*outline,255))
 return np.asarray(im)

def markings57(g):
 x,y,z,nx,nz=[g[k] for k in ['x','y','z','nx','nz']]
 stamp,group=[g[k]for k in ['stamp','group']]
 layer=np.zeros((g['N'],g['N'],4),np.uint8)
 # Slender, freestanding cream race number with dark outline, readable on both sides.
 number=lettering('57','timesi.ttf',420,IVORY,7)
 u=np.where(x<0,(-.68-y)/.335,(y+1.015)/.335)
 stamp(layer,number,u,(.103-z)/.205,g['fuselage']&(abs(nx)>.55))
 # Hand-drawn oval sponsor badge; kept separate from paint in the editable markings layer.
 logo=Image.new('RGBA',(680,340));d=ImageDraw.Draw(logo)
 d.ellipse((8,8,672,332),fill=(*IVORY,255),outline=(*EDGE,255),width=9)
 d.ellipse((35,33,645,307),outline=(169,20,28,255),width=8)
 font=ImageFont.truetype('C:/Windows/Fonts/arialbi.ttf',143)
 d.text((340,165),'SOHIO',font=font,fill=(166,18,25,255),anchor='mm')
 logo=np.asarray(logo)
 u=np.where(x<0,(-1.05-y)/.165,(y+1.215)/.165)
 stamp(layer,logo,u,(.017-z)/.050,g['fuselage']&(abs(nx)>.45))
 # Red diamond within the white cowl cheek.
 diamond=Image.new('RGBA',(160,100));d=ImageDraw.Draw(diamond)
 d.polygon([(10,50),(80,10),(150,50),(80,90)],fill=(174,13,22,255),outline=(*EDGE,255),width=8)
 u=np.where(x<0,(.263-y)/.045,(y-.218)/.045)
 stamp(layer,np.asarray(diamond),u,(.021-z)/.029,group(('cowl',))&(abs(nx)>.65))
 # Identification on the upper wing as visible in the supplied aerial photographs.
 reg=lettering('N5588N','arialbi.ttf',160,(18,20,20))
 number_black=lettering('57','arialbd.ttf',250,(18,20,20))
 top=g['wing']&(nz>.45)
 stamp(layer,reg,(x-.59)/.49,(-.24-y)/.085,top&(x>0))
 stamp(layer,number_black,(x+1.16)/.19,(-.15-y)/.12,top&(x<0))
 # Repeat visible identification underneath, oriented for an underside view.
 lower=(g['wing']|g['doors'])&(nz<-.4)&~g['inside']
 stamp(layer,reg,(-x-.59)/.49,(-.24-y)/.085,lower&(x<0))
 stamp(layer,number_black,(1.16-x)/.19,(-.15-y)/.12,lower&(x>0))
 return layer
