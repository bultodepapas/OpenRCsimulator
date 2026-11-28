// Include the production float64 kernel and the normalized, stock MT8 model generated alongside this probe.
#include "ground_vehicle_kernel.hpp"
#include "stock_model.hpp"
#include <iomanip>
#include <iostream>
#include <numeric>
#include <stdexcept>

namespace gv = openrc::ground_vehicle;
using State = std::array<double, gv::kStateSize>;

State resting(const gv::Model& m) {
    State s{};
    s[6] = 1;
    const double travel = .25 * m.sprung_mass_kg * m.gravity_m_per_s2 / m.suspension_stiffness_n_per_m;
    const double tire_sag = (.25 * m.sprung_mass_kg + m.unsprung_mass_kg) * m.gravity_m_per_s2 / m.tire_stiffness_n_per_m;
    s[2] = -(m.cg_height_above_chassis_datum_m + m.wheel_center_rest_below_chassis_datum_m - travel + m.tire_radius_m - tire_sag);
    for (int i=0; i<4; ++i) s[13+i] = travel;
    return s;
}
gv::EvalResult evaluated(const State& s, const gv::Model& m, const gv::Controls& c, double mu, const gv::Vec14* rhs=nullptr) {
    gv::Surface road{0, {0,0,-1}, mu, 1};
    std::vector<gv::Surface> roads(4 + m.hull_probe_radii_m.size(), road);
    gv::EvalResult result;
    gv::evaluate(s,m,c,roads,true,true,rhs,result);
    return result;
}
void require(bool value, const std::string &message) { if (!value) throw std::runtime_error(message); }
void airborne() {
    const auto m=stock_model();
    for (double pitch: {-90., 0., 45., 89.999999, 89.999999999, 90., 90.000001, 180.}) {
        State s{};
        s[2]=-10.;
        const double a=pitch*std::acos(-1.)/360.; s[6]=std::cos(a); s[8]=std::sin(a);
        const auto r=evaluated(s,m,{},.85);
        const bool singular=std::abs(std::cos(2*a))<=1e-10;
        require(r.ok != singular,"airborne signature");
        double max_load=*std::max_element(r.wheel_load_n.begin(),r.wheel_load_n.end());
        if(r.ok) require(r.airborne && max_load==0.,"airborne control touched road");
        std::cout<<"airborne pitch_deg="<<pitch<<" projected_forward="<<std::abs(std::cos(2*a))<<" ok="<<r.ok<<" max_wheel_load_N="<<max_load<<" reason="<<r.error<<'\n';
    }
}
void wall(double mu, double intrusion, double brake = 0) {
    auto m=stock_model(); auto s=resting(m); gv::CornerGeometry geom{}; std::string error;
    require(gv::corner_geometry(s,m,0,0,0,geom,error),error);
    double east_extent=-1;
    for(const auto& p:geom.hub_position_body) east_extent=std::max(east_extent,p[1]+m.tire_radius_m);
    for(size_t i=0;i<m.hull_probe_radii_m.size();++i) east_extent=std::max(east_extent,m.hull_probe_centers_frd_m[i][1]+m.hull_probe_radii_m[i]);
    double ywall=east_extent-intrusion;
    gv::Vec14 rhs{}; int ncontacts=0; const gv::Vec3 wall_normal{0,-1,0};
    for(size_t i=0;i<4;++i){
        auto r=geom.hub_position_body[i]; double pen=r[1]+m.tire_radius_m-ywall;
        if(pen<=0) continue;
        auto f=gv::scale(wall_normal,pen*m.tire_stiffness_n_per_m);
        gv::add_contact_force(rhs,r,f,geom.hub_position_derivative_body[i],i,geom.spin_axis_body[i],gv::scale(wall_normal,-m.tire_radius_m)); ++ncontacts;
    }
    for(size_t i=0;i<m.hull_probe_radii_m.size();++i){
        auto r=m.hull_probe_centers_frd_m[i]; double pen=r[1]+m.hull_probe_radii_m[i]-ywall;
        if(pen<=0) continue;
        gv::add_body_force(rhs,gv::add(r,gv::scale(wall_normal,-m.hull_probe_radii_m[i])),gv::scale(wall_normal,pen*m.hull_contact_stiffness_n_per_m)); ++ncontacts;
    }
    gv::Controls controls{}; controls.brake=brake;
    auto post=evaluated(s,m,controls,mu); require(post.ok,post.error);
    const auto pre=evaluated(s,m,controls,mu,&rhs); require(pre.ok,pre.error);
    gv::Factor fact; require(gv::factor_generalized_mass(gv::generalized_mass_matrix(m,geom),fact,error),error);
    gv::Vec14 delta{}; require(gv::solve_generalized(fact,rhs,delta),"wall factor");
    gv::add_scaled(post.generalized_acceleration,delta,1.0);
    double a_post=0,a_pre=0;
    for(size_t i=0;i<4;++i){
        gv::Vec3 rho{0,0,m.tire_radius_m};
        auto row=gv::contact_row({1.,0.,0.,0.},{0.,1.,0.},gv::add(geom.hub_position_body[i],rho),geom.hub_position_derivative_body[i],geom.spin_axis_body[i],rho,i);
        a_post=std::max(a_post,std::abs(gv::dot14(row,post.generalized_acceleration))); a_pre=std::max(a_pre,std::abs(gv::dot14(row,pre.generalized_acceleration)));
    }
    const auto total=[](const auto& f){return std::accumulate(f.begin(),f.end(),0.);};
    std::cout<<"wall mu="<<mu<<" brake="<<brake<<" intrusion_m="<<intrusion<<" count="<<ncontacts<<" east_plane_m="<<ywall<<" external_east_N="<<rhs[1]<<" road_lateral_post_N="<<total(post.wheel_lateral_force_n)<<" road_lateral_pre_N="<<total(pre.wheel_lateral_force_n)<<" max_patch_lateral_accel_post_mps2="<<a_post<<" max_patch_lateral_accel_pre_mps2="<<a_pre<<" road_load_sum_N="<<total(post.wheel_load_n)<<'\n';
    if(mu>0 && intrusion>0) require(a_post>0.1 && a_pre<(brake>0 ? 0.001 : 1e-5),"expected constrained wall signature");
    else require(std::abs(a_post-a_pre)<1.e-8,"wall control mismatch");
}
void fitted_uneven_spawn(){
    // The production make_terrain_state fit for a 1 mm flat-topped pad under FL.
    // The relative patch position and elevation rotate with the entire scene.
    const auto m=stock_model(); auto s=resting(m); s[2]-=.00025;
    for (int i=0; i<4; ++i) s[13+i]+=(i==0 ? .00075 : -.00025);
    std::vector<gv::Surface> roads(4+m.hull_probe_radii_m.size(),{0.,{0.,0.,-1.},.85,1.});
    roads[0].height_m=.001;
    gv::EvalResult north,east;
    require(gv::evaluate(s,m,{},roads,true,true,nullptr,north),north.error);
    s[6]=std::sqrt(.5);s[9]=std::sqrt(.5);
    require(gv::evaluate(s,m,{},roads,true,true,nullptr,east),east.error);
    std::cout<<"fitted_spawn raised_FL_m=.001 north_FL_lateral_N="<<north.wheel_lateral_force_n[0]<<" east_FL_lateral_N="<<east.wheel_lateral_force_n[0]<<" north_roll_radps2="<<north.generalized_acceleration[3]<<" east_roll_radps2="<<east.generalized_acceleration[3]<<" north_sweeps="<<north.friction_sweeps_used<<" east_sweeps="<<east.friction_sweeps_used<<'\n';
    require(std::abs(east.wheel_lateral_force_n[0]-north.wheel_lateral_force_n[0])>.1,"uneven spawn yaw signature");
}
void rest_rotation(double perturbation){
    const auto m=stock_model(); auto s=resting(m); s[13]+=perturbation;
    const auto north=evaluated(s,m,{},.85); require(north.ok,north.error);
    s[6]=std::sqrt(.5);s[9]=std::sqrt(.5);
    const auto east=evaluated(s,m,{},.85); require(east.ok,east.error);
    double diff=0; for(size_t i=0;i<14;++i) diff=std::max(diff,std::abs(north.generalized_acceleration[i]-east.generalized_acceleration[i]));
    double peak=0; for(double f:east.wheel_lateral_force_n) peak=std::max(peak,std::abs(f));
    std::cout<<"rest_yaw travel_perturb_m="<<perturbation<<" north_sweeps="<<north.friction_sweeps_used<<" east_sweeps="<<east.friction_sweeps_used<<" east_peak_lateral_N="<<peak<<" north_east_accel_diff_mixed="<<diff<<" north_front_left_lateral_N="<<north.wheel_lateral_force_n[0]<<" east_front_left_lateral_N="<<east.wheel_lateral_force_n[0]<<" north_roll_accel_radps2="<<north.generalized_acceleration[3]<<" east_roll_accel_radps2="<<east.generalized_acceleration[3]<<'\n';
}
int main(){ std::cout<<std::unitbuf<<std::setprecision(14); airborne(); wall(.85,.0005); wall(.85,.0005,.5); wall(0.,.0005); wall(.85,-.001); rest_rotation(0.);rest_rotation(.001);rest_rotation(.005); fitted_uneven_spawn(); }
