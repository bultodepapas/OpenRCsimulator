// NK-3 uniform weather stage input. Mirrors app/physics/wind_field.gd's v1-v4
// sample/sample_world and direction law, app/sim/environment.gd's wind_world,
// app/sim/flight_session.gd's turbulence_at, and the dry standard column in
// app/physics/atmosphere.gd. Construction takes already validated settings;
// the caller owns admission, configuration identity and tick transactions.
//
// The session still owns the OU RNG and advances it once in pre_tick. Its
// resulting aux interval is read, never mutated, during any number of stages.
// Spatial weather v5 has a different point-flow law and is not implemented here.
#pragma once

#include <array>
#include <cmath>
#include <cstddef>
#include <vector>

#include "nk_math.hpp"

namespace nk {

constexpr double kWeatherTau = 6.2831853071795864769252867666; // GDScript TAU
constexpr double kWeatherSeaPressure = 101325.0;
constexpr double kWeatherSeaTemperature = 288.15;
constexpr double kWeatherSeaDensity = 1.225;
constexpr double kWeatherGravity = 9.80665;
constexpr double kWeatherLapse = 0.0065;
constexpr double kWeatherDryGas = 287.05287;
constexpr double kWeatherEarthRadius = 6356766.0;

struct WeatherModel {
	std::array<R, 3> mean_ned{0.0, 0.0, 0.0};
	std::array<R, 3> gust_ned{0.0, 0.0, 0.0};
	R gust_duration_s = 4.0;
	R gust_period_s = 12.0;
	R gust_delay_s = 2.0;
	bool calm = true;
	bool has_gust = false;
	bool has_turbulence = false;
	bool vertical_atmosphere = false;
	R field_elevation_m = 0.0;
	R uniform_density = kWeatherSeaDensity;
	R uniform_charge = 1.0;
};

struct WeatherAir {
	bool ok = false;
	R density = kNan;
	R engine_charge_ratio = kNan;
};

inline std::array<R, 3> weather_invalid_wind() {
	return {kNan, kNan, kNan};
}

// Godot 4.7.2 Math::fposmod: fmod, sign correction, then the +0.0 sign scrub.
// This helper is an engine function rather than a GDScript binary expression.
inline R weather_fposmod(R value, R period) {
	R result = ::fmod(value.v, period.v);
	if ((result.v < 0.0 && period.v > 0.0) || (result.v > 0.0 && period.v < 0.0)) {
		result += period;
	}
	result += 0.0;
	return result;
}

// WindField._direction_ned. Zero and cardinal headings deliberately avoid sin/
// cos; the minus signs on magnitude are part of the returned binary64 values.
inline std::array<R, 3> weather_direction(R from_deg, R magnitude) {
	if (magnitude.v == 0.0) {
		return {0.0, 0.0, 0.0};
	}
	if (from_deg.v == 0.0) {
		return {-magnitude, 0.0, 0.0};
	}
	if (from_deg.v == 90.0) {
		return {0.0, -magnitude, 0.0};
	}
	if (from_deg.v == 180.0) {
		return {magnitude, 0.0, 0.0};
	}
	if (from_deg.v == 270.0) {
		return {0.0, magnitude, 0.0};
	}
	// Godot Math::deg_to_rad multiplies by the precomputed PI / 180 constant.
	const R radians = from_deg * (kPi / 180.0);
	return {-magnitude * cos_(radians), -magnitude * sin_(radians), 0.0};
}

// WindField._apply_config. The input is a canonical, validated v1-v4 weather
// configuration. Uniform atmosphere values are prepared by the existing
// validated field; standard-column density is evaluated at each stage instead.
inline WeatherModel weather_uniform(R speed, R from_deg, R gust, R gust_up, R duration, R period, R delay,
		bool has_turbulence, bool vertical_atmosphere, R field_elevation, R uniform_density, R uniform_charge) {
	WeatherModel out;
	out.mean_ned = weather_direction(from_deg, speed);
	out.gust_ned = weather_direction(from_deg, gust);
	out.gust_ned[2] = -gust_up;
	out.gust_duration_s = duration;
	out.gust_period_s = period;
	out.gust_delay_s = delay;
	out.has_gust = gust.v != 0.0 || gust_up.v != 0.0;
	out.has_turbulence = has_turbulence;
	out.calm = speed.v == 0.0 && !out.has_gust && !has_turbulence;
	out.vertical_atmosphere = vertical_atmosphere;
	out.field_elevation_m = field_elevation;
	out.uniform_density = uniform_density;
	out.uniform_charge = uniform_charge;
	return out;
}

// Environment.wind_world -> WeatherField.sample_world -> sample. stage_time
// must already include FlightSession.air_data's NaN -> sim.time() substitution.
// position_ned is exactly three state scalars, and dt is the full kernel tick,
// not an RK substep. A malformed sample returns the reference's all-NaN wind.
inline std::array<R, 3> weather_wind(const WeatherModel &model, const R *position_ned, R stage_time,
		const std::vector<R> &aux, int turbulence_index, R dt) {
	if (position_ned == nullptr || !is_finite(position_ned[0]) || !is_finite(position_ned[1]) ||
			!is_finite(position_ned[2]) || !is_finite(stage_time) || stage_time.v < 0.0) {
		return weather_invalid_wind();
	}
	std::array<R, 3> wind;
	if (model.calm) {
		wind = {0.0, 0.0, 0.0};
	} else if (!model.has_gust) {
		wind = model.mean_ned;
	} else {
		const R elapsed = stage_time - model.gust_delay_s;
		if (elapsed.v < 0.0) {
			wind = model.mean_ned;
		} else {
			const R phase = weather_fposmod(elapsed, model.gust_period_s);
			if (!is_finite(phase)) {
				return weather_invalid_wind();
			}
			if (phase.v <= 0.0 || phase.v >= model.gust_duration_s.v) {
				wind = model.mean_ned;
			} else {
				const R fraction = phase / model.gust_duration_s;
				const R pulse = R(0.5) * (R(1.0) - cos_(kWeatherTau * fraction));
				for (int axis = 0; axis < 3; ++axis) {
					wind[axis] = model.mean_ned[axis] + pulse * model.gust_ned[axis];
				}
			}
		}
	}
	for (R value : wind) {
		if (!is_finite(value)) {
			return weather_invalid_wind();
		}
	}
	if (!model.has_turbulence) {
		// The session's empty noise sample is not a vector of +0.0: returning
		// without addition preserves signed zeros in the weather field.
		return wind;
	}
	// FlightSession._turbulence_noise validates its complete sampled layout.
	if (turbulence_index < 4 || aux.size() < 7 ||
			static_cast<std::size_t>(turbulence_index) != aux.size() - 7 || !is_finite(dt) || dt.v <= 0.0) {
		return weather_invalid_wind();
	}
	const std::size_t index = static_cast<std::size_t>(turbulence_index);
	const R fraction = clampf((stage_time - aux[index + 6]) / dt, 0.0, 1.0);
	std::array<R, 3> noise;
	for (std::size_t axis = 0; axis < 3; ++axis) {
		noise[axis] = aux[index + axis] + fraction * (aux[index + 3 + axis] - aux[index + axis]);
	}
	for (R value : noise) {
		if (!is_finite(value)) {
			return weather_invalid_wind();
		}
	}
	for (std::size_t axis = 0; axis < 3; ++axis) {
		wind[axis] += noise[axis];
		if (!is_finite(wind[axis])) {
			return weather_invalid_wind();
		}
	}
	return wind;
}

// atmosphere.gd _density_altitude_geometric_m; its finite-result validation is
// part of standard_column even though the stage needs only density and charge.
inline R weather_density_altitude(R density) {
	const R sea_density = R(kWeatherSeaPressure) / (R(kWeatherDryGas) * kWeatherSeaTemperature);
	const R exponent = R(kWeatherGravity) / (R(kWeatherDryGas) * kWeatherLapse) - 1.0;
	const R ratio = density / sea_density;
	if (ratio.v <= 0.0 || exponent.v <= 0.0) {
		return kNan;
	}
	const R geopotential = R(kWeatherSeaTemperature) / kWeatherLapse * (R(1.0) - pow_(ratio, R(1.0) / exponent));
	return kWeatherEarthRadius * geopotential / (kWeatherEarthRadius - geopotential);
}

// WindField.air_density/engine_charge_ratio and Atmosphere.standard_column.
// A uniform field ignores down_m exactly as the reference does; the vertical
// column samples geometric altitude = field elevation - NED datum down.
inline WeatherAir weather_air(const WeatherModel &model, R down_m) {
	if (!model.vertical_atmosphere) {
		return {true, model.uniform_density, model.uniform_charge};
	}
	const R altitude = model.field_elevation_m - down_m;
	if (!is_finite(altitude) || altitude.v < -500.0 || altitude.v > 11000.0) {
		return {};
	}
	const R geopotential = kWeatherEarthRadius * altitude / (kWeatherEarthRadius + altitude);
	const R temperature = kWeatherSeaTemperature - kWeatherLapse * geopotential;
	const R pressure_base = temperature / kWeatherSeaTemperature;
	if (!is_finite(temperature) || temperature.v <= 0.0 || !is_finite(pressure_base) || pressure_base.v <= 0.0) {
		return {};
	}
	const R exponent = R(kWeatherGravity) / (R(kWeatherDryGas) * kWeatherLapse);
	const R pressure = kWeatherSeaPressure * pow_(pressure_base, exponent);
	const R density = pressure / (R(kWeatherDryGas) * temperature);
	const R sigma = density / kWeatherSeaDensity;
	const R density_altitude = weather_density_altitude(density);
	if (!is_finite(pressure) || pressure.v <= 0.0 || !is_finite(density) || density.v <= 0.0 ||
			!is_finite(sigma) || !is_finite(density_altitude)) {
		return {};
	}
	return {true, density, sigma};
}

} // namespace nk
