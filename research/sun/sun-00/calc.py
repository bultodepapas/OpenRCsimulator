# SUN-00 (docs/research/sun/SUN-00/README.md): calculation behind the research snapshot's tables, 2026-10-19.
# Run: python3 research/sun/sun-00/calc.py   (standard library and numpy)
import math
# --- CIE general disability glare (Bara & Bao-Varela 2023 eq.2) ---
def psi(th, A=40, p=0.5):
    return 10/th**3 + (5/th**2 + 0.1*p/th)*(1+(A/62.5)**4) + 2.5e-3*p
def stiles_age(th, A=40):
    return 10*(1+(A/70)**4)/th**2
def vos84(th):  # Spencer/Vos 1984 photopic PSF (sr^-1?), theta deg
    f0=2.61e6*math.exp(-(th/0.02)**2); f1=20.91/(th+0.02)**3; f2=72.37/(th+0.02)**2
    return 0.384*f0+0.478*f1+0.138*f2
# --- KS91 sky scattering (calibrated to cd/m2) ---
NL=3.183e-6  # cd/m2 per nanoLambert
def ks91(rho, k=0.172, Xs=1.0, X=1.0, m=-26.74):
    Istar=10**(-0.4*(m+16.57))
    fR=2.27e5*(1.06+math.cos(math.radians(rho))**2)
    fM=6.2e7/rho**2 if rho<10 else 10**(6.15-rho/40)
    f=fR+fM
    B=f*Istar*10**(-0.4*k*Xs)*(1-10**(-0.4*k*X))
    return B*NL, fM*Istar*10**(-0.4*k*Xs)*(1-10**(-0.4*k*X))*NL
E=100e3 # lux at eye, normal to sun
print("theta  psi(A40,p.5)  StilesAge40  Vos84   Lveil(cd/m2)  Lsky_KS91  Laureole")
for th in [0.3,0.5,1,2,3,5,7,10,15,20,30,45]:
    ls, la = ks91(th)
    print(f"{th:5}  {psi(th):10.4g}  {stiles_age(th):10.4g}  {vos84(th):8.4g}  {psi(th)*E:10.4g}  {ls:10.4g}  {la:10.4g}")
# --- retinal illuminance & steady-state bleach ---
pupil_d=2.5  # mm
area=math.pi*(pupil_d/2)**2
print("\npupil area mm2",area)
I0=10**4.3
print("theta  L_total  td  bleached_fraction")
for th in [1,2,3,5,7,10,15,20,30,45,90]:
    ls,_=ks91(th); L=ls+psi(th)*E
    td=L*area
    print(th, f"{L:.3g}", f"{td:.3g}", f"{td/(td+I0):.3f}")
Lsun=1.6e9
print("sun disc td", Lsun*area, "bleach", Lsun*area/(Lsun*area+I0))
# --- Crumey photopic threshold ---
def crumey(B, A_sr):
    r3,r4=1.772e-4,7.167e-5
    R=(r3*B**-0.25+r4)**2
    Cinf=2.720e-3
    q=1.146-0.0885*math.log10(B) if B>=3.40 else 0.6
    return ((R/A_sr)**q + Cinf**q)**(1/q)
print("\nplane visibility (target luminance Lt), area 0.4 m2")
Lt=2500.0
for d in [100,150,200,300]:
    A=0.4/d**2
    row=[]
    for th in [1,2,3,5,10,20]:
        ls,_=ks91(th); Lv=psi(th)*E
        C=abs(Lt-ls)/(ls+Lv)
        Cth=crumey(ls+Lv, A)
        row.append(f"{th}deg C={C:.3f} Cth={Cth:.4f} ratio={C/Cth:.0f}")
    print(d, "m:", "; ".join(row))
# --- refraction flattening ---
def sae(h): # true alt deg -> refraction arcmin
    return 1.02/math.tan(math.radians(h+10.3/(h+5.11)))
def ben(ha): # apparent alt -> arcmin
    return 1/math.tan(math.radians(ha+7.31/(ha+4.4)))
D=32.0 # arcmin
for app_low in [0.0, 1.0, 2.0, 5.0]:
    # lower limb apparent alt app_low; true lower = app_low - R(app_low)
    tl = app_low - ben(app_low)/60
    tu = tl + D/60
    au = tu + sae(tu)/60
    vert=(au-app_low)*60
    print(f"lower limb apparent {app_low}deg: R_low={ben(app_low):.1f}' vertical diam={vert:.1f}' ratio={vert/D:.3f}")
# --- limb darkening ---
for lam in [0.43,0.45,0.49,0.55,0.56,0.63,0.65]:
    print("HM98 alpha", lam, round(-0.023+0.292/lam,3))
a=-0.023+0.292/0.55
# best linear-law u fitting mu^a with flux weighting (mu dmu over r)
import numpy as np
mu=np.linspace(0,1,10001); w=mu  # area weight on disc: r dr = mu dmu
y=mu**a
# minimize sum w (1-u(1-mu) - y)^2 -> u = sum w (1-mu)(1-y)/sum w (1-mu)^2
u=np.sum(w*(1-mu)*(1-y))/np.sum(w*(1-mu)**2)
print("linear-law u best fit to mu^%.3f:"%a, round(u,3))
print("mean disc intensity mu^a:", 2/(a+2), " Allen 0.3+0.93mu-0.23mu^2:", 2*(0.3/2+0.93/3-0.23/4))
# sun half angle / Er
print("after-image threshold Ho2011 for sun omega=0.0094:", 3.59e-5/0.0094**1.77, "W/cm2; sun Er=8")
