import contextlib, io, json, math, runpy
import numpy as np
from scipy.optimize import root
from pathlib import Path
base=Path(r'D:\OpenRC-release-v012-temp\yaw-circulation-prototype-20dc6efe')
with contextlib.redirect_stdout(io.StringIO()):
 g=runpy.run_path(str(base/'prototype.py'))
mesh=g['mesh6']; K=g['k6']; speed=float(g['speed']); rho=float(g['rho']); lift=g['proxy_lift']; n=len(mesh['chords_m']);

def force(alpha,rate,ge):
  gamma=.5*np.asarray(mesh['chords_m'])*ge
  return g['force_yaw'](mesh,gamma,alpha,rate,speed,rho)
def explore(deg,rate):
  alpha=math.radians(deg); u,w=g['rate_flow'](mesh,alpha,rate,speed); ext=np.hypot(u,w); scale=float(np.max(ext));
  def residual(x):
    gg=x*scale; we=w-K@gg; ae=np.arctan2(we,u); cl=np.array([lift(float(a))[0] for a in ae]); return x-(np.hypot(u,we)/scale)*cl
  seeds=[]
  for v in [-5,-3,-2,-1,-.5,0,.1,.25,.5,1,2,3,5,10]: seeds.append((np.full(n,v*scale),f'uniform_{v}'))
  for v in [0.5,1,2,3,5]:
    seeds += [(np.linspace(-v*scale,v*scale,n),f'linear_asc_{v}'),(np.linspace(v*scale,-v*scale,n),f'linear_desc_{v}'),(np.array([(-1.)**i*v*scale for i in range(n)]),f'alternating_{v}')]
  roots=[]
  for seed,name in seeds:
    ans=root(residual,seed/scale,method='hybr',options={'xtol':1e-11,'maxfev':1000}); rr=float(np.max(np.abs(residual(ans.x))));
    if not np.isfinite(rr) or rr>1e-10: continue
    gg=ans.x*scale
    if any(np.max(np.abs(gg-r['g_mps']))/scale<1e-6 for r in roots): continue
    we=w-K@gg; ae=np.arctan2(we,u); cl=np.array([lift(float(a))[0] for a in ae]); ff=force(alpha,rate,gg)
    roots.append({'seed':name,'g_mps':gg.tolist(),'cl':cl.tolist(),'alpha_eff_deg':np.degrees(ae).tolist(),'relative_residual_inf':rr,'residual_inf_mps':rr*scale,'solver_success':bool(ans.success),'solver_message':str(ans.message),'yaw_kj_nm':ff['yaw_kj_nm'],'fx_kj_n':ff['fx_kj_n']})
  gaps=[]
  for i in range(len(roots)):
    for j in range(i+1,len(roots)):
      gaps.append({'i':i,'j':j,'g_gap_inf_mps':float(np.max(np.abs(np.array(roots[i]['g_mps'])-roots[j]['g_mps']))),'yaw_gap_nm':abs(roots[i]['yaw_kj_nm']-roots[j]['yaw_kj_nm']),'fx_gap_n':abs(roots[i]['fx_kj_n']-roots[j]['fx_kj_n'])})
  maxyaw=max(gaps,key=lambda z:z['yaw_gap_nm']) if gaps else None
  return {'external_alpha_deg':deg,'rate_rad_s':rate,'external_u_mps':u.tolist(),'external_w_mps':w.tolist(),'external_speed_mps':ext.tolist(),'root_velocity_scale_mps':scale,'roots':roots,'max_force_gap':maxyaw}
res={'interpretation':'proxy-only branch check using induced-adjusted local speed; identical external panel u,w are used for every seed','kernel_eigenvalues':np.linalg.eigvalsh(K).tolist(),'cases':[explore(20.0,0.0),explore(20.0,0.05)]}
(base/'multiroot_effectivespeed.json').write_text(json.dumps(res,indent=2)+'\n',encoding='utf-8')
for c in res['cases']:
 print(f"alpha={c['external_alpha_deg']} rate={c['rate_rad_s']} roots={len(c['roots'])} maxgap={c['max_force_gap']}")
 for i,r in enumerate(c['roots']): print(i,r['seed'],'res=',r['relative_residual_inf'],'yaw=',r['yaw_kj_nm'],'fx=',r['fx_kj_n'],'g=',r['g_mps'],'ae=',r['alpha_eff_deg'])




