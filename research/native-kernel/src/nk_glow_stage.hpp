// Godot-independent GlowFlight point/evaluate composition. The first step
// samples the stage state, mass and blade; the shared airframe/ground code then
// uses that blade wrench and appropriate live mass; finish closes fuel feed,
// lifecycle and rotor dynamics without calling back into GDScript. Events,
// source-mode transitions and accepted-endpoint projection stay with session.
#pragma once

#include <array>
#include <cmath>
#include <vector>

#include "nk_glow_coupling.hpp"
#include "nk_glow_feed.hpp"
#include "nk_glow_mass.hpp"

namespace nk {

struct GlowStageModel {
	bool ready = false;
	GlowLifecycleModel lifecycle;
	GlowBladeModel blade;
	LiquidMassModel mass;
	bool has_feed = false;
	GlowFeedModel feed;
	bool has_pickup = false;
	std::array<R, 3> pickup{};
	bool has_line = false;
	R main_capacity_kg = 0.0;
	R line_capacity_kg = 0.0;
	R unusable_kg = 0.0;
};

struct GlowStageTrial {
	bool ok = false;
	GlowLifecycleState state;
	GlowStageMass stage_mass; // _stage_mass_context
	LiquidMassProperties raw_mass; // properties(raw total, raw line), used by hull/no-feed
	GlowBladePoint blade;
	std::array<R, 6> blade_loads{};
	std::array<R, 3> hub_air{};
	R rpm = 0.0;
	R density = 0.0;
	R dry_density = 0.0;
	R ambient_k = 0.0;
	R cooling_mps = 0.0;
	R mixture = 0.0;
	R lifecycle_floor = 0.0;
	double mode = 0.0; // GDScript int(value[18]) after truncation
};

struct GlowStageResult {
	bool ok = false;
	std::array<R, 6> loads{}; // output wrench at the fixed datum
	std::vector<R> derivative; // 19 glow slots, then wheel rates
	std::array<R, 3> rotor{};
	std::array<R, 13> body_derivative{};
	R feed_factor = 1.0;
};

// GlowFlight.properties(raw total, raw line); unlike _stage_mass_context this
// does not first clamp the line and reconstruct total before subtracting it.
inline LiquidMassProperties glow_raw_mass(const GlowStageModel &model, R total, R line) {
	if (!is_finite(total) || !is_finite(line)) return {};
	if (model.has_line) {
		const R amounts[2] = {clampf(total - line, 0.0, model.main_capacity_kg),
				clampf(line, 0.0, model.line_capacity_kg)};
		return liquid_mass_evaluate(model.mass, amounts, 2);
	}
	if (absf(line).v > 1e-15) return {};
	const R amount[1] = {clampf(total, 0.0, model.main_capacity_kg)};
	return liquid_mass_evaluate(model.mass, amount, 1);
}

// state is the 19-entry serialized GlowFlight prefix plus wheel states.
// hub_air has already been resolved by Propulsion.stage_air_velocity; it must
// be the same local inflow used for blade loads and cooling. `injected_cut`
// represents the session's failure cut and differs from simply switching off:
// Life.cut clears the transported fuel before evaluating this stage.
inline GlowStageTrial glow_stage_prepare(const GlowStageModel &model, const PropModel &prop,
		const R *body, const R *values, int count, int wheel_count, const R *hub_air,
		R density, R charge_ratio, R ambient_k, bool engine_running, bool injected_cut) {
	GlowStageTrial out;
	if (!model.ready || body == nullptr || values == nullptr || hub_air == nullptr || wheel_count < 0 ||
			count != 19 + wheel_count) return out;
	for (int i = 0; i < count; ++i) if (!is_finite(values[i])) return out;
	for (int i = 0; i < 3; ++i) if (!is_finite(hub_air[i])) return out;
	if ((values[7].v != 0.0 && values[7].v != 1.0) || values[8].v != std::floor(values[8].v) ||
			values[8].v < 0.0 || values[8].v >= 7.0 || values[11].v < 0.0 || values[11].v >= 1.0) return out;
	// unpack casts counters to int before lifecycle validation. Out-of-range
	// casts are refused instead of invoking undefined C++ integer conversion.
	const double count_limit = 9223372036854775808.0;
	const double opportunities = std::trunc(values[9].v), fires = std::trunc(values[10].v);
	if (opportunities < 0.0 || fires < 0.0 || opportunities >= count_limit || fires >= count_limit || fires > opportunities) return out;
	GlowLifecycleState state;
	state.fuel_kg = values[1]; state.temperature_k = values[2]; state.servo_fraction = values[3];
	state.air_fraction = values[4]; state.fuel_transport_kg_s = values[5]; state.phase_revolutions = values[6];
	state.running = values[7].v == 1.0;
	if (state.fuel_kg.v < 0.0) state.fuel_kg = 1e-30;
	if (state.temperature_k.v <= 0.0 || state.phase_revolutions.v < 0.0) return out;
	if (injected_cut) {
		// Life.cut validates accepted transport and clears it, before stage evaluation.
		if (state.fuel_transport_kg_s.v < 0.0) return out;
		state.running = false;
		state.fuel_transport_kg_s = 0.0;
	} else if (!engine_running) {
		state.running = false;
	}
	const GlowStageMass mass = glow_stage_mass(model.mass, values[1], values[17], model.main_capacity_kg,
			model.has_line, model.line_capacity_kg);
	if (!mass.ok) return out;
	const double mode = std::trunc(values[18].v);
	if (mode == 1.0 && !model.has_line && mass.main_fuel_kg.v <= model.unusable_kg.v) {
		// Connected left limit while locating the residue boundary.
		state.fuel_kg = model.unusable_kg + 1e-30;
	}
	const R rpm = maxf(0.0, values[0]);
	const R axis[3] = {prop.has_axis ? prop.axis[0] : R(1.0), prop.has_axis ? prop.axis[1] : R(0.0),
			prop.has_axis ? prop.axis[2] : R(0.0)};
	const R axial = hub_air[0] * axis[0] + hub_air[1] * axis[1] + hub_air[2] * axis[2];
	const GlowBladePoint blade = glow_blade_evaluate(model.blade, rpm, axial, density);
	if (!blade.ok) return out;
	const R speed = sqrt_(hub_air[0] * hub_air[0] + hub_air[1] * hub_air[1] + hub_air[2] * hub_air[2]);
	const R cooling = speed + sqrt_(maxf(0.0, blade.thrust_n) /
			(2.0 * density * R(kPi) * prop.diameter * prop.diameter / 4.0));
	out.state = state;
	out.stage_mass = mass;
	out.raw_mass = glow_raw_mass(model, values[1], values[17]);
	out.blade = blade;
	out.blade_loads = prop_loads_from_thrust_torque(hub_air, rpm, prop, density, blade.thrust_n, blade.torque_nm);
	for (int i = 0; i < 3; ++i) out.hub_air[i] = hub_air[i];
	out.rpm = rpm;
	out.density = density;
	out.dry_density = 1.225 * charge_ratio;
	out.ambient_k = ambient_k;
	out.cooling_mps = cooling;
	out.mixture = values[12];
	out.lifecycle_floor = model.has_line ? R(0.0) : model.unusable_kg;
	out.mode = mode;
	out.ok = true;
	return out;
}

struct GlowStageFeedPayload {
	GlowLifecyclePoint life;
	GlowCoupledStage coupling;
};

// The exact stage's airframe+propeller+ground external wrench is supplied at
// fixed datum O. With a feed block it must be evaluated before lifecycle/feed
// closure; otherwise it can be evaluated after the trial blade. `wheel_rates`
// must be from that same ground sample. The feed solve invokes only native
// pure functions and never crosses the Godot boundary.
inline GlowStageResult glow_stage_finish(const GlowStageModel &model, const GlowStageTrial &trial,
		const PropModel &prop, const R *body, const R *values, const R *external,
		const R *wheel_rates, int wheel_count, R throttle, R gravity) {
	GlowStageResult out;
	if (!model.ready || !trial.ok || body == nullptr || values == nullptr || external == nullptr || wheel_count < 0 ||
			(wheel_count > 0 && wheel_rates == nullptr)) return out;
	// With feed the point owns the clipped stage mass; otherwise evaluate()
	// falls back to raw properties. The ground owner may need raw mass in both.
	const LiquidMassProperties &mass = model.has_feed ? trial.stage_mass.properties : trial.raw_mass;
	if (!mass.ok) return out;
	const GlowLifecycleState &state = trial.state;
	GlowLifecyclePoint life;
	GlowCoupledStage coupling;
	R feed_factor = trial.mode == 0.0 ? R(0.0) : R(1.0);
	const R *omega = body + 10;
	R tank_arm[3] = {model.feed.tank_center[0] - mass.cg[0], model.feed.tank_center[1] - mass.cg[1],
			model.feed.tank_center[2] - mass.cg[2]};
	if (model.has_feed && trial.mode == 1.0) {
		const R solve_fuel = maxf(trial.stage_mass.main_fuel_kg, model.unusable_kg + 1e-30);
		// Flight.admission_at uses the raw lifecycle air_fraction, not the
		// lifecycle evaluator's clamped opening.
		const R breathing = glow_source_table_sample(model.lifecycle.source.breathing, trial.rpm);
		const R cycle = model.lifecycle.source.family == GlowFamily::TwoStroke ? R(1.0) : R(2.0);
		const R admission = glow_carb_admission(state.air_fraction, trial.rpm, breathing,
				model.lifecycle.source.displacement_m3, cycle, model.lifecycle.throttle_capacity_m3_s);
		const auto context = glow_feed_prepare_context(model.feed, solve_fuel, model.main_capacity_kg,
				model.unusable_kg, admission, trial.rpm);
		if (!context.ok) return out;
		const GlowLifecyclePoint base = glow_lifecycle_evaluate(model.lifecycle, state, trial.rpm, throttle,
				trial.mixture, trial.dry_density, trial.ambient_k, trial.cooling_mps, 1.0, trial.lifecycle_floor);
		GlowCoupledStage base_coupling;
		if (base.ok) base_coupling = glow_coupled_stage(body, external, values, prop, model.lifecycle, state,
				base, trial.blade, mass, trial.dry_density, gravity);
		const bool reuse = base.ok && base_coupling.ok;
		const R current = maxf(0.0, state.fuel_transport_kg_s);
		const bool active = state.running && state.fuel_kg.v > trial.lifecycle_floor.v;
		R target = kNan;
		if (reuse) target = glow_feed_factor_for_stage(context, model.feed, external, mass.mass_kg, tank_arm,
				base_coupling.body_derivative.data() + 10, omega, model.has_pickup ? model.pickup.data() : nullptr);
		auto solve = glow_feed_solve<GlowStageFeedPayload>([&](R candidate) {
			GlowFeedProbe<GlowStageFeedPayload> probe;
			GlowLifecyclePoint sampled;
			GlowCoupledStage response;
			if (reuse) {
				sampled = base;
				const R flow = base.fuel_target_kg_s * candidate;
				const R rate = active ? (flow - current) / model.lifecycle.fuel_transport_time_constant_s :
						-current / model.lifecycle.fuel_transport_time_constant_s;
				if (!is_finite(rate)) return probe;
				sampled.fuel_target_kg_s = flow;
				sampled.rates[4] = rate;
				response = base_coupling;
			} else {
				sampled = glow_lifecycle_evaluate(model.lifecycle, state, trial.rpm, throttle,
						trial.mixture, trial.dry_density, trial.ambient_k, trial.cooling_mps, candidate, trial.lifecycle_floor);
				if (!sampled.ok) return probe;
				response = glow_coupled_stage(body, external, values, prop, model.lifecycle, state,
						sampled, trial.blade, mass, trial.dry_density, gravity);
			}
			if (!response.ok) return probe;
			const R candidate_target = reuse ? target : glow_feed_factor_for_stage(context, model.feed,
					external, mass.mass_kg, tank_arm, response.body_derivative.data() + 10, omega,
					model.has_pickup ? model.pickup.data() : nullptr);
			if (!is_finite(candidate_target)) return probe;
			probe.ok = true;
			probe.target_factor = candidate_target;
			probe.payload = {sampled, response};
			return probe;
		}, 1.0);
		if (!solve.ok) return out;
		feed_factor = solve.factor;
		life = solve.payload.life;
		coupling = solve.payload.coupling;
	} else {
		life = glow_lifecycle_evaluate(model.lifecycle, state, trial.rpm, throttle, trial.mixture,
				trial.dry_density, trial.ambient_k, trial.cooling_mps, feed_factor, trial.lifecycle_floor);
		if (!life.ok) return out;
		coupling = glow_coupled_stage(body, external, values, prop, model.lifecycle, state, life, trial.blade,
				mass, trial.dry_density, gravity);
		if (!coupling.ok) return out;
		if (model.has_feed) {
			// point() still evaluates feed telemetry off the main tank, without
			// pickup; apparent-gravity *inputs* must validate even if its computed
			// pressure factor is unused by the active source.
			const R breathing = glow_source_table_sample(model.lifecycle.source.breathing, trial.rpm);
			const R cycle = model.lifecycle.source.family == GlowFamily::TwoStroke ? R(1.0) : R(2.0);
			const R admission = glow_carb_admission(state.air_fraction, trial.rpm, breathing,
					model.lifecycle.source.displacement_m3, cycle, model.lifecycle.throttle_capacity_m3_s);
			const auto context = glow_feed_prepare_context(model.feed, maxf(trial.stage_mass.main_fuel_kg, 0.0),
					model.main_capacity_kg, model.unusable_kg, admission, trial.rpm);
			if (!context.ok || !is_finite(mass.mass_kg) || mass.mass_kg.v <= 0.0) return out;
			for (int i = 0; i < 3; ++i) if (!is_finite(external[i]) || !is_finite(tank_arm[i]) ||
					!is_finite(coupling.body_derivative[i + 10]) || !is_finite(omega[i])) return out;
		}
	}
	// The reused rotor/body response was built at feed factor 1, while the
	// selected lifecycle payload has the solved transport derivative.
	for (int i = 0; i < 6; ++i) coupling.derivative[i + 1] = life.rates[i];
	if (trial.mode == 2.0) coupling.derivative[17] = life.rates[0];
	out.loads = coupling.loads;
	out.rotor = coupling.rotor;
	out.body_derivative = coupling.body_derivative;
	out.derivative.reserve(static_cast<size_t>(19 + wheel_count));
	for (R rate : coupling.derivative) out.derivative.push_back(rate);
	for (int i = 0; i < wheel_count; ++i) out.derivative.push_back(wheel_rates[i]);
	out.feed_factor = feed_factor;
	out.ok = true;
	return out;
}

} // namespace nk
