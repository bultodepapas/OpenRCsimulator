# SUN-00 (docs/research/sun/SUN-00/README.md): calculation behind the research snapshot's tables, 2026-10-19.
# Run: python3 research/sun/sun-00/calc2.py   (standard library)
import math
def psi(th, A=40, p=0.5):
    return 10/th**3 + (5/th**2 + 0.1*p/th)*(1+(A/62.5)**4) + 2.5e-3*p
def vos84(th):
    f0=2.61e6*math.exp(-(th/0.02)**2); f1=20.91/(th+0.02)**3; f2=72.37/(th+0.02)**2
    return 0.384*f0+0.478*f1+0.138*f2
def integ(f, a, b, n=200000):
    # integrate f(theta_deg) * 2*pi*sin(theta_rad) dtheta_rad, log spacing
    la, lb = math.log(a), math.log(b); s=0.0
    for i in range(n):
        t0=math.exp(la+(lb-la)*i/n); t1=math.exp(la+(lb-la)*(i+1)/n); tm=0.5*(t0+t1)
        s+= f(tm)*2*math.pi*math.sin(math.radians(tm))*math.radians(t1-t0)
    return s
for A in [20,40,60,70]:
    print("A",A,"frac scattered 0.1-90deg:", round(integ(lambda t: psi(t,A,0.5),0.1,90),4), " 1-90:", round(integ(lambda t: psi(t,A,0.5),1,90),4), " 5-90:", round(integ(lambda t: psi(t,A,0.5),5,90),4))
print("Vos84 total 0-90:", integ(vos84,1e-5,90), " beyond 0.1:", integ(vos84,0.1,90))
# sun disc
Om=math.pi*math.radians(0.2666)**2
print("sun solid angle sr", Om, " mean L for 100 klx", 1e5/Om, " center L (mean/0.797)", 1e5/Om/0.797)
# ratio of veil at 0.5 deg vs sun mean
for th in [0.3,0.5,1,2,5,10,20]:
    print(th, "Lveil/Lsun_mean", psi(th)*1e5/(1e5/Om))
