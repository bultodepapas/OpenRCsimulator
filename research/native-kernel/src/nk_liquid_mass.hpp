// Finite-resource fixed-datum mass and rigid-body stage laws. Mirrors
// mass_inventory.gd evaluate_reference, rigid_body.gd and fixed_datum_body.gd derivative.
// Configuration preparation, resource events and accepted-step projection stay in GDScript.
#pragma once

#include <array>
#include <cmath>
#include <limits>
#include <vector>

#include "nk_math.hpp"

namespace nk {

struct LiquidMassResource {
	R reference_kg = 0.0;
	R capacity_kg = 0.0;
	std::array<R, 3> center{};
	std::array<R, 6> tensor_per_kg{};
};

struct LiquidMassModel {
	R reference_mass_kg = 0.0;
	std::array<R, 6> reference_inertia{};
	std::vector<LiquidMassResource> resources;
};

struct LiquidMassProperties {
	bool ok = false;
	R mass_kg = 0.0;
	std::array<R, 3> cg{};
	std::array<R, 6> inertia{};
	std::array<R, 6> inverse{};
	std::array<R, 6> inertia_origin{};
};

// LiquidFlight.properties reconstructs absolute onboard mass first, then
// Liquid.properties converts it back to usable inventory. Keep both operations:
// a nonzero unusable residue can introduce a rounding difference.
inline R liquid_trial_onboard_mass(R usable, R unusable, R capacity) {
	return clampf(maxf(0.0, usable) + unusable, unusable, capacity);
}

inline R liquid_inventory_usable_mass(R onboard, R unusable, R capacity) {
	return clampf(maxf(onboard, unusable) - unusable, 0.0, capacity - unusable);
}

inline bool liquid_finite6(const std::array<R, 6> &values) {
	for (R value : values) {
		if (!is_finite(value)) return false;
	}
	return true;
}

// RB.inertia_inverse, with the exact symmetric tensor cofactor order.
inline std::array<R, 6> liquid_inertia_inverse(const std::array<R, 6> &j) {
	const R a = j[0], b = j[1], c = j[2], d = j[3], e = j[4], f = j[5];
	const R c00 = b * c - f * f;
	const R c11 = a * c - e * e;
	const R c22 = a * b - d * d;
	const R c01 = e * f - d * c;
	const R c02 = d * f - b * e;
	const R c12 = d * e - a * f;
	const R det = a * c00 + d * c01 + e * c02;
	return {c00 / det, c11 / det, c22 / det, c01 / det, c02 / det, c12 / det};
}

inline R liquid_tensor_scale(const std::array<R, 6> &tensor) {
	R scale = 0.0;
	for (R value : tensor) scale = maxf(scale, absf(value));
	return scale;
}

inline std::array<R, 6> liquid_normalized_tensor(const std::array<R, 6> &tensor, R scale) {
	std::array<R, 6> result{};
	for (int i = 0; i < 6; ++i) result[i] = tensor[i] / scale;
	return result;
}

inline R liquid_scaled_determinant(const std::array<R, 6> &tensor) {
	if (!liquid_finite6(tensor)) return kNan;
	const R scale = liquid_tensor_scale(tensor);
	if (scale.v == 0.0) return 0.0;
	const auto n = liquid_normalized_tensor(tensor, scale);
	const R a = n[0], b = n[1], c = n[2], d = n[3], e = n[4], f = n[5];
	const R c00 = b * c - f * f;
	const R c01 = e * f - d * c;
	const R c02 = d * f - b * e;
	return a * c00 + d * c01 + e * c02;
}

inline bool liquid_is_spd(const std::array<R, 6> &tensor) {
	if (!liquid_finite6(tensor)) return false;
	const R scale = liquid_tensor_scale(tensor);
	if (scale.v == 0.0) return false;
	const auto n = liquid_normalized_tensor(tensor, scale);
	const R a = n[0], b = n[1], c = n[2], d = n[3], e = n[4], f = n[5];
	return a.v > 0.0 && b.v > 0.0 && c.v > 0.0 && (a * b - d * d).v > 0.0 &&
			(a * c - e * e).v > 0.0 && (b * c - f * f).v > 0.0 && liquid_scaled_determinant(tensor).v > 0.0;
}

inline bool liquid_scaled_spd_inverse(const std::array<R, 6> &tensor, std::array<R, 6> &inverse) {
	if (!liquid_is_spd(tensor)) return false;
	const R scale = liquid_tensor_scale(tensor);
	const auto normalized = liquid_normalized_tensor(tensor, scale);
	const auto normalized_inverse = liquid_inertia_inverse(normalized);
	if (!liquid_finite6(normalized_inverse)) return false;
	inverse = normalized_inverse;
	for (R &value : inverse) value /= scale;
	return liquid_finite6(inverse) && liquid_is_spd(inverse);
}

// The decoder supplies resources in the same order as MassInventory.evaluate_reference.
// Trial amounts must already have the owner's correct clamping/residue convention.
inline LiquidMassProperties liquid_mass_evaluate(const LiquidMassModel &model, const R *amounts, int count) {
	LiquidMassProperties out;
	if (amounts == nullptr || count <= 0 || static_cast<size_t>(count) != model.resources.size()) return out;
	R mass = model.reference_mass_kg;
	for (int i = 0; i < count; ++i) {
		const auto &resource = model.resources[static_cast<size_t>(i)];
		if (!is_finite(amounts[i]) || amounts[i].v < 0.0 || amounts[i].v > resource.capacity_kg.v) return out;
		const R removed = resource.reference_kg - amounts[i];
		mass -= removed;
	}
	if (!is_finite(mass) || mass.v <= 0.0) return out;
	const R first_removed = model.resources[0].reference_kg - amounts[0];
	const R first_scale = -first_removed / mass;
	std::array<R, 3> cg = {model.resources[0].center[0] * first_scale,
		model.resources[0].center[1] * first_scale, model.resources[0].center[2] * first_scale};
	std::array<R, 6> inertia_origin = model.reference_inertia;
	for (int i = 0; i < count; ++i) {
		const auto &resource = model.resources[static_cast<size_t>(i)];
		const R removed = resource.reference_kg - amounts[i];
		if (i > 0) {
			const R scale = -removed / mass;
			for (int k = 0; k < 3; ++k) cg[k] = cg[k] + resource.center[k] * scale;
		}
		for (int k = 0; k < 6; ++k) inertia_origin[k] -= removed * resource.tensor_per_kg[k];
	}
	for (R value : cg) if (!is_finite(value)) return out;
	const R x = cg[0], y = cg[1], z = cg[2];
	// rectangular_box_per_kg(cg, [0,0,0]); the zero-size terms are significant to signed-zero parity.
	const R zero = 0.0;
	const std::array<R, 6> parallel = {(zero * zero + zero * zero) / 12.0 + y * y + z * z,
		(zero * zero + zero * zero) / 12.0 + x * x + z * z,
		(zero * zero + zero * zero) / 12.0 + x * x + y * y, -x * y, -x * z, -y * z};
	std::array<R, 6> inertia = model.reference_inertia;
	for (int k = 0; k < 6; ++k) inertia[k] = inertia_origin[k] - mass * parallel[k];
	const R minor2 = inertia[0] * inertia[1] - inertia[3] * inertia[3];
	const R determinant = inertia[0] * (inertia[1] * inertia[2] - inertia[5] * inertia[5]) +
			inertia[3] * (inertia[4] * inertia[5] - inertia[3] * inertia[2]) +
			inertia[4] * (inertia[3] * inertia[5] - inertia[4] * inertia[1]);
	std::array<R, 6> inverse{};
	bool inverse_ready = false;
	const double minimum_normal = std::numeric_limits<double>::min();
	if (inertia[0].v > 0.0 && is_finite(minor2) && minor2.v >= minimum_normal &&
			is_finite(determinant) && determinant.v >= minimum_normal) {
		inverse = liquid_inertia_inverse(inertia);
		inverse_ready = liquid_finite6(inverse);
	}
	if (!inverse_ready && !liquid_scaled_spd_inverse(inertia, inverse)) return out;
	out.ok = true;
	out.mass_kg = mass;
	out.cg = cg;
	out.inertia = inertia;
	out.inverse = inverse;
	out.inertia_origin = inertia_origin;
	return out;
}

// RigidBody.derivative followed by FixedDatumBody.derivative's co-moving-efflux correction.
// body[13], force[3], moment about live CG[3] and rotor momentum[3] are required. The caller
// supplies a successful stage-local properties sample and validates the resulting derivative.
inline std::array<R, 13> liquid_fixed_datum_derivative(const R *s, const LiquidMassProperties &properties,
		const R *force, const R *moment, R gravity, const R *rotor) {
	const R v0 = s[3], v1 = s[4], v2 = s[5];
	const R q0 = s[6], q1 = s[7], q2 = s[8], q3 = s[9];
	const R w0 = s[10], w1 = s[11], w2 = s[12];
	const R t0 = (q2 * v2 - q3 * v1) * 2.0;
	const R t1 = (q3 * v0 - q1 * v2) * 2.0;
	const R t2 = (q1 * v1 - q2 * v0) * 2.0;
	const R pn = (v0 + t0 * q0) + (q2 * t2 - q3 * t1);
	const R pe = (v1 + t1 * q0) + (q3 * t0 - q1 * t2);
	const R pd = (v2 + t2 * q0) + (q1 * t1 - q2 * t0);
	const R n1 = -q1, n2 = -q2, n3 = -q3;
	const R g0 = (n2 * gravity - n3 * 0.0) * 2.0;
	const R g1 = (n3 * 0.0 - n1 * gravity) * 2.0;
	const R g2 = (n1 * 0.0 - n2 * 0.0) * 2.0;
	const R gx = (0.0 + g0 * q0) + (n2 * g2 - n3 * g1);
	const R gy = (0.0 + g1 * q0) + (n3 * g0 - n1 * g2);
	const R gz = (gravity + g2 * q0) + (n1 * g1 - n2 * g0);
	const R k = 1.0 / properties.mass_kg;
	const R ud = (force[0] * k + gx) - (w1 * v2 - w2 * v1);
	const R vd = (force[1] * k + gy) - (w2 * v0 - w0 * v2);
	const R wd = (force[2] * k + gz) - (w0 * v1 - w1 * v0);
	const R qd0 = (q0 * 0.0 - q1 * w0 - q2 * w1 - q3 * w2) * 0.5;
	const R qd1 = (q0 * w0 + q1 * 0.0 + q2 * w2 - q3 * w1) * 0.5;
	const R qd2 = (q0 * w1 - q1 * w2 + q2 * 0.0 + q3 * w0) * 0.5;
	const R qd3 = (q0 * w2 + q1 * w1 - q2 * w0 + q3 * 0.0) * 0.5;
	const auto &j = properties.inertia;
	const auto &inv = properties.inverse;
	R h0 = j[0] * w0 + j[3] * w1 + j[4] * w2;
	R h1 = j[3] * w0 + j[1] * w1 + j[5] * w2;
	R h2 = j[4] * w0 + j[5] * w1 + j[2] * w2;
	h0 = h0 + rotor[0]; h1 = h1 + rotor[1]; h2 = h2 + rotor[2];
	const R m0 = moment[0] - (w1 * h2 - w2 * h1);
	const R m1 = moment[1] - (w2 * h0 - w0 * h2);
	const R m2 = moment[2] - (w0 * h1 - w1 * h0);
	const R a0 = inv[0] * m0 + inv[3] * m1 + inv[4] * m2;
	const R a1 = inv[3] * m0 + inv[1] * m1 + inv[5] * m2;
	const R a2 = inv[4] * m0 + inv[5] * m1 + inv[2] * m2;
	const auto &cg = properties.cg;
	const R ac0 = a1 * cg[2] - a2 * cg[1];
	const R ac1 = a2 * cg[0] - a0 * cg[2];
	const R ac2 = a0 * cg[1] - a1 * cg[0];
	const R wc0 = w1 * cg[2] - w2 * cg[1];
	const R wc1 = w2 * cg[0] - w0 * cg[2];
	const R wc2 = w0 * cg[1] - w1 * cg[0];
	const R wwc0 = w1 * wc2 - w2 * wc1;
	const R wwc1 = w2 * wc0 - w0 * wc2;
	const R wwc2 = w0 * wc1 - w1 * wc0;
	return {pn, pe, pd, ud - (ac0 + wwc0), vd - (ac1 + wwc1), wd - (ac2 + wwc2),
		qd0, qd1, qd2, qd3, a0, a1, a2};
}

} // namespace nk
