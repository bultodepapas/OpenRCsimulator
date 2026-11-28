// Component audit harness. Python supplies normalized, pinned repository data.
// Compile with C++17 and research/native-kernel/src on the include path.
#include "nk_pack_ecm.hpp"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

double number() {
    double value;
    if (!(std::cin >> value)) throw std::runtime_error("missing numeric input");
    return value;
}

std::vector<double> numbers() {
    const auto size = static_cast<std::size_t>(number());
    std::vector<double> values(size);
    for (double &value : values) value = number();
    return values;
}

struct Model {
    nk::ElectricMotorModel motor;
    nk::PackEcmModel pack;
    nk::PropModel prop;
};

Model read_model() {
    Model model;
    model.motor = {number(), number(), number()};
    model.prop.diameter = number();
    model.prop.rotor_inertia = number();
    model.prop.ct = numbers();
    model.prop.cp = numbers();
    auto &p = model.pack;
    p.series = static_cast<int>(number());
    p.branches = static_cast<int>(number());
    p.group_capacity_c = number();
    p.initial_soc = number();
    p.weak_capacity_factor = number();
    p.weak_resistance_factor = number();
    p.weak_soc_offset = number();
    p.interconnect_ohm = number();
    p.auxiliary_current_a = number();
    p.cooling_airflow_fraction = number();
    p.thermal_capacity_j_per_k = number();
    p.h_still_w_per_k = number();
    p.h_forced_w_per_k_sqrt_mps = number();
    p.lvc_filter_s = number();
    p.soc_knots = numbers();
    p.temperature_knots_k = numbers();
    p.ocv = numbers();
    p.r0 = numbers();
    for (int i = 0; i < p.branches; ++i) {
        p.rc_r.push_back(numbers());
        p.rc_tau.push_back(numbers());
    }
    if (!nk::pack_ecm_model_valid(p) || !nk::electric_motor_model_valid(model.motor))
        throw std::runtime_error("source did not satisfy native validation");
    return model;
}

struct Point {
    double residual, pack_current, bus_voltage, shaft_torque, load_torque;
};

Point evaluate(const Model &m, double rpm, double axial, double rho, double pack_temperature) {
    const auto &p = m.pack;
    std::vector<nk::R> state(nk::pack_ecm_block_size(p));
    const int t = nk::pack_ecm_temperature_index(p);
    state[0] = nk::pack_ecm_initial_charge(p);
    state[t] = pack_temperature;
    state[t + 2] = 1.0;
    state[t + 5] = p.series;
    const auto point = nk::pack_ecm_stage(rpm, 1.0, state.data(), static_cast<int>(state.size()),
                                          p, m.motor, true, pack_temperature, 0.0);
    if (!point.ok) throw std::runtime_error("native pack stage refused point");
    const double load = nk::prop_torque(rpm, axial, m.prop, rho);
    return {point.motor.shaft_torque_nm.v - load, point.pack_current_a.v, point.bus_voltage_v.v,
            point.motor.shaft_torque_nm.v, load};
}

double equilibrium(const Model &m, double axial, double rho, double pack_temperature) {
    double low = 5000, high = 15000;
    if (!(evaluate(m, low, axial, rho, pack_temperature).residual > 0 &&
          evaluate(m, high, axial, rho, pack_temperature).residual < 0))
        throw std::runtime_error("no sign bracket");
    for (int i = 0; i < 80; ++i) {
        const double mid = (low + high) / 2;
        if (evaluate(m, mid, axial, rho, pack_temperature).residual > 0) low = mid;
        else high = mid;
    }
    return (low + high) / 2;
}

} // namespace

int main() {
    const Model model = read_model();
    std::cout << std::setprecision(14);
    const auto cases = static_cast<int>(number());
    for (int i = 0; i < cases; ++i) {
        std::string name;
        std::cin >> name;
        const double rho = number(), temperature = number(), wind = number();
        const double axial = 6.5 + wind * std::cos(5.0 * nk::kPi / 180.0);
        const double old_rpm = equilibrium(model, 6.5, rho, 288.15);
        const double new_rpm = equilibrium(model, axial, rho, temperature);
        const auto at_release = evaluate(model, old_rpm, axial, rho, temperature);
        const auto at_root = evaluate(model, new_rpm, axial, rho, temperature);
        if (std::abs(at_root.residual) > 1e-10) throw std::runtime_error("reference root residual");
        const double slope = (evaluate(model, new_rpm + 1.0, axial, rho, temperature).residual -
                              evaluate(model, new_rpm - 1.0, axial, rho, temperature).residual) / 2.0;
        if (!(slope < 0)) throw std::runtime_error("non-restoring reference root");
        std::cout << name << " axial=" << axial << " rho=" << rho << " setup_rpm=" << old_rpm
                  << " matched_rpm=" << new_rpm << " setup_net_torque_Nm=" << at_release.residual
                  << " electrical_shaft_torque_Nm=" << at_release.shaft_torque
                  << " air_load_torque_Nm=" << at_release.load_torque
                  << " isolated_net_accel_rad_s2=" << at_release.residual / model.prop.rotor_inertia.v
                  << " release_pack_A=" << at_release.pack_current
                  << " matched_pack_A=" << at_root.pack_current
                  << " root_residual_Nm=" << at_root.residual << '\n';
    }
    // A direct hardware-independent check of the fixed-wing equivalent-port power ledger.
    double worst = 0;
    for (double duty : {0., .1, .5, 1.})
        for (double rpm : {0., 2000., 10000., 18000.})
            for (bool enabled : {false, true}) {
                const auto m = nk::electric_motor_evaluate(rpm, duty, 24., model.motor, enabled);
                if (!m.ok) throw std::runtime_error("motor failed");
                const double residual = m.bus_power_w.v - m.shaft_power_w.v -
                                        m.copper_loss_w.v - m.rotational_loss_w.v;
                worst = std::max(worst, std::abs(residual));
            }
    std::cout << "fixed-wing 32-point power balance max_abs_W=" << worst << '\n';
}
