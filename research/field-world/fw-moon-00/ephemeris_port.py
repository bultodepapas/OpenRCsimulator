# FW-MOON-00: Python port of app/render/world/ephemeris.gd (Schlyter moon, NOAA sun, Bennett refraction,
# topocentric parallax) for offline surveys only. The GDScript module stays authoritative; keep both in step.
import math
r=math.radians; d2=math.degrees
def jd(y,m,d,h):
    if m<=2: y-=1; m+=12
    a=math.floor(y/100); b=2-a+math.floor(a/4)
    return math.floor(365.25*(y+4716))+math.floor(30.6001*(m+1))+d+b-1524.5+h/24
def gmst(j):
    t=(j-2451545)/36525
    return (280.46061837+360.98564736629*(j-2451545)+t*t*(0.000387933-t/38710000))%360
def sun(j):
    t=(j-2451545)/36525
    l0=(280.46646+t*(36000.76983+t*0.0003032))%360
    m=r(357.52911+t*(35999.05029-0.0001537*t))
    c=math.sin(m)*(1.914602-t*(0.004817+0.000014*t))+math.sin(2*m)*(0.019993-0.000101*t)+math.sin(3*m)*0.000289
    om=125.04-1934.136*t
    lam=r(l0+c-0.00569-0.00478*math.sin(r(om)))
    sec=21.448-t*(46.815+t*(0.00059-t*0.001813))
    eps=r(23+(26+sec/60)/60+0.00256*math.cos(r(om)))
    return d2(math.atan2(math.cos(eps)*math.sin(lam),math.cos(lam)))%360, d2(math.asin(math.sin(eps)*math.sin(lam))), d2(lam)%360
def ecl2eq(lon,lat,ob):
    l,b,e=r(lon),r(lat),r(ob)
    ra=math.atan2(math.sin(l)*math.cos(e)-math.tan(b)*math.sin(e),math.cos(l))
    dec=math.asin(math.sin(b)*math.cos(e)+math.cos(b)*math.sin(e)*math.sin(l))
    return d2(ra)%360,d2(dec)
def moon(j):
    d=j-2451543.5
    n=125.1228-0.0529538083*d; inc=5.1454; w=318.0634+0.1643573223*d; a=60.2666; e=0.0549
    mm=(115.3654+13.0649929509*d)%360; ms=(356.0470+0.9856002585*d)%360; ws=282.9404+4.70935e-5*d
    E=mm+d2(e*math.sin(r(mm))*(1+e*math.cos(r(mm))))
    for _ in range(8):
        s=(E-d2(e*math.sin(r(E)))-mm)/(1-e*math.cos(r(E))); E-=s
    xv=a*(math.cos(r(E))-e); yv=a*math.sqrt(1-e*e)*math.sin(r(E))
    v=math.atan2(yv,xv); rr=math.hypot(xv,yv)
    nr=r(n); vw=v+r(w); ir=r(inc)
    xh=rr*(math.cos(nr)*math.cos(vw)-math.sin(nr)*math.sin(vw)*math.cos(ir))
    yh=rr*(math.sin(nr)*math.cos(vw)+math.cos(nr)*math.sin(vw)*math.cos(ir))
    zh=rr*math.sin(vw)*math.sin(ir)
    lon=d2(math.atan2(yh,xh)); lat=d2(math.atan2(zh,math.hypot(xh,yh)))
    ls=ms+ws; lm=mm+w+n; D=r(lm-ls); F=r(lm-n); M=r(mm); S=r(ms)
    lon+=(-1.274*math.sin(M-2*D)+0.658*math.sin(2*D)-0.186*math.sin(S)-0.059*math.sin(2*M-2*D)-0.057*math.sin(M-2*D+S)
          +0.053*math.sin(M+2*D)+0.046*math.sin(2*D-S)+0.041*math.sin(M-S)-0.035*math.sin(D)-0.031*math.sin(M+S)
          -0.015*math.sin(2*F-2*D)+0.011*math.sin(M-4*D))
    lat+=(-0.173*math.sin(F-2*D)-0.055*math.sin(M-F-2*D)-0.046*math.sin(M+F-2*D)+0.033*math.sin(F+2*D)+0.017*math.sin(2*M+F))
    rr+=-0.58*math.cos(M-2*D)-0.46*math.cos(2*D)
    ra,dec=ecl2eq(lon,lat,23.4393-3.563e-7*d)
    return ra,dec,lon%360,lat,rr
def horiz(ra,dec,lat,lon,j):
    h=r(gmst(j)+lon-ra); dc=r(dec); la=r(lat)
    el=math.asin(math.sin(la)*math.sin(dc)+math.cos(la)*math.cos(dc)*math.cos(h))
    az=math.atan2(-math.cos(dc)*math.sin(h),math.sin(dc)*math.cos(la)-math.cos(dc)*math.sin(la)*math.cos(h))
    return d2(az)%360,d2(el)
def refr(el):
    return 0 if el<-1 else 1.02/math.tan(r(el+10.3/(el+5.11)))/60
def sky(y,mo,da,hour,utc,lat=40.0,lon=-3.7):
    j=jd(y,mo,da,hour-utc)
    sra,sdec,slon=sun(j); saz,sel=horiz(sra,sdec,lat,lon,j); sel+=refr(sel)
    mra,mdec,mlon,mlat,mr=moon(j); maz,mel=horiz(mra,mdec,lat,lon,j)
    mel-=d2(math.asin(math.cos(r(mel))/mr)); mel+=refr(mel)
    el=math.acos(math.cos(r(slon-mlon))*math.cos(r(mlat)))
    illum=(1+math.cos(math.pi-el))/2
    waxing=((mlon-slon)%360)<180
    return dict(saz=saz,sel=sel,maz=maz,mel=mel,illum=illum,waxing=waxing,dist=mr)
