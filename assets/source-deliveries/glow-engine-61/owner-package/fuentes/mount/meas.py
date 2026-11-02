import numpy as np, json
c=json.load(open("cam_amazon.json")); f,cx,cy=c["f"],c["cx"],c["cy"]; R=np.array(c["R"]); t=np.array(c["t"])
C=-R.T@t
def ray(u,v):
    d=R.T@np.array([(u-cx)/f,(v-cy)/f,1.0]); return d/np.linalg.norm(d)
def on_plane(u,v,n,d):
    dv=ray(u,v); n=np.asarray(n,float); s=(d-n@C)/(n@dv); return C+s*dv
def proj(P):
    X=R@np.asarray(P,float)+t; return f*X[0]/X[2]+cx, f*X[1]/X[2]+cy
if __name__=="__main__":
    Z0=([0,0,1],0.0)
    for name,uv in [("Ltip_outer",(65,606)),("Ltip_inner",(111,630)),("Rtip_A",(382.5,780)),("Rtip_B",(426,802.5)),
                    ("Lhole_r",(246.5,380.5)),("Rhole_f",(469.7,697.7))]:
        print(name, on_plane(*uv,*Z0).round(2))
    print("up dir in image:", proj([0,0,-10]), proj([0,0,0]))
