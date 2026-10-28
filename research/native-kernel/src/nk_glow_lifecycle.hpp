// Prepared NITRO lifecycle stage rates: carburettor, mean-cycle source, thermal balance and
// fuel transport. Mirrors glow/lifecycle.gd, carburetor.gd and thermal.gd. Resource/feed
// transitions and the same-stage fuel-feed closure remain the caller's responsibility.
#pragma once

#include <array>
#include <cmath>

#include "nk_glow_source.hpp"

namespace nk {

struct GlowThermalModel {
	R heat_capacity_j_k = 0.0;
	R head_heat_fraction = 0.0;
	R cooling_base_w_k = 0.0;
	R cooling_airflow_w_s_m_k = 0.0;
	R premix_evaporation_j_kg = 0.0;
	R evaporation_head_fraction = 0.0;
};

struct GlowLifecycleModel {
	GlowSourceModel source;
	GlowThermalModel thermal;
	R nominal_mixture = 0.0;
	R idle_opening = 0.0;
	R idle_offset = 0.0;
	R travel_exponent = 0.0;
	R throttle_capacity_m3_s = 0.0;
	R servo_time_constant_s = 0.0;
	R air_time_constant_s = 0.0;
	R fuel_transport_time_constant_s = 0.0;
	R lean_misfire_zero_ratio = 0.0;
	R lean_misfire_start_ratio = 0.0;
	R rich_misfire_start_ratio = 0.0;
	R rich_misfire_zero_ratio = 0.0;
	R temperature_firing_min_k = 0.0;
	R temperature_firing_full_k = 0.0;
	R temperature_firing_hot_full_k = 0.0;
	R temperature_firing_hot_zero_k = 0.0;
};

struct GlowLifecycleState {
	R fuel_kg = 0.0;
	R temperature_k = 0.0;
	R servo_fraction = 0.0;
	R air_fraction = 0.0;
	R fuel_transport_kg_s = 0.0;
	R phase_revolutions = 0.0;
	bool running = false;
};

struct GlowLifecyclePoint {
	bool ok = false;
	GlowSourcePoint source;
	std::array<R, 6> rates{}; // fuel, temperature, servo, air, fuel transport, phase
	R firing_fraction = 0.0;
	R fuel_target_kg_s = 0.0;
	R admission = 0.0;
	R actual_mixture = 0.0;
};

constexpr double kGlowCriticalRatio = 0.5282817877171742;
constexpr double kGlowPsiChoked = 0.6847314563772704;

inline R glow_carb_charge_ratio(R y) {
	if (!is_finite(y) || y.v < 0.0) return kNan;
	if (y.v <= kGlowCriticalRatio) return y;
	const R gamma = 1.4;
	const R a = y * sqrt_(2.0 * gamma / (gamma - 1.0)) / kGlowPsiChoked;
	const R t = 2.0 / (1.0 + sqrt_(1.0 + 4.0 / (a * a)));
	return pow_(t, gamma / (gamma - 1.0));
}

inline R glow_carb_lens_fraction(R u) {
	if (!is_finite(u)) return kNan;
	if (u.v <= 0.0) return 1.0;
	if (u.v >= 1.0) return 0.0;
	// Here u is strictly inside [0,1], so Math3d.acos_ is the same glibc acos
	// on the supported Linux engine; the invalid-domain clamp is never reached.
	return R(2.0) / kPi * (R(::acos(u.v)) - u * sqrt_(1.0 - u * u));
}

inline R glow_carb_idle_offset(R idle_opening) {
	if (!is_finite(idle_opening) || idle_opening.v <= 0.0 || idle_opening.v >= 1.0) return kNan;
	R lo = 0.0, hi = 1.0;
	for (int i = 0; i < 64; ++i) {
		const R mid = 0.5 * (lo + hi);
		if (glow_carb_lens_fraction(mid).v > idle_opening.v) lo = mid;
		else hi = mid;
	}
	return 0.5 * (lo + hi);
}

inline R glow_carb_capacity(R area_m2) {
	if (!is_finite(area_m2) || area_m2.v <= 0.0) return kNan;
	return area_m2 * kGlowPsiChoked * sqrt_(R(287.05) * 288.15);
}

inline R glow_carb_opening(R servo, R idle_offset, R exponent) {
	if (!is_finite(servo) || !is_finite(idle_offset) || idle_offset.v < 0.0 || idle_offset.v > 1.0 ||
			!is_finite(exponent) || exponent.v <= 0.0) return kNan;
	const R closed = 1.0 - clampf(servo, 0.0, 1.0);
	return glow_carb_lens_fraction(idle_offset * (closed.v > 0.0 ? pow_(closed, exponent) : R(0.0)));
}

inline R glow_carb_admission(R open_fraction, R rpm, R breathing, R displacement,
		R cycle_revolutions, R capacity) {
	if (!is_finite(open_fraction) || open_fraction.v <= 0.0 || open_fraction.v > 1.0 ||
			!is_finite(capacity) || capacity.v <= 0.0 || !is_finite(rpm) || rpm.v < 0.0 ||
			!is_finite(breathing) || breathing.v < 0.0 || !is_finite(displacement) || displacement.v <= 0.0 ||
			!is_finite(cycle_revolutions) || cycle_revolutions.v <= 0.0) return kNan;
	const R demand = displacement * breathing * rpm / (60.0 * cycle_revolutions);
	if (!is_finite(demand)) return kNan;
	if (demand.v <= 0.0) return 1.0;
	const R x = demand / capacity;
	const R restricted = glow_carb_charge_ratio(open_fraction / x);
	const R wide_open = glow_carb_charge_ratio(1.0 / x);
	if (!is_finite(restricted) || !is_finite(wide_open) || wide_open.v <= 0.0) return kNan;
	return minf(restricted / wide_open, 1.0);
}

inline R glow_smoothstep(R value) {
	const R x = clampf(value, 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}

inline R glow_firing_fraction(const GlowLifecycleModel &model, R actual_mixture, R temperature) {
	if (actual_mixture.v <= 0.0) return 0.0;
	const R relative = actual_mixture / model.nominal_mixture;
	R factor = 1.0;
	if (relative.v <= model.lean_misfire_zero_ratio.v) {
		factor = 0.0;
	} else if (relative.v < model.lean_misfire_start_ratio.v) {
		const R x = (relative - model.lean_misfire_zero_ratio) /
				(model.lean_misfire_start_ratio - model.lean_misfire_zero_ratio);
		factor = glow_smoothstep(x);
	} else if (relative.v > model.rich_misfire_start_ratio.v) {
		const R x = (model.rich_misfire_zero_ratio - relative) /
				(model.rich_misfire_zero_ratio - model.rich_misfire_start_ratio);
		factor = glow_smoothstep(x);
	}
	const R cold = (temperature - model.temperature_firing_min_k) /
			(model.temperature_firing_full_k - model.temperature_firing_min_k);
	const R hot = (model.temperature_firing_hot_zero_k - temperature) /
			(model.temperature_firing_hot_zero_k - model.temperature_firing_hot_full_k);
	return clampf(factor * glow_smoothstep(cold) * glow_smoothstep(hot), 0.0, 1.0);
}

struct GlowThermalPoint { bool ok = false; R temperature_rate = 0.0; };

inline GlowThermalPoint glow_thermal_evaluate(const GlowSourcePoint &source, const GlowThermalModel &model,
		R temperature, R ambient, R cooling_speed) {
	GlowThermalPoint out;
	if (!source.ok || !is_finite(temperature) || temperature.v <= 0.0 || !is_finite(ambient) || ambient.v <= 0.0 ||
			!is_finite(cooling_speed) || cooling_speed.v < 0.0) return out;
	const R rejected = source.chemical_power_w - source.indicated_power_w;
	if (rejected.v < 0.0) return out;
	const R mechanical_heat = source.mechanical_loss_w + source.pumping_loss_w + source.valve_loss_w;
	const R combustion_to_head = rejected * model.head_heat_fraction;
	const R exhaust_heat = rejected - combustion_to_head;
	const R evaporation = source.delivered_fuel_kg_s * model.premix_evaporation_j_kg * model.evaporation_head_fraction;
	const R conductance = model.cooling_base_w_k + model.cooling_airflow_w_s_m_k * cooling_speed;
	const R cooling = conductance * (temperature - ambient);
	const R stored = combustion_to_head + mechanical_heat - evaporation - cooling;
	const R rate = stored / model.heat_capacity_j_k;
	if (!is_finite(exhaust_heat) || !is_finite(evaporation) || !is_finite(cooling) ||
			!is_finite(stored) || !is_finite(rate)) return out;
	out.ok = true;
	out.temperature_rate = rate;
	return out;
}

// The caller has validated discrete lifecycle fields and applied GlowFlight.point's
// negative-fuel left-limit convention before this pure prepared-stage evaluation.
inline GlowLifecyclePoint glow_lifecycle_evaluate(const GlowLifecycleModel &model, const GlowLifecycleState &state,
		R rpm, R throttle, R mixture, R dry_density, R ambient, R cooling_speed, R feed_factor, R unusable_fuel) {
	GlowLifecyclePoint out;
	const R state_values[] = {state.fuel_kg, state.temperature_k, state.servo_fraction, state.air_fraction,
		state.fuel_transport_kg_s, state.phase_revolutions};
	for (R value : state_values) if (!is_finite(value)) return out;
	if (state.temperature_k.v <= 0.0 || state.phase_revolutions.v < 0.0 || !is_finite(rpm) || rpm.v < 0.0 ||
			rpm.v > model.source.max_rpm.v || !is_finite(throttle) || throttle.v < 0.0 || throttle.v > 1.0 ||
			!is_finite(mixture) || mixture.v < 0.0 || !is_finite(dry_density) || dry_density.v <= 0.0 ||
			!is_finite(ambient) || ambient.v <= 0.0 || !is_finite(cooling_speed) || cooling_speed.v < 0.0 ||
			!is_finite(feed_factor) || feed_factor.v < 0.0 || !is_finite(unusable_fuel) || unusable_fuel.v < 0.0 ||
			!glow_source_shapes_valid(model.source)) return out;
	const R servo = clampf(state.servo_fraction, 0.0, 1.0);
	const R opening = clampf(state.air_fraction, model.idle_opening, 1.0);
	const R breathing = glow_source_table_sample(model.source.breathing, rpm);
	const R cycle = model.source.family == GlowFamily::TwoStroke ? R(1.0) : R(2.0);
	const R admission = glow_carb_admission(opening, rpm, breathing, model.source.displacement_m3,
			cycle, model.throttle_capacity_m3_s);
	if (!is_finite(admission)) return out;
	const R air_target = glow_carb_opening(servo, model.idle_offset, model.travel_exponent);
	const R servo_rate = (throttle - state.servo_fraction) / model.servo_time_constant_s;
	const R air_rate = (air_target - state.air_fraction) / model.air_time_constant_s;
	const bool active = state.running && state.fuel_kg.v > unusable_fuel.v;
	R target_fuel_flow = 0.0;
	R actual_mixture = mixture;
	const R current_transport = maxf(0.0, state.fuel_transport_kg_s);
	if (active && admission.v > 0.0) {
		const R baseline_mixture = mixture.v > 0.0 ? mixture : model.nominal_mixture;
		const GlowUnitFlow flow = glow_unit_fuel_flow(model.source, rpm, admission, baseline_mixture, dry_density);
		if (!flow.ok) return out;
		target_fuel_flow = flow.kg_s_per_mixture * mixture * feed_factor;
		actual_mixture = flow.kg_s_per_mixture.v > 1e-15 ? current_transport / flow.kg_s_per_mixture : mixture;
	}
	R firing = 0.0;
	if (active) firing = glow_firing_fraction(model, actual_mixture, state.temperature_k);
	const GlowSourcePoint source = glow_source_evaluate(model.source, rpm, admission, actual_mixture,
			dry_density, active, firing);
	if (!source.ok) return out;
	const GlowThermalPoint thermal = glow_thermal_evaluate(source, model.thermal, state.temperature_k,
			ambient, cooling_speed);
	if (!thermal.ok) return out;
	const R transport_rate = active ? (target_fuel_flow - current_transport) / model.fuel_transport_time_constant_s :
			-current_transport / model.fuel_transport_time_constant_s;
	const R fuel_rate = -source.delivered_fuel_kg_s;
	const R phase_rate = rpm / 60.0;
	const std::array<R, 6> rates = {fuel_rate, thermal.temperature_rate, servo_rate, air_rate, transport_rate, phase_rate};
	for (R value : rates) if (!is_finite(value)) return out;
	out.ok = true;
	out.source = source;
	out.rates = rates;
	out.firing_fraction = firing;
	out.fuel_target_kg_s = target_fuel_flow;
	out.admission = admission;
	out.actual_mixture = actual_mixture;
	return out;
}

} // namespace nk
