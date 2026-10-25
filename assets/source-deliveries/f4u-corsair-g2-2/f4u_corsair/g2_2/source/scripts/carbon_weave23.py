"""Surface-registered, filtered continuous 2/2 twill. Executed by build_carbon23."""
print('CARBON23_SURFACE_WEAVE',flush=True)
s=ax.copy();t=y.copy()
wrap=(fuselage|cowl)&covered
# Estimate each local elliptical cross section from the assembled skin, rather
# than wrapping a constant-radius cylinder around the tapered body.
ys=np.linspace(float(y[wrap].min()),float(y[wrap].max()),192,dtype=np.float32)
bins=np.clip(np.searchsorted(ys,y[wrap])-1,0,len(ys)-1)
rx=np.zeros(len(ys),np.float32);zt=np.full(len(ys),-np.inf,np.float32);zb=-zt.copy()
np.maximum.at(rx,bins,ax[wrap]);np.maximum.at(zt,bins,z[wrap]);np.minimum.at(zb,bins,z[wrap])
good=np.isfinite(zt)&(rx>.002)
for a in (rx,zt,zb):
 a[:]=np.interp(ys,ys[good],a[good])
 a[:]=np.convolve(np.pad(a,(2,2),mode='edge'),np.array([1,2,3,2,1])/9,'valid')
 # Fuselage mesh also contains small dorsal fittings. Robust longitudinal
 # fitting prevents antenna/door outliers from kinking the fibre coordinates.
 keep=np.ones(len(ys),bool)
 for iteration in range(5):
  fit=np.polynomial.Chebyshev.fit(ys[keep],a[keep],8)
  residual=a-fit(ys);mad=np.median(abs(residual-np.median(residual)))
  keep=abs(residual)<max(.012,3.5*1.4826*mad)
 a[:]=fit(ys)
rx=np.maximum(rx,.004)
rz=np.maximum((zt-zb)*.5,.004);cz=(zt+zb)*.5
angles=np.linspace(0,np.pi,513,dtype=np.float32)
speed=np.sqrt((rx[:,None]*np.cos(angles))**2+(rz[:,None]*np.sin(angles))**2)
arc=np.zeros_like(speed);arc[:,1:]=np.cumsum((speed[:,1:]+speed[:,:-1])*.5*np.pi/512,axis=1)
wy=y[wrap];rxx=np.interp(wy,ys,rx);rzz=np.interp(wy,ys,rz);czz=np.interp(wy,ys,cz)
phi=np.arctan2(ax[wrap]/rxx,(z[wrap]-czz)/rzz)
fy=np.clip((wy-ys[0])/(ys[-1]-ys[0])*(len(ys)-1),0,len(ys)-1.0001)
fa=np.clip(phi/np.pi*512,0,511.9999);iy=fy.astype(np.int32);ia=fa.astype(np.int32);ay=fy-iy;aa=fa-ia
surface_arc=(arc[iy,ia]*(1-aa)+arc[iy,ia+1]*aa)*(1-ay)+(arc[iy+1,ia]*(1-aa)+arc[iy+1,ia+1]*aa)*ay
s[wrap]=wy;t[wrap]=surface_arc
del bins,wy,rxx,rzz,czz,phi,fy,fa,iy,ia,ay,aa,surface_arc,speed
# Integrate the gull-wing centre-surface span. The same field registers fixed
# skins, fold covers, flaps and ailerons in their closed reference pose.
xs=np.linspace(.0,1.26,253,dtype=np.float32)
wm=wing&covered&(abs(y+.17)<.018)
bi=np.clip(np.searchsorted(xs,ax[wm])-1,0,len(xs)-1)
wtop=np.full(len(xs),-np.inf,np.float32);wbot=-wtop.copy()
np.maximum.at(wtop,bi,z[wm]);np.minimum.at(wbot,bi,z[wm]);good=np.isfinite(wtop)
zc=np.interp(xs,xs[good],(wtop[good]+wbot[good])*.5)
zc=np.convolve(np.pad(zc,(3,3),mode='edge'),np.ones(7)/7,'valid')
wing_arc=np.r_[0,np.cumsum(np.sqrt(np.diff(xs)**2+np.diff(zc)**2))]
s[wing]=np.interp(ax[wing],xs,wing_arc)
s[fin]=y[fin];t[fin]=z[fin]
door_side=doors&(abs(nx)>.55);s[door_side]=y[door_side];t[door_side]=z[door_side]
pitch=.0036
u=((s+t)*(.707106781/pitch)).astype(np.float32)
v=((s-t)*(.707106781/pitch)).astype(np.float32)
del s,t
du_y,du_x=np.gradient(u);dv_y,dv_x=np.gradient(v)
# Atlas boundaries must not act as enormous footprints for the prefilter.
for a in (du_y,du_x,dv_y,dv_x):np.clip(a,-1.5,1.5,out=a)
rough=np.full((N,N),.31,np.float32);height=np.zeros((N,N),np.float32)
over_coverage=np.zeros((N,N),np.float32);aniso_strength=np.zeros_like(height)
for r0 in range(0,N,128):
 sl=np.s_[r0:min(r0+128,N),:];shape=u[sl].shape
 shade_sum=np.zeros(shape,np.float32);h_sum=np.zeros(shape,np.float32);o_sum=np.zeros(shape,np.float32);r_sum=np.zeros(shape,np.float32)
 for dx,dy in [(-.25,-.25),(.25,-.25),(-.25,.25),(.25,.25)]:
  us=u[sl]+dx*du_x[sl]+dy*du_y[sl];vs=v[sl]+dx*dv_x[sl]+dy*dv_y[sl]
  iu=np.floor(us);iv=np.floor(vs);fu=us-iu;fv=vs-iv
  ov=np.remainder(iu-iv,4)<2
  across=np.where(ov,fv,fu)
  along=np.where(ov,np.remainder(us-iv,4)*.5,np.remainder(vs-iu-1,4)*.5)
  crown=np.sin(np.pi*across)**.35
  float_end=.78+.22*np.maximum(np.sin(np.pi*np.clip(along,0,1)),0)**.55
  edge=ramp(.018,.09,across)*(1-ramp(.91,.982,across))
  footprint=np.where(ov,np.hypot(dv_x[sl],dv_y[sl]),np.hypot(du_x[sl],du_y[sl]))
  attenuation=np.exp(-(np.pi*4*footprint)**2/6)
  filament=np.cos(across*8*np.pi)*attenuation
  shade_sum+=14+edge*(7.0+3.0*crown*float_end+1.5*ov+.8*filament)
  h_sum+=.000008*crown*float_end*edge
  r_sum+=.30+.035*(1-crown)+.012*(1-edge)
  o_sum+=ov
 shade=shade_sum*.25
 base[sl+(slice(0,3),)]=np.clip(shade[...,None]*np.array([.96,.99,1.02]),0,255).astype(np.uint8)
 height[sl]=h_sum*.25;rough[sl]=r_sum*.25;over_coverage[sl]=o_sum*.25
 aniso_strength[sl]=.45*np.abs(o_sum*.5-1)
base[:,:,3]=covered*255
assert np.isfinite(height).all() and np.isfinite(rough).all()
over=over_coverage>=.5
del du_y,du_x,dv_y,dv_x,over_coverage
print('CARBON23_WEAVE_READY',float(pitch),flush=True)
