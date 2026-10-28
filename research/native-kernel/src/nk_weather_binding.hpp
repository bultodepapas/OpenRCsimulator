// Strict, prepare-time adapter for NK-3 weather snapshots. Inputs are detached
// from a validated WeatherField by the session/oracle; no Godot object, RNG or
// GDScript callback is retained for stage queries. Identity and mutation guards
// for the originating provider remain the caller's responsibility.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <initializer_list>
#include <limits>
#include <string>
#include <vector>

#include "nk_spatial_weather.hpp"

namespace nk {

// Snapshot v1 schema:
// {format, kind, vertical_atmosphere, has_turbulence, atmosphere, uniform|spatial}.
// atmosphere float64 = [field elevation, uniform density, uniform charge].
// uniform float64 = [speed, from degrees, gust, gust-up, duration, period, delay].
// spatial has domain[7], profile[14], layers[4*N], gust_values[4*N],
// gust_max_duration, turbulence_rms, modes[9*N], and thermal. See decode_spatial
// for each vector's order. thermal is {} or {domain[5], cells[9*N]}.
// All vectors must be PackedFloat64Array, not generic Arrays.
struct WeatherSnapshotDecoder {
	std::string error;

	bool fail(const std::string &reason) {
		if (error.empty()) {
			error = reason;
		}
		return false;
	}

	bool keys(const godot::Dictionary &dict, const char *where, std::initializer_list<const char *> allowed) {
		const godot::Array names = dict.keys();
		for (int64_t index = 0; index < names.size(); ++index) {
			const godot::Variant key = names[index];
			if (key.get_type() != godot::Variant::STRING && key.get_type() != godot::Variant::STRING_NAME) {
				return fail(std::string(where) + " has a non-string key");
			}
			const godot::String name = key;
			bool found = false;
			for (const char *allowed_name : allowed) {
				if (name == godot::String(allowed_name)) {
					found = true;
					break;
				}
			}
			if (!found) {
				return fail(std::string("unsupported ") + where + "." + name.utf8().get_data());
			}
		}
		return true;
	}

	bool string(const godot::Dictionary &dict, const char *key, godot::String &out) {
		if (!dict.has(key) || dict[key].get_type() != godot::Variant::STRING) {
			return fail(std::string("missing or non-string ") + key);
		}
		out = dict[key];
		return true;
	}

	bool boolean(const godot::Dictionary &dict, const char *key, bool &out) {
		if (!dict.has(key) || dict[key].get_type() != godot::Variant::BOOL) {
			return fail(std::string("missing or non-boolean ") + key);
		}
		out = static_cast<bool>(dict[key]);
		return true;
	}

	bool number(const godot::Dictionary &dict, const char *key, R &out) {
		if (!dict.has(key)) {
			return fail(std::string("missing ") + key);
		}
		const godot::Variant value = dict[key];
		if (value.get_type() == godot::Variant::FLOAT) {
			out = static_cast<double>(value);
		} else if (value.get_type() == godot::Variant::INT) {
			out = static_cast<double>(static_cast<int64_t>(value));
		} else {
			return fail(std::string("non-numeric ") + key);
		}
		return is_finite(out) || fail(std::string("nonfinite ") + key);
	}

	bool dictionary(const godot::Dictionary &dict, const char *key, godot::Dictionary &out) {
		if (!dict.has(key) || dict[key].get_type() != godot::Variant::DICTIONARY) {
			return fail(std::string("missing or non-dictionary ") + key);
		}
		out = dict[key];
		return true;
	}

	bool packed(const godot::Dictionary &dict, const char *key, std::vector<R> &out, int64_t exact_size = -1) {
		if (!dict.has(key) || dict[key].get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) {
			return fail(std::string("missing or non-float64 array ") + key);
		}
		const godot::PackedFloat64Array values = dict[key];
		if ((exact_size >= 0 && values.size() != exact_size) || values.size() > 1024) {
			return fail(std::string("invalid array length ") + key);
		}
		out.clear();
		out.reserve(static_cast<std::size_t>(values.size()));
		for (int64_t index = 0; index < values.size(); ++index) {
			const R value = values[index];
			if (!is_finite(value)) {
				return fail(std::string("nonfinite array value ") + key);
			}
			out.push_back(value);
		}
		return true;
	}
};

inline bool weather_snapshot_in_range(R value, double low, double high) {
	return is_finite(value) && value.v >= low && value.v <= high;
}

inline bool weather_snapshot_thermal(WeatherSnapshotDecoder &dec, const godot::Dictionary &raw,
		const SpatialWeather &spatial, SpatialThermalField &thermal) {
	if (!dec.keys(raw, "thermal", {"domain", "cells"})) {
		return false;
	}
	std::vector<R> domain, cells;
	if (!dec.packed(raw, "domain", domain, 5) || !dec.packed(raw, "cells", cells)) {
		return false;
	}
	if (domain[0].v != spatial.half_extent_north_m.v || domain[1].v != spatial.half_extent_east_m.v ||
			domain[2].v != spatial.max_height_agl_m.v || domain[3].v != spatial.time_horizon_s.v ||
			domain[4].v != spatial.epoch_offset_s.v || domain[2].v < 200.0 || domain[3].v < 120.0 ||
			cells.size() % 9 != 0 || cells.size() > 9 * 16) {
		return dec.fail("thermal domain or cell layout is inconsistent");
	}
	thermal.half_extent_north_m = domain[0];
	thermal.half_extent_east_m = domain[1];
	thermal.max_height_agl_m = domain[2];
	thermal.time_horizon_s = domain[3];
	thermal.epoch_offset_s = domain[4];
	R previous_birth = -kInf;
	for (std::size_t i = 0; i < cells.size(); i += 9) {
		const R birth = cells[i], duration = cells[i + 1], cn = cells[i + 2], ce = cells[i + 3];
		const R dn = cells[i + 4], de = cells[i + 5], radius = cells[i + 6], top = cells[i + 7], peak = cells[i + 8];
		if (!weather_snapshot_in_range(birth, 0.0, 86400.0) || !weather_snapshot_in_range(duration, 120.0, 720.0) ||
				!weather_snapshot_in_range(cn, -10000.0, 10000.0) || !weather_snapshot_in_range(ce, -10000.0, 10000.0) ||
				!weather_snapshot_in_range(dn, -20.0, 20.0) || !weather_snapshot_in_range(de, -20.0, 20.0) ||
				!weather_snapshot_in_range(radius, 10.0, 80.0) || !weather_snapshot_in_range(top, 200.0, 1200.0) ||
				!weather_snapshot_in_range(peak, -3.0, 3.0) || birth.v < previous_birth.v ||
				(birth + duration).v > domain[3].v || top.v > domain[2].v || radius.v > (R(0.5) * top).v ||
				(absf(cn) + absf(dn) * duration + R(5.0) * radius).v > domain[0].v ||
				(absf(ce) + absf(de) * duration + R(5.0) * radius).v > domain[1].v) {
			return dec.fail("thermal cell is malformed or outside its domain");
		}
		previous_birth = birth;
		thermal.cells.push_back({birth, duration, cn, ce, dn, de, radius, top, peak});
	}
	for (const SpatialThermalCell &origin : thermal.cells) {
		int count = 0;
		R peak_sum = 0.0;
		for (const SpatialThermalCell &candidate : thermal.cells) {
			if (candidate.birth_s.v <= origin.birth_s.v &&
					origin.birth_s.v < (candidate.birth_s + candidate.duration_s).v) {
				++count;
				peak_sum += absf(candidate.peak_updraft_mps);
			}
		}
		if (count > 4 || peak_sum.v > 6.0) {
			return dec.fail("thermal overlap exceeds the validated domain");
		}
	}
	return true;
}


inline bool weather_snapshot_spatial(WeatherSnapshotDecoder &dec, const godot::Dictionary &raw,
		SpatialWeather &spatial) {
	if (!dec.keys(raw, "spatial", {"domain", "profile", "layers", "gust_values", "gust_max_duration",
			"turbulence_rms", "modes", "thermal"})) {
		return false;
	}
	std::vector<R> domain, profile, layers;
	godot::Dictionary thermal;
	if (!dec.packed(raw, "domain", domain, 7) || !dec.packed(raw, "profile", profile, 14) ||
			!dec.packed(raw, "layers", layers) || !dec.packed(raw, "gust_values", spatial.gust_values) ||
			!dec.number(raw, "gust_max_duration", spatial.gust_max_duration) ||
			!dec.number(raw, "turbulence_rms", spatial.turbulence_rms) ||
			!dec.packed(raw, "modes", spatial.modes) || !dec.dictionary(raw, "thermal", thermal)) {
		return false;
	}
	// domain = [halfN, halfE, max_height, time_horizon, ground_extension, epoch_offset, gust_transition].
	if (!weather_snapshot_in_range(domain[0], 100.0, 10000.0) || !weather_snapshot_in_range(domain[1], 100.0, 10000.0) ||
			!weather_snapshot_in_range(domain[2], 20.0, 1000.0) || !weather_snapshot_in_range(domain[3], 60.0, 86400.0) ||
			!weather_snapshot_in_range(domain[4], 0.01, 1.0) || !weather_snapshot_in_range(domain[5], 0.0, 86400.0) ||
			!weather_snapshot_in_range(domain[6], 0.1, 50.0) || domain[5].v > domain[3].v || domain[6].v > domain[2].v) {
		return dec.fail("spatial domain is invalid");
	}
	spatial.half_extent_north_m = domain[0]; spatial.half_extent_east_m = domain[1];
	spatial.max_height_agl_m = domain[2]; spatial.time_horizon_s = domain[3];
	spatial.ground_extension_m = domain[4]; spatial.epoch_offset_s = domain[5]; spatial.gust_transition_height = domain[6];
	// profile = [speed, roughness, displacement, wall, surface_top, free_air_join,
	// direction_cosine, direction_sine, log_denominator, wall_scale, wall_slope, freeN, freeE, freeD].
	if (!weather_snapshot_in_range(profile[0], 0.0, 20.0) || !weather_snapshot_in_range(profile[1], 0.001, 0.5) ||
			!weather_snapshot_in_range(profile[2], 0.0, 20.0) || !weather_snapshot_in_range(profile[3], 0.1, 100.0) ||
			!weather_snapshot_in_range(profile[4], 1.0, 500.0) || !weather_snapshot_in_range(profile[5], 0.1, 200.0) ||
			!weather_snapshot_in_range(profile[6], -1.0, 1.0) || !weather_snapshot_in_range(profile[7], -1.0, 1.0) ||
			profile[8].v <= 0.0 || profile[9].v <= 0.0 || profile[10].v <= 0.0 ||
			!weather_snapshot_in_range(profile[11], -30.0, 30.0) || !weather_snapshot_in_range(profile[12], -30.0, 30.0) ||
			profile[13].v != 0.0 || profile[3].v < (profile[2] + maxf(0.3, R(10.0) * profile[1])).v ||
			profile[3].v >= profile[4].v || (profile[4] + profile[5]).v > domain[2].v) {
		return dec.fail("spatial profile is invalid");
	}
	spatial.reference_speed = profile[0]; spatial.roughness_length = profile[1]; spatial.displacement_height = profile[2];
	spatial.wall_height = profile[3]; spatial.surface_top = profile[4]; spatial.free_air_join_height = profile[5];
	spatial.direction_cosine = profile[6]; spatial.direction_sine = profile[7]; spatial.log_denominator = profile[8];
	spatial.wall_scale = profile[9]; spatial.wall_scale_slope = profile[10];
	spatial.free_air_ned = {profile[11], profile[12], profile[13]};
	// layers = [center, half thickness, deltaN, deltaE] in provider order.
	if (layers.size() % 4 != 0 || layers.size() > 4 * 16) {
		return dec.fail("spatial layer layout is invalid");
	}
	R previous_top = -kInf;
	for (std::size_t i = 0; i < layers.size(); i += 4) {
		const R center = layers[i], half = layers[i + 1], dn = layers[i + 2], de = layers[i + 3];
		if (!weather_snapshot_in_range(center, 0.0, 1000.0) || !weather_snapshot_in_range(half, 0.1, 100.0) ||
				!weather_snapshot_in_range(dn, -5.0, 5.0) || !weather_snapshot_in_range(de, -5.0, 5.0) ||
				(center - half).v < profile[3].v || (center + half).v > domain[2].v ||
				(center - half).v < previous_top.v) {
			return dec.fail("spatial layer is malformed, overlapping or outside the domain");
		}
		previous_top = center + half;
		spatial.layers.push_back({center, half, dn, de});
	}
	if (spatial.gust_values.size() % 4 != 0 || spatial.gust_values.size() > 4 * 32 ||
			spatial.gust_max_duration.v < 0.0 || !weather_snapshot_in_range(spatial.turbulence_rms, 0.0, 1.0) ||
			spatial.modes.size() % 9 != 0 || spatial.modes.size() < 9 * 8 || spatial.modes.size() > 9 * 64) {
		return dec.fail("spatial gust or mode layout is invalid");
	}
	R previous_start = -kInf;
	R longest = 0.0;
	for (std::size_t i = 0; i < spatial.gust_values.size(); i += 4) {
		const R start = spatial.gust_values[i], duration = spatial.gust_values[i + 1];
		if (!weather_snapshot_in_range(start, 0.0, 86400.0) || !weather_snapshot_in_range(duration, 0.1, 120.0) ||
				!weather_snapshot_in_range(spatial.gust_values[i + 2], -2.5, 2.5) ||
				!weather_snapshot_in_range(spatial.gust_values[i + 3], -2.5, 2.5) ||
				start.v < previous_start.v || (start + duration).v > domain[3].v) {
			return dec.fail("spatial gust agenda is invalid");
		}
		previous_start = start;
		longest = maxf(longest, duration);
	}
	if (longest.v != spatial.gust_max_duration.v) {
		return dec.fail("spatial gust maximum duration is inconsistent");
	}
	for (std::size_t origin = 0; origin < spatial.gust_values.size(); origin += 4) {
		int count = 0;
		R amplitude_sum = 0.0;
		const R time = spatial.gust_values[origin];
		for (std::size_t candidate = 0; candidate < spatial.gust_values.size(); candidate += 4) {
			const R start = spatial.gust_values[candidate], duration = spatial.gust_values[candidate + 1];
			if (start.v <= time.v && time.v < (start + duration).v) {
				++count;
				const R n = spatial.gust_values[candidate + 2], e = spatial.gust_values[candidate + 3];
				amplitude_sum += sqrt_(n * n + e * e);
			}
		}
		if (count > 4 || amplitude_sum.v > 8.0) {
			return dec.fail("spatial gust overlap exceeds the validated domain");
		}
	}
	for (std::size_t i = 0; i < spatial.modes.size(); i += 9) {
		if (spatial.modes[i + 2].v <= 0.0 || !weather_snapshot_in_range(spatial.modes[i + 3], -1.0, 1.0) ||
				!weather_snapshot_in_range(spatial.modes[i + 4], -1.0, 1.0) || spatial.modes[i + 6].v < 0.0 ||
				!weather_snapshot_in_range(spatial.modes[i + 7], 0.0, kSpatialWeatherTau)) {
			return dec.fail("spatial mode is invalid");
		}
	}
	spatial.has_thermal = !thermal.is_empty();
	return !spatial.has_thermal || weather_snapshot_thermal(dec, thermal, spatial, spatial.thermal);
}


class WeatherBinding {
	bool ready_ = false;
	bool spatial_ = false;
	WeatherModel weather_;
	SpatialWeather spatial_model_;

public:
	bool ready() const { return ready_; }
	bool is_spatial() const { return ready_ && spatial_; }

	godot::Dictionary prepare_weather(const godot::Dictionary &config) {
		ready_ = false;
		WeatherSnapshotDecoder dec;
		godot::Dictionary out;
		godot::String format, kind;
		bool vertical = false, turbulent = false;
		std::vector<R> atmosphere, uniform;
		godot::Dictionary spatial;
		if (!dec.keys(config, "weather", {"format", "kind", "vertical_atmosphere", "has_turbulence", "atmosphere",
				"uniform", "spatial"}) || !dec.string(config, "format", format) || !dec.string(config, "kind", kind) ||
				!dec.boolean(config, "vertical_atmosphere", vertical) || !dec.boolean(config, "has_turbulence", turbulent) ||
				!dec.packed(config, "atmosphere", atmosphere, 3)) {
			return failure(dec.error);
		}
		if (format != godot::String("openrc-nk3-weather-snapshot-v1") ||
				(kind != godot::String("uniform") && kind != godot::String("spatial"))) {
			return failure("unknown weather snapshot format or kind");
		}
		if (!weather_snapshot_in_range(atmosphere[0], -500.0, 4000.0) || atmosphere[1].v <= 0.0 || atmosphere[2].v <= 0.0) {
			return failure("invalid atmosphere snapshot");
		}
		WeatherModel weather;
		SpatialWeather spatial_model;
		const bool spatial_kind = kind == godot::String("spatial");
		if (!spatial_kind) {
			if (config.has("spatial") || !dec.packed(config, "uniform", uniform, 7)) {
				return failure(dec.error.empty() ? "uniform snapshot has spatial input" : dec.error);
			}
			if (!weather_snapshot_in_range(uniform[0], 0.0, 15.0) || !weather_snapshot_in_range(uniform[1], 0.0, 360.0) ||
					uniform[1].v == 360.0 || !weather_snapshot_in_range(uniform[2], 0.0, 8.0) ||
					!weather_snapshot_in_range(uniform[3], -8.0, 8.0) || !weather_snapshot_in_range(uniform[4], 0.5, 20.0) ||
					!weather_snapshot_in_range(uniform[5], 0.5, 120.0) || !weather_snapshot_in_range(uniform[6], 0.0, 3600.0) ||
					uniform[5].v < uniform[4].v) {
				return failure("invalid uniform weather snapshot");
			}
			weather = weather_uniform(uniform[0], uniform[1], uniform[2], uniform[3], uniform[4], uniform[5], uniform[6],
					turbulent, vertical, atmosphere[0], atmosphere[1], atmosphere[2]);
		} else {
			if (turbulent || config.has("uniform") || !dec.dictionary(config, "spatial", spatial)) {
				return failure(dec.error.empty() ? "spatial snapshot must not carry legacy wind or OU" : dec.error);
			}
			if (!weather_snapshot_spatial(dec, spatial, spatial_model)) {
				return failure(dec.error);
			}
			weather.vertical_atmosphere = vertical;
			weather.field_elevation_m = atmosphere[0];
			weather.uniform_density = atmosphere[1];
			weather.uniform_charge = atmosphere[2];
		}
		weather_ = weather;
		spatial_model_ = std::move(spatial_model);
		spatial_ = spatial_kind;
		ready_ = true;
		out["ok"] = true;
		out["error"] = "";
		return out;
	}

	std::array<R, 3> wind(const R *position_ned, R stage_time, const std::vector<R> &aux,
			int turbulence_index, R dt) const {
		if (!ready_) {
			return weather_invalid_wind();
		}
		return spatial_ ? spatial_weather_wind(spatial_model_, position_ned, stage_time) :
				weather_wind(weather_, position_ned, stage_time, aux, turbulence_index, dt);
	}

	WeatherAir air(R down_m) const { return ready_ ? weather_air(weather_, down_m) : WeatherAir(); }

	godot::PackedFloat64Array weather_component(const godot::PackedFloat64Array &position_ned, double stage_time,
			const godot::PackedFloat64Array &aux, int64_t turbulence_index, double dt) const {
		std::array<R, 3> result = weather_invalid_wind();
		if (position_ned.size() == 3) {
			const R position[3] = {position_ned[0], position_ned[1], position_ned[2]};
			std::vector<R> copied_aux;
			copied_aux.reserve(static_cast<std::size_t>(aux.size()));
			for (int64_t i = 0; i < aux.size(); ++i) copied_aux.push_back(aux[i]);
			const int index = turbulence_index >= std::numeric_limits<int>::min() &&
					turbulence_index <= std::numeric_limits<int>::max() ? static_cast<int>(turbulence_index) : -1;
			result = wind(position, stage_time, copied_aux, index, dt);
		}
		godot::PackedFloat64Array out;
		out.resize(3);
		for (int i = 0; i < 3; ++i) out[i] = result[i].v;
		return out;
	}

	godot::PackedFloat64Array air_component(double down_m) const {
		const WeatherAir value = air(down_m);
		godot::PackedFloat64Array out;
		out.resize(2);
		out[0] = value.density.v;
		out[1] = value.engine_charge_ratio.v;
		return out;
	}

private:
	static godot::Dictionary failure(const std::string &reason) {
		godot::Dictionary out;
		out["ok"] = false;
		out["error"] = godot::String(reason.c_str());
		return out;
	}
};

} // namespace nk
