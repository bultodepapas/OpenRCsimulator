// Electric FlightSession._coupled_response's single-shaft numerical solve.
// The caller supplies same-stage hub air, the validated source point, and complete
// pre-reaction airframe/wake/ground loads. No events or GDScript callbacks occur here.
#pragma once

#include <array>
#include "nk_electric.hpp"
#include "nk_rotor_coupling.hpp"

namespace nk {

struct ElectricCouplingSource {
	bool ok = false;
	R shaft_torque_nm = 0.0;
	R motor_current_a = 0.0;
};

struct ElectricCouplingResult {
	bool ok = false;
	bool locked = false;
	std::array<R, 6> loads{};
	std::array<R, 3> reaction{};
	std::array<R, 3> rotor{};
	R rpm_rate = 0.0;
	R spin_acceleration = 0.0;
};

// Arrays use the existing simulation layout. `prop_air` is already the validated
// stage-local velocity from Propulsion.stage_air_velocity, not datum velocity.
// For a dynamic pack the source owner has validated the trial block and computed
// this stage's source point/rates; fixed voltage follows shaft_rate's additional
// throttle, inflow, density and charge-ratio guards.
inline ElectricCouplingResult electric_coupled_response(const R *body, R trial_rpm, const PropModel &prop,
		const ElectricMotorModel &motor, const R *inertia, const R *inverse, const R *prop_air, R rho,
		R charge_ratio, R throttle, bool dynamic_battery, const ElectricCouplingSource &source, const R *external) {
	ElectricCouplingResult out;
	if (body == nullptr || inertia == nullptr || inverse == nullptr || prop_air == nullptr || external == nullptr ||
			!is_finite(trial_rpm) || !source.ok) return out;
	for (int i = 0; i < 3; ++i) if (!is_finite(prop_air[i])) return out;
	const R rpm = maxf(0.0, trial_rpm);
	const R axis[3] = {prop.has_axis ? prop.axis[0] : R(1.0), prop.has_axis ? prop.axis[1] : R(0.0),
			prop.has_axis ? prop.axis[2] : R(0.0)};
	const R axial = prop_air[0] * axis[0] + prop_air[1] * axis[1] + prop_air[2] * axis[2];
	if (!dynamic_battery && (!is_finite(rpm) || rpm.v < 0.0 || !is_finite(throttle) || !is_finite(axial) ||
			!is_finite(rho) || rho.v <= 0.0 || !is_finite(charge_ratio) || charge_ratio.v < 0.0 ||
			!is_finite(prop.rotor_inertia) || prop.rotor_inertia.v <= 0.0)) return out;
	if (rpm.v >= kStoppedRpm && (prop.cp.size() < 4 || prop.cp.size() % 2 != 0)) return out;
	const R load_torque = prop_torque(rpm, axial, prop, rho);
	R rate = (source.shaft_torque_nm - load_torque) / prop.rotor_inertia * 60.0 / kTauConstant;
	if (!is_finite(rate)) return out;
	bool locked = false;
	if (trial_rpm.v <= 0.0) {
		// This is deliberately grouped unlike ElectricMotor's own kt calculation.
		const R kt = 60.0 / (R(kTauConstant) * motor.kv_rpm_per_volt);
		const R friction = kt * motor.no_load_current_a;
		const R drive = kt * source.motor_current_a;
		if (trial_rpm.v < 0.0) {
			// Left limit used only while locating a stop event.
			rate = (drive - friction) / prop.rotor_inertia * 60.0 / kTauConstant;
		} else if (rpm.v == 0.0) {
			const R w0 = body[10], w1 = body[11], w2 = body[12];
			const R h0 = inertia[0] * w0 + inertia[3] * w1 + inertia[4] * w2;
			const R h1 = inertia[3] * w0 + inertia[1] * w1 + inertia[5] * w2;
			const R h2 = inertia[4] * w0 + inertia[5] * w1 + inertia[2] * w2;
			const R m0 = external[3] - (w1 * h2 - w2 * h1);
			const R m1 = external[4] - (w2 * h0 - w0 * h2);
			const R m2 = external[5] - (w0 * h1 - w1 * h0);
			const R a0 = inverse[0] * m0 + inverse[3] * m1 + inverse[4] * m2;
			const R a1 = inverse[3] * m0 + inverse[1] * m1 + inverse[5] * m2;
			const R a2 = inverse[4] * m0 + inverse[5] * m1 + inverse[2] * m2;
			const R required = prop.rotor_inertia * (axis[0] * a0 + axis[1] * a1 + axis[2] * a2);
			if (absf(drive - required).v <= friction.v) {
				locked = true;
				rate = required / prop.rotor_inertia * 60.0 / kTauConstant;
			} else if ((drive - required).v < (-friction).v) {
				return out; // reverse breakaway is unsupported
			} else {
				rate = (drive - friction) / prop.rotor_inertia * 60.0 / kTauConstant;
			}
		}
	}
	const R omega[3] = {body[10], body[11], body[12]};
	const R moment[3] = {external[3], external[4], external[5]};
	RotorCouplingResult response = rotor_coupling_response(omega, moment, inertia, inverse, axis,
			prop.rotor_inertia, rpm * kTauConstant / 60.0, rate * prop.rotor_inertia * kTauConstant / 60.0);
	if (!response.ok) return out;
	if (locked) {
		response.spin_acceleration = 0.0;
		response.reaction = {0.0, 0.0, 0.0};
	}
	for (int i = 0; i < 6; ++i) out.loads[i] = external[i];
	for (int i = 0; i < 3; ++i) out.loads[i + 3] += response.reaction[i];
	out.rotor = prop_rotor_momentum(prop, rpm);
	out.reaction = response.reaction;
	out.rpm_rate = response.spin_acceleration * 60.0 / kTauConstant;
	out.spin_acceleration = response.spin_acceleration;
	out.locked = locked;
	out.ok = true;
	return out;
}

} // namespace nk
