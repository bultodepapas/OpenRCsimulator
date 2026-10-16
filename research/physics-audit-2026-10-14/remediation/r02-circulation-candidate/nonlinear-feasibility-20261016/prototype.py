from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import math
import sys
from pathlib import Path

import numpy as np
import scipy
from scipy.optimize import root

REPO = Path(r"C:\DEVELOPMENT\OpenRCsimulator")
OUT = Path(r"D:\OpenRC-release-v012-temp\yaw-circulation-prototype-20dc6efe")
CANDIDATE_PATH = REPO / "research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/circulation_candidate-v3.py"
D11F_PATH = REPO / "research/aero/d11f/wing_yaw_damping.py"
STIK_PATH = REPO / "app/data/aircraft/jensen_ugly_stik_60.json"
AERO_PATH = REPO / "app/physics/aero.gd"
POLAR_PATH = REPO / "app/physics/wing_polar.gd"
INPUT_PATH = REPO / "docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/d11g-repair/yaw_r02_input_export-v1.json"
OUT.mkdir(parents=True, exist_ok=True)

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def import_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    with contextlib.redirect_stdout(io.StringIO()):
        spec.loader.exec_module(module)
    return module

candidate = import_module("preserved_candidate_v3", CANDIDATE_PATH)
with contextlib.redirect_stdout(io.StringIO()):
    d11f = candidate.load_d11f()

def matvec(k: np.ndarray, g: np.ndarray) -> np.ndarray:
    return k @ g

def smoothstep(x: float) -> float:
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    return x*x*(3.0 - 2.0*x)

def fallback_cl(alpha: float, cl0: float, cla: float, cd90: float,
                a1: float, n1: float, width: float) -> tuple[float, float]:
    if alpha >= 0.0:
        w = smoothstep((alpha-a1)/width)
    else:
        w = smoothstep((-alpha-n1)/width)
    base = cl0 + cla*alpha
    plate = 0.5*cd90*math.sin(2.0*alpha)
    return (1.0-w)*base + w*plate, w

def solve_start(cl0: float, cla: float, cd90: float, width: float,
                target: float, sign: float) -> float:
    lo = 0.0
    hi = ((target-cl0)/cla)*sign
    def extreme(start: float) -> float:
        best = 0.0
        for k in range(801):
            alpha = sign*(start + width*(k/800.0)*1.25)
            value, _ = fallback_cl(alpha, cl0, cla, cd90, start, start, width)
            if value*sign > best*sign:
                best = value
        return best
    for _ in range(60):
        mid = 0.5*(lo+hi)
        if mid == lo or mid == hi:
            break
        if extreme(mid)*sign < target*sign:
            lo = mid
        else:
            hi = mid
    return 0.5*(lo+hi)

def local_solve(mesh: dict, k: np.ndarray, u: np.ndarray, w: np.ndarray,
                lift: callable, seed: np.ndarray | None = None,
                maxfev: int | None = None) -> dict:
    u = np.asarray(u, dtype=np.float64)
    w = np.asarray(w, dtype=np.float64)
    n = len(u)
    if len(w) != n or k.shape != (n,n):
        raise ValueError("inconsistent local system")
    speed = np.hypot(u,w)
    velocity_scale = float(np.max(speed)) if n else 0.0
    if velocity_scale == 0.0:
        # Exact zero-input root; no dimensional tolerance or epsilon is needed.
        g = np.zeros(n, dtype=np.float64)
        weff = w-matvec(k,g)
        alpha = np.arctan2(weff,u)
        cl_values=[]
        for a in alpha:
            value=lift(float(a))
            cl_values.append(value[0] if isinstance(value,tuple) else value)
        cl=np.asarray(cl_values,dtype=np.float64)
        return {"g_mps":g,"gamma_m2_s":0.5*np.asarray(mesh["chords_m"],dtype=np.float64)*g,
                "cl":cl,"alpha_effective_rad":alpha,"w_effective_mps":weff,
                "speed_external_mps":speed,"residual_inf_mps":0.0,
                "relative_residual_inf":0.0,"root_velocity_scale_mps":0.0,
                "success":True,"solver_success":True,"solver_message":"exact zero-input root",
                "iterations":0,"residual_calls":0}
    x0=np.zeros(n,dtype=np.float64) if seed is None else np.asarray(seed,dtype=np.float64).copy()/velocity_scale
    calls=0
    def residual(x):
        nonlocal calls
        calls += 1
        g=x*velocity_scale
        weff=w-matvec(k,g)
        alpha=np.arctan2(weff,u)
        cl_values=[]
        for a in alpha:
            value=lift(float(a))
            cl_values.append(value[0] if isinstance(value,tuple) else value)
        cl=np.asarray(cl_values,dtype=np.float64)
        return x-(speed/velocity_scale)*cl
    result=root(residual,x0,method="hybr",
                options={"xtol":1.0e-11,"maxfev":maxfev or max(200,80*n)})
    scaled_residual=residual(result.x)
    relative_norm=float(np.max(np.abs(scaled_residual))) if n else 0.0
    norm_mps=relative_norm*velocity_scale
    g=np.asarray(result.x,dtype=np.float64)*velocity_scale
    weff=w-matvec(k,g)
    alpha=np.arctan2(weff,u)
    cl_values=[]
    for a in alpha:
        value=lift(float(a))
        cl_values.append(value[0] if isinstance(value,tuple) else value)
    cl=np.asarray(cl_values,dtype=np.float64)
    finite=(np.all(np.isfinite(g)) and np.all(np.isfinite(cl))
            and np.all(np.isfinite(scaled_residual)))
    success=bool(finite and relative_norm<=1.0e-10
                 and (result.success or relative_norm<=1.0e-12))
    return {"g_mps":g,"gamma_m2_s":0.5*np.asarray(mesh["chords_m"],dtype=np.float64)*g,
            "cl":cl,"alpha_effective_rad":alpha,"w_effective_mps":weff,
            "speed_external_mps":speed,"residual_inf_mps":norm_mps,
            "relative_residual_inf":relative_norm,"root_velocity_scale_mps":velocity_scale,
            "success":success,"solver_success":bool(result.success),"solver_message":str(result.message),
            "iterations":int(result.nfev),"residual_calls":calls}
def rate_flow(mesh: dict, alpha: float, rate: float, speed: float) -> tuple[np.ndarray,np.ndarray]:
    ys = np.asarray(mesh["y_centres_m"], dtype=np.float64)
    return speed*math.cos(alpha)-rate*ys, np.full(len(ys), speed*math.sin(alpha), dtype=np.float64)

def force_yaw(mesh: dict, gamma: np.ndarray, alpha: float, rate: float,
              speed: float, rho: float, quadrature_order: int = 16) -> dict:
    nodes, weights = candidate.GAUSS_LEGENDRE[quadrature_order]
    edges = mesh["edges_m"]
    yaw = 0.0
    total_fx = 0.0
    for i, circulation in enumerate(gamma):
        left, right = edges[i], edges[i+1]
        width = right-left
        center = 0.5*(left+right)
        down = candidate.wake_downwash_at_bound(mesh, gamma.tolist(), center)
        for node, weight in zip(nodes, weights):
            y = center + 0.5*width*node
            dy = 0.5*width*weight
            u = speed*math.cos(alpha)-rate*y
            w = speed*math.sin(alpha)
            fx = -rho*circulation*(w-down)*dy
            total_fx += fx
            yaw += y*fx
    return {"yaw_kj_nm":float(yaw),"fx_kj_n":float(total_fx)}

def cnr(moment_at: callable, rho: float, speed: float, span: float, area: float, h: float) -> float:
    qS = 0.5*rho*speed*speed*area
    return (moment_at(h)-moment_at(-h))/(2*h)/(qS*span*span/(2*speed))

def profile_yaw_midpoint(mesh: dict, alpha: float, rate: float, speed: float, rho: float, cd0: float) -> float:
    total=0.0
    edges=mesh["edges_m"]
    w=speed*math.sin(alpha)
    for i,ch in enumerate(mesh["chords_m"]):
        y=mesh["y_centres_m"][i]
        u=speed*math.cos(alpha)-rate*y
        dy=edges[i+1]-edges[i]
        total += y*0.5*rho*cd0*(u*u+w*w)*ch*dy
    return total

def profile_yaw_continuum(mesh: dict, alpha: float, rate: float, speed: float, rho: float, cd0: float) -> float:
    return candidate.exact_linear_yaw_profile_loads(mesh,alpha,rate,speed,rho,cd0)["yaw_profile_Nm"]
def d11f_kj_yaw(alpha: float, rate: float) -> float:
    # Independent historical D11f implementation with its midpoint profile force removed.
    _, n_total = d11f.loads(alpha, rate)
    w = d11f.V*math.sin(alpha)
    n_profile = 0.0
    for i, y in enumerate(d11f.ys):
        u = d11f.V*math.cos(alpha)-rate*y
        dy = d11f.edges[i+1]-d11f.edges[i]
        n_profile += y*0.5*(u*u+w*w)*d11f.c*dy*d11f.CD0
    return n_total-n_profile

def d11f_manual_kj_yaw(alpha: float, rate: float, alpha_zero: list[float], rho_scale: float=1.0) -> float:
    w0=d11f.V*math.sin(alpha)
    u=[d11f.V*math.cos(alpha)-rate*y for y in d11f.ys]
    n=len(u)
    operator=[]
    rhs=[]
    for i in range(n):
        row=[]
        for j in range(n):
            value=-d11f.horseshoe_w(d11f.c/2,d11f.ys[i],j)*0.5*u[j]*d11f.c/u[i]
            if i==j:
                value += 1.0/d11f.a0-1.0/(2.0*math.pi)
            row.append(value)
        operator.append(row)
        rhs.append(w0/u[i]+alpha_zero[i])
    cl=d11f.solve(operator,rhs)
    gamma=[0.5*u[i]*d11f.c*cl[i] for i in range(n)]
    yaw=0.0
    for i in range(n):
        down=-sum(d11f.trailing_w(0.0,d11f.ys[i],j)*gamma[j] for j in range(n))
        fx=-gamma[i]*(w0-down)*(d11f.edges[i+1]-d11f.edges[i])
        yaw += d11f.ys[i]*fx
    return rho_scale*yaw
# Exact aircraft-fallback lift curve, used only as a mathematical boundedness proxy.
stik = json.loads(STIK_PATH.read_text(encoding="utf-8"))
aero = stik["aero"]
coeff = {k: float(v["value"]) for k,v in aero["coefficients"].items() if k in ("CL0","CLa","CD0","CL_minD","k_induced")}
envj = aero["envelope"]
env = {k: float(v["value"]) for k,v in envj.items() if k in ("CL_max","CL_min","stall_blend_width","CD90")}
width = math.radians(env["stall_blend_width"])
a1 = solve_start(coeff["CL0"], coeff["CLa"], env["CD90"], width, env["CL_max"], +1.0)
n1 = solve_start(coeff["CL0"], coeff["CLa"], env["CD90"], width, env["CL_min"], -1.0)
proxy_lift = lambda alpha: fallback_cl(alpha, coeff["CL0"], coeff["CLa"], env["CD90"], a1,n1,width)
linear_slope = float(d11f.a0)
linear_lift = lambda alpha: (linear_slope*alpha, 0.0)

# D11f mesh / source kernel; its operator sign is checked against its direct solve.
span = float(d11f.b)
chord = float(d11f.c)
rho = float(d11f.RHO_KG_M3) if hasattr(d11f, "RHO_KG_M3") else 1.225
speed = float(d11f.V)
mesh6 = candidate.make_mesh(span,[chord]*int(d11f.n))
k6 = np.asarray(candidate.induced_angle_kernel(mesh6),dtype=np.float64)
e6 = np.asarray(candidate.effective_map(k6.tolist(),linear_slope),dtype=np.float64)
alpha4 = math.radians(4.0)

linear_identity_rows = []
for deg in (0.01,0.1,0.5,1.0,4.0):
    alpha = math.radians(deg)
    u,w = rate_flow(mesh6,alpha,0.05,speed)
    ref = candidate.candidate_circulation(k6.tolist(),e6.tolist(),mesh6["chords_m"],linear_slope,
                                          u.tolist(),w.tolist(),[0.0]*len(u))["g_mps"]
    nonlin = local_solve(mesh6,k6,u,w,linear_lift,seed=np.asarray(ref))
    linear_identity_rows.append({
        "alpha_deg":deg,
        "rate_rad_s":0.05,
        "max_abs_g_gap_mps":float(np.max(np.abs(nonlin["g_mps"]-ref))),
        "max_rel_g_gap":float(np.max(np.abs(nonlin["g_mps"]-ref))/max(1e-30,float(np.max(np.abs(ref))))),
        "solver_residual_inf_mps":nonlin["residual_inf_mps"],
        "converged":nonlin["success"],
    })

direct_rows=[]
for deg in (0.01,2.0,4.0,8.0):
    alpha=math.radians(deg)
    for rate in (-0.05,0.0,0.05):
        u,w=rate_flow(mesh6,alpha,rate,speed)
        solved=candidate.candidate_circulation(k6.tolist(),e6.tolist(),mesh6["chords_m"],linear_slope,
                                               u.tolist(),w.tolist(),[0.0]*len(u))
        direct=candidate.direct_rate_dependent_cl(k6.tolist(),linear_slope,u.tolist(),w.tolist(),[0.0]*len(u))
        direct_rows.append({
            "alpha_deg":deg,"rate_rad_s":rate,
            "max_abs_cl_gap":float(np.max(np.abs(np.asarray(solved["cl"])-np.asarray(direct)))),
            "max_abs_g_gap_mps":float(np.max(np.abs(np.asarray(solved["g_mps"])-u*np.asarray(direct)))),
        })

# D11f versus reused force integration; use nonzero incidence to avoid a near-zero force-comparison artifact.
d11f_force_rows=[]
for rate in (-0.05,0.0,0.05):
    u,w=rate_flow(mesh6,alpha4,rate,speed)
    alpha_zero=[0.02]*len(u)
    exact=candidate.candidate_circulation(k6.tolist(),e6.tolist(),mesh6["chords_m"],linear_slope,
                                          u.tolist(),w.tolist(),alpha_zero)
    reused=force_yaw(mesh6,np.asarray(exact["gamma_m2_s"]),alpha4,rate,speed,rho)
    independent=d11f_manual_kj_yaw(alpha4,rate,alpha_zero,rho)
    d11f_force_rows.append({"rate_rad_s":rate,"alpha_zero_rad":0.02,
                            "candidate_yaw_kj_nm":reused["yaw_kj_nm"],
                            "manual_d11f_yaw_kj_nm":independent,
                            "abs_gap_nm":abs(reused["yaw_kj_nm"]-independent)})
# Nonlinear bounded section closure: g=V_external*Cl(atan2(w-Kg,u)).
# This is finite for u=0/reverse and has the correct attached differential; its
# exact full-angle / Re law is not identified by this Stik fallback proxy.
def nonlinear_cnr_for_nside(nside: int, h: float=0.0125) -> dict:
    mesh=candidate.make_mesh(span,[chord]*(2*nside))
    k=np.asarray(candidate.induced_angle_kernel(mesh),dtype=np.float64)
    e=np.asarray(candidate.effective_map(k.tolist(),coeff["CLa"]),dtype=np.float64)
    moments={"kj":{},"profile_midpoint":{},"profile_continuum":{}}
    solves=[]
    for rate in (-h,h):
        u,w=rate_flow(mesh,alpha4,rate,speed)
        seed=candidate.candidate_circulation(k.tolist(),e.tolist(),mesh["chords_m"],coeff["CLa"],
                                             u.tolist(),w.tolist(),[0.0]*len(u))["g_mps"]
        solved=local_solve(mesh,k,u,w,proxy_lift,seed=np.asarray(seed))
        if not solved["success"]:
            raise RuntimeError(f"fallback proxy solve failed nside={nside} r={rate}: {solved}")
        moments["kj"][rate]=force_yaw(mesh,solved["gamma_m2_s"],alpha4,rate,speed,rho)["yaw_kj_nm"]
        moments["profile_midpoint"][rate]=profile_yaw_midpoint(mesh,alpha4,rate,speed,rho,coeff["CD0"])
        moments["profile_continuum"][rate]=profile_yaw_continuum(mesh,alpha4,rate,speed,rho,coeff["CD0"])
        solves.append({"rate_rad_s":rate,"residual_inf_mps":solved["residual_inf_mps"],
                       "max_abs_cl":float(np.max(np.abs(solved["cl"]))),
                       "max_abs_g_mps":float(np.max(np.abs(solved["g_mps"])))})
    denom=(rho,speed,span,span*chord,h)
    kj=cnr(lambda r:moments["kj"][r],*denom)
    profile_mid=cnr(lambda r:moments["profile_midpoint"][r],*denom)
    profile_cont=cnr(lambda r:moments["profile_continuum"][r],*denom)
    return {"panels_per_semispan":nside,"total_panels":2*nside,"h_rad_s":h,
            "Cnr_kj":kj,"Cnr_profile_midpoint_comparator":profile_mid,
            "Cnr_profile_continuum_comparator":profile_cont,
            "Cnr_total_midpoint_comparator":kj+profile_mid,
            "Cnr_total_continuum_comparator":kj+profile_cont,
            "moments_nm":{kind:{str(rate):moment for rate,moment in values.items()} for kind,values in moments.items()},
            "solves":solves}

# D11f same-convention comparator: KJ, midpoint profile, and total are reported separately.
def d11f_cnr_parts(h: float=0.0125) -> dict:
    # Original D11f loads omit rho; rho=1 in numerator and denominator preserves its Cnr.
    d11f_rho=1.0
    kj=cnr(lambda r:d11f_kj_yaw(alpha4,r),d11f_rho,speed,span,span*chord,h)
    profile_mid=cnr(lambda r:profile_yaw_midpoint(mesh6,alpha4,r,speed,d11f_rho,float(d11f.CD0)),
                     d11f_rho,speed,span,span*chord,h)
    profile_cont=cnr(lambda r:profile_yaw_continuum(mesh6,alpha4,r,speed,d11f_rho,float(d11f.CD0)),
                     d11f_rho,speed,span,span*chord,h)
    full=cnr(lambda r:d11f.loads(alpha4,r)[1],d11f_rho,speed,span,span*chord,h)
    return {"Cnr_kj":kj,"Cnr_profile_midpoint_comparator":profile_mid,
            "Cnr_profile_continuum_comparator":profile_cont,
            "Cnr_total_midpoint_from_parts":kj+profile_mid,
            "Cnr_total_continuum_from_parts":kj+profile_cont,
            "Cnr_total_d11f_original_midpoint":full}
# Discrete D11f zero-camber and bounded fallback proxy Cnr convergence.
convergence=[]
for nside in (3,5,10,20,30,40,60):
    mesh=candidate.make_mesh(span,[chord]*(2*nside))
    k=np.asarray(candidate.induced_angle_kernel(mesh),dtype=np.float64)
    e=np.asarray(candidate.effective_map(k.tolist(),linear_slope),dtype=np.float64)
    moments={}
    maxres=0.0
    for rate in (-0.0125,0.0125):
        u,w=rate_flow(mesh,alpha4,rate,speed)
        seed=candidate.candidate_circulation(k.tolist(),e.tolist(),mesh["chords_m"],linear_slope,
                                             u.tolist(),w.tolist(),[0.0]*len(u))["g_mps"]
        sol=local_solve(mesh,k,u,w,linear_lift,seed=np.asarray(seed))
        if not sol["success"]:
            raise RuntimeError(f"linear nonlinearization solve failed nside={nside}: {sol}")
        moments[rate]=force_yaw(mesh,sol["gamma_m2_s"],alpha4,rate,speed,rho)["yaw_kj_nm"]
        maxres=max(maxres,sol["residual_inf_mps"])
    convergence.append({"panels_per_semispan":nside,"total_panels":2*nside,
                        "Cnr_kj_linear_polar":cnr(lambda r:moments[r],rho,speed,span,span*chord,0.0125),
                        "max_residual_inf_mps":maxres})

# A small angle stencil checks whether finite-angle differences vanish at the attached tangent.
stencil=[]
for deg in (4.0,2.0,1.0,0.5,0.1,0.01):
    # Recompute at the requested trim angle, not the reference 4-degree state.
    mesh=mesh6; k=k6; e=e6; alpha=math.radians(deg)
    moments={}
    for rate in (-0.0125,0.0125):
        u,w=rate_flow(mesh,alpha,rate,speed)
        seed=candidate.candidate_circulation(k.tolist(),e.tolist(),mesh["chords_m"],linear_slope,
                                             u.tolist(),w.tolist(),[0.0]*len(u))["g_mps"]
        sol=local_solve(mesh,k,u,w,linear_lift,seed=np.asarray(seed))
        if not sol["success"]:
            raise RuntimeError(f"angle stencil failed at {deg} deg")
        moments[rate]=force_yaw(mesh,sol["gamma_m2_s"],alpha,rate,speed,rho)["yaw_kj_nm"]
    stencil.append({"alpha_deg":deg,"Cnr_kj":cnr(lambda r:moments[r],rho,speed,span,span*chord,0.0125)})

# Finite-difference step convergence for the bounded Stik-fallback proxy at 4 deg.
h_convergence=[]
for h in (0.05,0.025,0.0125,0.00625):
    h_convergence.append(nonlinear_cnr_for_nside(3,h))

# C1 checks of the exact app fallback lift envelope and its reverse-angle seam.
def derivative_pair(fun, x, h):
    return ((fun(x)-fun(x-h))/h,(fun(x+h)-fun(x))/h)
c1_rows=[]
for name, point in (("positive_start",a1),("positive_end",a1+width),
                    ("negative_start",-n1),("negative_end",-(n1+width))):
    h=1.0e-7
    left,right=derivative_pair(lambda x:fallback_cl(x,coeff["CL0"],coeff["CLa"],env["CD90"],a1,n1,width)[0],point,h)
    c1_rows.append({"boundary":name,"alpha_rad":point,"value":fallback_cl(point,coeff["CL0"],coeff["CLa"],env["CD90"],a1,n1,width)[0],
                    "left_derivative":left,"right_derivative":right,"slope_gap":abs(left-right)})
seam_eps=1.0e-7
seam_values=[fallback_cl(math.pi-seam_eps,coeff["CL0"],coeff["CLa"],env["CD90"],a1,n1,width)[0],
             fallback_cl(-math.pi+seam_eps,coeff["CL0"],coeff["CLa"],env["CD90"],a1,n1,width)[0]]
# Scalar zero-axial approach for a 360-degree airfoil using the authored generic fallback.
scalar_zero=[]
for eps in (1.0e-1,1.0e-2,1.0e-3,1.0e-4,1.0e-5):
    forward=eps*fallback_cl(0.0,coeff["CL0"],coeff["CLa"],env["CD90"],a1,n1,width)[0]
    reverse=eps*fallback_cl(math.pi,coeff["CL0"],coeff["CLa"],env["CD90"],a1,n1,width)[0]
    scalar_zero.append({"abs_axial_speed_mps":eps,"forward_g_mps":forward,"reverse_g_mps":reverse,
                        "forward_slope":forward/eps,"reverse_slope":reverse/eps})

# Zero-flow, velocity similarity, and axial zero-crossing/reverse-flow robustness.
zero_flow=local_solve(mesh6,k6,np.zeros(len(mesh6["chords_m"])),np.zeros(len(mesh6["chords_m"])),proxy_lift,seed=np.zeros(len(mesh6["chords_m"])))
scale_rows=[]
base_u,base_w=rate_flow(mesh6,alpha4,0.02,speed)
base_scale_solution=local_solve(mesh6,k6,base_u,base_w,proxy_lift,seed=np.zeros(len(base_u)))
if not base_scale_solution["success"]:
    raise RuntimeError("base velocity-similarity state did not converge")
for scale in (1.0,0.3,0.01):
    u,w=scale*base_u,scale*base_w
    zero_seed_solution=local_solve(mesh6,k6,u,w,proxy_lift,seed=np.zeros(len(u)))
    continued_solution=local_solve(mesh6,k6,u,w,proxy_lift,seed=scale*base_scale_solution["g_mps"])
    force=force_yaw(mesh6,continued_solution["gamma_m2_s"],alpha4,0.02*scale,speed*scale,rho)
    normalized_gap=float(np.max(np.abs(continued_solution["g_mps"]/scale-base_scale_solution["g_mps"])))
    scale_rows.append({"scale":scale,"converged":continued_solution["success"],
                       "max_abs_g_mps":float(np.max(np.abs(continued_solution["g_mps"]))),
                       "normalized_g_gap_from_base_mps":normalized_gap,
                       "max_abs_residual_mps":continued_solution["residual_inf_mps"],
                       "zero_seed_also_converged":zero_seed_solution["success"],
                       "zero_seed_max_abs_g_mps":float(np.max(np.abs(zero_seed_solution["g_mps"]))),
                       "zero_seed_gap_to_continued_mps":float(np.max(np.abs(zero_seed_solution["g_mps"]-continued_solution["g_mps"]))),
                       "yaw_kj_nm_at_scaled_velocity":force["yaw_kj_nm"],
                       "yaw_div_scale_squared":force["yaw_kj_nm"]/(scale*scale)})
critical_rate=speed*math.cos(math.radians(2.0))/max(abs(y) for y in mesh6["y_centres_m"])
zero_cross_rows=[]
for drate in (-0.01,-0.001,0.0,0.001,0.01):
    alpha=math.radians(2.0)
    rate=critical_rate+drate
    u,w=rate_flow(mesh6,alpha,rate,speed)
    sol=local_solve(mesh6,k6,u,w,proxy_lift,seed=np.zeros(len(u)))
    zero_cross_rows.append({"rate_rad_s":rate,"rate_offset_from_outer_u_zero":drate,
                            "min_u_mps":float(np.min(u)),"max_u_mps":float(np.max(u)),
                            "outer_effective_angle_deg":float(np.rad2deg(sol["alpha_effective_rad"][-1])),
                            "outer_g_mps":float(sol["g_mps"][-1]),
                            "outer_cl":float(sol["cl"][-1]),
                            "max_abs_angle_deg":float(np.max(np.abs(np.rad2deg(sol["alpha_effective_rad"])))),
                            "max_abs_g_mps":float(np.max(np.abs(sol["g_mps"]))),
                            "residual_inf_mps":sol["residual_inf_mps"],"converged":sol["success"]})

reverse_rate=speed/max(abs(y) for y in mesh6["y_centres_m"])+0.5
u_rev,w_rev=rate_flow(mesh6,0.0,reverse_rate,speed)
reverse_sol=local_solve(mesh6,k6,u_rev,w_rev,proxy_lift,seed=np.zeros(len(u_rev)))
reverse_force=force_yaw(mesh6,reverse_sol["gamma_m2_s"],0.0,reverse_rate,speed,rho)
angle_max=float(max(abs(x) for x in reverse_sol["alpha_effective_rad"]))

# Data/provenance summary and results. No runtime edit, calibration, or CD0 used in new KJ results.
result={
    "title":"Bounded nonlinear circulation feasibility prototype",
    "status":"research-only mathematical prototype; not a production candidate",
    "equations":{
        "reference":"g = 2 Gamma / c [m/s]; K_ij = -0.5 c_j H_ij - delta_ij/(2 pi) [dimensionless].",
        "attached_d11f":"(I/a0 + K) g = w + u alpha0; with alpha0=0 this is the existing D11f / candidate-v3 operator.",
        "nonlinear_prototype":"g_i = |V_external,i| Cl(alpha_i); alpha_i = atan2(w_i - (K g)_i, u_i).",
        "linear_tangent":"For u>0 and small alpha, |V|≈u and atan2(w-Kg,u)≈(w-Kg)/u, so Cl=a0 alpha yields g=a0(w-Kg), exactly the attached dimensional operator to first order.",
        "force":"Reuse candidate-v3 center-downwash Kutta-Joukowski line-force closure; no induced-drag k(Cl-ClminD)^2 added. Profile force omitted from nonlinear candidate because CD0 available here is borrowed whole-aircraft data."
    },
    "provenance":{
        "repo_head":"20dc6efe93cfc0a4149ed7617e0d6e5f6075d59e",
        "python":sys.version.split()[0],"numpy":np.__version__,"scipy":scipy.__version__,
        "source_sha256":{
            "candidate_v3":sha256(CANDIDATE_PATH),"d11f":sha256(D11F_PATH),
            "aero_gd":sha256(AERO_PATH),"wing_polar_gd":sha256(POLAR_PATH),
            "stik_json":sha256(STIK_PATH),"r02_input_export":sha256(INPUT_PATH)
        },
        "reference_geometry":{"span_m":span,"chord_m":chord,"area_m2":span*chord,
                              "panels":len(mesh6["chords_m"]),"a0_per_rad":linear_slope},
        "bounded_fallback_proxy":{
            "CL0":coeff["CL0"],"CLa_per_rad":coeff["CLa"],"CLmax_assumed_whole_aircraft":env["CL_max"],
            "CLmin_assumed_whole_aircraft":env["CL_min"],"stall_width_rad":width,
            "positive_start_rad":a1,"negative_start_magnitude_rad":n1,"CD90":env["CD90"],
            "limitation":"This is the simulator's whole-aircraft fallback lift law/envelope used only to exercise nonlinear bounds; it is not a sourced section polar. The borrowed whole-aircraft CD0 is deliberately omitted."
        }
    },
    "checks":{
        "d11f_candidate_direct_linear_identity":direct_rows,
        "d11f_force_kernel_agreement":d11f_force_rows,
        "nonlinear_vs_attached_operator_amplitude_stencil":linear_identity_rows,
        "zero_camber_kj_cnr_panel_convergence":convergence,
        "stik_fallback_proxy_cnr_at_4deg_step_convergence":h_convergence,
        "stik_fallback_proxy_panel_convergence":[nonlinear_cnr_for_nside(nside,0.0125) for nside in (3,5,10,20,40,60,80)],
        "d11f_same_convention_cnr_parts":d11f_cnr_parts(0.0125),
        "attached_tangent_Cnr_angle_stencil":stencil,
        "fallback_polar_C1_boundaries":c1_rows,
        "fallback_polar_periodic_reverse_angle":{
            "epsilon_rad":seam_eps,"cl_at_pi_minus_eps":seam_values[0],"cl_at_minuspi_plus_eps":seam_values[1],
            "absolute_gap":abs(seam_values[0]-seam_values[1])
        },
        "zero_flow":{
            "converged":zero_flow["success"],"max_abs_g_mps":float(np.max(np.abs(zero_flow["g_mps"]))),
            "residual_inf_mps":zero_flow["residual_inf_mps"]
        },
        "velocity_similarity":scale_rows,
        "u_zero_nonzero_vertical_flow_crossing":zero_cross_rows,
        "reverse_flow":{
            "rate_rad_s":reverse_rate,"min_external_u_mps":float(np.min(u_rev)),
            "max_abs_effective_angle_deg":math.degrees(angle_max),
            "converged":reverse_sol["success"],"residual_inf_mps":reverse_sol["residual_inf_mps"],
            "max_abs_g_mps":float(np.max(np.abs(reverse_sol["g_mps"]))),
            "yaw_kj_nm":reverse_force["yaw_kj_nm"]
        },
        "zero_axial_forward_reverse_circulation_slope_probe":scalar_zero
    },
    "limitations":[
        "No Stik 2-D section polar/Re distribution was established in the authored aircraft data. CL0, CLa and stall limits used for the bounded case are whole-aircraft/estimated fallback values; they cannot justify production section circulation.",
        "The diagonal -1/(2 pi) self correction is inherited from D11f and extrapolated through separation in this prototype; that nonlinear use has not been derived from a section boundary-value problem.",
        "The center-downwash Kutta-Joukowski force closure is the existing finite-strip D11f research closure, not a continuum wake validation.",
        "The shared global/local model selector and exact Stik/R02 .orfl tape are not included. Any runtime law change requires regenerating the 15 m/s, alpha-about-4-degree, neutral-control derivative from the changed law and replaying exact baseline tapes; this prototype cannot predict the whole-aircraft change.",
        "The borrowed whole-aircraft CD0 and induced-drag factor are not used as section data; no global/local drag closure is proposed."
    ]
}
(OUT/"results.json").write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
print(json.dumps({
    "output":str(OUT/"results.json"),
    "d11f_cl_gap_max":max(r["max_abs_cl_gap"] for r in direct_rows),
    "force_gap_nm_max":max(r["abs_gap_nm"] for r in d11f_force_rows),
    "linear_tangent_rel_g_gap":linear_identity_rows,
    "zero_camber_convergence":convergence,
    "proxy_cnr":h_convergence,
    "stall_c1":c1_rows,
    "zero_flow":result["checks"]["zero_flow"],
    "zero_cross_converged":all(x["converged"] for x in zero_cross_rows),
    "reverse_converged":reverse_sol["success"],
    "reverse_max_angle_deg":math.degrees(angle_max)
},indent=2))











