// NK-3: legacy fixed-pitch propeller (first-order rpm model) as the Stik route calls it, mirroring
// app/physics/propulsion.gd stage_air_velocity (datum inflow for a legacy "glow_prop" without glow/electric data),
// coefficient, thrust_torque and the untilted loads_from_thrust_torque, plus dynamics.gd rotor_momentum.
// Tilted shafts, crossflow tables, glow/electric/turbine sources and slipstream are refused at prepare time.
#pragma once

#include <array>
#include <vector>

#include "nk_math.hpp"

namespace nk {

constexpr double kStoppedRpm = 1.0;
constexpr double kCtFloor = -0.1;
constexpr double kCpFloor = 0.0;
constexpr double kTauConstant = 6.2831853071795864769252867666; // GDScript TAU (Math::TAU)

struct PropModel {
	R diameter = 0.0;
	R offset[3] = {0.0, 0.0, 0.0};
	std::vector<double> ct;
	std::vector<double> cp;
	R cp_min = 0.0;
	R rotor_inertia = 0.0;
};

// propulsion.gd coefficient: piecewise-linear [J0, v0, J1, v1, ...], engine lerpf, floored extrapolation.
inline R prop_coefficient(const std::vector<double> &table, R J, R floor_value) {
	const int n = static_cast<int>(table.size()) / 2;
	if (J.v <= table[0]) {
		return table[1];
	}
	for (int i = 1; i < n; ++i) {
		if (J.v <= table[2 * i]) {
			const R j0 = table[2 * i - 2];
			const R j1 = table[2 * i];
			return lerpf(table[2 * i - 1], table[2 * i + 1], (J - j0) / (j1 - j0));
		}
	}
	const R ja = table[2 * n - 4];
	const R jb = table[2 * n - 2];
	const R slope = (R(table[2 * n - 1]) - table[2 * n - 3]) / (jb - ja);
	return maxf(floor_value, table[2 * n - 1] + slope * (J - jb));
}

// propulsion.gd loads(v_air, rpm, prop, rho) for an untilted legacy propeller.
inline std::array<R, 6> prop_loads(const R *v_air, R rpm, const PropModel &prop, R rho) {
	if (rpm.v < kStoppedRpm) {
		return {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	}
	// thrust_torque
	const R D = prop.diameter;
	const R n = rpm / 60.0;
	const R u = v_air[0];
	const R J = maxf(u, 0.0) / (n * D);
#ifdef NK_MUTATION
	const R thrust = prop_coefficient(prop.ct, J, kCtFloor) * (rho * n * n) * pow_(D, 4.0); // negative control
#else
	const R thrust = prop_coefficient(prop.ct, J, kCtFloor) * rho * n * n * pow_(D, 4.0);
#endif
	const R power = prop_coefficient(prop.cp, J, minf(kCpFloor, prop.cp_min)) * rho * n * n * n * pow_(D, 5.0);
	const R torque = power / (kTauConstant * n);
	// loads_from_thrust_torque without an axis: arm = cross(at, [thrust, 0, 0]).
	const R at0 = -prop.offset[0];
	const R at1 = prop.offset[1];
	const R at2 = -prop.offset[2];
	const R arm0 = at1 * 0.0 - at2 * 0.0;
	const R arm1 = at2 * thrust - at0 * 0.0;
	const R arm2 = at0 * 0.0 - at1 * thrust;
	return {thrust, 0.0, 0.0, -torque + arm0, arm1, arm2};
}

// dynamics.gd rotor_momentum for a non-turbine propeller without an axis.
inline std::array<R, 3> prop_rotor_momentum(const PropModel &prop, R rpm) {
	const R h = prop.rotor_inertia * rpm * kTauConstant / 60.0;
	return {h, 0.0, 0.0};
}

} // namespace nk
