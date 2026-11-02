"""Refine the product-photo camera by silhouette IoU (mount mesh fixed), holes as soft anchors."""
import numpy as np, cv2, json, sys
from PIL import Image
from scipy.optimize import minimize
from scipy.spatial.transform import Rotation as Rot
c=json.load(open("cam_amazon.json")); R0=np.array(c["R"]); t0=np.array(c["t"]); f0=c["f"]; cx,cy=c["cx"],c["cy"]
d=np.load(sys.argv[1] if len(sys.argv)>1 else "mount_mesh.npz"); V=d["V"]; T=d["T"]
# engine -> photo frame
Vm=np.c_[V[:,0], 14.5-V[:,1], -6.7-V[:,2]]
ph=np.asarray(Image.open("ref/amazon_mount.jpg").convert("L")).astype(int); H,W=ph.shape
phm=(ph<232); phm[:, :65]=False; phm[:,735:]=False; phm[:73,:]=False; phm[830:,:]=False
n,lab,st,_=cv2.connectedComponentsWithStats(phm.astype(np.uint8)); k=1+np.argmax(st[1:,4]); phm=lab==k
holes_img=np.array([(246.5,380.5),(148.0,526.5),(566.6,543.9),(469.7,697.7)]); holes_obj=np.array([(-26,0,0),(-26,25,0),(26,0,0),(26,25,0)],float)
def cam(p):
    rv=Rot.from_matrix(R0).as_rotvec()+p[:3]*0.01; R=Rot.from_rotvec(rv).as_matrix(); t=t0+p[3:6]; f=f0*np.exp(p[6]*0.05); return R,t,f
def proj(P,R,t,f):
    X=P@R.T+t; return np.c_[f*X[:,0]/X[:,2]+cx, f*X[:,1]/X[:,2]+cy]
def raster(R,t,f):
    uv=np.round(proj(Vm,R,t,f)*8).astype(np.int32); m=np.zeros((H,W),np.uint8)
    for tri in uv[T]:
        cv2.fillConvexPoly(m,tri,1,lineType=cv2.LINE_8,shift=3)
    return m>0
def loss(p,verbose=False):
    R,t,f=cam(p); m=raster(R,t,f); iou=(m&phm).sum()/max(1,(m|phm).sum())
    hres=np.linalg.norm(proj(holes_obj,R,t,f)-holes_img,axis=1).mean()
    if verbose: print("IoU",round(iou,4),"hole px",round(hres,2),"f",round(f,1))
    return (1-iou)+0.004*hres
p0=np.zeros(7); loss(p0,True)
r=minimize(loss,p0,method="Powell",options={"maxiter":4000,"xtol":1e-3,"ftol":1e-6})
loss(r.x,True)
R,t,f=cam(r.x); json.dump({"f":f,"cx":cx,"cy":cy,"R":R.tolist(),"t":t.tolist()},open("cam_amazon_fit.json","w"))
print("camera centre",(-R.T@t).round(1))
