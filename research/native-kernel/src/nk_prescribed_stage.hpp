// Prescribed-fuel shaft and turbine stages. The normalized source is detached
// at preparation. FlightSession owns sampled shaft/spool and all discrete policy.
// The coupled gas response mirrors FlightSession._coupled_response; its core
// is identical to the finite-liquid response, without a fuel-flow calculation.
#pragma once

#include "nk_liquid_propulsion.hpp"

namespace nk {

enum class PrescribedKind { None, ShaftSplit, ShaftCoupled, TurbineSampled, TurbineContinuous };

struct PrescribedModel {
	PrescribedKind kind = PrescribedKind::None;
	LiquidGasShaft shaft;
	LiquidTurbine turbine;
	bool ready() const { return kind != PrescribedKind::None; }
	bool gas() const { return kind == PrescribedKind::ShaftSplit || kind == PrescribedKind::ShaftCoupled; }
	bool coupled() const { return kind == PrescribedKind::ShaftCoupled; }
	bool is_turbine() const { return kind == PrescribedKind::TurbineSampled || kind == PrescribedKind::TurbineContinuous; }
	bool continuous_turbine() const { return kind == PrescribedKind::TurbineContinuous; }
};

struct PrescribedGasStage {
	bool ok = false;
	std::array<R, 6> loads{}; // about live CG, including rotor reaction
	std::array<R, 3> rotor{};
	R rpm_rate = 0.0;
};

// FlightSession._coupled_response for a finite-fuel combustion propeller. `external` already
// contains this stage's aero/propulsion/ground loads shifted once from datum to live CG. The
// explicit_air flag records the stage-air key: at the stopped-friction boundary the old law
// uses prop_air for that key but datum_air otherwise. The caller owns wash/wheel derivatives.
inline PrescribedGasStage prescribed_gas_coupled_stage(const R *body, const R *external, const R *prop_air,
		const R *datum_air, bool explicit_air, R rpm, R throttle, R rho, R charge_ratio, bool running,
		const LiquidGasShaft &shaft, const PropModel &prop,
		const R *inertia, const R *inverse) {
	PrescribedGasStage out;
	if (body == nullptr || external == nullptr || prop_air == nullptr || datum_air == nullptr ||
			inertia == nullptr || inverse == nullptr) return out;
	R axis[3] = {1.0, 0.0, 0.0};
	if (prop.has_axis) for (int i = 0; i < 3; ++i) axis[i] = prop.axis[i];
	const R axial = prop_air[0] * axis[0] + prop_air[1] * axis[1] + prop_air[2] * axis[2];
	R rate = liquid_gas_shaft_rate(rpm, throttle, axial, shaft, prop, rho, charge_ratio, running);
	if (!is_finite(rate)) return out;
	bool locked = false;
	if (!running && rpm.v <= kStoppedRpm && rate.v == 0.0) {
		const R friction = shaft.friction[0];
		const R w0 = body[10], w1 = body[11], w2 = body[12];
		const R body_h0 = inertia[0] * w0 + inertia[3] * w1 + inertia[4] * w2;
		const R body_h1 = inertia[3] * w0 + inertia[1] * w1 + inertia[5] * w2;
		const R body_h2 = inertia[4] * w0 + inertia[5] * w1 + inertia[2] * w2;
		const std::array<R, 3> rotor_h = prop_rotor_momentum(prop, rpm);
		const R h0 = body_h0 + rotor_h[0], h1 = body_h1 + rotor_h[1], h2 = body_h2 + rotor_h[2];
		const R m0 = external[3] - (w1 * h2 - w2 * h1);
		const R m1 = external[4] - (w2 * h0 - w0 * h2);
		const R m2 = external[5] - (w0 * h1 - w1 * h0);
		const R free0 = inverse[0] * m0 + inverse[3] * m1 + inverse[4] * m2;
		const R free1 = inverse[3] * m0 + inverse[1] * m1 + inverse[5] * m2;
		const R free2 = inverse[4] * m0 + inverse[5] * m1 + inverse[2] * m2;
		const R required = prop.rotor_inertia * (axis[0] * free0 + axis[1] * free1 + axis[2] * free2);
		const R *drive_air = explicit_air ? prop_air : datum_air;
		const R drive_u = drive_air[0] * axis[0] + drive_air[1] * axis[1] + drive_air[2] * axis[2];
		const R drive = -prop_torque(rpm, drive_u, prop, rho);
		if (!is_finite(friction) || friction.v < 0.0 || !is_finite(required) || !is_finite(drive)) return out;
		if (absf(drive - required).v <= friction.v) {
			locked = true;
			rate = required / prop.rotor_inertia * 60.0 / kTauConstant;
		} else if ((drive - required).v < (-friction).v) {
			return out; // reverse breakaway remains outside the authored law
		} else {
			rate = (drive - friction) / prop.rotor_inertia * 60.0 / kTauConstant;
		}
	}
	const R moments[3] = {external[3], external[4], external[5]};
	RotorCouplingResult coupled = rotor_coupling_response(body + 10, moments, inertia, inverse, axis,
			prop.rotor_inertia, rpm * kTauConstant / 60.0, rate * prop.rotor_inertia * kTauConstant / 60.0);
	if (!coupled.ok) return out;
	if (locked) {
		coupled.spin_acceleration = 0.0;
		coupled.reaction = {0.0, 0.0, 0.0};
	}
	for (int i = 0; i < 6; ++i) out.loads[i] = external[i];
	for (int i = 0; i < 3; ++i) out.loads[3 + i] += coupled.reaction[i];
	out.rpm_rate = coupled.spin_acceleration * 60.0 / kTauConstant;
	out.rotor = prop_rotor_momentum(prop, rpm);
	out.ok = true;
	return out;
}

// _turbine_evaluate retains prescribed-fuel cutoff semantics: an off source
// is admissible only at zero RPM and its rate is exactly zero. Unlike the
// finite-liquid source it has no invented rundown or resource derivative.
struct PrescribedTurbineStage {
	bool ok = false;
	std::array<R, 6> loads{};
	std::array<R, 3> rotor{};
	R rpm_rate = 0.0;
};

inline PrescribedTurbineStage prescribed_turbine_stage(const R *inlet, R rpm, R throttle,
		const LiquidTurbine &turbine, R rho, bool running, bool continuous) {
	PrescribedTurbineStage out;
	if (inlet == nullptr) return out;
	if (continuous && (!is_finite(rpm) || rpm.v < 0.0 || rpm.v > turbine.max_rpm.v || (!running && rpm.v != 0.0))) return out;
	out.loads = liquid_turbine_loads(inlet, rpm, turbine, rho);
	out.rotor = liquid_turbine_rotor_momentum(rpm, turbine);
	if (continuous && running) {
		out.rpm_rate = liquid_turbine_spool_rate(rpm, liquid_turbine_demand_rpm(throttle, turbine), turbine);
	}
	out.ok = true;
	return out;
}

} // namespace nk
