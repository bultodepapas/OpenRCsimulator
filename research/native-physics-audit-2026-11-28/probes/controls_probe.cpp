// Exercise the project's actual header functions at stock parameters. Compile
// from the repository root with -std=c++17 -O2 -ffp-contract=off
// -I research/native-kernel/src. This component probe does not launch Godot.
#include "nk_helicopter_controls.hpp"
#include "nk_helicopter_tail_rotor.hpp"
#include "nk_pre_step.hpp"

#include <array>
#include <cassert>
#include <cmath>
#include <iomanip>
#include <iostream>

namespace {
using nk::R;

bool close(double a, double b) {
    return std::abs(a-b) <= 1e-12;
}

void fixed_wing() {
    // Jensen Ugly Stik model: neutral-to-full slew 0.14 s, elevator throw 20 deg.
    constexpr double dt = 1.0 / 240;
    constexpr double rate = 1.0 / .14;
    constexpr double throw_deg = 20.0;
    std::cout << "CTRL-03: fixed-wing native pre-step and independent continuous slew\n";
    for (double demand : {1.0, -1.0, 0.01, 0.0}) {
        const double start = 0.0;
        const double endpoint = nk::pre_step_rate_limit(start, demand, rate, dt).v;
        const double reach = std::min(dt, std::abs(demand-start) / rate);
        // Rectangle after target arrival plus the integrating ramp trapezoid.
        const double area = (start + endpoint) * .5 * reach + endpoint * (dt-reach);
        const double mean = area / dt;
        if (std::abs(demand) == 1) assert(close(mean, endpoint/2));
        if (demand == 0.01) assert(close(mean, .00832));
        if (demand == 0.0) assert(close(mean, 0));
        std::cout << " demand=" << demand << " stage_held_deg=" << endpoint * throw_deg
                  << " continuous_mean_deg=" << mean * throw_deg
                  << " stage_held_area_deg_s=" << endpoint * dt * throw_deg
                  << " continuous_area_deg_s=" << area * throw_deg << '\n';
    }
}

nk::HeliTrainerModel xcell_controls() {
    // app/data/aircraft/xcell_60_research.json, electronics and swash, 407–600.
    nk::HeliTrainerModel m;
    m.normal_pitch = {-.2, .1, .45, .7, 1.};
    m.normal_throttle = {.85, .85, .85, .85, .85};
    m.idle_pitch = {-1., -.5, 0., .5, 1.};
    m.idle_throttle = {1., 1., 1., 1., 1.};
    m.collective_rad_per_unit = .22;
    m.longitudinal_rad_per_unit = .06;
    m.lateral_rad_per_unit = .06;
    m.collective_min_rad = -.22;
    m.collective_max_rad = .22;
    m.cyclic_max_rad = .06;
    m.tail_collective_trim_rad = .1;
    m.tail_collective_min_rad = -.3;
    m.tail_collective_max_rad = .3;
    m.yaw_control_sign = 1;
    m.yaw_deadzone = .025;
    m.yaw_max_rate_rad_s = 1.5;
    m.yaw_heading_gain_per_s = 2;
    m.yaw_rate_kp_rad_per_rad_s = .05;
    m.yaw_rate_ki_rad_per_rad = .02;
    m.yaw_integrator_limit_rad = .15;
    m.trainer_max_tilt_rad = .35;
    m.trainer_roll_attitude_gain_per_s = 3;
    m.trainer_pitch_attitude_gain_per_s = 3;
    m.trainer_roll_rate_limit_rad_s = 1.5;
    m.trainer_pitch_rate_limit_rad_s = 1.5;
    m.trainer_roll_cyclic_gain_rad_per_rad_s = .03;
    m.trainer_pitch_cyclic_gain_rad_per_rad_s = .03;
    return m;
}

nk::HeliTailRotorModel xcell_tail() {
    // Stock tail data with the prepared solidity, blockage and wake geometry.
    nk::HeliTailRotorModel m;
    m.rho_kg_m3 = 1.225;
    m.tail_rotor_radius_m = .13;
    m.blade_lift_curve_slope_per_rad = 5.;
    m.blade_section_cd0 = .024;
    m.thrust_coefficient_max = .05;
    m.tail_to_main_speed_ratio = 4.66;
    m.hub_distance_aft_m = .91;
    m.hub_height_above_cg_m = .08;
    m.trim_collective_rad = .1;
    m.wake_efficiency = .9;
    m.rotation_sense = 1.;
    m.solidity = 2*.029/(nk::kPi*.13);
    m.blockage_factor = 1-3*.012/(4*nk::kPi*.13*.13);
    m.wake_gi = (.91-.775-.13)/.08;
    m.wake_gf = (.91-.775+.13)/.08;
    return m;
}

void helicopter() {
    const auto electronics = xcell_controls();
    const auto rotor = xcell_tail();
    const std::array<R, 3> still{};
    std::array<R, 19> body{};
    body[2] = -10;
    body[6] = 1;
    body[13] = 167;
    body[16] = 4;
    const nk::HeliTrim neutral{};
    std::cout << "CTRL-04: X-Cell actuator commands and tail loads, same physical state\n";
    for (double main_speed : {167.0, 0.0}) {
        body[13] = main_speed;
        for (double sign : {-1.0, 1.0, 0.0}) {
            const std::array<R, 4> sticks = {0., .5*sign, sign, 0.};
            const auto control = nk::heli_trainer_electronics(electronics, body.data(), sticks,
                                                              false, false, neutral);
            assert(control.ok);
            assert(close(control.cyclic_right.v, .03*sign));
            assert(close(control.tail_collective.v, .1+.075*sign));
            assert(close(control.collective.v, .45*.22));
            const auto tail = nk::heli_tail_rotor(rotor, body[13], body[16], still, still,
                                                 control.tail_collective, 167.);
            assert(tail.ok);
            if (main_speed == 0) assert(close(tail.loads[5].v, 0));
            std::cout << " omega=" << main_speed << " roll_stick=" << .5*sign
                      << " yaw_stick=" << sign << " cyclic_right_rad=" << control.cyclic_right.v
                      << " tail_collective_rad=" << control.tail_collective.v
                      << " tail_yaw_moment_Nm=" << tail.loads[5].v << '\n';
        }
    }
}
} // namespace

int main() {
    std::cout << std::fixed << std::setprecision(9);
    fixed_wing();
    helicopter();
}
