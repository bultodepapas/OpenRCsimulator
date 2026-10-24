"""Three-blade black/yellow paint, independent UV1, packed and repeatable."""
import bpy,math,struct,zlib
import numpy as np
def bind_naval_prop(P,refresh=False):
 rotor=bpy.data.objects['propeller_rotor'];mesh=rotor.data
 name='naval_propeller_basecolor'
 if refresh and name in bpy.data.images:bpy.data.images.remove(bpy.data.images[name])
 im=bpy.data.images.get(name)
 if im is None:
  uv=mesh.uv_layers.get('NavalBladeUV') or mesh.uv_layers.new(name='NavalBladeUV')
  pts=[rotor.matrix_world@v.co*.9 for v in mesh.vertices]
  angles=np.array([math.atan2(p.z,p.x)for p in pts]);radii=np.array([math.hypot(p.x,p.z)for p in pts]);centers=np.array([math.pi/2+i*2*math.pi/3 for i in range(3)])
  for _ in range(4):
   delta=np.angle(np.exp(1j*(angles[:,None]-centers[None,:])));labels=np.argmin(abs(delta),axis=1)
   for i in range(3):
    a=angles[(labels==i)&(radii>.20)];centers[i]=math.atan2(np.sin(a).mean(),np.cos(a).mean())
  for loop in mesh.loops:
   co=pts[loop.vertex_index];a=centers[labels[loop.vertex_index]]
   uv.data[loop.index].uv=(math.hypot(co.x,co.z)/.42,.5+(-co.x*math.sin(a)+co.z*math.cos(a))/.10)
  yy,xx=np.mgrid[:256,:1024];radius=xx/1023*.42;chord=1-yy/255
  pix=np.empty((256,1024,3),np.uint8);pix[:]=(14,18,21)
  pix[radius>.371]=(231,173,30)
  # Original pictorial inspection badge, no manufacturer mark or serial copied.
  e=((radius-.228)/.010)**2+((chord-.5)/.10)**2
  pix[e<1]=(214,201,166);pix[e<.70]=(129,28,29)
  pix[(e<.45)&(abs(chord-.5)<.014)]=(220,206,172)
  # Restrained stencil bars on the inboard blade, visually secondary to tip safety band.
  for rr in [.159,.163,.167]:pix[(abs(radius-rr)<.0008)&(abs(chord-.5)<.045)]=(168,143,75)
  def chunk(k,d):return struct.pack('>I',len(d))+k+d+struct.pack('>I',zlib.crc32(k+d)&0xffffffff)
  scan=b''.join(bytes([0])+r.tobytes()for r in pix);path=P/'textures/liveries/midnight/propeller_basecolor.png'
  path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1024,256,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scan,6))+chunk(b'IEND',b''))
  im=bpy.data.images.load(str(path));im.name=name;im.colorspace_settings.name='sRGB';im.pack()
 mat=bpy.data.materials.get('naval_blade_paint') or bpy.data.materials.new('naval_blade_paint');mat.use_nodes=True
 nodes=mat.node_tree.nodes;bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
 for n in list(nodes):
  if n.type not in {'BSDF_PRINCIPLED','OUTPUT_MATERIAL'}:nodes.remove(n)
 bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=.37
 tex=nodes.new('ShaderNodeTexImage');tex.image=im;uvnode=nodes.new('ShaderNodeUVMap');uvnode.uv_map='NavalBladeUV'
 mat.node_tree.links.new(uvnode.outputs['UV'],tex.inputs['Vector']);mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
 for i,m in enumerate(mesh.materials):
  if m.name in {'rubber','naval_blade_paint'}:mesh.materials[i]=mat
 print('NAVAL_PROP_BOUND',flush=True)
