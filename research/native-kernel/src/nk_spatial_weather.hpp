// NK-3 spatial weather point queries. Mirrors the per-query laws in
// app/physics/wind_spatial_field.gd and wind_thermal_field.gd. The caller
// supplies a detached snapshot of the validated provider's construction-time
// profile coefficients, ordered gusts and resolved xorshift modes. No random
// state, mutable clock, scene object or GDScript callback is used at a stage.
// Aircraft station geometry and aerodynamic point-flow composition are owned
// separately by the vehicle's stage evaluator.
#pragma once

#include <array>
#include <cmath>
#include <cstddef>
#include <vector>

#include "nk_weather.hpp"

namespace nk {

constexpr double kSpatialWeatherTau = 6.283185307179586476925286766559;
constexpr double kSpatialThermalPi = 3.1415926535897932384626433832795;
constexpr std::size_t kSpatialWeatherModeSize = 9;
constexpr std::size_t kSpatialWeatherGustSize = 4;

struct SpatialWeatherLayer {
	R center_agl_m = 0.0;
	R half_thickness_m = 1.0;
	R delta_north = 0.0;
	R delta_east = 0.0;
};

struct SpatialThermalCell {
	R birth_s = 0.0;
	R duration_s = 1.0;
	R center_north_m = 0.0;
	R center_east_m = 0.0;
	R drift_north_mps = 0.0;
	R drift_east_mps = 0.0;
	R radius_m = 1.0;
	R top_agl_m = 1.0;
	R peak_updraft_mps = 0.0;
};

struct SpatialThermalField {
	R half_extent_north_m = 0.0;
	R half_extent_east_m = 0.0;
	R max_height_agl_m = 0.0;
	R time_horizon_s = 0.0;
	R epoch_offset_s = 0.0;
	std::vector<SpatialThermalCell> cells;
};

struct SpatialWeather {
	// wind_spatial_field.gd _config.domain and _config.identity.
	R half_extent_north_m = 0.0;
	R half_extent_east_m = 0.0;
	R max_height_agl_m = 0.0;
	R time_horizon_s = 0.0;
	R ground_extension_m = 0.0;
	R epoch_offset_s = 0.0;

	// The provider's immutable, construction-time _prepare_profile_and_gusts
	// values and _config.profile.free_air_wind_ned_mps. Preserve these bytes.
	R reference_speed = 0.0;
	R roughness_length = 1.0;
	R displacement_height = 0.0;
	R wall_height = 1.0;
	R surface_top = 1.0;
	R free_air_join_height = 1.0;
	R direction_cosine = 1.0;
	R direction_sine = 0.0;
	R log_denominator = 1.0;
	R wall_scale = 0.0;
	R wall_scale_slope = 0.0;
	std::array<R, 3> free_air_ned{0.0, 0.0, 0.0};
	std::vector<SpatialWeatherLayer> layers;

	R gust_transition_height = 1.0;
	R gust_max_duration = 0.0;
	// Authored order including ties: [start_s, duration_s, amplitude_north,
	// amplitude_east] repeated exactly as the provider's _gust_values.
	std::vector<R> gust_values;
	R turbulence_rms = 0.0;
	// Provider's _modes: [kN,kE,kD,axisN,axisE,cross_k,amplitude,phase,omega].
	std::vector<R> modes;
	bool has_thermal = false;
	SpatialThermalField thermal;
};

struct SpatialWeatherSample {
	bool ok = false;
	std::array<R, 3> wind_ned{kNan, kNan, kNan};
};

inline R spatial_smooth5(R value) {
	const R x = clampf(value, 0.0, 1.0);
	return x * x * x * (R(10.0) + x * (R(-15.0) + 6.0 * x));
}

inline R spatial_smooth5_derivative(R value) {
	const R x = clampf(value, 0.0, 1.0);
	return R(30.0) * x * x * (R(1.0) - x) * (R(1.0) - x);
}

// wind_spatial_field.gd _neutral_profile, using the same prepared denominator.
inline std::array<R, 3> spatial_neutral_profile(const SpatialWeather &model, R height_agl) {
	if (model.reference_speed.v == 0.0) {
		return {0.0, 0.0, 0.0};
	}
	const R log_argument = (height_agl - model.displacement_height) / model.roughness_length;
	const R scale = R(::log(log_argument.v)) / model.log_denominator;
	const R north = -model.reference_speed * model.direction_cosine * scale;
	const R east = -model.reference_speed * model.direction_sine * scale;
	return {north, east, 0.0};
}

// wind_spatial_field.gd _wall_join.
inline std::array<R, 3> spatial_wall_join(const SpatialWeather &model, R height_agl) {
	if (height_agl.v <= 0.0 || model.reference_speed.v == 0.0) {
		return {0.0, 0.0, 0.0};
	}
	const R unit_north = -model.direction_cosine;
	const R unit_east = -model.direction_sine;
	const R s = clampf(height_agl / model.wall_height, 0.0, 1.0);
	const R h01 = R(-2.0) * s * s * s + R(3.0) * s * s;
	const R h11 = s * s * s - s * s;
	const R north = model.reference_speed * unit_north *
			(h01 * model.wall_scale + h11 * model.wall_height * model.wall_scale_slope);
	const R east = model.reference_speed * unit_east *
			(h01 * model.wall_scale + h11 * model.wall_height * model.wall_scale_slope);
	return {north, east, 0.0};
}

// wind_spatial_field.gd _profile_wind; layers retain authored summation order.
inline std::array<R, 3> spatial_profile_wind(const SpatialWeather &model, R height_agl) {
	std::array<R, 3> result;
	if (height_agl.v < model.wall_height.v) {
		result = spatial_wall_join(model, height_agl);
	} else if (height_agl.v <= model.surface_top.v) {
		result = spatial_neutral_profile(model, height_agl);
	} else {
		R fraction = (height_agl - model.surface_top) / model.free_air_join_height;
		fraction = clampf(fraction, 0.0, 1.0);
		if (fraction.v >= 1.0) {
			result = model.free_air_ned;
		} else {
			const R weight = spatial_smooth5(fraction);
			const std::array<R, 3> neutral = spatial_neutral_profile(model, height_agl);
			result = {neutral[0] * (R(1.0) - weight) + model.free_air_ned[0] * weight,
					neutral[1] * (R(1.0) - weight) + model.free_air_ned[1] * weight, 0.0};
		}
	}
	for (const SpatialWeatherLayer &layer : model.layers) {
		const R normalized = absf(height_agl - layer.center_agl_m) / layer.half_thickness_m;
		if (normalized.v >= 1.0) {
			continue;
		}
		const R weight = R(1.0) - spatial_smooth5(normalized);
		result[0] += layer.delta_north * weight;
		result[1] += layer.delta_east * weight;
	}
	return result;
}

// wind_spatial_field.gd _first_possible_gust. Do not replace the subtraction
// with epoch_time >= start + duration: that changes rounding near event ends.
inline std::size_t spatial_first_possible_gust(const SpatialWeather &model, R epoch_time) {
	std::size_t first = 0;
	std::size_t last = model.gust_values.size() / kSpatialWeatherGustSize;
	while (first < last) {
		const std::size_t middle = (first + last) >> 1;
		if ((epoch_time - model.gust_values[middle * kSpatialWeatherGustSize]).v >= model.gust_max_duration.v) {
			first = middle + 1;
		} else {
			last = middle;
		}
	}
	return first;
}

// wind_spatial_field.gd _gust_wind; tied starts and additions remain ordered.
inline std::array<R, 3> spatial_gust_wind(const SpatialWeather &model, R height_agl, R epoch_time) {
	std::array<R, 3> result{0.0, 0.0, 0.0};
	if (model.gust_values.empty() || (epoch_time - model.gust_values[0]).v < 0.0) {
		return result;
	}
	const std::size_t first = spatial_first_possible_gust(model, epoch_time) * kSpatialWeatherGustSize;
	if (first == model.gust_values.size()) {
		return result;
	}
	const R wall_weight = spatial_smooth5(clampf(height_agl / model.gust_transition_height, 0.0, 1.0));
	for (std::size_t offset = first; offset < model.gust_values.size(); offset += kSpatialWeatherGustSize) {
		const R start = model.gust_values[offset];
		const R duration = model.gust_values[offset + 1];
		const R elapsed = epoch_time - start;
		if (elapsed.v < 0.0) {
			break;
		}
		if (elapsed.v >= duration.v) {
			continue;
		}
		const R s = elapsed / duration;
		const R one_minus_s = R(1.0) - s;
		const R pulse = R(64.0) * s * s * s * one_minus_s * one_minus_s * one_minus_s;
		result[0] += model.gust_values[offset + 2] * pulse * wall_weight;
		result[1] += model.gust_values[offset + 3] * pulse * wall_weight;
	}
	return result;
}

// wind_spatial_field.gd _turbulence_wind. Modes were seeded/resolved once by
// the owner; every position and epoch phase is evaluated at this stage.
inline std::array<R, 3> spatial_turbulence_wind(const SpatialWeather &model, R north_m, R east_m,
		R height_agl, R epoch_time) {
	R result_north = 0.0;
	R result_east = 0.0;
	R result_down = 0.0;
	if (model.turbulence_rms.v == 0.0) {
		return {result_north, result_east, result_down};
	}
	for (std::size_t offset = 0; offset < model.modes.size(); offset += kSpatialWeatherModeSize) {
		const R k_north = model.modes[offset];
		const R k_east = model.modes[offset + 1];
		const R k_down = model.modes[offset + 2];
		const R axis_north = model.modes[offset + 3];
		const R axis_east = model.modes[offset + 4];
		const R cross_wavenumber = model.modes[offset + 5];
		const R amplitude = model.modes[offset + 6];
		const R phase_offset = model.modes[offset + 7];
		const R omega = model.modes[offset + 8];
		const R spatial_phase = k_north * north_m + k_east * east_m + phase_offset;
		const R temporal_phase = omega * epoch_time;
		const R phase = weather_fposmod(weather_fposmod(spatial_phase, kSpatialWeatherTau) +
				weather_fposmod(temporal_phase, kSpatialWeatherTau), kSpatialWeatherTau);
		const R cosine_phase = cos_(phase);
		const R sine_phase = sin_(phase);
		const R vertical_phase = k_down * height_agl;
		const R sine_vertical = sin_(vertical_phase);
		const R cosine_vertical = cos_(vertical_phase);
		const R wall_fraction = clampf(vertical_phase / kSpatialWeatherTau, 0.0, 1.0);
		const R wall_weight = spatial_smooth5(wall_fraction);
		R wall_derivative = 0.0;
		if (wall_fraction.v > 0.0 && wall_fraction.v < 1.0) {
			wall_derivative = spatial_smooth5_derivative(wall_fraction) * k_down / kSpatialWeatherTau;
		}
		const R potential_height = wall_weight * sine_vertical;
		const R potential_height_derivative = wall_derivative * sine_vertical + wall_weight * k_down * cosine_vertical;
		const R horizontal_derivative = amplitude * potential_height_derivative * cosine_phase;
		const R vertical_velocity = amplitude * potential_height * cross_wavenumber * sine_phase;
		result_north += axis_east * horizontal_derivative;
		result_east -= axis_north * horizontal_derivative;
		result_down += vertical_velocity;
	}
	return {result_north, result_east, result_down};
}

// wind_thermal_field.gd _cell_velocity; all cell and axis sums stay ordered.
inline std::array<R, 3> spatial_thermal_cell_wind(const SpatialThermalCell &cell, R north_m, R east_m,
		R height_agl, R epoch_time) {
	const std::array<R, 3> zero{0.0, 0.0, 0.0};
	if (height_agl.v <= 0.0 || height_agl.v >= cell.top_agl_m.v) {
		return zero;
	}
	const R age = epoch_time - cell.birth_s;
	if (age.v < 0.0 || age.v >= cell.duration_s.v) {
		return zero;
	}
	const R time_fraction = age / cell.duration_s;
	const R remainder = R(1.0) - time_fraction;
	const R lifecycle = R(64.0) * time_fraction * time_fraction * time_fraction * remainder * remainder * remainder;
	const R center_north = cell.center_north_m + cell.drift_north_mps * age;
	const R center_east = cell.center_east_m + cell.drift_east_mps * age;
	const R offset_north = north_m - center_north;
	const R offset_east = east_m - center_east;
	const R radius_squared = cell.radius_m * cell.radius_m;
	const R radial_squared = offset_north * offset_north + offset_east * offset_east;
	const R radial_distance = sqrt_(radial_squared);
	if (radial_distance.v >= (R(5.0) * cell.radius_m).v) {
		return zero;
	}
	R taper = 1.0;
	R taper_derivative = 0.0;
	const R radial_ratio = radial_distance / cell.radius_m;
	if (radial_ratio.v > 4.0) {
		const R taper_fraction = radial_ratio - 4.0;
		taper = R(1.0) - spatial_smooth5(taper_fraction);
		taper_derivative = -spatial_smooth5_derivative(taper_fraction) / cell.radius_m;
	}
	const R vertical_wave = kSpatialThermalPi * height_agl / cell.top_agl_m;
	const R vertical_value = cell.peak_updraft_mps * sin_(vertical_wave) * sin_(vertical_wave);
	const R vertical_derivative = cell.peak_updraft_mps * kSpatialThermalPi / cell.top_agl_m * sin_(2.0 * vertical_wave);
	const R exponent = -radial_squared / radius_squared;
	const R exponential = ::exp(exponent.v);
	const R radial_velocity = R(-0.5) * lifecycle * vertical_derivative * radial_distance * exponential * taper;
	R vertical_up_velocity = 0.0;
	if (radial_distance.v == 0.0) {
		vertical_up_velocity = lifecycle * vertical_value;
	} else {
		const R radial_derivative = exponential *
				(R(2.0) * radial_distance * (R(1.0) - radial_squared / radius_squared) * taper +
				 radial_squared * taper_derivative);
		vertical_up_velocity = R(0.5) * lifecycle * vertical_value * radial_derivative / radial_distance;
	}
	R north_velocity = 0.0;
	R east_velocity = 0.0;
	if (radial_distance.v > 0.0) {
		north_velocity = radial_velocity * offset_north / radial_distance;
		east_velocity = radial_velocity * offset_east / radial_distance;
	}
	return {north_velocity, east_velocity, -vertical_up_velocity};
}

// wind_thermal_field.gd sample_world; retains its separate domain and clock.
inline SpatialWeatherSample spatial_thermal_sample(const SpatialThermalField &model, const R *position_ned,
		R simulation_time) {
	if (position_ned == nullptr || !is_finite(position_ned[0]) || !is_finite(position_ned[1]) ||
			!is_finite(position_ned[2]) || !is_finite(simulation_time) || simulation_time.v < 0.0) {
		return {};
	}
	if (absf(position_ned[0]).v > model.half_extent_north_m.v ||
			absf(position_ned[1]).v > model.half_extent_east_m.v) {
		return {};
	}
	const R height_agl = -position_ned[2];
	if (height_agl.v < 0.0 || height_agl.v > model.max_height_agl_m.v || simulation_time.v > model.time_horizon_s.v) {
		return {};
	}
	const R epoch_time = simulation_time + model.epoch_offset_s;
	if (!is_finite(epoch_time) || epoch_time.v > model.time_horizon_s.v) {
		return {};
	}
	if (height_agl.v == 0.0) {
		return {true, {0.0, 0.0, 0.0}};
	}
	std::array<R, 3> result{0.0, 0.0, 0.0};
	for (const SpatialThermalCell &cell : model.cells) {
		const std::array<R, 3> cell_wind = spatial_thermal_cell_wind(cell, position_ned[0], position_ned[1], height_agl, epoch_time);
		for (std::size_t axis = 0; axis < 3; ++axis) {
			result[axis] += cell_wind[axis];
			if (!is_finite(result[axis])) {
				return {};
			}
		}
	}
	return {true, result};
}

// wind_spatial_field.gd sample_world. stage_time is the actual RK query time,
// after the FlightSession NaN -> sim.time() substitution if applicable.
inline SpatialWeatherSample spatial_weather_sample(const SpatialWeather &model, const R *position_ned, R stage_time) {
	if (position_ned == nullptr || !is_finite(position_ned[0]) || !is_finite(position_ned[1]) ||
			!is_finite(position_ned[2]) || !is_finite(stage_time) || stage_time.v < 0.0) {
		return {};
	}
	if (absf(position_ned[0]).v > model.half_extent_north_m.v ||
			absf(position_ned[1]).v > model.half_extent_east_m.v || stage_time.v > model.time_horizon_s.v) {
		return {};
	}
	const R epoch_time = stage_time + model.epoch_offset_s;
	if (!is_finite(epoch_time) || epoch_time.v > model.time_horizon_s.v) {
		return {};
	}
	const R height_agl = -position_ned[2];
	if (height_agl.v < (-model.ground_extension_m).v || height_agl.v > model.max_height_agl_m.v) {
		return {};
	}
	if (height_agl.v <= 0.0) {
		return {true, {0.0, 0.0, 0.0}};
	}
	// Prepared arrays are bounded and checked at decode. Still reject malformed
	// sizes here so an accidental bad context cannot index outside the arrays.
	if (model.gust_values.size() % kSpatialWeatherGustSize != 0 ||
			(model.turbulence_rms.v != 0.0 && model.modes.size() % kSpatialWeatherModeSize != 0)) {
		return {};
	}
	std::array<R, 3> wind = spatial_profile_wind(model, height_agl);
	const std::array<R, 3> gust = spatial_gust_wind(model, height_agl, epoch_time);
	const std::array<R, 3> turbulent = spatial_turbulence_wind(model, position_ned[0], position_ned[1], height_agl, epoch_time);
	for (std::size_t axis = 0; axis < 3; ++axis) {
		wind[axis] += gust[axis] + turbulent[axis];
		if (!is_finite(wind[axis])) {
			return {};
		}
	}
	if (model.has_thermal) {
		const SpatialWeatherSample thermal = spatial_thermal_sample(model.thermal, position_ned, stage_time);
		if (!thermal.ok) {
			return {};
		}
		for (std::size_t axis = 0; axis < 3; ++axis) {
			wind[axis] += thermal.wind_ned[axis];
			if (!is_finite(wind[axis])) {
				return {};
			}
		}
	}
	return {true, wind};
}

// Environment.wind_world converts a refused spatial result to three NaNs. v5
// disallows FlightSession's separate OU turbulence, so no extra noise is added.
inline std::array<R, 3> spatial_weather_wind(const SpatialWeather &model, const R *position_ned, R stage_time) {
	const SpatialWeatherSample sample = spatial_weather_sample(model, position_ned, stage_time);
	return sample.ok ? sample.wind_ned : weather_invalid_wind();
}

} // namespace nk
