// GlowFlight's fixed-axis rotor/body coupling and continuous derivative assembly.
// The caller supplies this exact stage's airframe loads, live mass, lifecycle point and
// blade-element result. Fuel-feed closure, contact/wake evaluation and events remain separate.
#pragma once

#include <array>

#include "nk_glow_lifecycle.hpp"
#include "nk_glow_propeller.hpp"
#include "nk_liquid_mass.hpp"
#include "nk_rotor_coupling.hpp"

namespace nk {

struct GlowCoupledStage {
	bool ok = false;
	std::array<R, 6> loads{}; // output loads remain about the fixed datum
	std::array<R, 3> rotor{};
	std::array<R, 13> body_derivative{};
	std::array<R, 19> derivative{}; // wheel derivatives append after this block
};

// `values` is the 19-entry GlowFlight prefix; caller validates its discrete serialized
// fields and length and supplies stage-local density/charge and life/propeller evaluations.
inline GlowCoupledStage glow_coupled_stage(const R *body, const R *external, const R *values,
		const PropModel &prop, const GlowLifecycleModel &model, const GlowLifecycleState &state,
		const GlowLifecyclePoint &life, const GlowBladePoint &blade, const LiquidMassProperties &mass,
		R dry_density, R gravity) {
	GlowCoupledStage out;
	if (body == nullptr || external == nullptr || values == nullptr || !mass.ok || !life.ok || !blade.ok) return out;
	R axis[3] = {1.0, 0.0, 0.0};
	if (prop.has_axis) for (int i = 0; i < 3; ++i) axis[i] = prop.axis[i];
	const R force[3] = {external[0], external[1], external[2]};
	const auto &cg = mass.cg;
	const R shift0 = cg[1] * force[2] - cg[2] * force[1];
	const R shift1 = cg[2] * force[0] - cg[0] * force[2];
	const R shift2 = cg[0] * force[1] - cg[1] * force[0];
	const R torque[3] = {external[3] - shift0, external[4] - shift1, external[5] - shift2};
	const R w0 = body[10], w1 = body[11], w2 = body[12];
	R drive = life.source.shaft_torque_nm;
	const R load_torque = blade.torque_nm;
	bool locked = false;
	if (values[0].v <= 0.0) {
		const R coast_rpm = 0.001;
		const R breathing = glow_source_table_sample(model.source.breathing, coast_rpm);
		const R cycle = model.source.family == GlowFamily::TwoStroke ? R(1.0) : R(2.0);
		const R admission = glow_carb_admission(state.air_fraction, coast_rpm, breathing,
				model.source.displacement_m3, cycle, model.throttle_capacity_m3_s);
		const GlowSourcePoint coast = glow_source_evaluate(model.source, coast_rpm, admission, values[12],
				dry_density, false, 1.0);
		if (!coast.ok) return out;
		const R friction = -coast.shaft_torque_nm;
		const auto &j = mass.inertia;
		const auto &inverse = mass.inverse;
		const R h0 = j[0] * w0 + j[3] * w1 + j[4] * w2;
		const R h1 = j[3] * w0 + j[1] * w1 + j[5] * w2;
		const R h2 = j[4] * w0 + j[5] * w1 + j[2] * w2;
		const R m0 = torque[0] - (w1 * h2 - w2 * h1);
		const R m1 = torque[1] - (w2 * h0 - w0 * h2);
		const R m2 = torque[2] - (w0 * h1 - w1 * h0);
		const R a0 = inverse[0] * m0 + inverse[3] * m1 + inverse[4] * m2;
		const R a1 = inverse[3] * m0 + inverse[1] * m1 + inverse[5] * m2;
		const R a2 = inverse[4] * m0 + inverse[5] * m1 + inverse[2] * m2;
		const R axial_alpha = axis[0] * a0 + axis[1] * a1 + axis[2] * a2;
		const R demand = -load_torque - prop.rotor_inertia * axial_alpha;
		if (values[0].v < 0.0) {
			drive = -friction;
		} else if (demand.v < (-friction).v) {
			return out;
		} else if (demand.v <= friction.v) {
			locked = true;
			drive = load_torque + prop.rotor_inertia * axial_alpha;
		} else {
			drive = -friction;
		}
	}
	const R rpm = maxf(0.0, values[0]);
	const R omega[3] = {w0, w1, w2};
	RotorCouplingResult response = rotor_coupling_response(omega, torque, mass.inertia.data(), mass.inverse.data(),
			axis, prop.rotor_inertia, rpm * kTauConstant / 60.0, drive - load_torque);
	if (!response.ok) return out;
	if (locked) {
		response.spin_acceleration = 0.0;
		response.reaction = {0.0, 0.0, 0.0};
	}
	const R moment[3] = {torque[0] + response.reaction[0], torque[1] + response.reaction[1],
		torque[2] + response.reaction[2]};
	const R rotor_scale = prop.rotor_inertia * rpm * kTauConstant / 60.0;
	const std::array<R, 3> rotor = {axis[0] * rotor_scale, axis[1] * rotor_scale, axis[2] * rotor_scale};
	out.body_derivative = liquid_fixed_datum_derivative(body, mass, force, moment, gravity, rotor.data());
	for (int i = 0; i < 6; ++i) out.loads[i] = external[i];
	for (int i = 0; i < 3; ++i) out.loads[i + 3] += response.reaction[i];
	out.rotor = rotor;
	out.derivative[0] = response.spin_acceleration * 60.0 / kTauConstant;
	for (int i = 0; i < 6; ++i) out.derivative[i + 1] = life.rates[i];
	if (values[18].v == 2.0) out.derivative[17] = out.derivative[1];
	out.derivative[13] = life.source.brake_power_w;
	out.derivative[14] = blade.shaft_power_w;
	out.derivative[15] = blade.thrust_power_w;
	out.derivative[16] = life.source.chemical_power_w;
	out.ok = true;
	return out;
}

} // namespace nk
