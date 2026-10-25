"""Joint fit: product-photo camera (7) + mount proportions (beam depth, plate depth / height / width / centre,
tip length) against the photo silhouette (outer contours filled), lug holes as anchors."""
import numpy as np, cv2, json
from PIL import Image
from scipy.optimize import minimize
from scipy.spatial.transform import Rotation as Rot
c=json.load(open("cam_amazon.json")); R0=np.array(c["R"]); t0=np.array(c["t"]); f0=c["f"]; cx,cy=c["cx"],c["cy"]
d=np.load("mount_mesh.npz"); V=d["V"]; T=d["T"]
Vm0=np.c_[V[:,0], 14.5-V[:,1], -6.7-V[:,2]]          # photo frame: y_m toward the tips, z_m down
def solid(m):
    cs,_=cv2.findContours(m.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
    o=np.zeros(m.shape,np.uint8); cv2.drawContours(o,cs,-1,1,-1); return o>0
ph=np.asarray(Image.open("ref/amazon_mount.jpg").convert("L")).astype(int); H,W=ph.shape
phm=(ph<235); phm[:, :66]=False; phm[:,734:]=False; phm[:74,:]=False; phm[829:,:]=False
phm=cv2.morphologyEx(phm.astype(np.uint8),cv2.MORPH_CLOSE,np.ones((5,5),np.uint8))>0
n,lab,st,_=cv2.connectedComponentsWithStats(phm.astype(np.uint8)); k=1+np.argmax(st[1:,4]); phm=solid(lab==k)
EXCL=np.zeros((H,W),bool)
cv2.fillPoly(EXCL.view(np.uint8),[np.array([(330,285),(450,270),(620,370),(612,470),(320,470)],np.int32)],1)
EXCL=EXCL.view(bool)
holes_img=np.array([(246.5,380.5),(148.0,526.5),(566.6,543.9),(469.7,697.7)]); holes_obj=np.array([(-26,0,0),(-26,25,0),(26,0,0),(26,25,0)],float)
inplate=Vm0[:,1]<=-29.9; beamz=(Vm0[:,2]>0.0); tipv=Vm0[:,1]>30
def geo(g):
    h,dep,ph_,pw,pz,tip=g
    Vm=Vm0.copy()
    Vm[beamz,2]=Vm0[beamz,2]*h/15.6
    Vm[inplate,1]=-30+(Vm0[inplate,1]+30)*dep/8.5
    zc=-0.4
    Vm[inplate,2]=zc+pz+(Vm0[inplate,2]-zc)*ph_/60.0
    Vm[inplate,0]=Vm0[inplate,0]*pw/60.0
    Vm[tipv,1]=Vm0[tipv,1]+tip
    return Vm
def cam(p):
    rv=Rot.from_matrix(R0).as_rotvec()+p[:3]*0.01; R=Rot.from_rotvec(rv).as_matrix(); t=t0+p[3:6]; f=f0*np.exp(p[6]*0.05); return R,t,f
def proj(P,R,t,f):
    X=P@R.T+t; return np.c_[f*X[:,0]/X[:,2]+cx, f*X[:,1]/X[:,2]+cy]
def raster(Vm,R,t,f):
    uv=np.round(proj(Vm,R,t,f)*8).astype(np.int32); m=np.zeros((H,W),np.uint8)
    for tri in uv[T]: cv2.fillConvexPoly(m,tri,1,shift=3)
    return solid(m>0)
G0=np.array([15.6,8.5,60.0,60.0,0.0,0.0])
def unpack(q): return q[:7], G0+q[7:]*np.array([1,1,2,2,1,1])
def loss(q,verbose=False):
    p,g=unpack(q); R,t,f=cam(p); m=raster(geo(g),R,t,f); iou=((m&phm)&~EXCL).sum()/max(1,((m|phm)&~EXCL).sum())
    hres=np.linalg.norm(proj(holes_obj,R,t,f)-holes_img,axis=1).mean()
    if verbose: print("IoU",round(iou,4),"holes px",round(hres,2),"f",round(f),"geo",np.round(g,2))
    return (1-iou)+0.02*max(0,hres-0.8)
q0=np.zeros(13); loss(q0,True)
best=None
for it in range(3):
    r=minimize(loss,q0 if best is None else best.x,method="Powell",options={"maxiter":6000,"xtol":1e-3,"ftol":1e-7})
    best=r; loss(r.x,True)
p,g=unpack(best.x); R,t,f=cam(p)
json.dump({"geo":dict(zip(["beam_h","plate_depth","plate_h","plate_w","plate_dz_down","tip_dy"],g.round(2).tolist())),
           "f":f,"R":R.tolist(),"t":t.tolist(),"cx":cx,"cy":cy},open("geofit_excl.json","w"),indent=1)
m=raster(geo(g),R,t,f); dd=np.zeros((H,W,3),np.uint8); dd[phm&~m]=(255,80,0); dd[m&~phm]=(0,140,255); dd[m&phm]=(200,200,200)
Image.fromarray(dd).save("geofit_excl_diff.png")
