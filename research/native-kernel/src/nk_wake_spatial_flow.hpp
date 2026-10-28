// NK-3 draft: pure station and wake-point sampling from wind_aircraft_flow.gd.
// The actual wind-world provider and its decoder remain separate; calls here
// are native function pointers, never Godot calls from an RK stage.
#pragma once

#include <array>
#include "nk_wake.hpp"
#include "nk_hull.hpp" // q_rotate3, the exact Math3D.q_rotate scalar form

namespace nk {

struct SpatialWindProvider {
	bool (*sample)(void *context, const R *position_ned, R time, R *wind_ned) = nullptr;
	void *context = nullptr;
};

// One stage only. The caller keeps it alive until wake_loads has returned;
// its provider must be a pure, read-only evaluator for the duration.
struct SpatialPointContext {
	SpatialWindProvider provider;
	R position[3] = {0.0, 0.0, 0.0};
	R body_to_ned[4] = {1.0, 0.0, 0.0, 0.0};
	R ned_to_body[4] = {1.0, 0.0, 0.0, 0.0};
	R reference_wind[3] = {0.0, 0.0, 0.0};
	R time = 0.0;
};

inline bool spatial_flow_finite3(const R *value) {
	return is_finite(value[0]) && is_finite(value[1]) && is_finite(value[2]);
}

inline bool spatial_point_delta(void *opaque, const R *arm, R *delta) {
	const auto &point = *static_cast<const SpatialPointContext *>(opaque);
	if (!spatial_flow_finite3(arm) || point.provider.sample == nullptr) return false;
	const auto rotated = q_rotate3(point.body_to_ned, arm);
	const R position[3] = {point.position[0] + rotated[0], point.position[1] + rotated[1], point.position[2] + rotated[2]};
	if (!spatial_flow_finite3(position)) return false;
	R wind[3];
	if (!point.provider.sample(point.provider.context, position, point.time, wind) || !spatial_flow_finite3(wind)) return false;
	if (wind[0] == point.reference_wind[0] && wind[1] == point.reference_wind[1] && wind[2] == point.reference_wind[2]) {
		delta[0] = 0.0; delta[1] = 0.0; delta[2] = 0.0;
		return true;
	}
	const R difference[3] = {point.reference_wind[0] - wind[0], point.reference_wind[1] - wind[1],
		point.reference_wind[2] - wind[2]};
	const auto rotated_delta = q_rotate3(point.ned_to_body, difference);
	for (int axis = 0; axis < 3; ++axis) delta[axis] = rotated_delta[axis];
	return spatial_flow_finite3(delta);
}

inline WakePointSampler spatial_wake_sampler(SpatialPointContext &point) {
	return {spatial_point_delta, &point};
}

struct SpatialFlowResult {
	bool ok = false, uniform = false;
	const char *error = nullptr;
	int station = -1;
	Air air;
	// Six wing stations, horizontal/vertical slots. The propulsion point is
	// separate because its flow includes omega x r but the wake delta does not.
	std::array<R, 24> aero_deltas{};
	std::array<R, 3> propulsion_air{}, wake_source_delta{};
};

inline SpatialFlowResult spatial_flow_failure(const char *error, int station = -1) {
	SpatialFlowResult out;
	out.error = error;
	out.station = station;
	return out;
}

// prop_offset is authored-datum LE [aft,right,up] relative to O, not the CG;
// use the turbine intake or propeller offset selected by the prepared model.
// The decoder validates geometry/capability (including six ordered stations),
// then the CG may be replaced each stage for a finite-resource aircraft.
inline SpatialFlowResult spatial_flow_sample(const R *s, const AeroModel &m, const R *prop_offset,
		const SpatialWindProvider &provider, R time, R rho, SpatialPointContext &point) {
	if (m.ys.size() != 6 || prop_offset == nullptr || provider.sample == nullptr) {
		return spatial_flow_failure("invalid prepared station geometry or provider");
	}
	for (int i = 0; i < 13; ++i) if (!is_finite(s[i])) return spatial_flow_failure("state must be a finite full rigid-body state with a nondegenerate quaternion");
	const R norm_sq = s[6] * s[6] + s[7] * s[7] + s[8] * s[8] + s[9] * s[9];
	if (!is_finite(norm_sq) || norm_sq <= 1e-24) return spatial_flow_failure("state must be a finite full rigid-body state with a nondegenerate quaternion");
	if (!is_finite(time) || time < 0.0) return spatial_flow_failure("time_s must be finite and nonnegative");
	if (!is_finite(rho) || rho <= 0.0) return spatial_flow_failure("invalid stage density");
	point.provider = provider;
	point.time = time;
	for (int i = 0; i < 3; ++i) point.position[i] = s[i];
	point.body_to_ned[0] = s[6]; point.body_to_ned[1] = s[7];
	point.body_to_ned[2] = s[8]; point.body_to_ned[3] = s[9];
	point.ned_to_body[0] = s[6]; point.ned_to_body[1] = -s[7];
	point.ned_to_body[2] = -s[8]; point.ned_to_body[3] = -s[9];
	if (!provider.sample(provider.context, point.position, time, point.reference_wind) || !spatial_flow_finite3(point.reference_wind)) {
		return spatial_flow_failure("environment rejected the datum wind sample");
	}
	SpatialFlowResult out;
	out.air = air_compute(s, point.reference_wind, rho);
	if (!spatial_flow_finite3(out.air.v)) return spatial_flow_failure("datum air-relative body velocity is nonfinite");
	if (!is_finite(out.air.V) || !is_finite(out.air.qbar)) return spatial_flow_failure("nonfinite stage air data");
	const bool tailless = !m.tailless.station_x.empty();
	const R wing_arm[3] = {-(m.arp[0] - m.cg[0]), m.arp[1] - m.cg[1], -(m.arp[2] - m.cg[2])};
	if (!spatial_flow_finite3(wing_arm)) return spatial_flow_failure("main-wing aerodynamic reference arm is nonfinite");
	bool uniform = true;
	for (int i = 0; i < 9; ++i) {
		if (tailless && i == 6) continue;
		R arm[3];
		if (i < 6) {
			arm[0] = tailless ? -(m.tailless.station_x[i] - m.cg[0]) + 0.0 : wing_arm[0];
			arm[1] = wing_arm[1] + m.ys[i]; arm[2] = wing_arm[2];
		} else if (i < 8) {
			const Tail &tail = i == 7 ? m.vertical : m.horizontal;
			arm[0] = -(tail.position[0] - m.cg[0]); arm[1] = tail.position[1] - m.cg[1];
			arm[2] = -(tail.position[2] - m.cg[2]);
		} else {
			arm[0] = -prop_offset[0]; arm[1] = prop_offset[1]; arm[2] = -prop_offset[2];
		}
		const auto rotated = q_rotate3(point.body_to_ned, arm);
		const R position[3] = {point.position[0] + rotated[0], point.position[1] + rotated[1], point.position[2] + rotated[2]};
		if (!spatial_flow_finite3(position)) return spatial_flow_failure("station world position is nonfinite", i);
		R wind[3];
		if (!provider.sample(provider.context, position, time, wind) || !spatial_flow_finite3(wind)) {
			return spatial_flow_failure("environment rejected wind at station", i);
		}
		const bool station_uniform = wind[0] == point.reference_wind[0] && wind[1] == point.reference_wind[1] && wind[2] == point.reference_wind[2];
		uniform = uniform && station_uniform;
		R delta[3] = {0.0, 0.0, 0.0};
		if (!station_uniform) {
			const R difference[3] = {point.reference_wind[0] - wind[0], point.reference_wind[1] - wind[1], point.reference_wind[2] - wind[2]};
			const auto rotated_delta = q_rotate3(point.ned_to_body, difference);
			for (int axis = 0; axis < 3; ++axis) delta[axis] = rotated_delta[axis];
		}
		const R rate[3] = {s[11] * arm[2] - s[12] * arm[1], s[12] * arm[0] - s[10] * arm[2],
			s[10] * arm[1] - s[11] * arm[0]};
		R local_air[3] = {out.air.v[0], out.air.v[1], out.air.v[2]};
		for (int axis = 0; axis < 3; ++axis) if (rate[axis] != 0.0) local_air[axis] += rate[axis];
		if (!station_uniform) for (int axis = 0; axis < 3; ++axis) if (delta[axis] != 0.0) local_air[axis] += delta[axis];
		if (!spatial_flow_finite3(delta) || !spatial_flow_finite3(local_air)) return spatial_flow_failure("station relative flow is nonfinite", i);
		if (i < 8) for (int axis = 0; axis < 3; ++axis) out.aero_deltas[3 * i + axis] = delta[axis];
		else for (int axis = 0; axis < 3; ++axis) { out.propulsion_air[axis] = local_air[axis]; out.wake_source_delta[axis] = delta[axis]; }
	}
	out.uniform = uniform;
	out.ok = true;
	return out;
}

} // namespace nk
