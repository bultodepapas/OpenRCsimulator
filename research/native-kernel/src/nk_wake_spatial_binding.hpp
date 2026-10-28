// Component-only Godot bridge for the draft spatial flow/aero/wake helpers.
// Stage evaluation uses prepared C++ models and a native weather callback;
// these conversion methods are not part of the in-stage path.
#pragma once

#include "nk_wake_spatial_aero.hpp"
#include "nk_wake_spatial_flow.hpp"
#include "nk_weather_binding.hpp"

namespace nk {

struct SpatialWeatherCall {
	const WeatherBinding *weather = nullptr;
	const std::vector<R> *aux = nullptr;
	int turbulence_index = -1;
	R dt = 0.0;
};

inline bool spatial_weather_callback(void *opaque, const R *position, R time, R *wind) {
	const auto &call = *static_cast<const SpatialWeatherCall *>(opaque);
	const auto sample = call.weather->wind(position, time, *call.aux, call.turbulence_index, call.dt);
	for (int axis = 0; axis < 3; ++axis) wind[axis] = sample[axis];
	return spatial_flow_finite3(wind);
}

inline godot::PackedFloat64Array spatial_binding_pack(const R *values, std::size_t size) {
	godot::PackedFloat64Array result;
	result.resize(static_cast<int64_t>(size));
	for (std::size_t i = 0; i < size; ++i) result[static_cast<int64_t>(i)] = values[i].v;
	return result;
}

inline godot::Dictionary spatial_binding_failure(const char *error) {
	godot::Dictionary result;
	result["ok"] = false;
	result["error"] = error;
	return result;
}

inline bool spatial_binding_state(const godot::PackedFloat64Array &raw, R *state) {
	if (raw.size() != 13) return false;
	for (int i = 0; i < 13; ++i) state[i] = raw[i];
	return true;
}

inline bool spatial_binding_deflections(const godot::PackedFloat64Array &raw, Deflections &d) {
	if (raw.size() != 4 && raw.size() != 5) return false;
	d.elevator = raw[0]; d.aileron_right = raw[1]; d.aileron_left = raw[2]; d.rudder = raw[3];
	d.flap = raw.size() == 5 ? R(raw[4]) : R(0.0);
	return true;
}

inline godot::Dictionary spatial_aero_component(const AeroModel &model, const godot::PackedFloat64Array &body,
		const godot::PackedFloat64Array &wind, double rho, const godot::PackedFloat64Array &controls,
		const godot::PackedFloat64Array &deltas, double downwash, double ground_up, bool continuation) {
	R state[13], ned[3];
	Deflections d;
	if (!spatial_binding_state(body, state) || wind.size() != 3 || !spatial_binding_deflections(controls, d)) {
		return spatial_binding_failure("invalid component argument shape");
	}
	for (int i = 0; i < 3; ++i) ned[i] = wind[i];
	std::vector<R> delta;
	delta.reserve(static_cast<std::size_t>(deltas.size()));
	for (int64_t i = 0; i < deltas.size(); ++i) delta.push_back(deltas[i]);
	const Air air = air_compute(state, ned, rho);
	const SpatialAeroResult evaluated = spatial_aero_loads(state, air, d, model, rho, delta.data(), delta.size(),
		downwash, ground_up, continuation);
	if (!evaluated.ok) return spatial_binding_failure(evaluated.error);
	godot::Dictionary result;
	result["ok"] = true;
	result["error"] = "";
	result["uniform"] = evaluated.uniform;
	result["loads"] = spatial_binding_pack(evaluated.loads.data(), 6);
	result["delta"] = spatial_binding_pack(evaluated.delta.data(), 6);
	result["held_wake_mps"] = evaluated.held_wake.v;
	result["domain"] = spatial_binding_pack(std::array<R, 3>{evaluated.max_alpha, evaluated.max_beta, evaluated.max_pressure}.data(), 3);
	result["zero_planes"] = godot::PackedInt32Array();
	godot::PackedInt32Array zeros;
	zeros.push_back(evaluated.reference_zero_planes); zeros.push_back(evaluated.spatial_zero_planes);
	result["zero_planes"] = zeros;
	return result;
}

// Caller-owned point stays valid through both the returned flow and any wake
// evaluation. No result or callback may be retained for the next RK stage.
inline SpatialFlowResult spatial_binding_flow(const AeroModel &model, const R *prop_offset, const WeatherBinding &weather,
		const R *state, R time, R rho, const std::vector<R> &aux, int turbulence_index, R dt,
		SpatialWeatherCall &call, SpatialPointContext &point) {
	call = {&weather, &aux, turbulence_index, dt};
	const SpatialWindProvider provider{spatial_weather_callback, &call};
	return spatial_flow_sample(state, model, prop_offset, provider, time, rho, point);
}

inline godot::Dictionary spatial_flow_component(const AeroModel &model, const R *prop_offset, const WeatherBinding &weather,
		const godot::PackedFloat64Array &body, double time, double rho, const godot::PackedFloat64Array &raw_aux,
		int turbulence_index, double dt) {
	R state[13];
	if (!spatial_binding_state(body, state)) return spatial_binding_failure("invalid component argument shape");
	std::vector<R> aux;
	aux.reserve(static_cast<std::size_t>(raw_aux.size()));
	for (int64_t i = 0; i < raw_aux.size(); ++i) aux.push_back(raw_aux[i]);
	SpatialWeatherCall call;
	SpatialPointContext point;
	const SpatialFlowResult flow = spatial_binding_flow(model, prop_offset, weather, state, time, rho, aux,
		turbulence_index, dt, call, point);
	if (!flow.ok) {
		godot::Dictionary result = spatial_binding_failure(flow.error);
		result["station"] = flow.station;
		return result;
	}
	godot::Dictionary result;
	result["ok"] = true;
	result["error"] = "";
	result["reference_wind_ned"] = spatial_binding_pack(point.reference_wind, 3);
	result["station_delta_body"] = spatial_binding_pack(flow.aero_deltas.data(), flow.aero_deltas.size());
	result["propulsion_air_body"] = spatial_binding_pack(flow.propulsion_air.data(), 3);
	result["wake_source_delta_body"] = spatial_binding_pack(flow.wake_source_delta.data(), 3);
	result["uniform"] = flow.uniform;
	return result;
}

inline godot::Dictionary spatial_wake_component(const AeroModel &model, const PropModel &prop, const WakeModel &wake,
		const WeatherBinding &weather, const godot::PackedFloat64Array &body, double time, double rho,
		const godot::PackedFloat64Array &controls, double rpm, const godot::PackedFloat64Array &tq, double downwash,
		const godot::PackedFloat64Array &raw_lagged, const godot::PackedFloat64Array &raw_aux, int turbulence_index, double dt) {
	R state[13];
	Deflections d;
	if (!spatial_binding_state(body, state) || !spatial_binding_deflections(controls, d) || tq.size() != 2 ||
		(raw_lagged.size() != 0 && raw_lagged.size() != static_cast<int64_t>(wake.pieces.size()))) {
		return spatial_binding_failure("invalid component argument shape");
	}
	std::vector<R> aux, lagged;
	aux.reserve(static_cast<std::size_t>(raw_aux.size()));
	lagged.reserve(static_cast<std::size_t>(raw_lagged.size()));
	for (int64_t i = 0; i < raw_aux.size(); ++i) aux.push_back(raw_aux[i]);
	for (int64_t i = 0; i < raw_lagged.size(); ++i) lagged.push_back(raw_lagged[i]);
	SpatialWeatherCall call;
	SpatialPointContext point;
	const SpatialFlowResult flow = spatial_binding_flow(model, prop.offset, weather, state, time, rho, aux,
		turbulence_index, dt, call, point);
	if (!flow.ok) return spatial_binding_failure(flow.error);
	const WakePointSampler sampler = spatial_wake_sampler(point);
	const Loads loads = wake_loads(state, flow.air, d, model, prop, wake, rpm, rho, tq[0], tq[1], downwash,
		lagged.empty() ? nullptr : lagged.data(), flow.wake_source_delta.data(), &sampler);
	godot::Dictionary result;
	result["ok"] = true;
	result["error"] = "";
	result["loads"] = spatial_binding_pack(loads.data(), 6);
	return result;
}

} // namespace nk
