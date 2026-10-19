"""FUEL-00 audit: hydrostatic feed factor k = sqrt((p+dh)/(p+dh_needled)) as in fuel_feed.gd.

Usage: python3 -I glow_feed.py
Inputs copied from the generated Stik glow data on 2026-10-19 (profile density 856.92 kg/m3, CG 0.1209 m,
tank box [-0.1,0,0] size 0.09x0.05x0.05 m, carburetor 2T [-0.24,0,0.02] / 4T [-0.20,0,0.045],
drive pressures 2T 1.5/6 kPa, 4T 1/4 kPa, all estimated). Rotational terms are NOT in the runtime law;
the last lines only size them.
"""
import math
rho=856.92; g=9.80665
cg=[0.1209,0,0]
tank=[cg[0]-(-0.1),0,cg[2]-0]; size=[0.09,0.05,0.05]
def head(geff,fill,carb):
    n=math.sqrt(sum(x*x for x in geff)); d=[x/n for x in geff]
    depth=sum(abs(d[i])*size[i] for i in range(3))
    surf=sum(d[i]*tank[i] for i in range(3))+(0.5-fill)*depth
    return rho*n*(sum(d[i]*carb[i] for i in range(3))-surf)
for fam,carb_le,idle,wot in [('2T',[-0.24,0,0.02],1500,6000),('4T',[-0.20,0,0.045],1000,4000)]:
    carb=[cg[0]-carb_le[0],carb_le[1]-cg[1],cg[2]-carb_le[2]]
    hn=head([0,0,g],1.0,carb)
    for label,geff,fill in [('level 1g full',[0,0,g],1.0),('level 1g empty',[0,0,g],0.0),('level 1g half',[0,0,g],0.5),('vertical upline 1g, 10%',[-g,0,0.0001],0.1),('3g pull, 10%',[0,0,3*g],0.1)]:
        h=head(geff,fill,carb)
        ki=math.sqrt(max(0,idle+h)/(idle+hn)); kw=math.sqrt(max(0,wot+h)/(wot+hn))
        print(fam,label,'head=%.0f Pa needled=%.0f Pa k_idle=%.3f k_wot=%.3f'%(h,hn,ki,kw))
# rotational term magnitude at tank: q=3 rad/s pitch
r=0.2209
for q in (2,3,5):
    print('centripetal at tank q=%g rad/s: %.2f m/s^2 (%.0f%% g)'%(q,q*q*r,100*q*q*r/g))
