// NK-3: one joint RK stage for the fixed-wing "wheel" route, mirroring FlightSession._wheel_evaluate for an aircraft
// without wash pieces (rotor index 0): air_data (calm, non-spatial weather), Dynamics.loads_from_air (aero +
// untilted legacy propeller, no slipstream), _ground_up, _ground_evaluation (soft hull + GP-02 wheels, fixed gear,
// no glow/live mass) and rotor_momentum. The per-tick context (aux after pre_tick, inputs, the session's own
// deflections, sim time) is set once per tick by the caller; stage() then reads only packed scalars.
#pragma once

#include <array>
#include <utility>
#include <vector>

#include "nk_aero.hpp"
#include "nk_hull.hpp"
#include "nk_prop.hpp"
#include "nk_wheels.hpp"

namespace nk {

struct StageLayout {
	int aux_size = 0;
	int rpm = 0;          // FlightSession.AUX_RPM
	int servo = 1;        // FlightSession.AUX_SERVO (steer = aux[servo + 2])
	int anchors = 4;      // FlightSession.AUX_ANCHORS
	int anchor_count = 0;
	int downwash = -1;    // downwash_index()
	int wheel_count = 0;
	int rotor_index = 0;  // _rotor_index(): continuous wash pieces before the wheels (0 here)
	int wheel_index = 0;  // wheel_index()
	int brake_input = -1; // wheel_brake_input_index()
	int input_count = 0;
};

struct StageModel {
	AeroModel aero;
	PropModel prop;
	GroundContext ground;
	HullPrepared hull;
	bool soft_hull = false;
	StageLayout layout;
	R density = 0.0;            // weather.air_density(): uniform field, no vertical column
	R ground_effect_reach = 0.0; // FlightSession._ground_effect_reach
};

struct TickContext {
	bool ready = false;
	std::vector<R> aux;
	R brake = 0.0;
	Deflections deflections;
	R time_now = 0.0;
};

struct StageResult {
	bool shaped = false; // false: the reference returns {} (kernel rejects the stage)
	std::array<R, 6> loads{};
	std::vector<R> derivative;
	std::array<R, 3> rotor{};
};

// FlightSession._ground_up.
inline R stage_ground_up(const R *s, const StageModel &m) {
	if (m.ground_effect_reach.v <= 0.0) {
		return kNan;
	}
	if ((-s[2]).v >= (m.ground_effect_reach + max_height_validated(m.ground.surfaces)).v) {
		return kNan;
	}
	static const LakeTerrain kNoLake;
	return terrain_sample_validated(s[0], s[1], m.ground.surfaces, kNoLake)[0];
}

// FlightSession._ground_evaluation for fixed gear: false = {ok: false}.
inline bool stage_ground(const R *s, const StageModel &m, const TickContext &ctx, const R *values, int value_count,
		std::array<R, 6> &loads, bool &has_loads, std::vector<R> &rates) {
	const StageLayout &L = m.layout;
	const R steer = ctx.aux[L.servo + 2];
	const R brake = ctx.brake;
	double anchors[64];
	int anchor_values = 0;
	for (int i = L.anchors; i < L.anchors + L.anchor_count * 3 && i < static_cast<int>(ctx.aux.size()) && anchor_values < 64; ++i) {
		anchors[anchor_values++] = ctx.aux[i].v;
	}
	std::array<R, 6> hull{};
	bool has_hull = false;
	if (m.soft_hull) {
		has_hull = hull_loads(s, m.hull, hull);
		if (has_hull) {
			for (const R &value : hull) {
				if (!is_finite(value)) {
					return false;
				}
			}
		}
	}
	if (L.wheel_count == 0) {
		return false; // the legacy no-wheel-state law is not ported (refused at prepare)
	}
	if (value_count != L.wheel_index + L.wheel_count) {
		return false;
	}
	double speeds[16];
	for (int i = 0; i < L.wheel_count; ++i) {
		speeds[i] = values[L.wheel_index + i].v;
		if (!std::isfinite(speeds[i])) {
			return false;
		}
	}
	static thread_local std::vector<R> wheel_loads;
	wheels_evaluate(s, m.ground, steer, anchors, anchor_values, speeds, L.wheel_count, brake, wheel_loads, rates);
	if ((!wheel_loads.empty() && wheel_loads.size() != 6) || static_cast<int>(rates.size()) != L.wheel_count) {
		return false;
	}
	for (const R &value : wheel_loads) {
		if (!is_finite(value)) {
			return false;
		}
	}
	for (const R &value : rates) {
		if (!is_finite(value)) {
			return false;
		}
	}
	// _add_loads(wheels, hull)
	if (!has_hull) {
		has_loads = !wheel_loads.empty();
		for (int i = 0; i < 6 && has_loads; ++i) {
			loads[i] = wheel_loads[i];
		}
	} else if (wheel_loads.empty()) {
		has_loads = true;
		loads = hull;
	} else {
		has_loads = true;
		for (int i = 0; i < 6; ++i) {
			loads[i] = wheel_loads[i] + hull[i];
		}
	}
	return true;
}

// FlightSession._wheel_evaluate.
inline StageResult stage_evaluate(const R *s, const R *values, int value_count, R stage_time, const StageModel &m,
		const TickContext &ctx) {
	StageResult out;
	const StageLayout &L = m.layout;
	const int expected = L.rotor_index;
	if (L.wheel_count == 0 || value_count != expected + L.wheel_count || !ctx.ready) {
		return out;
	}
	const std::vector<R> &a = ctx.aux;
	const int lag = L.downwash;
	const R downwash_cl = lag >= 0 && lag < static_cast<int>(a.size()) ? a[lag] : R(kNan);
	// air_data(s, stage_time): calm uniform weather, FlightSession.wind_at -> Environment.wind_world.
	const R at = is_nan(stage_time) ? ctx.time_now : stage_time;
	R wind[3] = {0.0, 0.0, 0.0};
	if (!is_finite(s[0]) || !is_finite(s[1]) || !is_finite(s[2]) || !is_finite(at) || at.v < 0.0) {
		wind[0] = wind[1] = wind[2] = kNan;
	}
	const R rho = m.density;
	const Air air = air_compute(s, wind, rho);
	const R ground_up = stage_ground_up(s, m);
	// Dynamics.loads_from_air: Aero.loads, then the propeller at its stage inflow.
	const Loads aero = aero_loads(s, air, ctx.deflections, m.aero, rho, downwash_cl, ground_up);
	std::array<R, 6> total;
	if (!is_finite(air.v[0]) || !is_finite(air.v[1]) || !is_finite(air.v[2])) {
		total = {kNan, kNan, kNan, kNan, kNan, kNan}; // Propulsion.stage_air_velocity refuses: _invalid_components
	} else {
		const std::array<R, 6> propulsion = prop_loads(air.v, a[L.rpm], m.prop, rho);
		total = aero;
		for (int i = 0; i < 6; ++i) {
			total[i] += propulsion[i];
		}
	}
	std::array<R, 6> ground_loads{};
	bool has_ground_loads = false;
	std::vector<R> rates;
	if (!stage_ground(s, m, ctx, values, value_count, ground_loads, has_ground_loads, rates)) {
		return out;
	}
	if (has_ground_loads) {
		for (int i = 0; i < 6; ++i) {
			total[i] += ground_loads[i];
		}
	}
	out.derivative = std::move(rates); // expected == 0: transfer the completed wheel rates without another allocation
	if (static_cast<int>(out.derivative.size()) != value_count) {
		return out;
	}
	out.shaped = true;
	out.loads = total;
	out.rotor = prop_rotor_momentum(m.prop, a[L.rpm]);
	return out;
}

} // namespace nk
