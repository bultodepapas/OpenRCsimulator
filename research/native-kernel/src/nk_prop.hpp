// NK-3: fixed-pitch propeller geometry and loads, mirroring app/physics/propulsion.gd and
// dynamics.gd. The Ct/Cp functions apply to the legacy, gasoline and electric propellers; a glow
// blade-element source may instead supply its own thrust and torque to prop_loads_from_thrust_torque.
// Admission of any source or stage remains the caller's responsibility.
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
	bool has_axis = false;
	R axis[3] = {1.0, 0.0, 0.0};
	std::vector<double> normal_force;
	std::vector<double> pfactor_moment;
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

struct PropAir {
	bool ok = false;
	std::array<R, 3> velocity{};
};

// Propulsion.stage_air_velocity for a propeller. The caller validates array shapes: body is the
// 13-entry RB state and both air pointers, when present, contain three values. An explicit stage
// velocity is already local and takes precedence even over invalid datum air. Otherwise only
// electric/glow installations set local_hub; the legacy gasoline route retains datum inflow.
inline PropAir prop_stage_air_velocity(const R *body, const R *datum_air, const PropModel &prop,
		bool local_hub, const R *explicit_air = nullptr) {
	PropAir out;
	if (explicit_air != nullptr) {
		for (int i = 0; i < 3; ++i) {
			if (!is_finite(explicit_air[i])) {
				return out;
			}
			out.velocity[i] = explicit_air[i];
		}
		out.ok = true;
		return out;
	}
	if (datum_air == nullptr) {
		return out;
	}
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(datum_air[i])) {
			return out;
		}
	}
	if (local_hub) {
		if (body == nullptr) {
			return out;
		}
		const R x = -prop.offset[0];
		const R y = prop.offset[1];
		const R z = -prop.offset[2];
		const R p = body[10];
		const R q = body[11];
		const R r = body[12];
		out.velocity = {datum_air[0] + q * z - r * y,
			datum_air[1] + r * x - p * z, datum_air[2] + p * y - q * x};
	} else {
		out.velocity = {datum_air[0], datum_air[1], datum_air[2]};
	}
	for (const R &value : out.velocity) {
		if (!is_finite(value)) {
			return PropAir{};
		}
	}
	out.ok = true;
	return out;
}

// Propulsion.thrust_torque for a Ct/Cp propeller. The glowing blade-element law is separate.
inline std::array<R, 3> prop_thrust_torque(const R *v_air, R rpm, const PropModel &prop, R rho) {
	if (rpm.v < kStoppedRpm) {
		return {0.0, 0.0, 0.0};
	}
	const R D = prop.diameter;
	const R n = rpm / 60.0;
	const R u = prop.has_axis ? v_air[0] * prop.axis[0] + v_air[1] * prop.axis[1] + v_air[2] * prop.axis[2]
			: v_air[0];
	const R J = maxf(u, 0.0) / (n * D);
	const R thrust = prop_coefficient(prop.ct, J, kCtFloor) * rho * n * n * pow_(D, 4.0);
	const R power = prop_coefficient(prop.cp, J, minf(kCpFloor, prop.cp_min)) * rho * n * n * n * pow_(D, 5.0);
	return {thrust, power / (kTauConstant * n), J};
}

// Propulsion.prop_torque has a different operation order from thrust_torque. Do not derive it
// by taking the latter's torque: the shaft derivative needs the reference's exact arithmetic.
inline R prop_torque(R rpm, R axial_speed, const PropModel &prop, R rho) {
	if (rpm.v < kStoppedRpm) {
		return 0.0;
	}
	const R D = prop.diameter;
	const R n = rpm / 60.0;
	const R J = maxf(axial_speed, 0.0) / (n * D);
	return prop_coefficient(prop.cp, J, minf(kCpFloor, prop.cp_min)) * rho * n * n * pow_(D, 5.0) / kTauConstant;
}

// Propulsion._crossflow as used by its public normal_force/pfactor_moment helpers. This has a
// STOPPED_RPM cutoff distinct from the tilted-loads path's rpm != 0 test.
inline std::array<R, 3> prop_crossflow(const R *v_air, R rpm, const PropModel &prop, R rho,
		const std::vector<double> &table, R power) {
	const R speed = sqrt_(v_air[0] * v_air[0] + v_air[1] * v_air[1] + v_air[2] * v_air[2]);
	if (table.empty() || rpm.v < kStoppedRpm || speed.v < 1e-6) {
		return {0.0, 0.0, 0.0};
	}
	const R a0 = prop.has_axis ? prop.axis[0] : R(1.0);
	const R a1 = prop.has_axis ? prop.axis[1] : R(0.0);
	const R a2 = prop.has_axis ? prop.axis[2] : R(0.0);
	const R along = v_air[0] * a0 + v_air[1] * a1 + v_air[2] * a2;
	const R cross0 = v_air[0] - a0 * along;
	const R cross1 = v_air[1] - a1 * along;
	const R cross2 = v_air[2] - a2 * along;
	const R D = prop.diameter;
	const R n = rpm / 60.0;
	const R J = maxf(along, 0.0) / (n * D);
	const R scale = -prop_coefficient(table, J, 0.0) * rho * n * n * pow_(D, power) / speed;
	return {cross0 * scale, cross1 * scale, cross2 * scale};
}

inline std::array<R, 3> prop_normal_force(const R *v_air, R rpm, const PropModel &prop, R rho) {
	return prop_crossflow(v_air, rpm, prop, rho, prop.normal_force, 4.0);
}

inline std::array<R, 3> prop_pfactor_moment(const R *v_air, R rpm, const PropModel &prop, R rho) {
	return prop_crossflow(v_air, rpm, prop, rho, prop.pfactor_moment, 5.0);
}

// Propulsion.loads_from_thrust_torque. The supplied values must be from the same RK stage; in
// particular this permits a stopped glow propeller to produce its passive blade-element loads.
inline std::array<R, 6> prop_loads_from_thrust_torque(const R *v_air, R rpm, const PropModel &prop, R rho,
		R thrust, R torque) {
	const R at0 = -prop.offset[0];
	const R at1 = prop.offset[1];
	const R at2 = -prop.offset[2];
	if (!prop.has_axis) {
		const R arm0 = at1 * 0.0 - at2 * 0.0;
		const R arm1 = at2 * thrust - at0 * 0.0;
		const R arm2 = at0 * 0.0 - at1 * thrust;
		return {thrust, 0.0, 0.0, -torque + arm0, arm1, arm2};
	}
	const R a0 = prop.axis[0];
	const R a1 = prop.axis[1];
	const R a2 = prop.axis[2];
	const R v0 = v_air[0];
	const R v1 = v_air[1];
	const R v2 = v_air[2];
	R nf0 = 0.0, nf1 = 0.0, nf2 = 0.0;
	R pf0 = 0.0, pf1 = 0.0, pf2 = 0.0;
	const R speed = sqrt_(v0 * v0 + v1 * v1 + v2 * v2);
	if (!(speed.v < 1e-6) && rpm.v != 0.0) {
		const R along = v0 * a0 + v1 * a1 + v2 * a2;
		const R c0 = v0 - a0 * along;
		const R c1 = v1 - a1 * along;
		const R c2 = v2 - a2 * along;
		const R D = prop.diameter;
		const R n = rpm / 60.0;
		const R J = maxf(along, 0.0) / (n * D);
		if (!prop.normal_force.empty()) {
			const R k = -prop_coefficient(prop.normal_force, J, 0.0) * rho * n * n * pow_(D, 4.0) / speed;
			nf0 = c0 * k;
			nf1 = c1 * k;
			nf2 = c2 * k;
		}
		if (!prop.pfactor_moment.empty()) {
			const R k = -prop_coefficient(prop.pfactor_moment, J, 0.0) * rho * n * n * pow_(D, 5.0) / speed;
			pf0 = c0 * k;
			pf1 = c1 * k;
			pf2 = c2 * k;
		}
	}
	const R f0 = a0 * thrust + nf0;
	const R f1 = a1 * thrust + nf1;
	const R f2 = a2 * thrust + nf2;
	return {f0, f1, f2,
		((at1 * f2 - at2 * f1) - a0 * torque) + pf0,
		((at2 * f0 - at0 * f2) - a1 * torque) + pf1,
		((at0 * f1 - at1 * f0) - a2 * torque) + pf2};
}

// propulsion.gd loads(v_air, rpm, prop, rho) for an untilted legacy propeller.
inline std::array<R, 6> prop_loads(const R *v_air, R rpm, const PropModel &prop, R rho) {
	if (rpm.v < kStoppedRpm) {
		return {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	}
	if (prop.has_axis) {
		const std::array<R, 3> tq = prop_thrust_torque(v_air, rpm, prop, rho);
		return prop_loads_from_thrust_torque(v_air, rpm, prop, rho, tq[0], tq[1]);
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

// dynamics.gd rotor_momentum for a non-turbine propeller.
inline std::array<R, 3> prop_rotor_momentum(const PropModel &prop, R rpm) {
	const R h = prop.rotor_inertia * rpm * kTauConstant / 60.0;
	if (prop.has_axis) {
		return {prop.axis[0] * h, prop.axis[1] * h, prop.axis[2] * h};
	}
	return {h, 0.0, 0.0};
}

} // namespace nk
