// NK-6u: FlightSession._substeps_with_context (app/sim/flight_session.gd), the contact and shaft refinement that sets
// a tick's RK4 piece count, for the kernel's own tick integrator, exactly. The plan holds the inputs only the guarded
// configuration decides (FlightSession.native_substep_plan, captured at installation); the tick supplies the state,
// the aux and the stage's preview. A tick the plan does not cover answers -1, and the session's callback decides:
// a shaft refinement that needs the power latch or the coupled response (no finite preview rate).
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

#include "nk_math.hpp"

namespace nk {

struct SubstepPlan {
	bool ready = false;
	bool battery_dynamic = false;
	int gear_mode = 0; // 0: no landing-gear dictionary; 1: fixed gear; 2: retractable gear (the aux decides)
	int64_t gear_count = 1; // int(gear.get("substeps", 1)); 1 for an empty gear dictionary
	double reach = 0.0; // float(gear.reach) when gear_count > 1
	double terrain = 0.0; // 0 or GroundTerrain.max_height_validated(surfaces)
	int64_t gear_aux_index = -1;
	int64_t gear_aux_size = 2;
	bool shaft_base = false; // coupled shaft, neither electric nor glow, with rotor dynamics
	bool liquid = false;
	int64_t rotor_index = 0;
	double stopped_rpm = 1.0;
	int64_t max_substeps = 16;
	double margin = 0.05;
};

// The joint callback's stage context: `valid` when _substep_stage_context_is_valid holds for it, `has_rate` when it
// also carries a finite source_off_rpm_rate.
struct SubstepPreview {
	bool valid = false;
	bool has_rate = false;
	R rate = 0.0;
};

inline bool substep_fraction_valid(R x) { return is_finite(x) && x.v >= 0.0 && x.v <= 1.0; }

// Ground.substeps(body, gear, dt, surfaces) for the plan's gear, with no RC-track overlay.
inline int64_t substep_ground(const SubstepPlan &p, const R *body, R dt) {
	if (p.gear_count <= 1) return 1;
	const R speed_bound = absf(body[3]) + absf(body[4]) + absf(body[5]);
	if ((-body[2]).v > (R(p.reach) + R(p.terrain) + speed_bound * dt + R(p.margin)).v) return 1;
	return p.gear_count;
}

// combined: the 13 body values then the continuous values; aux: the tick's aux (sim.aux inside the tick).
inline int64_t substep_count(const SubstepPlan &p, const R *combined, int size, const double *aux, int64_t aux_size, R dt,
		bool electric_policy, const SubstepPreview &preview) {
	if (!p.ready) return -1;
	if (p.battery_dynamic && electric_policy) return 1;
	int64_t count = 1;
	if (p.gear_mode != 0) {
		// current_landing_gear(): a retractable gear is {} unless its aux is valid; its pose keeps substeps and reach.
		bool gear = true;
		if (p.gear_mode == 2) {
			const int64_t i = p.gear_aux_index;
			gear = i >= 0 && aux_size >= i + p.gear_aux_size && substep_fraction_valid(R(aux[i])) &&
				(aux[i + 1] == 0.0 || aux[i + 1] == 1.0);
		}
		if (gear) count = substep_ground(p, combined, dt);
	}
	if (p.shaft_base) {
		if (!p.liquid) return -1; // source_may_stop_this_tick reads this tick's power latch
		const int64_t extra = size - 13;
		if (extra > p.rotor_index) {
			const R rpm = combined[13 + p.rotor_index];
			if (is_finite(rpm) && rpm.v > p.stopped_rpm) {
				if (!preview.valid || !preview.has_rate) return -1; // the reference evaluates _coupled_response
				const R rate = preview.rate;
				if (!is_finite(rate)) {
					count = std::max(count, p.max_substeps + 1);
				} else if (rate.v < 0.0) {
					const R stage_drop = dt * -rate * R(1.25);
					const R required = stage_drop / rpm;
					if (!is_finite(stage_drop) || !is_finite(required) || required.v > static_cast<double>(p.max_substeps)) {
						count = std::max(count, p.max_substeps + 1);
					} else {
						count = std::max(count, std::max<int64_t>(1, static_cast<int64_t>(std::ceil(required.v))));
					}
				}
			}
		}
	}
	return count;
}

} // namespace nk
