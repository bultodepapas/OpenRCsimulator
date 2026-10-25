import sys, math
sys.argv=[sys.argv[0]]; sys.path.insert(0,"/home/claude/engine")
import numpy as np
import build_engine as be
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
P=dict(be.HEAD_SE_P0); Q=dict(be.HEAD_SE2)
z0=57.5; zb=z0+P["band_h"]; zt=z0+13.2; R=P["r"]
xs=np.linspace(-R,R,700); X,Y=np.meshgrid(xs,xs,indexing="ij")
F=be.head_se_height(X,Y,P,Q,z0,zb,zt); F[np.hypot(X,Y)>R]=np.nan
fig,ax=plt.subplots(1,2,figsize=(16,7.5))
im=ax[0].imshow(F.T,origin="lower",extent=(-R,R,-R,R),cmap="viridis"); plt.colorbar(im,ax=ax[0])
ax[0].set_title("height field (x right, y up)")
for phi in (0,20,35,42,46,50):
    a=math.radians(phi); r=np.linspace(10,R-0.01,400)
    x,y=r*math.cos(a),r*math.sin(a)
    ax[1].plot(r,be.head_se_height(x,y,P,Q,z0,zb,zt),label=f"phi {phi}")
ax[1].set_aspect("equal"); ax[1].grid(); ax[1].legend(); ax[1].set_title("radial sections through +X crescent")
plt.tight_layout(); plt.savefig(sys.argv[-1] if len(sys.argv)>1 else "/tmp/claude-0/-home-claude/5aad6050-4747-5d68-bd16-c5cdce93a416/scratchpad/hf.png",dpi=80)
