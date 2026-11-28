// Native rotorcraft component audit. X-Cell inputs are the generated 8d4169f8 profile.
// Compile with c++ -std=c++17 -O2 -ffp-contract=off -I research/native-kernel/src
// This file drives the real headers. No Godot session, graphics or hardware is involved.
#include <cassert>
#include <cmath>
#include <iomanip>
#include <iostream>
#include "nk_helicopter_stage.hpp"
using namespace nk;

int main() {
    HeliMainRotorModel m;
    m.rho_kg_m3=1.225; m.rotor_radius_m=.775; m.blade_lift_curve_slope_per_rad=5.5;
    m.solidity=2*.058/(kPi*.775); m.blade_section_cd0=.024; m.thrust_coefficient_max=.0055;
    m.gamma_flybar=.8; m.flapback_k_mu=.2; m.omega_nominal_rad_s=167.;
    m.cyclic_longitudinal_gain_nominal_rad_per_rad=4.2; m.cyclic_lateral_gain_nominal_rad_per_rad=4.2;
    m.hub_spring_stiffness_nm_per_rad=54.; m.rotation_sense=1.; m.hub_z_m=-.235;
    HeliTailRotorModel tail;
    tail.rho_kg_m3=1.225; tail.tail_rotor_radius_m=.13; tail.blade_lift_curve_slope_per_rad=5.;
    tail.solidity=2*.029/(kPi*.13); tail.blade_section_cd0=.024; tail.thrust_coefficient_max=.05;
    tail.tail_to_main_speed_ratio=4.66; tail.hub_distance_aft_m=.91; tail.hub_height_above_cg_m=.08;
    tail.trim_collective_rad=.1; tail.wake_efficiency=.9; tail.rotation_sense=1.;
    tail.blockage_factor=1-3*.012/(4*kPi*.13*.13);
    tail.wake_gi=(.91-.775-.13)/.08; tail.wake_gf=(.91-.775+.13)/.08;
    HeliDriveModel drive{1.2,1800.,8.3,.9,167.,.08,.08,.001};
    const Vec3 zero{};
    const double weight=8.2*9.80665, rho=1.225, radius=.775, area=kPi*radius*radius;
    const double omega=167., tip=omega*radius, speed=15., mu=speed/tip;
    const double vh=std::sqrt(weight/(2*rho*area));
    // Closed form of vi*sqrt(U^2+vi^2)=vh^2, outside ground effect.
    const double vi=std::sqrt(2*std::pow(vh,4)/(speed*speed+std::hypot(speed*speed,2*vh*vh)));
    const double ct=weight/(rho*area*tip*tip);
    const double theta=(2*ct/(m.blade_lift_curve_slope_per_rad*m.solidity)+.5*vi/tip)/(1./3+.5*mu*mu);
    const double profile=rho*area*std::pow(tip,3)*m.blade_section_cd0*m.solidity*(1.+7./3*mu*mu)/8.0;
    std::cout<<std::fixed<<std::setprecision(10);
    std::cout<<"XCell W_N="<<weight<<" vh="<<vh<<" mu15="<<mu<<" vi="<<vi<<" theta="<<theta<<'\n';
    for (double deg : {-8.,0.,8.}) {
        const double a=deg*kPi/180;
        const double longitudinal=2.0*m.flapback_k_mu*(4*theta/3-vi/tip);
        const double cyclic=(longitudinal*mu-a)/m.cyclic_longitudinal_gain_nominal_rad_per_rad;
        assert(std::abs(cyclic)<=.06); // Authored cyclic travel.
        const auto r=heli_main_stage(m,{a,0,vi},omega,{speed,0,0},zero,theta,cyclic,0,.1,-1,1,0,-std::cos(a));
        assert(r.ok);
        const double shaft=omega*r.rotor.torque, body=speed*r.rotor.loads[0];
        std::cout<<"tilt_deg="<<deg<<" T_N="<<r.rotor.thrust<<" shaft_W="<<shaft<<" Tvi_W="<<weight*vi
                 <<" profile_W="<<profile<<" FdotU_W="<<body<<" residual_W="<<shaft-body-weight*vi-profile
                 <<" adot="<<r.derivative[0]<<" vidot="<<r.derivative[2]<<'\n';
    }
    for (double u : {-1e-8,0.,1e-8}) {
        const auto r=heli_main_rotor(m,omega,1.,{u,14,5},zero,.07,0,0,0,0);
        assert(r.ok);
        std::cout<<"lateral_u="<<u<<" v=14 w=5 adot="<<r.flap_a_rate<<'\n';
    }
    const double pole=20./(std::sqrt(2.)*radius);
    for (double head : {16.7,16.700001,pole*(1.+1e-6),omega}) {
        const auto r=heli_main_rotor(m,head,1.,{20,0,1},zero,.07,0,0,0,0);
        std::cout<<"crossflow20_head="<<head<<" ok="<<r.ok;
        if (r.ok) std::cout<<" adot_rad_s="<<r.flap_a_rate;
        std::cout<<'\n';
    }
    for (double x : {0.,.75,1.5,3.,4.}) {
        const auto g=heli_inflow_target(weight,rho,radius,0,x*vh,1.1,1,0);
        const auto f=heli_inflow_target(weight,rho,radius,0,x*vh,-1,1,0);
        assert(g.ok && f.ok);
        const double downward=f.velocity/std::hypot(x*vh,f.velocity);
        std::cout<<"ground_VoverVh="<<x<<" native_IGE_OGE="<<g.velocity/f.velocity
                 <<" wake_cos="<<downward<<" h_ray_over_R="<<1.1/downward<<'\n';
    }
    for (double down : {-1.,-1e-8,0.,1e-8,1.}) {
        const auto g=heli_main_stage(m,{0,0,vh},omega,zero,zero,.1,0,0,.1,1.1,1,0,down);
        assert(g.ok);
        std::cout<<"thrust_axis_down="<<down<<" ground_factor="<<g.inflow.ground_factor<<'\n';
    }
    for (double f : {0.,1.}) {
        for (double z : {-1.5,-.45,1.,-3.}) {
            const auto r=heli_inflow_normalized(z,0,f,1);
            assert(r.ok);
            std::cout<<"Johnson_f="<<f<<" z="<<z<<" vi_over_vh="<<r.ratio<<'\n';
        }
        for (double x : {.95-1e-9,.95+1e-9}) {
            const auto r=heli_inflow_normalized(-1.3,x,f,1);
            assert(r.ok);
            std::cout<<"M_seam_f="<<f<<" z=-1.3 x="<<x<<" vi_over_vh="<<r.ratio<<'\n';
        }
    }
    for (double x : {.75-1e-9,.75+1e-9}) {
        const auto r=heli_inflow_normalized(-1.428,x,0,1);
        assert(r.ok);
        std::cout<<"C_seam_f=0 z=-1.428 x="<<x<<" vi_over_vh="<<r.ratio<<'\n';
    }
    for (double head : {0.,5.,omega}) {
        for (double w : {-20.,0.,20.}) {
            const auto r=heli_main_rotor(m,head,1.,{0,0,w},zero,.05,0,0,0,0);
            const auto t=heli_tail_rotor(tail,head,1.,{0,0,w},zero,.1,omega);
            const auto d=heli_drive(drive,head,1.,true,0.);
            assert(r.ok && t.ok && d.ok);
            std::cout<<"windmill_omega="<<head<<" vz="<<w<<" T_N="<<r.thrust<<" Qmain_Nm="<<r.torque
                     <<" Qtail_Nm="<<t.torque<<" held_drive_Nm="<<d.net_torque<<'\n';
        }
    }
    const Vec3 w={.4,-.8,1.1}, moment={.35,.22,-.45}, b={0,.076*.05/4.66,.076};
    const std::array<R,6> I={.18,.34,.28,0,0,0}, inv={1/.18,1/.34,1/.28,0,0,0};
    const double J=.0798, s=130., torque=-.7;
    const auto c=heli_geared_coupling(w,moment,I,inv,b,J,s,torque,0);
    assert(c.ok);
    Vec3 grad=heli_inertia_mul(I,w);
    for (int i=0;i<3;++i) grad[i]+=b[i]*s;
    const double lhs=heli_dot3(grad,c.body_acceleration)+(heli_dot3(b,w)+J*s)*c.spin_acceleration;
    const double rhs=heli_dot3(w,moment)+s*torque;
    std::cout<<"geared_J="<<J<<" kinetic_W="<<lhs<<" external_work_W="<<rhs
             <<" residual_W="<<std::scientific<<lhs-rhs<<'\n';
}
