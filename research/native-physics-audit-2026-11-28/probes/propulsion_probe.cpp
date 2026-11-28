// Standalone production-header checks. propulsion_probe.py supplies stock aircraft values.
#include <algorithm>
#include <array>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "nk_glow_propeller.hpp"
#include "nk_glow_source.hpp"
#include "nk_liquid_propulsion.hpp"
#include "nk_wake_spatial_flow.hpp"

using nk::R;

double number() {
    double result;
    if (!(std::cin >> result) || !std::isfinite(result)) throw std::runtime_error("bad numeric input");
    return result;
}

std::vector<double> table() {
    int pairs;
    if (!(std::cin >> pairs) || pairs < 2 || pairs > 512) throw std::runtime_error("bad table count");
    std::vector<double> values(2 * pairs);
    for (double &value : values) value = number();
    return values;
}

void row(const std::string &id, const std::string &test, std::initializer_list<double> results) {
    std::cout << id << ' ' << test;
    for (double result : results) std::cout << ' ' << result;
    std::cout << '\n';
}

bool still_air(void *, const R *, R, R *wind) {
    std::fill(wind, wind + 3, R(0));
    return true;
}

void gasoline(const std::string &id) {
    nk::PropModel prop;
    prop.diameter = number();
    prop.rotor_inertia = number();
    for (R &component : prop.offset) component = number();
    const double down = number() * std::acos(-1.0) / 180.0;
    const double right = number() * std::acos(-1.0) / 180.0;
    prop.has_axis = true;
    prop.axis[0] = std::cos(down) * std::cos(right);
    prop.axis[1] = std::cos(down) * std::sin(right);
    prop.axis[2] = std::sin(down);
    prop.ct = table();
    prop.cp = table();
    for (std::size_t i = 1; i < prop.cp.size(); i += 2) prop.cp_min = std::min(prop.cp_min.v, prop.cp[i]);
    prop.normal_force = table();
    prop.pfactor_moment = table();
    nk::LiquidGasShaft shaft;
    shaft.power_curve = table();
    for (R &term : shaft.friction) term = number();
    shaft.idle_power = number();
    shaft.peak_indicated_power = number();
    const double idle_rpm = number();
    nk::LiquidGasConsumption fuel;
    fuel.bsfc_kg_kwh = number();
    fuel.idle_flow_kg_s = number();
    fuel.idle_power_w = shaft.idle_power;

    nk::AeroModel stations;
    stations.ys = {-0.75, -0.45, -0.15, 0.15, 0.45, 0.75}; // other stations only see uniform wind
    for (double pitch_rate : {0.0, 2.0}) {
        nk::SpatialPointContext context;
        R body[13] = {};
        body[3] = 25.0;
        body[6] = 1.0;
        body[11] = pitch_rate;
        const auto point = nk::spatial_flow_sample(body, stations, prop.offset, {still_air, nullptr}, 0.0, 1.225, context);
        if (!point.ok || !point.uniform) throw std::runtime_error("constant spatial field failed");
        const auto uniform = nk::prop_stage_air_velocity(body, point.air.v, prop, false);
        const auto spatial = nk::prop_stage_air_velocity(body, point.air.v, prop, false, point.propulsion_air.data());
        if (!uniform.ok || !spatial.ok) throw std::runtime_error("invalid propeller inflow");
        const auto a = nk::prop_loads(uniform.velocity.data(), 4500.0, prop, 1.225);
        const auto b = nk::prop_loads(spatial.velocity.data(), 4500.0, prop, 1.225);
        row(id, pitch_rate == 0.0 ? "hub_zero" : "hub_pitch", {spatial.velocity[0] - uniform.velocity[0],
            spatial.velocity[1] - uniform.velocity[1], spatial.velocity[2] - uniform.velocity[2],
            b[0]-a[0], b[1]-a[1], b[2]-a[2], b[3]-a[3], b[4]-a[4], b[5]-a[5]});
    }
    const double omega = idle_rpm * nk::kTauConstant / 60.0;
    for (double extra : {0.0, 50.0, 500.0}) {
        const double throttle = extra / (shaft.peak_indicated_power.v - shaft.idle_power.v);
        const R torque = nk::liquid_gas_engine_torque(idle_rpm, throttle, shaft, 1.0);
        const double brake = torque.v * omega;
        const double fuel_rate = nk::liquid_gas_fuel_flow(fuel, true, brake).v;
        row(id, "fuel_" + std::to_string(static_cast<int>(extra)), {brake, fuel_rate});
    }
    for (double rpm : {0.0, 0.5, 1.0, 100.0, 3000.0, 4500.0}) {
        for (double u : {-20.0, 0.0, 20.0, 30.0, 40.0}) {
            R air[3] = {u * prop.axis[0], u * prop.axis[1], u * prop.axis[2]};
            const auto force = nk::prop_thrust_torque(air, rpm, prop, 1.225);
            const auto off_rate = nk::liquid_gas_shaft_rate(rpm, 0.0, u, shaft, prop, 1.225, 1.0, false);
            row(id, "advance", {rpm, u, force[0], force[1], off_rate});
        }
    }
}

void glow(const std::string &id) {
    double values[8];
    for (double &value : values) value = number();
    const auto blade = nk::glow_blade_prepare(values[0], values[1], values[2], values[3], values[4], values[5], values[6], values[7]);
    for (double u : {-20.0, 0.0, 20.0, 40.0}) {
        const auto res = nk::glow_blade_evaluate(blade, 0.0, u, 1.225);
        if (!res.ok) throw std::runtime_error("glow stopped query rejected");
        row(id, "glow_stopped", {u, res.thrust_n, res.torque_nm, res.dissipation_w});
    }
    double minimum_ratio = 1.0e9;
    for (int sample = 0; sample <= 2000; ++sample) {
        const double u = (sample / 1000.0) * (10000.0 / 60.0) * values[0];
        const auto res = nk::glow_blade_evaluate(blade, 10000.0, u, 1.225);
        if (!res.ok) throw std::runtime_error("glow axial sweep rejected");
        if (res.thrust_n.v <= 0.0) continue;
        const double area = std::acos(-1.0) * values[0] * values[0] / 4.0;
        const double ideal = 0.5 * res.thrust_n.v * (u + std::sqrt(u*u + 2*res.thrust_n.v/(1.225*area)));
        minimum_ratio = std::min(minimum_ratio, res.shaft_power_w.v / ideal);
    }
    row(id, "glow_min_positive_thrust_power_ratio", {minimum_ratio});
}

void turbine_transient(const std::string &id, const nk::LiquidTurbine &t, double command, int frequency) {
    const double dt = 1.0 / frequency;
    const double target = nk::liquid_turbine_demand_rpm(command, t);
    double rpm = nk::liquid_turbine_demand_rpm(1.0-command, t);
    const auto rate = [&](double n) { return nk::liquid_turbine_spool_rate(n, target, t).v; };
    const auto fuel = [&](double n) { return nk::liquid_turbine_fuel_flow(n, t, true).v; };
    const auto force = [&](double n) { return nk::liquid_turbine_gross_thrust(n, t, 1.225, 0.0).v; };
    const double start_force = force(rpm), final_force = force(target);
    double t10 = -1.0, t90 = -1.0, used = 0.0, prev_fraction = 0.0;
    for (int step = 0; step < frequency*6; ++step) {
        const double k1 = rate(rpm);
        const double n2 = rpm + 0.5*dt*k1, k2 = rate(n2);
        const double n3 = rpm + 0.5*dt*k2, k3 = rate(n3);
        const double n4 = rpm + dt*k3, k4 = rate(n4);
        used += dt*(fuel(rpm) + 2*fuel(n2) + 2*fuel(n3) + fuel(n4))/6.0;
        rpm += dt*(k1+2*k2+2*k3+k4)/6.0;
        const double fraction = (force(rpm)-start_force)/(final_force-start_force);
        const auto crossing = [&](double threshold) {
            return dt*(step + (threshold-prev_fraction)/(fraction-prev_fraction));
        };
        if (prev_fraction < 0.1 && fraction >= 0.1) t10 = crossing(0.1);
        if (prev_fraction < 0.9 && fraction >= 0.9) t90 = crossing(0.9);
        prev_fraction = fraction;
    }
    if (t10 < 0 || t90 <= t10) throw std::runtime_error("turbine threshold not reached");
    row(id, "turbine_six_seconds", {double(frequency), command, t10, t90, used});
}

void turbine(const std::string &id) {
    nk::LiquidTurbine t;
    t.max_rpm = number();
    t.governor_tau = number();
    t.installed_factor = number();
    t.ram_flow = number();
    t.rotor_inertia = number();
    t.rotor_sense = number();
    t.throttle_map = table();
    t.accel_limit = table();
    t.decel_limit = table();
    t.static_thrust = table();
    t.mass_flow = table();
    t.ram_jet = table();
    t.fuel_flow = table();
    R air[3] = {};
    for (double rpm : {44000.0, 110000.0, 154000.0}) {
        for (double throttle : {0.0, 1.0}) {
            const auto res = nk::liquid_turbine_stage(air, rpm, throttle, t, 1.225, true);
            if (!res.ok) throw std::runtime_error("turbine stage rejected");
            const double power = t.rotor_inertia.v * (rpm*nk::kTauConstant/60.0) * (res.rpm_rate.v*nk::kTauConstant/60.0);
            row(id, "turbine", {rpm, throttle, res.loads[0], res.rpm_rate, res.fuel_rate, power});
        }
    }
    for (int frequency : {120, 240, 480}) {
        for (double throttle : {0.0, 1.0}) turbine_transient(id, t, throttle, frequency);
    }
}

void glow_source(const std::string &id) {
    nk::GlowSourceModel m;
    const bool two = number() == 2.0;
    m.family = two ? nk::GlowFamily::TwoStroke : nk::GlowFamily::FourStroke;
    m.max_rpm = number();
    m.displacement_m3 = number();
    m.oil_fraction = number();
    m.stoich_air_fuel_ratio = number();
    m.fuel_lhv_j_kg = number();
    m.intake_pressure_drop_pa = number();
    m.breathing = table();
    m.pumping_pressure = table();
    m.mechanical_torque_nm = table();
    m.combustion_efficiency = table();
    m.indicated_efficiency = table();
    if (two) m.trapping_efficiency = table();
    else m.valve_torque_nm = table();
    if (!nk::glow_source_model_valid(m)) throw std::runtime_error("invalid stock glow source");
    const double rpm = number(), mixture = number(), reference_density = number(), rated_power = number();
    for (double dry_fraction : {1.0, 0.85}) {
        const auto res = nk::glow_source_evaluate(m, rpm, 1.0, mixture, reference_density*dry_fraction, true, 1.0);
        if (!res.ok) throw std::runtime_error("glow rated-point query rejected");
        row(id, "glow_source", {double(two ? 2 : 4), dry_fraction, rpm, rated_power,
            res.opportunity_frequency_hz, res.shaft_torque_nm, res.brake_power_w, res.indicated_power_w,
            res.chemical_power_w, res.fuel_input_power_w, res.delivered_fuel_kg_s, res.burned_fuel_kg_s,
            res.unburned_fuel_kg_s, res.mechanical_loss_w, res.pumping_loss_w, res.valve_loss_w});
    }
}

int main() {
    std::cout << std::setprecision(17);
    std::string kind, id;
    while (std::cin >> kind >> id) {
        if (kind == "gas") gasoline(id);
        else if (kind == "glow") glow(id);
        else if (kind == "glow_source") glow_source(id);
        else if (kind == "turbine") turbine(id);
        else throw std::runtime_error("unknown fixture");
    }
}
