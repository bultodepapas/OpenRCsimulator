import numpy as np, cv2, json
img_pts=np.array([(246.5,380.5),(148.0,526.5),(566.6,543.9),(469.7,697.7)],float)
obj=np.array([(-26,0),(-26,25),(26,0),(26,25)],float)   # beam-top plane, y forward (toward tips), origin at rear-hole line
H,_=cv2.findHomography(obj,img_pts)
cx,cy=400.0,451.5
def solve_f(H):
    best=None
    for f in np.linspace(300,20000,20000):
        Ki=np.linalg.inv(np.array([[f,0,cx],[0,f,cy],[0,0,1]]))
        r1=Ki@H[:,0]; r2=Ki@H[:,1]
        e=abs(r1@r2)/(np.linalg.norm(r1)*np.linalg.norm(r2))+abs(np.linalg.norm(r1)-np.linalg.norm(r2))/np.linalg.norm(r1)
        if best is None or e<best[0]: best=(e,f)
    return best
e,f=solve_f(H); print("f",f,"err",e)
K=np.array([[f,0,cx],[0,f,cy],[0,0,1]]); Ki=np.linalg.inv(K)
r1=Ki@H[:,0]; r2=Ki@H[:,1]; t=Ki@H[:,2]; s=2/(np.linalg.norm(r1)+np.linalg.norm(r2))
r1*=s; r2*=s; t*=s; r3=np.cross(r1,r2)
R=np.column_stack([r1,r2,r3]); U,_,Vt=np.linalg.svd(R); R=U@Vt
if t[2]<0: R[:,0]*=-1;R[:,1]*=-1;t=-t; R[:,2]=np.cross(R[:,0],R[:,1])
print("R",R.round(3),"t",t.round(1))
json.dump({"f":f,"cx":cx,"cy":cy,"R":R.tolist(),"t":t.tolist()},open("cam_amazon.json","w"))
C=-R.T@t; print("camera center (mm, mount frame, z toward?)",C.round(1))
