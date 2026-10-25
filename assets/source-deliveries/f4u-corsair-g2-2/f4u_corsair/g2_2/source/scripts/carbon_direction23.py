"""Bake each visible tow axis into the existing UV tangent basis."""
rotation=np.zeros((N,N),np.float32)
uy,ux=np.gradient(u);vy,vx=np.gradient(v)
for r0 in range(0,N,128):
 sl=np.s_[r0:min(r0+128,N),:]
 # A vector tangent to an iso-v contour follows a u-oriented visible float.
 dx=np.where(over[sl],vy[sl],uy[sl]);dy=-np.where(over[sl],vx[sl],ux[sl])
 direction=pu[sl]*dx[...,None]+pv[sl]*dy[...,None]
 bitangent=np.cross(normal[sl],tangent[sl])
 handed=np.sign(np.sum(-pv[sl]*bitangent,axis=2));bitangent*=handed[...,None]
 a=np.sum(direction*tangent[sl],axis=2);b=np.sum(direction*bitangent,axis=2)
 rotation[sl]=np.remainder(np.arctan2(b,a)/(2*np.pi),.5)
aniso_strength[~ok]=0
del u,v,uy,ux,vy,vx,over
# Pad direction as a doubled-angle vector, so averaging near 0/180 degrees
# does not invent a perpendicular fibre direction.
directions=np.stack([np.cos(rotation*4*np.pi),np.sin(rotation*4*np.pi)],axis=2)
valid=covered.copy()
for _ in range(12):
 acc=np.zeros_like(directions);sacc=np.zeros_like(aniso_strength);weight=np.zeros_like(aniso_strength)
 for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:
  m=np.roll(valid,(dy,dx),(0,1));acc+=np.roll(directions,(dy,dx),(0,1))*m[...,None];sacc+=np.roll(aniso_strength,(dy,dx),(0,1))*m;weight+=m
 m=(~valid)&(weight>0);directions[m]=acc[m]/weight[m,None];aniso_strength[m]=sacc[m]/weight[m];valid|=m
rotation=np.remainder(np.arctan2(directions[:,:,1],directions[:,:,0])/(4*np.pi),.5)
Image.fromarray(np.round(np.clip(aniso_strength,0,1)*255).astype(np.uint8)).save(D/'anisotropy_strength.png')
Image.fromarray(np.round(rotation*65535).astype(np.uint16)).save(D/'anisotropy_rotation.png')
direction_preview=np.zeros((N,N,3),np.uint8)
direction_preview[:,:,:2]=np.round((directions*.5+.5)*255).astype(np.uint8)
direction_preview[:,:,2]=np.round(np.clip(aniso_strength,0,1)*255).astype(np.uint8)
Image.fromarray(direction_preview).save(D/'weave_direction_preview.png')
print('CARBON23_DIRECTION_READY',json.dumps({'strength_max':float(aniso_strength.max()),'carbon_coverage':float((aniso_strength>0).mean()),'rotation_bits':16}),flush=True)
del directions,direction_preview,acc,sacc,weight,rotation,aniso_strength
