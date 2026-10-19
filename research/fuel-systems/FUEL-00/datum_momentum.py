"""FUEL-00 audit: independent check of FuelMass.datum_derivative (fixed wet-CG datum, co-moving efflux).

Usage: python3 -I datum_momentum.py
Zero external wrench and gravity, non-principal spin, 280 s burn of 0.12 kg (Stik-like numbers, not a fixture).
1) CM velocity of the remaining particles must stay constant; 2) remaining-body momentum plus momentum carried
away by the efflux must be conserved. Without the datum correction both fail independently of dt.
"""
import math
def cross(a,b): return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def add(a,b): return [x+y for x,y in zip(a,b)]
def sc(a,s): return [x*s for x in a]
def mat(I): return [[I[0],I[3],I[4]],[I[3],I[1],I[5]],[I[4],I[5],I[2]]]
def mv(M,v): return [sum(M[i][j]*v[j] for j in range(3)) for i in range(3)]
def inv3(M):
    a,b,c=M[0];d,e,f=M[1];g,h,i=M[2]
    det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
    return [[(e*i-f*h)/det,(c*h-b*i)/det,(b*f-c*e)/det],[(f*g-d*i)/det,(a*i-c*g)/det,(c*d-a*f)/det],[(d*h-e*g)/det,(b*g-a*h)/det,(a*e-b*d)/det]]
def qrot(q,v):
    w,x,y,z=q; u=[x,y,z]; t=sc(cross(u,v),2); return add(add(v,sc(t,w)),cross(u,t))
def qmul(a,b):
    return [a[0]*b[0]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3],a[0]*b[1]+a[1]*b[0]+a[2]*b[3]-a[3]*b[2],a[0]*b[2]-a[1]*b[3]+a[2]*b[0]+a[3]*b[1],a[0]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[0]]
M0=2.6; f0=0.12; tank=[0.2209,0.01,-0.02]; size=[0.09,0.05,0.05]
Iw=[0.116,0.32,0.42,-0.008,0.008,0.0006]; rate=f0/290.0
def box(c,s):
    x,y,z=c; return [(s[1]**2+s[2]**2)/12+y*y+z*z,(s[0]**2+s[2]**2)/12+x*x+z*z,(s[0]**2+s[1]**2)/12+x*x+y*y,-x*y,-x*z,-y*z]
def props(f):
    r=f0-f; m=M0-r; c=sc(tank,-r/m); T=box(tank,size); P=box(c,[0,0,0])
    return m,c,[Iw[i]-r*T[i]-m*P[i] for i in range(6)]
def deriv(s,correct):
    q=s[0:4]; v=s[4:7]; w=s[7:10]; f=s[10]
    m,c,I=props(f); J=mat(I); Ji=inv3(J)
    alpha=mv(Ji,sc(cross(w,mv(J,w)),-1))
    vd=sc(cross(w,v),-1)
    if correct: vd=[vd[i]-add(cross(alpha,c),cross(w,cross(w,c)))[i] for i in range(3)]
    qd=sc(qmul(q,[0]+w),0.5)
    return qd+vd+alpha+[-rate]
def rk4(s,dt,correct):
    k1=deriv(s,correct);k2=deriv([a+0.5*dt*b for a,b in zip(s,k1)],correct)
    k3=deriv([a+0.5*dt*b for a,b in zip(s,k2)],correct);k4=deriv([a+dt*b for a,b in zip(s,k3)],correct)
    n=[a+dt/6*(b+2*c+2*d+e) for a,b,c,d,e in zip(s,k1,k2,k3,k4)]
    qn=math.sqrt(sum(x*x for x in n[0:4])); n[0:4]=[x/qn for x in n[0:4]]; return n
def vcm(s):
    m,c,I=props(s[10]); return qrot(s[0:4],add(s[4:7],cross(s[7:10],c)))
for correct in (True,False):
    s=[1,0,0,0, 5,0,0, 2.0,3.0,1.0, f0]; v0=vcm(s); dt=1/240
    for k in range(int(280/dt)): s=rk4(s,dt,correct)
    v1=vcm(s); print('datum correction' if correct else 'no correction   ','fuel %.4f kg'%s[10],'|dv_cm|=%.3e m/s'%math.sqrt(sum((a-b)**2 for a,b in zip(v0,v1))))
def ejected_rate(s):
    # mass leaves at the tank centroid with that body point's velocity: dP_ej/dt = rate * R(v_O + w x r_t)
    return sc(qrot(s[0:4],add(s[4:7],cross(s[7:10],tank))),rate)
def total(s,Pej):
    m,c,I=props(s[10]); return add(sc(vcm(s),m),Pej)
for correct in (True,False):
    for dt in (1/120,1/240):
        s=[1,0,0,0, 5,0,0, 2.0,3.0,1.0, f0]; Pej=[0,0,0]; P0=total(s,Pej)
        for k in range(int(280/dt)):
            # RK4 on the ejected-momentum integral alongside the body (same stages)
            k1=ejected_rate(s); s2=[a+0.5*dt*b for a,b in zip(s,deriv(s,correct))]
            s_new=rk4(s,dt,correct)
            k4=ejected_rate(s_new); km=ejected_rate(s2)
            Pej=[p+dt/6*(a+4*b+c) for p,a,b,c in zip(Pej,k1,km,k4)]
            s=s_new
        P1=total(s,Pej)
        print(('datum correction' if correct else 'no correction   '),'dt=1/%d'%round(1/dt),'|dP_total|=%.3e kg m/s (P0=%.3f)'%(sum((a-b)**2 for a,b in zip(P0,P1))**0.5, sum(x*x for x in P0)**0.5))
