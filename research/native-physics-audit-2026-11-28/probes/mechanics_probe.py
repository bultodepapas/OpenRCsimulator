#!/usr/bin/env python3
"""Read-only audit of OpenRC contact laws. Pass the checkout as the only argument.

Stock vehicle data is translated into a temporary C++ initializer exactly as in
VehicleData._make_model. The C++ includes the production kernel unmodified. The
scenery and water outputs below are independent formula/source-path oracles.
"""
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
HERE = Path(__file__).resolve().parent


def model_header():
    values = {k: v['value'] for k, v in json.loads((ROOT/'app/data/vehicles/ground/mt8_bisonte.json').read_text())['parameters'].items()}
    cg_x = values.pop('cg_forward_from_datum_m'); cg_y = values.pop('cg_right_from_datum_m'); cg_z = values['cg_height_above_chassis_datum_m']
    values['corner_x_m'] = [v-cg_x for v in values.pop('corner_x_datum_frd_m')]
    values['corner_y_m'] = [v-cg_y for v in values.pop('corner_y_datum_frd_m')]
    values.pop('corner_z_datum_frd_m')
    centers = values.pop('hull_probe_centers_datum_frd_m')
    values['hull_probe_centers_frd_m'] = [[centers[i]-cg_x,centers[i+1]-cg_y,centers[i+2]+cg_z] for i in range(0,len(centers),3)]
    def literal(v):
        return '{'+','.join(literal(w) for w in v)+'}' if isinstance(v,list) else repr(v)
    return '\n'.join(['inline openrc::ground_vehicle::Model stock_model() {','openrc::ground_vehicle::Model m;'] + [f'm.{k}={literal(v)};' for k,v in values.items()] + ['return m;','}'])


def native_checks():
    inc = ROOT/'research/rc-monster-truck/native/src'
    with tempfile.TemporaryDirectory() as folder:
        d=Path(folder)
        (d/'stock_model.hpp').write_text(model_header())
        compiler='g++'
        print(subprocess.check_output([compiler,'--version'],text=True).splitlines()[0],flush=True)
        subprocess.run([compiler,'-std=c++17','-O2','-fno-fast-math','-ffp-contract=off','-I',str(inc),'-I',str(d),str(HERE/'mechanics_probe.cpp'),'-o',str(d/'probe')],check=True)
        subprocess.run([str(d/'probe')],check=True)


def box():
    raw=json.loads((ROOT/'app/data/aircraft/jensen_ugly_stik_60.json').read_text())
    parts=raw['inventory']; mass=sum(p['mass']['value'] for p in parts)
    cg=[sum(p['mass']['value']*p['position']['value'][i] for p in parts)/mass for i in range(3)]
    hull=[(cg[0]-x,y-cg[1],cg[2]-z) for x,y,z in raw['crash_hull']['value']]
    radius=max(math.hypot(*p) for p in hull)
    def pad(degrees): return 1e-9+radius*(1-math.cos(math.radians(degrees)/2))
    def case(id,roll,clearance,travel):
        # Large flat box face; roll about the face normal keeps each ordinate x exact.
        # Every probe remains inside both transverse slabs so only the entry slab varies.
        front=max(p[0] for p in hull)
        hits=[];oracle=[]
        for name,(x,_,_) in zip(raw['crash_hull_ids'],hull):
            gap=(front-x)+clearance
            if gap>0 and gap<travel: oracle.append((name,gap/travel))
            # Exact production inside/same-face branches, reduced to this geometry.
            margin=pad(roll)
            if gap>margin and gap-margin < travel: hits.append((name,(gap-margin)/travel))
            elif 0 <= margin-gap<=1e-10 and travel>1e-12: hits.append((name,0))
        print('box',id,'points',len(hull),'max_radius_m',radius,'padding_m',pad(roll),'initial_gap_m',clearance,'true',oracle,'source_signature',hits)
        return oracle,hits
    assert len(hull)==26
    orc,h=case('roll_into_face',1.5,.000020,.01);assert len(orc)==1 and not h
    _,h=case('zero_roll',0,.000020,.01);assert len(h)==1
    _,h=case('beyond_pad',1.5,.001,.01);assert len(h)==1
    _,h=case('outward',1.5,.000020,-.01);assert not h
    joint=.5*(pad(1.48)+pad(1.50))
    orc,h=case('previous_tick',1.48,.01+joint,.01);assert not orc and not h
    orc,h=case('next_tick',1.50,joint,.01);assert len(orc)==1 and not h


def capsule():
    # New dimensions and trajectories. Inside both cylinder endplanes; exact signed
    # distance to the exterior equals r-R throughout. Only the full-sphere equation changes sign.
    R=.32; L=.64
    for sign in (-1.,1.):
        r0,r1=.26,.25; z0,z1=sign*.44,sign*.46
        x=r0; z=z0-sign*L; dx=r1-r0; dz=z1-z0; Rp=R+1e-9
        a=dx*dx+dz*dz; b=2*(x*dx+z*dz); c=x*x+z*z-Rp*Rp
        t=(-b-math.sqrt(b*b-4*a*c))/(2*a)
        assert 0<t<1 and b+2*a*t<-1e-12
        true_gap=x+dx*t-R
        print('hidden_cap','sign',sign,'fraction',t,'exterior_gap_m',true_gap,'true_start_m',r0-R,'true_finish_m',r1-R,'inward_mps',-dx*240)
        assert true_gap<-.06 and max(abs(z0),abs(z1))<L


def water():
    raw=json.loads((ROOT/'app/data/fields/lake.json').read_text()); waves=raw['waves']['components']; dt=1/240
    # Fixed scene location, from the independent solution of the two wave crest phase equations.
    n,e=106.6487798441,128.0210815711
    speed=57.6; heading=math.radians(-120); vn=speed*math.cos(heading); ve=speed*math.sin(heading); tmid=dt/2
    def g(f):
        t=f*dt; north=n+(t-tmid)*vn; east=e+(t-tmid)*ve
        elevation=sum(w['amplitude_m']*math.sin(math.tau*(north*math.cos(w['heading_rad'])+east*math.sin(w['heading_rad']))/w['wavelength_m']-math.tau*t/w['period_s']+w['phase_rad']) for w in waves)
        return .3951-raw['water_level_down_m']+elevation
    steps=max([1,math.ceil(speed*dt/.25)]+[math.ceil(speed*dt/(w['wavelength_m']/8)) for w in waves]+[math.ceil(dt/(w['period_s']/8)) for w in waves]); lo,hi=0,.5
    for _ in range(70):
        mid=(lo+hi)*.5
        if g(mid)>0:hi=mid
        else:lo=mid
    print('water','subdivisions',steps,'start_middle_end_penetration_m',[g(i) for i in (0,.5,1)],'first_root_fraction',hi)
    assert steps==1 and g(0)<-1e-7 and g(.5)>9.9e-5 and g(1)<-1e-7 and 0<hi<.5


if __name__=='__main__':
    native_checks(); box(); capsule(); water()
