// Standalone audit of the production arithmetic headers. No GDExtension or Godot runtime is linked.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <vector>

#include "nk_pre_step.hpp"
#include "nk_liquid_mass.hpp"
#include "nk_tick.hpp"

using nk::R;
using V3 = std::array<double, 3>;

V3 add(V3 a, V3 b) { return {a[0]+b[0], a[1]+b[1], a[2]+b[2]}; }
V3 scale(V3 a, double b) { return {a[0]*b, a[1]*b, a[2]*b}; }
V3 cross(V3 a, V3 b) {
    return {a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]};
}
double magnitude(V3 a) { return std::hypot(a[0], a[1], a[2]); }
V3 vec(const R *a) { return {a[0].v, a[1].v, a[2].v}; }

// Unit rotation evaluated independently of nk_tick's body derivative.
V3 rotate(const R *q, V3 a) {
    const double norm = std::sqrt(q[0].v*q[0].v+q[1].v*q[1].v+q[2].v*q[2].v+q[3].v*q[3].v);
    const double w = q[0].v / norm;
    const V3 u = scale(vec(q+1), 1/norm);
    const V3 t = scale(cross(u, a), 2);
    return add(a, add(scale(t,w), cross(u,t)));
}
V3 inertia_times(const std::array<R,6>& j, V3 w) {
    return {j[0].v*w[0]+j[3].v*w[1]+j[4].v*w[2],j[3].v*w[0]+j[1].v*w[1]+j[5].v*w[2],
            j[4].v*w[0]+j[5].v*w[1]+j[2].v*w[2]};
}

// Ballistic free fall and rotation around a principal axis have closed-form solutions.
void ballistic(int hz) {
    std::array<R,13> s{}, next{};
    s[3]=7; s[4]=3; s[5]=-2; s[6]=1; s[10]=18;
    const double g=9.80665, duration=1;
    const R j[6]={1,1.25,1.5,0,0,0}, inv[6]={1,0.8,1/1.5,0,0,0}, zero[6]={};
    auto rhs=[&](const R *x,R, R *d) {
        nk::tick_rb_derivative(x,1,j,inv,zero,g,nullptr,d);
        return true;
    };
    nk::TickRk4Scratch work; work.size(s.size());
    for(int i=0;i<hz*duration;++i) {
        if(nk::tick_rk4_step_at(s.data(),s.size(),i/double(hz),1./hz,rhs,nullptr,next.data(),work)!=nk::TickStatus::Ok)
            throw std::runtime_error("ballistic RK4");
        s=next;
    }
    const auto velocity=rotate(s.data()+6,vec(s.data()+3));
    const double attitude_error=std::abs(2*std::atan2(s[7].v*std::cos(9.)-s[6].v*std::sin(9.),
                                                       s[6].v*std::cos(9.)+s[7].v*std::sin(9.)));
    const double qnorm=std::hypot(s[6].v,s[7].v);
    std::cout<<"ballistic "<<hz<<" "<<magnitude(add(vec(s.data()),{-7,-3,2-g/2}))<<" "
             <<magnitude(add(velocity,{-7,-3,2-g}))<<" "<<attitude_error<<" "<<std::abs(qnorm-1)<<"\n";
}

// For a distributed co-moving efflux the per-kilogram angular momentum about the world origin includes
// both r_tank x v_tank and the centroidal intrinsic angular momentum of the departing material.
void mass_flux(int hz, bool correct) {
    nk::LiquidMassModel mass;
    mass.reference_mass_kg=2.4;
    mass.reference_inertia={0.15,0.26,0.32,0.007,-0.004,0.005};
    const V3 c={0.29,-0.12,0.08}, dims={0.14,0.08,0.06};
    const double x=c[0],y=c[1],z=c[2];
    const V3 intrinsic={(dims[1]*dims[1]+dims[2]*dims[2])/12,
                        (dims[0]*dims[0]+dims[2]*dims[2])/12,(dims[0]*dims[0]+dims[1]*dims[1])/12};
    nk::LiquidMassResource tank; tank.reference_kg=0.4; tank.capacity_kg=0.4;
    tank.center={x,y,z};
    tank.tensor_per_kg={intrinsic[0]+y*y+z*z,intrinsic[1]+x*x+z*z,intrinsic[2]+x*x+y*y,-x*y,-x*z,-y*z};
    mass.resources={tank};
    std::array<R,20> s{}, next{};
    s[3]=4;s[4]=1;s[5]=-0.5;s[6]=1;s[10]=4;s[11]=5;s[12]=-3;s[13]=0.4;
    const double burn=0.04; const int duration=6;
    auto total=[&](const R *state) {
        const auto m=nk::liquid_mass_evaluate(mass,state+13,1);
        if(!m.ok) throw std::runtime_error("mass sample");
        const V3 cg=vec(m.cg.data()), w=vec(state+10);
        const V3 p=scale(rotate(state+6,add(vec(state+3),cross(w,cg))),m.mass_kg.v);
        const V3 world_cg=add(vec(state),rotate(state+6,cg));
        const V3 h=add(cross(world_cg,p),rotate(state+6,inertia_times(m.inertia,w)));
        return std::array<V3,2>{add(p,vec(state+14)),add(h,vec(state+17))};
    };
    auto rhs=[&](const R *a,R, R* d) {
        const auto m=nk::liquid_mass_evaluate(mass,a+13,1);
        if(!m.ok) return false;
        const R zero[6]={};
        if(correct) {
            const auto v=nk::liquid_fixed_datum_derivative(a,m,zero,zero,0,zero);
            std::copy(v.begin(),v.end(),d);
        } else {
            nk::tick_rb_derivative(a,m.mass_kg,m.inertia.data(),m.inverse.data(),zero,0,nullptr,d);
        }
        const V3 w=vec(a+10);
        const V3 v_tank=rotate(a+6,add(vec(a+3),cross(w,c)));
        const V3 x_tank=add(vec(a),rotate(a+6,c));
        const V3 h_intrinsic={intrinsic[0]*w[0], intrinsic[1]*w[1], intrinsic[2]*w[2]};
        const V3 h_tank=add(cross(x_tank,v_tank),rotate(a+6,h_intrinsic));
        d[13]=-burn;
        for(int j=0;j<3;++j){d[14+j]=burn*v_tank[j];d[17+j]=burn*h_tank[j];}
        return true;
    };
    const auto start=total(s.data());
    nk::TickRk4Scratch work;work.size(s.size());
    for(int i=0;i<duration*hz;++i) {
        if(nk::tick_rk4_step_at(s.data(),s.size(),i/double(hz),1./hz,rhs,nullptr,next.data(),work)!=nk::TickStatus::Ok)
            throw std::runtime_error("mass flux RK4");
        s=next;
    }
    const auto stop=total(s.data());
    std::cout<<(correct ? "mass" : "mass_omit_datum")<<" "<<hz<<" "<<magnitude(add(stop[0],scale(start[0],-1)))
             <<" "<<magnitude(add(stop[1],scale(start[1],-1)))<<" "<<s[13].v<<"\n";
}

// At zero advance ratio the force element decouples from the airframe. This is a static thrust fixture.
void prop_impulse(int cadence,double idle,double target,double lag,double diameter,double ct,double cp) {
    nk::StageModel model;
    model.layout.aux_size=4; model.prop.diameter=diameter;
    model.prop.ct={0,ct,0.1,ct}; model.prop.cp={0,cp,0.1,cp};
    nk::PreStepModel plan; plan.ready=true; plan.rpm_lag_ready=true; plan.input_count=4;
    plan.idle_rpm=idle;plan.max_rpm=target;plan.rpm_lag=lag;plan.servo_rate=1;
    nk::PreStepScratch work; nk::PreStepEngine host_libm={std::exp,std::log,std::sin,std::cos};
    const R inflow[3]={0,0,0}; const double control[4]={0,0,0,1};
    std::array<double,13> body{}; body[6]=1;
    std::vector<double> aux={idle,0,0,0},out;
    nk::PreStepInput in;
    in.state=body.data();in.state_size=13;in.inputs=control;in.input_size=4;in.aux_size=4;
    in.dt=1./cadence;in.engine_running=true;
    const double rho=1.225, duration=0.25; const int intervals=static_cast<int>(duration*cadence);
    const auto force=[&](double rpm){return nk::prop_thrust_torque(inflow,rpm,model.prop,rho)[0].v;};
    double hold=0,simpson=0,first=0; int64_t rng=0;
    std::vector<double> held_force;
    for(int i=0;i<intervals;++i) {
        in.aux=aux.data(); in.time_now=i/double(cadence);
        if(!nk::pre_step(model,plan,in,host_libm,work,out,rng))throw std::runtime_error("pre_step");
        const double a=aux[0], b=out[0], middle=target+(a-target)*std::exp(-0.5*in.dt.v/lag);
        hold+=in.dt.v*force(b);
        held_force.push_back(force(b));
        simpson+=in.dt.v/6.*(force(a)+4.*force(middle)+force(b));
        if(i==0)first=hold;
        aux.swap(out);
    }
    std::cout<<"prop "<<cadence<<" "<<hold<<" "<<simpson<<" "<<first<<" "<<aux[0]<<"\n";
    if(cadence==240) {
        // The actual 240-Hz RPM handoff is immutable here. Integrate each constant load over its exact
        // overlap with each plant step. A 120-Hz macro-step spans two input discontinuities at most.
        for(int plant_hz:{120,240,480}) {
            double impulse=0;
            for(int j=0;j<static_cast<int>(duration*plant_hz);++j) {
                for(int k=0;k<intervals;++k) {
                    const double a=std::max(j/double(plant_hz),k/double(cadence));
                    const double b=std::min((j+1)/double(plant_hz),(k+1)/double(cadence));
                    if(b>a)impulse+=(b-a)*held_force[k];
                }
            }
            std::cout<<"fixed_hold "<<plant_hz<<" "<<impulse<<"\n";
        }
    }
}

// A manufactured scalar stop tests event accuracy separately from the narrow root bracket of the numerical map.
void event(int hz) {
    const int index=13; const int size=15; const double k=75.0, t_hit=.0137;
    std::vector<R> state(size), next, times;
    state[6]=1;state[index]=std::expm1(k*t_hit); state[14]=1;
    auto rhs=[&](const R* x,R,R* d){
        std::fill(d,d+size,0.);d[index]=x[14].v>0 ? -k*(1+x[index].v) : 0.; return true;
    };
    auto transition=[](const R* x,int n,int at,std::vector<R>& out){
        out.assign(x,x+n);out[at]=0.;out[14]=0.;return true;
    };
    nk::TickRk4Scratch work;work.size(size);
    double root=-1;
    for(int i=0;i<hz/4;++i) {
        bool ok=false;times.clear();
        if(nk::tick_event_advance(state.data(),size,i/double(hz),1./hz,rhs,nullptr,index,transition,true,
                                  ok,next,times,work)!=nk::TickStatus::Ok||!ok)throw std::runtime_error("event");
        state.swap(next);
        if(!times.empty()){root=times.front().v;break;}
    }
    if(root<0)throw std::runtime_error("absent root");
    std::cout<<"event "<<hz<<" "<<root<<" "<<root-t_hit<<"\n";
}

// Exact reduction of the centered, neutral, zero-added-mass analytical airship fixture to pure heave.
// The script's max(k*penetration,0) force is fed to the actual shared RK4 header.
double bounce(int hz,double stiffness,double mass,double contact_delay_s) {
    std::array<R,13> s{}, next{}; s[2]=-contact_delay_s;s[5]=1.;s[6]=1.;
    auto rhs=[&](const R* x,R,R*d){
        std::fill(d,d+13,0.);d[2]=x[5];
        d[5]=-stiffness*std::max(0.,x[2].v)/mass;return true;
    };
    nk::TickRk4Scratch work;work.size(13);
    for(int i=0;i<2*hz;++i) {
        if(nk::tick_rk4_step_at(s.data(),13,i/double(hz),1./hz,rhs,nullptr,next.data(),work)!=nk::TickStatus::Ok)
            throw std::runtime_error("bounce RK4");
        s=next;
        if(s[2].v<0 && s[5].v<0)return -s[5].v;
    }
    throw std::runtime_error("bounce did not release");
}

void contact(int hz) {
    const double mass=1.225*std::acos(-1.)/3.;
    const double stiff=bounce(hz,1e6,mass,0.), moderate=bounce(hz,1e5,mass,0.), soft=bounce(hz,400,mass,0.);
    const double refined=bounce(hz*16,1e6,mass,0.);
    double max_phase_error=0;
    for(int phase=0;phase<32;++phase) {
        const double speed=bounce(hz*16,1e6,mass,phase/(32.*hz*16.));
        max_phase_error=std::max(max_phase_error,std::abs(speed*speed-1));
    }
    std::cout<<"contact "<<hz<<" "<<stiff<<" "<<stiff*stiff<<" "<<moderate*moderate<<" "<<soft*soft<<" "
             <<refined*refined<<" "<<max_phase_error<<"\n";
}

int main(int argc,char**argv) {
    if(argc!=7)return 2;
    std::cout<<std::setprecision(17);
    for(const int hz:{120,240,480}) {
        ballistic(hz);mass_flux(hz,true);mass_flux(hz,false);event(hz);contact(hz);
        prop_impulse(hz,std::stod(argv[1]),std::stod(argv[2]),std::stod(argv[3]),std::stod(argv[4]),
                     std::stod(argv[5]),std::stod(argv[6]));
    }
}
