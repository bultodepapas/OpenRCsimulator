// NITRO fuel-feed pressure and bounded factor solve, mirroring glow/fuel_feed.gd.
// The callback supplied to the solver is a native pure stage evaluator. Pickup/line
// transition events remain with the GDScript session.
#pragma once

#include <array>

#include "nk_math.hpp"

namespace nk {

struct GlowFeedModel {
	std::array<R, 3> carburetor{};
	std::array<R, 3> tank_center{};
	std::array<R, 3> tank_size{};
	R density_kg_m3 = 0.0;
	R idle_drive_pressure_pa = 0.0;
	R wot_drive_pressure_pa = 0.0;
	R rated_rpm = 0.0;
};

struct GlowFeedContext {
	bool ok = false;
	R fill_fraction = 0.0;
	R remaining_fuel_kg = 0.0;
	R unusable_fuel_kg = 0.0;
	R drive_pa = 0.0;
	R needled_head_pa = 0.0;
};

inline R glow_feed_head(const R *g_eff, R fill, const R *carburetor, const R *tank_center,
		const R *tank_size, R density) {
	const R gravity = sqrt_(g_eff[0] * g_eff[0] + g_eff[1] * g_eff[1] + g_eff[2] * g_eff[2]);
	if (gravity.v < 1e-6) return 0.0;
	const R scale = 1.0 / gravity;
	const R d0 = g_eff[0] * scale, d1 = g_eff[1] * scale, d2 = g_eff[2] * scale;
	const R depth = absf(d0) * tank_size[0] + absf(d1) * tank_size[1] + absf(d2) * tank_size[2];
	const R surface = (d0 * tank_center[0] + d1 * tank_center[1] + d2 * tank_center[2]) +
			(0.5 - clampf(fill, 0.0, 1.0)) * depth;
	return density * gravity * ((d0 * carburetor[0] + d1 * carburetor[1] + d2 * carburetor[2]) - surface);
}

inline R glow_feed_pickup_margin(const R *g_eff, R fill, const R *pickup, const R *tank_center,
		const R *tank_size) {
	if (!is_finite(fill) || fill.v < 0.0 || fill.v > 1.0) return kNan;
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(g_eff[i]) || !is_finite(pickup[i]) || !is_finite(tank_center[i]) ||
				!is_finite(tank_size[i])) return kNan;
	}
	const R gravity = sqrt_(g_eff[0] * g_eff[0] + g_eff[1] * g_eff[1] + g_eff[2] * g_eff[2]);
	if (!is_finite(gravity) || gravity.v < 1e-6) return kNan;
	const R scale = 1.0 / gravity;
	const R d0 = g_eff[0] * scale, d1 = g_eff[1] * scale, d2 = g_eff[2] * scale;
	const R depth = absf(d0) * tank_size[0] + absf(d1) * tank_size[1] + absf(d2) * tank_size[2];
	const R surface = (d0 * tank_center[0] + d1 * tank_center[1] + d2 * tank_center[2]) + (0.5 - fill) * depth;
	return (d0 * pickup[0] + d1 * pickup[1] + d2 * pickup[2]) - surface;
}

inline R glow_feed_drive(R admission, R rpm, const GlowFeedModel &model) {
	const R flow_share = clampf(admission, 0.0, 1.0) * maxf(0.0, rpm) / model.rated_rpm;
	return minf(model.wot_drive_pressure_pa, model.idle_drive_pressure_pa +
			(model.wot_drive_pressure_pa - model.idle_drive_pressure_pa) * flow_share * flow_share);
}

inline R glow_feed_pressure_factor(R drive, R head, R needled_head) {
	const R needled = drive + needled_head;
	if (needled.v <= 0.0) return 0.0;
	return clampf(sqrt_(maxf(0.0, drive + head) / needled), 0.0, 2.0);
}

inline GlowFeedContext glow_feed_prepare_context(const GlowFeedModel &model, R remaining_fuel, R capacity,
		R unusable, R admission, R rpm) {
	GlowFeedContext out;
	if (!is_finite(remaining_fuel) || !is_finite(capacity) || capacity.v <= 0.0 || !is_finite(unusable) ||
			unusable.v < 0.0 || unusable.v >= capacity.v || !is_finite(admission) || !is_finite(rpm) || rpm.v < 0.0) return out;
	const R reference_g[3] = {0.0, 0.0, 9.80665};
	out.ok = true;
	out.fill_fraction = clampf(remaining_fuel / capacity, 0.0, 1.0);
	out.remaining_fuel_kg = remaining_fuel;
	out.unusable_fuel_kg = unusable;
	out.drive_pa = glow_feed_drive(admission, rpm, model);
	out.needled_head_pa = glow_feed_head(reference_g, 1.0, model.carburetor.data(), model.tank_center.data(),
			model.tank_size.data(), model.density_kg_m3);
	return out;
}

// FuelFeed.factor_for_stage. pickup may be null when no pickup is authored.
inline R glow_feed_factor_for_stage(const GlowFeedContext &context, const GlowFeedModel &model,
		const R *force, R mass, const R *tank_arm, const R *alpha, const R *omega, const R *pickup = nullptr) {
	if (!context.ok || force == nullptr || tank_arm == nullptr || alpha == nullptr || omega == nullptr ||
			!is_finite(mass) || mass.v <= 0.0) return kNan;
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(force[i]) || !is_finite(tank_arm[i]) || !is_finite(alpha[i]) || !is_finite(omega[i])) return kNan;
	}
	const R translation_scale = -1.0 / mass;
	const R trans0 = force[0] * translation_scale, trans1 = force[1] * translation_scale,
			trans2 = force[2] * translation_scale;
	const R ac0 = alpha[1] * tank_arm[2] - alpha[2] * tank_arm[1];
	const R ac1 = alpha[2] * tank_arm[0] - alpha[0] * tank_arm[2];
	const R ac2 = alpha[0] * tank_arm[1] - alpha[1] * tank_arm[0];
	const R wc0 = omega[1] * tank_arm[2] - omega[2] * tank_arm[1];
	const R wc1 = omega[2] * tank_arm[0] - omega[0] * tank_arm[2];
	const R wc2 = omega[0] * tank_arm[1] - omega[1] * tank_arm[0];
	const R wwc0 = omega[1] * wc2 - omega[2] * wc1;
	const R wwc1 = omega[2] * wc0 - omega[0] * wc2;
	const R wwc2 = omega[0] * wc1 - omega[1] * wc0;
	const R g_eff[3] = {trans0 - (ac0 + wwc0), trans1 - (ac1 + wwc1), trans2 - (ac2 + wwc2)};
	const R head = glow_feed_head(g_eff, context.fill_fraction, model.carburetor.data(), model.tank_center.data(),
			model.tank_size.data(), model.density_kg_m3);
	bool pickup_wet = true;
	if (pickup != nullptr) {
		const R margin = glow_feed_pickup_margin(g_eff, context.fill_fraction, pickup,
				model.tank_center.data(), model.tank_size.data());
		if (!is_finite(margin)) return kNan;
		pickup_wet = margin.v >= 0.0;
	}
	if (context.remaining_fuel_kg.v <= context.unusable_fuel_kg.v) return 0.0;
	return pickup_wet ? glow_feed_pressure_factor(context.drive_pa, head, context.needled_head_pa) : R(0.0);
}

template <typename Payload> struct GlowFeedProbe {
	bool ok = false;
	R target_factor = 0.0;
	Payload payload{};
};

template <typename Payload> struct GlowFeedSolution {
	bool ok = false;
	R factor = 0.0;
	R target_factor = 0.0;
	R residual = 0.0;
	int evaluations = 0;
	int iterations = 0;
	Payload payload{};
};

// Callable signature: GlowFeedProbe<Payload>(R factor). The selected payload is retained,
// avoiding an extra stage evaluation or a GDScript callback. Failure rejects the stage.
template <typename Payload, typename Evaluate>
inline GlowFeedSolution<Payload> glow_feed_solve(Evaluate &&evaluate, R seed = 1.0) {
	using Solution = GlowFeedSolution<Payload>;
	auto sample = [&](R factor) -> Solution {
		Solution result;
		const GlowFeedProbe<Payload> raw = evaluate(factor);
		if (!raw.ok || !is_finite(raw.target_factor) || raw.target_factor.v < 0.0 || raw.target_factor.v > 2.0) return result;
		result.ok = true;
		result.factor = factor;
		result.target_factor = raw.target_factor;
		result.residual = factor - raw.target_factor;
		result.payload = raw.payload;
		return result;
	};
	Solution failure;
	if (!is_finite(seed)) return failure;
	R low = 0.0, high = 2.0;
	Solution low_sample = sample(low), high_sample = sample(high);
	if (!low_sample.ok || !high_sample.ok) return failure;
	R low_residual = low_sample.residual, high_residual = high_sample.residual;
	int evaluations = 2;
	if (low_residual.v > 0.0 || high_residual.v < 0.0) return failure;
	if (absf(low_residual).v <= 1e-8) { low_sample.evaluations = evaluations; return low_sample; }
	if (absf(high_residual).v <= 1e-8) { high_sample.evaluations = evaluations; return high_sample; }
	R candidate = clampf(seed, low, high);
	if (candidate.v <= low.v || candidate.v >= high.v) candidate = 0.5 * (low + high);
	Solution current = sample(candidate);
	++evaluations;
	if (!current.ok) return failure;
	if (absf(current.residual).v <= 1e-8) { current.evaluations = evaluations; return current; }
	if (current.residual.v < 0.0) {
		low = candidate; low_residual = current.residual; low_sample = current;
	} else {
		high = candidate; high_residual = current.residual; high_sample = current;
	}
	for (int iteration = 0; iteration < 32; ++iteration) {
		const R width = high - low;
		const R denominator = high_residual - low_residual;
		R next = denominator.v != 0.0 ? high - high_residual * width / denominator : R(kNan);
		const R guard = width * 1e-6;
		if (!is_finite(next) || next.v <= (low + guard).v || next.v >= (high - guard).v) next = low + 0.5 * width;
		current = sample(next);
		++evaluations;
		if (!current.ok) return failure;
		if (absf(current.residual).v <= 1e-8) {
			current.evaluations = evaluations;
			current.iterations = iteration + 1;
			return current;
		}
		if (current.residual.v < 0.0) {
			low = next; low_residual = current.residual; low_sample = current;
		} else {
			high = next; high_residual = current.residual; high_sample = current;
		}
	}
	return failure;
}

} // namespace nk
