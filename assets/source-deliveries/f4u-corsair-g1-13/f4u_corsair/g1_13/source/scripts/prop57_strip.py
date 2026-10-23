"""Native blade-tip strip on a separate UV set; original UVMap is preserved."""
import struct,zlib,math
import numpy as np

def make_prop_texture(rotor,path):
 mesh=rotor.data
 uv=mesh.uv_layers.get('Super57BladeUV') or mesh.uv_layers.new(name='Super57BladeUV')
 points=[(rotor.matrix_world@v.co)*.9 for v in mesh.vertices]
 angles=np.array([math.atan2(p.z,p.x)for p in points]);radii=np.array([math.hypot(p.x,p.z)for p in points])
 centers=np.array([math.pi/2+i*2*math.pi/3 for i in range(3)])
 for iteration in range(4):
  delta=np.angle(np.exp(1j*(angles[:,None]-centers[None,:])));labels=np.argmin(abs(delta),axis=1)
  for i in range(3):
   a=angles[(labels==i)&(radii>.20)]
   centers[i]=math.atan2(np.sin(a).mean(),np.cos(a).mean())
 for loop in mesh.loops:
  co=points[loop.vertex_index];center=centers[labels[loop.vertex_index]]
  radius=math.sqrt(co.x*co.x+co.z*co.z)
  tangent=-co.x*math.sin(center)+co.z*math.cos(center)
  uv.data[loop.index].uv=(radius/.42,.5+tangent/.10)
 N=1024;H=256;yy,xx=np.mgrid[:H,:N]
 radius=xx/(N-1)*.42;chord=1-yy/(H-1)
 pixels=np.empty((H,N,3),np.uint8);pixels[:]=(14,17,20)
 pixels[radius>.345]=(174,13,22);pixels[radius>.375]=(242,238,222)
 # The reference photos show small red oval blade badges. The simplified badge
 # is intentionally pictorial; it does not invent a serial or calibration number.
 ellipse=((radius-.225)/.013)**2+((chord-.5)/.095)**2
 pixels[ellipse<1.0]=(224,215,189)
 pixels[ellipse<.73]=(130,15,24)
 pixels[ellipse<.45]=(167,23,30)
 # A single restrained center stroke evokes the light emblem visible in the photos.
 pixels[(ellipse<.30)&(abs(chord-.5)<.012)]=(226,213,180)
 def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
 scan=b''.join(bytes([0])+row.tobytes()for row in pixels)
 path.write_bytes(bytes([137,80,78,71,13,10,26,10])+chunk(b'IHDR',struct.pack('>IIBBBBB',N,H,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scan,6))+chunk(b'IEND',b''))
 print('PROP57_TEXTURE',{'size':[N,H],'additional_uv':'Super57BladeUV','original_UVMap_preserved':True,'blade_axes_degrees':[math.degrees(x)for x in centers]},flush=True)
