#!/usr/bin/env python3
"""Bounded component audit of the fixed-wing native headers, no engine or repository writes.

Usage: python aerospace_probe.py [OpenRCsimulator checkout]
Linux C++17 compiler, procfs and Python 3 are required. The compiler writes the
executable to an anonymous memory file. Output is a component result, not an ORFL.
"""

import json
import math
import os
from pathlib import Path
import subprocess
import sys


root = Path(sys.argv[1] if len(sys.argv) == 2 else Path(__file__).resolve().parents[3]).resolve()
aircraft_dir = root / 'app/data/aircraft'
extra = json.loads((aircraft_dir / 'gp_extra_300s_60.json').read_text())
stik = json.loads((aircraft_dir / 'jensen_ugly_stik_60.json').read_text())


def num(value):
    return repr(float(value))


def array_fill(name, values):
    return '\n'.join(f'{name}[{i}] = {num(value)};' for i, value in enumerate(values))


def val(zone, key):
    return zone[key]['value']


def wing_centroids(reference):
    half = val(reference, 'wing_span') / 2
    root_chord, tip_chord = val(reference, 'root_chord'), val(reference, 'tip_chord')
    slope = (tip_chord - root_chord) / half
    area = half * (root_chord + tip_chord) / 2
    edges = [(math.sqrt(root_chord**2 + 2*slope*area*i/3) - root_chord)/slope for i in range(4)]
    right = [(0.5 * root_chord * (y2**2-y1**2) + slope * (y2**3-y1**3)/3)/(area/3) for y1, y2 in zip(edges, edges[1:])]
    return [-y for y in reversed(right)] + right


def extra_wake_input():
    a = extra['aero']; sur = a['surfaces']; ref = extra['reference']; prop = extra['propulsion']['propeller']; wash = prop['slipstream']
    mass = sum(val(item, 'mass') for item in extra['inventory'])
    cg = [sum(val(item, 'mass') * val(item, 'position')[i] for item in extra['inventory'])/mass for i in range(3)]
    f = [f'm.S={num(val(ref,"wing_area"))}; m.b={num(val(ref,"wing_span"))}; m.c={num(val(ref,"mean_chord"))};',array_fill('m.cg',cg),array_fill('m.arp',val(ref,'aero_reference_point'))]
    f.append('m.ys = {' + ', '.join(map(num, wing_centroids(ref))) + '};')
    f.append(f'm.wing_aileron_effectiveness={num(val(sur,"wing_aileron_effectiveness"))};')
    f.append('m.ground_effect=true;')
    for key in ['induced_coefficient','induced_exponent','downwash_coefficient','downwash_exponent']:
        f.append(f'm.ge_{key} = {num(val(a["ground_effect"],key))};')
    for key in ['tail_CD0','tail_k','tail_CD90','tail_local_limit','tail_stall_end']:
        v = val(sur, key)
        if sur[key]['unit'] == 'deg': v = math.radians(v)
        f.append(f'm.{key} = {num(v)};')
    for tailname in ['horizontal','vertical']:
        tail = sur[tailname]; name = 'm.' + tailname
        f += [f'{name}.present = true;',array_fill(name+'.position',val(tail,'position'))]
        for key in ['area','lift_slope','control_effectiveness','incidence']:
            f.append(f'{name}.{key} = {num(val(tail,key))};')
    h=sur['horizontal']; g=val(h,'downwash_gradient'); share=val(h,'area')/val(ref,'wing_area') * val(h,'lift_slope')
    target=val(a['coefficients'],'CLa')-share
    wing_cl0=val(a['coefficients'],'CL0')-share*val(h,'incidence')
    f += ['m.horizontal.free=true;',f'm.horizontal.free_slope={num(val(h,"lift_slope")/(1-g))};',f'm.horizontal.elevator_tau={num(val(h,"control_effectiveness")*(1-g))};',f'm.horizontal.downwash_per_cl={num(g/target)};',f'm.horizontal.free_incidence={num((1-g)*val(h,"incidence")+g/target*wing_cl0)};']
    down, right = map(math.radians,val(prop,'thrust_angles'))
    axis=[math.cos(down)*math.cos(right), math.cos(down)*math.sin(right),math.sin(down)]
    f += ['prop.has_axis=true;',array_fill('prop.axis',axis),f'prop.diameter={num(val(prop,"diameter"))};']
    f.append('prop.normal_force = {' + ','.join(num(x) for row in val(prop,'normal_force') for x in row) + '};')
    f += ['ss.enabled=true; ss.segmented=true;',array_fill('ss.hub',val(wash,'hub')),array_fill('ss.wash_factor',val(wash,'wash_factor'))]
    for dest, key in [('swirl_factor','swirl_factor'),('vertical_drift','vertical_drift'),('sidewash_gain','propeller_sidewash')]:
        f.append(f'ss.{dest}={num(val(wash,key))};')
    for i, piece in enumerate(wash['pieces']):
        name=f'p{i}'; f += [f'nk::WakePiece {name};',f'{name}.vertical={str(piece["surface"] == "vertical").lower()};',f'{name}.span={num(val(piece,"span"))};',f'{name}.area={num(val(piece,"area"))};',array_fill(name+'.root',val(piece,'root')),array_fill(name+'.span_dir',val(piece,'span_dir')),array_fill(name+'.chords',val(piece,'chords')),f'ss.pieces.push_back({name});']
    return '\n'.join(f)


def stik_coeffs():
    a, ref = stik['aero'], stik['reference']
    return '\n'.join([f'm.{key}={num(val(a["coefficients"],key))};' for key in ['CLa','CL0','CD0','CL_minD','k_induced','Cm0','Cma']]+[f'm.{dest}={num(val(ref,key))};' for dest,key in [('c','mean_chord'),('S','wing_area'),('b','wing_span')]])


cpp = r'''
#include <cstdio>
#include <cmath>
#include <vector>
#include "nk_wake_spatial_aero.hpp"
#include "nk_wake.hpp"
using namespace nk;
int main() {
    const R rho=1.225; R calm[3]={}; Deflections d;
    {
        // These are stock Extra geometry, tail, GE and wake properties with a prescribed
        // diagnostic stage state and T/Q. No complete engine, dynamics or flight is run.
        AeroModel m; PropModel prop; WakeModel ss;
        EXTRA_INPUT
        R state[13] = {}; state[6]=1; const double alpha=3*kPi/180;
        state[3]=15*std::cos(alpha); state[5]=15*std::sin(alpha);
        const Air air=air_compute(state,calm,rho);
        for (double hb : {0.1,0.25,2.01}) {
            state[2]=-hb*m.b+(m.arp[2]-m.cg[2]);
            std::vector<R> ge; ge_factors(state,m,0,ge); const R factor=ge.empty()?R(1):ge.back();
            const R free_wake=6;
            const auto nominal=wake_loads(state,air,d,m,prop,ss,9000,rho,16,.30,free_wake);
            const auto common=wake_loads(state,air,d,m,prop,ss,9000,rho,16,.30,free_wake*factor);
            const auto off=wake_loads(state,air,d,m,prop,ss,0,rho,0,0,free_wake);
            std::printf("AERO-01 Extra h/b %.3f sigma %.9f installed wake-only delta Fz %.9f My %.9f common-context Fz %.9f My %.9f disagreement Fz %.9f N My %.9f Nm off My %.9f\n",hb,factor.v,nominal[2].v,nominal[4].v,common[2].v,common[4].v,nominal[2].v-common[2].v,nominal[4].v-common[4].v,off[4].v);
        }
        // At fixed body/surface flow and held wing wake only the outer wake is powered.
        state[3]=0;state[5]=0; const auto still=air_compute(state,calm,rho);
        Deflections pos,neg; pos.aileron_right=.25;pos.aileron_left=-.25;neg.aileron_right=-.25;neg.aileron_left=.25;
        auto wp=wake_loads(state,still,pos,m,prop,ss,9000,rho,16,.30,0);auto wn=wake_loads(state,still,neg,m,prop,ss,9000,rho,16,.30,0);
        std::printf("Coverage only: Extra tail-wash Mx ±aileron %.9f %.9f delta %.9f Nm\n",wp[3].v,wn[3].v,wp[3].v-wn[3].v);
        // Effective angle is read before the induced-flow matrix. Only the station
        // kinematics are tested. These four thresholds are immaterial to the angles.
        m.a1=.22;m.a2=.32;m.n1=.22;m.n2=.32;
        state[3]=15*std::cos(10*kPi/180);state[5]=15*std::sin(10*kPi/180);
        const auto forward=air_compute(state,calm,rho); Deflections roll;
        roll.aileron_right=15*kPi/180;roll.aileron_left=-15*kPi/180;
        WingFlow neutral,offset;wing_flow(state,forward,d,m,neutral);wing_flow(state,forward,roll,m,offset);
        for(int i=3;i<6;++i)std::printf("AERO-04 Extra strip centre %.9f m: neutral %.9f deg, deflected %.9f deg, direct shift %.9f deg\n",m.ys[i].v,neutral.angles[i].v*180/kPi,offset.angles[i].v*180/kPi,(offset.angles[i].v-neutral.angles[i].v)*180/kPi);
    }
    {
        // Manufactured, level, six equal-area attached sections. No coupling map, twist or propeller.
        AeroModel m; m.S=.5;m.b=1.5;m.c=.3;m.CLa=4.5;m.CD0=.025;m.k_induced=.06;m.CD90=1.2;
        m.ys={-.625,-.375,-.125,.125,.375,.625};m.a1=.22;m.a2=.32;m.n1=.22;m.n2=.32;m.b1=.25;m.b2=.45;
        m.attached_limit=.14;m.tail_local_limit=.2;m.tail_stall_end=.42;m.tail_CD0=.012;m.tail_k=.08;m.tail_CD90=1.2;
        m.horizontal.present=true;m.horizontal.free=true;m.horizontal.free_slope=3.5;m.horizontal.downwash_per_cl=.10;
        m.horizontal.position[0]=.75;m.horizontal.area=.10;m.vertical.present=true;
        R state[13]={};state[3]=15; state[6]=1; const Air air=air_compute(state,calm,rho);
        R deltas[24]={};for(int i=0;i<6;++i)deltas[3*i+2]=1;
        const auto spatial=spatial_aero_loads(state,air,d,m,rho,deltas,24,0,kNan,true);
        std::vector<R> ge;const R source_now=wing_lift_coefficient_with(state,air,d,m,ge,true);
        WingFlow section;wing_flow(state,air,d,m,section,deltas);
        double direct=0;for(int i=0;i<6;++i)direct+=section.speeds[i].v*m.CLa.v*section.angles[i].v/6;
        double analytic=std::hypot(15.,1.)*4.5*std::atan2(1.,15.);
        const auto new_lag=[&](double source){double w=0;for(int tick=0;tick<60;++tick)w=source+(w-source)*std::exp(-15./(.75*240));return w;};
        std::printf("AERO-02 manufactured spatial accepted %d direct delta Fz %.9f N held wake %.9f m/s installed pre-step driver %.9f analytic spatial source %.9f native strip source %.9f after 60x240Hz (installed/analytic) %.9f %.9f m/s\n",spatial.ok,spatial.delta[2].v,spatial.held_wake.v,source_now.v,analytic,direct,new_lag(source_now.v),new_lag(analytic));
        if (!spatial.ok || std::abs(analytic-direct)>1e-12 || std::abs(source_now.v)>1e-12 || std::abs(spatial.delta[2].v)<1) return 2;
    }
    {
        // Exact stock Stik global attached coefficients, moment shown about the ARP.
        AeroModel m; STIK_INPUT
        m.a1=.22; m.a2=.32; m.n1=.22; m.n2=.32;m.b1=.25;m.b2=.45;
        for(double speed:{9.,15.,25.}){
            R state[13]={};const double alpha=2*kPi/180;state[6]=1;state[3]=speed*std::cos(alpha);state[5]=speed*std::sin(alpha);
            const Air air=air_compute(state,calm,rho);std::vector<R> ge;
            const auto l=global_loads(state,air,d,m,rho,kNan,ge); const double qS=air.qbar.v*m.S.v;
            const double CL=(l[0].v*std::sin(alpha)-l[2].v*std::cos(alpha))/qS;
            const double CD=-(l[0].v*std::cos(alpha)+l[2].v*std::sin(alpha))/qS;
            std::printf("AERO-03 Stik 2deg V %.1f Re %.0f Mach %.4f CL %.12f CD %.12f CM-ARP %.12f\n",speed,rho.v*speed*m.c.v/1.7894e-5,speed/340.3,CL,CD,l[4].v/(qS*m.c.v));
        }
    }
}
'''.replace('EXTRA_INPUT',extra_wake_input()).replace('STIK_INPUT',stik_coeffs())

with os.fdopen(os.memfd_create('openrc-aerodynamic-component-audit'),'w+b') as anonymous:
    fd=anonymous.fileno(); path=f'/proc/self/fd/{fd}'
    subprocess.run(['c++','-std=c++17','-O2','-fno-fast-math','-ffp-contract=off', '-I',str(root/'research/native-kernel/src'),'-x','c++','-','-o',path], input=cpp,text=True,pass_fds=(fd,),check=True)
    subprocess.run([path],pass_fds=(fd,),check=True)
