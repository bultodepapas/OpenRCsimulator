// NK-3: fixed-axis single-rotor response, mirroring RotorCoupling.response in
// app/physics/rotor_coupling.gd. This is the stage solve, not the distinct multi-rotor system
// or the event locator/projection. Shapes are validated by the caller before passing pointers.
#pragma once

#include <array>

#include "nk_math.hpp"

namespace nk {

struct RotorCouplingResult {
	bool ok = false;
	R spin_acceleration = 0.0;
	std::array<R, 3> reaction{};
	std::array<R, 3> momentum{};
};

// Inertia and inverse use [xx, yy, zz, xy, xz, yz]. The moment is the complete
// external moment about the live CG; relative_speed is rad/s and torque is N m.
inline RotorCouplingResult rotor_coupling_response(const R *body_rate, const R *external_moment,
		const R *inertia, const R *inertia_inverse, const R *axis, R rotor_inertia,
		R relative_speed, R net_shaft_torque) {
	RotorCouplingResult out;
	if (body_rate == nullptr || external_moment == nullptr || inertia == nullptr || inertia_inverse == nullptr ||
			axis == nullptr) {
		return out;
	}
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(body_rate[i])) {
			return out;
		}
	}
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(external_moment[i])) {
			return out;
		}
	}
	for (int i = 0; i < 6; ++i) {
		if (!is_finite(inertia[i])) {
			return out;
		}
	}
	for (int i = 0; i < 6; ++i) {
		if (!is_finite(inertia_inverse[i])) {
			return out;
		}
	}
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(axis[i])) {
			return out;
		}
	}
	if (absf(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2] - 1.0).v > 1e-12) {
		return out;
	}
	const R inverse_axis_x = inertia_inverse[0] * axis[0] + inertia_inverse[3] * axis[1] + inertia_inverse[4] * axis[2];
	const R inverse_axis_y = inertia_inverse[3] * axis[0] + inertia_inverse[1] * axis[1] + inertia_inverse[5] * axis[2];
	const R inverse_axis_z = inertia_inverse[4] * axis[0] + inertia_inverse[5] * axis[1] + inertia_inverse[2] * axis[2];
	const R axis_inverse_axis = axis[0] * inverse_axis_x + axis[1] * inverse_axis_y + axis[2] * inverse_axis_z;
	const R denominator = 1.0 - rotor_inertia * axis_inverse_axis;
	if (!is_finite(denominator) || denominator.v <= 0.0 || !is_finite(rotor_inertia) || rotor_inertia.v <= 0.0 ||
			!is_finite(relative_speed) || relative_speed.v < 0.0 || !is_finite(net_shaft_torque)) {
		return out;
	}
	const R momentum_scale = rotor_inertia * relative_speed;
	const R momentum_x = axis[0] * momentum_scale;
	const R momentum_y = axis[1] * momentum_scale;
	const R momentum_z = axis[2] * momentum_scale;
	const R total_h_x = inertia[0] * body_rate[0] + inertia[3] * body_rate[1] + inertia[4] * body_rate[2] + momentum_x;
	const R total_h_y = inertia[3] * body_rate[0] + inertia[1] * body_rate[1] + inertia[5] * body_rate[2] + momentum_y;
	const R total_h_z = inertia[4] * body_rate[0] + inertia[5] * body_rate[1] + inertia[2] * body_rate[2] + momentum_z;
	const R cross_x = body_rate[1] * total_h_z - body_rate[2] * total_h_y;
	const R cross_y = body_rate[2] * total_h_x - body_rate[0] * total_h_z;
	const R cross_z = body_rate[0] * total_h_y - body_rate[1] * total_h_x;
	const R moment_delta_x = external_moment[0] - cross_x;
	const R moment_delta_y = external_moment[1] - cross_y;
	const R moment_delta_z = external_moment[2] - cross_z;
	const R unreacted_x = inertia_inverse[0] * moment_delta_x + inertia_inverse[3] * moment_delta_y + inertia_inverse[4] * moment_delta_z;
	const R unreacted_y = inertia_inverse[3] * moment_delta_x + inertia_inverse[1] * moment_delta_y + inertia_inverse[5] * moment_delta_z;
	const R unreacted_z = inertia_inverse[4] * moment_delta_x + inertia_inverse[5] * moment_delta_y + inertia_inverse[2] * moment_delta_z;
	const R axial_unreacted = axis[0] * unreacted_x + axis[1] * unreacted_y + axis[2] * unreacted_z;
	const R acceleration = (net_shaft_torque / rotor_inertia - axial_unreacted) / denominator;
	const R reaction_scale = -rotor_inertia * acceleration;
	const R reaction_x = axis[0] * reaction_scale;
	const R reaction_y = axis[1] * reaction_scale;
	const R reaction_z = axis[2] * reaction_scale;
	if (!is_finite(acceleration)) {
		return out;
	}
	if (!is_finite(reaction_x) || !is_finite(reaction_y) || !is_finite(reaction_z)) {
		return out;
	}
	out.ok = true;
	out.spin_acceleration = acceleration;
	out.reaction = {reaction_x, reaction_y, reaction_z};
	out.momentum = {momentum_x, momentum_y, momentum_z};
	return out;
}

} // namespace nk
