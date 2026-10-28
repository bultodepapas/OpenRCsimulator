// NK-3 draft: Aero.ambient_spatial_loads and its full-angle continuation.
// The decoder must validate the normalized model, its tailless capability, the
// station arrays and all dictionary/array shapes before using this prepared API.
#pragma once

#include <cstddef>
#include "nk_aero.hpp"

namespace nk {

struct SpatialAeroResult {
	bool ok = false, uniform = false;
	const char *error = nullptr;
	Loads loads{}, delta{};
	R held_wake = kNan, max_alpha = 0.0, max_beta = 0.0, max_pressure = 0.0;
	int reference_zero_planes = 0, spatial_zero_planes = 0;
};

inline SpatialAeroResult spatial_aero_failure(const char *error) {
	SpatialAeroResult out;
	out.error = error;
	return out;
}

inline bool spatial_aero_flow_bounded(const R *flow) {
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(flow[i]) || absf(flow[i]) > 500.0) return false;
	}
	return sqrt_(flow[0] * flow[0] + flow[1] * flow[1] + flow[2] * flow[2]) <= 500.0;
}

inline bool spatial_aero_wing_bounded(const WingFlow &flow, int n) {
	if (!is_finite(flow.reference_speed) || flow.reference_speed > 500.0) return false;
	for (int i = 0; i < n; ++i) {
		const R values[] = {flow.angles[i], flow.speeds[i], flow.sources[i], flow.flap_shifts[i]};
		for (R value : values) {
			if (!is_finite(value) || absf(value) > 500.0) return false;
		}
	}
	return true;
}

inline bool spatial_aero_loads_valid(const Loads &loads, bool bounded) {
	for (R x : loads) {
		if (!is_finite(x) || (bounded && absf(x) > 1.0e12)) return false;
	}
	return true;
}

inline void spatial_aero_station_flow(const R *s, const Air &air, const AeroModel &m,
		int i, const R *deltas, R *before, R *after) {
	const int n = static_cast<int>(m.ys.size());
	R arm[3];
	if (i < n) {
		arm[0] = -(m.arp[0] - m.cg[0]);
		arm[1] = m.arp[1] - m.cg[1];
		arm[2] = -(m.arp[2] - m.cg[2]);
		if (!m.tailless.station_x.empty()) arm[0] = -(m.tailless.station_x[i] - m.cg[0]) + 0.0;
		arm[1] += m.ys[i];
	} else {
		const Tail &tail = i == n + 1 ? m.vertical : m.horizontal;
		arm[0] = -(tail.position[0] - m.cg[0]);
		arm[1] = tail.position[1] - m.cg[1];
		arm[2] = -(tail.position[2] - m.cg[2]);
	}
	before[0] = air.v[0] + (s[11] * arm[2] - s[12] * arm[1]);
	before[1] = air.v[1] + (s[12] * arm[0] - s[10] * arm[2]);
	before[2] = air.v[2] + (s[10] * arm[1] - s[11] * arm[0]);
	for (int a = 0; a < 3; ++a) after[a] = before[a] + deltas[3 * i + a];
}

// Inputs are the 13-value body, prepared Air/Deflections/model, and exactly
// 3*(n+2) station deltas. Optional attached-only mode matches the older bridge;
// flight_session's spatial route explicitly uses continuation=true.
inline SpatialAeroResult spatial_aero_loads(const R *s, const Air &air, const Deflections &d,
		const AeroModel &m, R rho, const R *deltas, std::size_t delta_count,
		R downwash = kNan, R ground_up = kNan, bool continuation = true) {
	if (!is_finite(rho) || rho <= 0.0 || (continuation && rho > 1000.0) ||
		(!is_finite(downwash) && !is_nan(downwash)) || (!is_finite(ground_up) && !is_nan(ground_up))) {
		return spatial_aero_failure("invalid body, density, wake or ground input");
	}
	for (int i = 0; i < 13; ++i) if (!is_finite(s[i])) return spatial_aero_failure("invalid body, density, wake or ground input");
	R quaternion_norm = 0.0;
	for (int i = 0; i < 4; ++i) quaternion_norm += s[6 + i] * s[6 + i];
	if (!is_finite(quaternion_norm) || quaternion_norm <= kGd1eMinus24) return spatial_aero_failure("invalid body quaternion");
	for (R v : air.v) if (!is_finite(v)) return spatial_aero_failure("invalid reference air velocity");
	if (!is_finite(air.V) || !is_finite(air.alpha) || !is_finite(air.beta) || !is_finite(air.qbar)) {
		return spatial_aero_failure("invalid reference air data");
	}
	if (continuation && (air.V < 0.0 || air.V > 500.0 || air.qbar < 0.0 || air.qbar > 125000000.0)) {
		return spatial_aero_failure("reference air data exceeds the defensive numerical bound");
	}
	if (continuation) for (R v : air.v) if (absf(v) > 500.0) return spatial_aero_failure("reference air velocity exceeds the defensive numerical bound");
	if (!is_finite(d.elevator) || !is_finite(d.aileron_left) || !is_finite(d.aileron_right) ||
		!is_finite(d.rudder)) return spatial_aero_failure("invalid surface deflection");
	if (!is_finite(d.flap)) return spatial_aero_failure("invalid flap deflection");
	const int n = static_cast<int>(m.ys.size());
	if (n <= 0 || n > 16 || deltas == nullptr || delta_count != static_cast<std::size_t>(3 * (n + 2))) {
		return spatial_aero_failure("spatial air needs one finite delta per wing and tail station");
	}
	for (std::size_t i = 0; i < delta_count; ++i) if (!is_finite(deltas[i])) return spatial_aero_failure("spatial air needs one finite delta per wing and tail station");
	const bool tailless = !m.tailless.station_x.empty();
	if (tailless && (deltas[3 * n] != 0.0 || deltas[3 * n + 1] != 0.0 || deltas[3 * n + 2] != 0.0)) {
		return spatial_aero_failure("tailless horizontal slot must remain zero");
	}
	bool uniform = true;
	for (std::size_t i = 0; i < delta_count; ++i) {
		if (continuation && absf(deltas[i]) > 1000.0) return spatial_aero_failure("station wind delta exceeds the defensive numerical bound");
		if (deltas[i] != 0.0) uniform = false;
	}
	SpatialAeroResult out;
	out.uniform = uniform;
	out.held_wake = downwash;
	if (uniform) {
		out.loads = aero_loads(s, air, d, m, rho, downwash, ground_up);
		if (!spatial_aero_loads_valid(out.loads, continuation)) return spatial_aero_failure(continuation
			? "reference aerodynamic evaluation is nonfinite or unbounded" : "reference aerodynamic evaluation is nonfinite");
		out.ok = true;
		return out;
	}
	WingFlow reference_wing, spatial_wing;
	wing_flow(s, air, d, m, reference_wing);
	wing_flow(s, air, d, m, spatial_wing, deltas);
	if (continuation) {
		if (!spatial_aero_wing_bounded(reference_wing, n) || !spatial_aero_wing_bounded(spatial_wing, n)) {
			return spatial_aero_failure("wing station flow is nonfinite or exceeds the defensive numerical bound");
		}
		for (int i = n; i < n + 2; ++i) {
			if (tailless && i == n) continue;
			R before[3], after[3];
			spatial_aero_station_flow(s, air, m, i, deltas, before, after);
			if (!spatial_aero_flow_bounded(before) || !spatial_aero_flow_bounded(after)) {
				return spatial_aero_failure("tail station flow is nonfinite or exceeds the defensive numerical bound");
			}
		}
	}
	std::vector<R> ge;
	ge_factors(s, m, ground_up, ge);
	const R wake = is_nan(downwash) ? wing_lift_coefficient_with(s, air, d, m, ge, true) : downwash;
	if (!is_finite(wake) || (continuation && absf(wake) > 1500.0)) return spatial_aero_failure(continuation
		? "reference wing wake is nonfinite or exceeds the defensive numerical bound" : "reference wing wake is nonfinite");
	out.held_wake = wake;
	if (!continuation) {
		const R stall_back = m.flaps.has_stall_shift_fraction ? 1.0 - m.flaps.stall_shift_fraction : R(0.0);
		for (int i = 0; i < n + 2; ++i) {
			if (tailless && i == n) continue;
			const bool vertical = i == n + 1;
			R before[3], after[3];
			spatial_aero_station_flow(s, air, m, i, deltas, before, after);
			for (int a = 0; a < 3; ++a) if (!is_finite(before[a]) || !is_finite(after[a])) return spatial_aero_failure("spatial bridge requires forward flow at every station");
			if (before[0] <= 0.0 || after[0] <= 0.0) return spatial_aero_failure("spatial bridge requires forward flow at every station");
			const R alpha0 = atan2_(before[2], before[0]), alpha1 = atan2_(after[2], after[0]);
			const R beta0 = atan2_(before[1], sqrt_(before[0] * before[0] + before[2] * before[2]));
			const R beta1 = atan2_(after[1], sqrt_(after[0] * after[0] + after[2] * after[2]));
			const int normal = vertical ? 1 : 2;
			const R plane0 = before[0] * before[0] + before[normal] * before[normal];
			const R plane1 = after[0] * after[0] + after[normal] * after[normal];
			const R pressure = absf(plane1 - plane0) / plane0;
			if (!is_finite(pressure)) return spatial_aero_failure("invalid section-plane pressure");
			out.max_alpha = maxf(out.max_alpha, absf(wrapf(alpha1 - alpha0, -kPi, kPi)));
			out.max_beta = maxf(out.max_beta, absf(beta1 - beta0));
			out.max_pressure = maxf(out.max_pressure, pressure);
			const R angle_limit = R(3.0) * R(kPi) / R(180.0);
			if (out.max_alpha > angle_limit || out.max_beta > angle_limit || out.max_pressure > 0.25) return spatial_aero_failure("ambient gradient exceeds the provisional angle/pressure domain");
			if (absf(beta0) >= m.b1 || absf(beta1) >= m.b1) return spatial_aero_failure("station sideslip is outside the attached domain");
			if (i < n) {
				for (const WingFlow *flow : {&reference_wing, &spatial_wing}) {
					const R angle = flow->angles[i], stall_angle = angle - stall_back * flow->flap_shifts[i];
					if (stall_weight(stall_angle, m) != 0.0) return spatial_aero_failure("wing station is outside the attached domain");
					if (m.polar.enabled) {
						const R polar_angle = m.polar.strip_factor.empty() ? angle : angle * m.polar.strip_factor[i];
						if (wing_polar_evaluate(polar_angle, 0.0, m.polar)[2] != 1.0) return spatial_aero_failure("tabulated wing station is outside the attached domain");
					}
				}
			} else {
				const Tail &tail = vertical ? m.vertical : m.horizontal;
				const R tail_wake = wake * (!ge.empty() ? ge[n + 1] : R(1.0));
				for (const R *flow : {before, after}) {
					R angle;
					if (!vertical && tail.free) {
						angle = wrapf(atan2_(flow[2], flow[0]) - downwash_angle(tail_wake, tail.downwash_per_cl,
							sqrt_(flow[0] * flow[0] + flow[2] * flow[2])) + tail.elevator_tau * d.elevator + tail.free_incidence, -kPi, kPi);
					} else {
						const R control = vertical ? -d.rudder : d.elevator;
						angle = wrapf(atan2_(flow[vertical ? 1 : 2], flow[0]) + tail.control_effectiveness * control + tail.incidence, -kPi, kPi);
					}
					if (absf(angle) >= m.tail_local_limit) return spatial_aero_failure("tail station is outside the attached domain");
				}
			}
		}
	}
	const Loads reference = local_loads(s, air, d, m, rho, wake, ge, nullptr, false);
	const Loads spatial = local_loads(s, air, d, m, rho, wake, ge, deltas, false);
	out.loads = aero_loads(s, air, d, m, rho, downwash, ground_up);
	if (continuation && (!spatial_aero_loads_valid(reference, true) || !spatial_aero_loads_valid(spatial, true) || !spatial_aero_loads_valid(out.loads, true))) {
		return spatial_aero_failure("reference or spatial aerodynamic evaluation is nonfinite or unbounded");
	}
	for (int i = 0; i < 6; ++i) {
		out.delta[i] = spatial[i] - reference[i];
		out.loads[i] += out.delta[i];
	}
	if (!spatial_aero_loads_valid(out.delta, continuation) || !spatial_aero_loads_valid(out.loads, continuation)) {
		return spatial_aero_failure(continuation ? "spatial aerodynamic result is nonfinite or unbounded" : "spatial aerodynamic evaluation is nonfinite");
	}
	for (int i = 0; i < n; ++i) {
		if (reference_wing.speeds[i] == 0.0) ++out.reference_zero_planes;
		if (spatial_wing.speeds[i] == 0.0) ++out.spatial_zero_planes;
	}
	out.ok = true;
	return out;
}

} // namespace nk
