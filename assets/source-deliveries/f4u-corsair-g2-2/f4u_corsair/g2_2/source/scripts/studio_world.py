"""Packed, locally generated studio reflection environment. No reference imagery."""
import bpy,math
import numpy as np
def chrome_world():
 im=bpy.data.images.get('chrome_studio_reflections')
 if im is None:
  w,h=1024,512;v,u=np.mgrid[:h,:w];az=(u+.5)/w*2*math.pi;el=((v+.5)/h-.5)*math.pi
  dz=np.sin(el);dx=np.cos(el)*np.cos(az);dy=np.cos(el)*np.sin(az)
  def soft(a,b,t):
   q=np.clip((t-a)/(b-a),0,1);return q*q*(3-2*q)
  value=.10+.42*soft(-.20,.70,dz)
  for angle,power,width in [(0,2.8,.28),(2.4,3.3,.36),(4.6,1.6,.22)]:
   d=abs(np.angle(np.exp(1j*(az-angle))))
   value+=power*(1-soft(width,width+.04,d))*soft(-.38,-.30,dz)*(1-soft(.75,.82,dz))
  value+=3.0*soft(.85,.88,dz)*(1-soft(.65,.70,abs(dx)))
  value*=1-.66*(1-soft(.025,.06,abs(dz+.12)))
  rgba=np.ones((h,w,4),np.float32);rgba[:,:,:3]=value[:,:,None]
  im=bpy.data.images.new('chrome_studio_reflections',width=w,height=h,float_buffer=True)
  im.colorspace_settings.name='Linear Rec.709';im.pixels.foreach_set(rgba.ravel())
  im.file_format='OPEN_EXR';im.filepath_raw=str(P/'textures/liveries/chrome/studio_reflections.exr');im.save();im.pack()
 world=bpy.data.worlds.get('Chrome Reflection Studio')or bpy.data.worlds.new('Chrome Reflection Studio')
 world.use_nodes=True;n=world.node_tree.nodes;l=world.node_tree.links;n.clear()
 out=n.new('ShaderNodeOutputWorld');env=n.new('ShaderNodeTexEnvironment');env.image=im
 light=n.new('ShaderNodeBackground');light.inputs['Strength'].default_value=.8;l.new(env.outputs['Color'],light.inputs['Color'])
 backdrop=n.new('ShaderNodeBackground');backdrop.inputs['Color'].default_value=(.035,.043,.052,1);backdrop.inputs['Strength'].default_value=.8
 rays=n.new('ShaderNodeLightPath');mix=n.new('ShaderNodeMixShader');l.new(rays.outputs['Is Camera Ray'],mix.inputs[0]);l.new(light.outputs[0],mix.inputs[1]);l.new(backdrop.outputs[0],mix.inputs[2]);l.new(mix.outputs[0],out.inputs['Surface'])
 bpy.context.scene.world=world
 return world
