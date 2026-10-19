"""FUEL-00 audit: FuelMass (wet-down, one tank) vs MassInventory (dry-up, resources) arithmetic.

Usage: python3 -I mass_kernel_compare.py <aircraft json with one glow_fuel item>
Python mirror of both GDScript kernels; agreement is to rounding, not bit identity.
"""
import json,sys
def box_per_kg(c,s):
    x,y,z=c
    return [(s[1]**2+s[2]**2)/12+y*y+z*z,(s[0]**2+s[2]**2)/12+x*x+z*z,(s[0]**2+s[1]**2)/12+x*x+y*y,-x*y,-x*z,-y*z]
def par(c): return box_per_kg(c,[0,0,0])
def inertia_about(parts,pt):
    j=[0.0]*6
    for m,p,s in parts:
        x=-(p[0]-pt[0]); y=p[1]-pt[1]; z=-(p[2]-pt[2])
        j[0]+=m*(y*y+z*z)+m*(s[1]**2+s[2]**2)/12; j[1]+=m*(x*x+z*z)+m*(s[0]**2+s[2]**2)/12; j[2]+=m*(x*x+y*y)+m*(s[0]**2+s[1]**2)/12
        j[3]-=m*x*y; j[4]-=m*x*z; j[5]-=m*y*z
    return j
f=sys.argv[1]
d=json.load(open(f))
parts=[];fuel=None
for it in d['inventory']:
    s=it.get('size',{}).get('value',[0,0,0])
    parts.append((it['mass']['value'],it['position']['value'],s))
    if it.get('energy_source')=='glow_fuel': fuel=parts[-1]
M=sum(p[0] for p in parts); cg=[sum(p[0]*p[1][k] for p in parts)/M for k in range(3)]
Jw=inertia_about(parts,cg)
f0,pf,sf=fuel
tank=[cg[0]-pf[0],pf[1]-cg[1],cg[2]-pf[2]]
def fuelmass(rem):
    removed=f0-rem; m=M-removed; c=[t*(-removed/m) for t in tank]
    T=box_per_kg(tank,sf); P=par(c)
    I=[Jw[i]-removed*T[i]-m*P[i] for i in range(6)]
    return m,c,I
# mass inventory: dry components about datum O=wet cg (FRD)
def to_frd(p): return [cg[0]-p[0],p[1]-cg[1],cg[2]-p[2]]
dry=[(m,to_frd(p),s) for (m,p,s) in parts if (m,p,s) is not fuel]
dry=[pp for pp in parts if pp is not fuel]
def massinv(rem):
    m=0;fm=[0,0,0];I=[0]*6
    for (mm,p,s) in dry:
        c=to_frd(p); m+=mm
        for k in range(3): fm[k]+=mm*c[k]
        cen=[mm*(s[1]**2+s[2]**2)/12,mm*(s[0]**2+s[2]**2)/12,mm*(s[0]**2+s[1]**2)/12,0,0,0]
        P=par(c)
        for i in range(6): I[i]+=cen[i]+mm*P[i]
    m+=rem
    for k in range(3): fm[k]+=rem*tank[k]
    cen_cap=[f0*(sf[1]**2+sf[2]**2)/12,f0*(sf[0]**2+sf[2]**2)/12,f0*(sf[0]**2+sf[1]**2)/12,0,0,0]
    P=par(tank)
    for i in range(6): I[i]+=rem*P[i]+(rem/f0)*cen_cap[i]
    c=[x/m for x in fm]; P=par(c)
    return m,c,[I[i]-m*P[i] for i in range(6)]
print(f,'M_wet=%.6f'%M,'tank_frd=',tank)
print(' J_wet=',['%.6f'%v for v in Jw])
for rem in [f0,f0/2,0.0]:
    a=fuelmass(rem);b=massinv(rem)
    dm=abs(a[0]-b[0]);dc=max(abs(a[1][k]-b[1][k]) for k in range(3));dI=max(abs(a[2][i]-b[2][i]) for i in range(6))
    print(' rem=%.3f m=%.6f cg_x=%+.6f m  I=[%s]  |FuelMass-MassInventory| dm=%.1e dcg=%.1e dI=%.1e'%(rem,a[0],a[1][0],', '.join('%.6f'%v for v in a[2][:3]),dm,dc,dI))
a=fuelmass(0.0)
print(' dry-vs-wet: dIxx=%.2f%% dIyy=%.2f%% dIzz=%.2f%%'%tuple(100*(a[2][i]-Jw[i])/Jw[i] for i in range(3)))
print(' fuel box volume %.1f ml; fuel volume at profile density 856.92: %.1f ml; at 0.8: %.1f ml'%(sf[0]*sf[1]*sf[2]*1e6, f0/856.92*1e6, f0/0.8e-3*1e-3*1e3))
