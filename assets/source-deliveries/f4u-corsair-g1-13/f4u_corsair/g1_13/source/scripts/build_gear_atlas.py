"""Shared 2048 PBR atlas for tyres, coated wheel webs and exposed metal."""
from pathlib import Path
import sys,zipfile,io
try:import numpy as np;from PIL import Image
except ImportError:
 sys.path.insert(0,str(Path(__file__).resolve().parents[5]/'work/plot_R58_deps'))
 import numpy as np
 from PIL import Image
P=Path(__file__).resolve().parents[2];D=P/'textures/gear';D.mkdir(parents=True,exist_ok=True);N=2048
yy,xx=np.mgrid[0:N,0:N];u=xx/(N-1);v=1-yy/(N-1)
base=np.zeros((N,N,4),np.uint8);base[:]=(222,224,213,255)
orm=np.zeros((N,N,3),np.uint8);orm[:]=(255,100,0)
tyre=v<.50;side=np.abs((v-.02)/.46-.5);grain=np.sin(u*2129+v*631)*np.sin(u*947-v*773)
tread=np.exp(-((side/.24)**4));tone=30+14*tread+grain*1.8
base[tyre,:3]=np.stack([tone,tone+1,tone+2],axis=-1)[tyre].clip(0,255).astype(np.uint8)
orm[tyre,1]=(188+20*tread[tyre]+grain[tyre]*4).astype(np.uint8)
detail=np.zeros_like(base)
# Fine moulding lines, scuff variation and a small balance dot; no invented specifications.
lines=np.exp(-((v-.067)/.0013)**2)+np.exp(-((v-.434)/.0013)**2)
detail[:,:,:3]=(63,65,62);detail[:,:,3]=(lines*tyre*85).clip(0,255).astype(np.uint8)
dot=((u-.78)/.0038)**2+((v-.074)/.0045)**2
detail[dot<1]=(136,36,28,200)
# Inner edge of the painted rim receives a narrow, restrained brake-dust band.
rim=(v>.52)&(v<.78);t=(v-.53)/.23
dust=np.exp(-((t-.16)/.13)**2)*(.75+.25*np.cos(u*29))
detail[rim,:3]=(90,79,65);detail[rim,3]=(dust[rim]*48).astype(np.uint8)
orm[rim,1]=(90+dust[rim]*24).astype(np.uint8)
# Dedicated swatches sampled by small hub, bolt, brake and valve components.
for lo,hi,color,rough,metal in [(.80,.86,(139,148,151),85,195),(.87,.93,(70,74,72),140,155),(.94,1.,(27,29,28),192,0)]:
 mask=(v>=lo)&(v<hi);base[mask,:3]=color;orm[mask,1]=rough;orm[mask,2]=metal;detail[mask,3]=0
alpha=detail[:,:,3:4]/255
rgb=(base[:,:,:3]*(1-alpha)+detail[:,:,:3]*alpha).round().astype(np.uint8)
Image.fromarray(rgb).save(D/'basecolor.png');Image.fromarray(orm).save(D/'orm.png')
Image.fromarray(base).save(D/'base_layer.png');Image.fromarray(detail).save(D/'finish_layer.png')
with zipfile.ZipFile(D/'source.ora','w',zipfile.ZIP_DEFLATED)as archive:
 archive.writestr('mimetype','image/openraster')
 for name,arr in [('base',base),('finish',detail),('mergedimage',np.concatenate([rgb,np.full((N,N,1),255,np.uint8)],axis=2))]:
  buf=io.BytesIO();Image.fromarray(arr).save(buf,format='PNG');archive.writestr(name+'.png',buf.getvalue())
 archive.writestr('stack.xml','<image version="0.0.3" w="2048" h="2048" name="Gear finishes g1.8"><stack><layer name="Moulding and localized finish" src="finish.png" opacity="1.0" visibility="visible" composite-op="svg:src-over"/><layer name="Tyre, coated rim and metal zones" src="base.png" opacity="1.0" visibility="visible" composite-op="svg:src-over"/></stack></image>')
print('GEAR_ATLAS_READY',flush=True)
