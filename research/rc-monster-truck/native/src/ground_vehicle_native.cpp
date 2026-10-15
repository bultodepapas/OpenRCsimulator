// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenRCsimulator contributors

#include "ground_vehicle_kernel.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <array>
#include <cstdint>
#include <limits>
#include <string>
#include <vector>

namespace {

using openrc::ground_vehicle::Controls;
using openrc::ground_vehicle::EvalResult;
using openrc::ground_vehicle::Model;
using openrc::ground_vehicle::Surface;
using openrc::ground_vehicle::Vec3;

constexpr const char *kBackendVersion = "openrc-ground-vehicle-native-evaluate-v3";
constexpr const char *kSolverVersion = "openrc-ground-vehicle-dynamics-rk4-v5";
constexpr int64_t kAbiVersion = 1;
constexpr int64_t kStateSize = 31;
constexpr int64_t kMaximumHullProbes = 64;

godot::Variant lookup(const godot::Dictionary &dictionary, const char *key) {
	return dictionary.get(godot::StringName(key), godot::Variant());
}

bool read_number(const godot::Dictionary &dictionary, const char *key, double &out) {
	const godot::Variant value = lookup(dictionary, key);
	if (value.get_type() != godot::Variant::FLOAT && value.get_type() != godot::Variant::INT) return false;
	out = static_cast<double>(value);
	return std::isfinite(out);
}

bool read_bool(const godot::Dictionary &dictionary, const char *key, bool &out) {
	const godot::Variant value = lookup(dictionary, key);
	if (value.get_type() != godot::Variant::BOOL) return false;
	out = static_cast<bool>(value);
	return true;
}

bool matches_text(const godot::Dictionary &dictionary, const char *key, const char *expected) {
	const godot::Variant value = lookup(dictionary, key);
	return value.get_type() == godot::Variant::STRING && static_cast<godot::String>(value) == expected;
}

bool matches_number(const godot::Dictionary &dictionary, const char *key, int64_t expected) {
	const godot::Variant value = lookup(dictionary, key);
	if (value.get_type() != godot::Variant::FLOAT && value.get_type() != godot::Variant::INT) return false;
	return static_cast<double>(value) == static_cast<double>(expected);
}

bool is_sha256(const godot::Variant &value) {
	if (value.get_type() != godot::Variant::STRING) return false;
	const godot::CharString text = static_cast<godot::String>(value).utf8();
	if (text.length() != 64) return false;
	for (int64_t i = 0; i < text.length(); ++i) {
		const char c = text[i];
		if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
	}
	return true;
}

bool read_float64_array(const godot::Dictionary &dictionary, const char *key,
		godot::PackedFloat64Array &out, std::string &error) {
	const godot::Variant value = lookup(dictionary, key);
	if (value.get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) {
		error = std::string("Model field must be PackedFloat64Array: ") + key;
		return false;
	}
	out = static_cast<godot::PackedFloat64Array>(value);
	for (int64_t i = 0; i < out.size(); ++i) {
		if (!std::isfinite(out[i])) {
			error = std::string("Model array contains a non-finite value: ") + key;
			return false;
		}
	}
	return true;
}

bool read_model(const godot::Dictionary &dictionary, Model &model, std::string &error) {
#define READ_MODEL_SCALAR(field) \
	if (!read_number(dictionary, #field, model.field)) { \
		error = std::string("Missing or invalid model scalar: ") + #field; return false; \
	}
	READ_MODEL_SCALAR(sprung_mass_kg)
	READ_MODEL_SCALAR(unsprung_mass_kg)
	READ_MODEL_SCALAR(wheel_spin_inertia_kg_m2)
	READ_MODEL_SCALAR(gravity_m_per_s2)
	READ_MODEL_SCALAR(arm_inner_offset_m)
	READ_MODEL_SCALAR(arm_length_m)
	READ_MODEL_SCALAR(cg_height_above_chassis_datum_m)
	READ_MODEL_SCALAR(wheel_center_rest_below_chassis_datum_m)
	READ_MODEL_SCALAR(tire_radius_m)
	READ_MODEL_SCALAR(suspension_stiffness_n_per_m)
	READ_MODEL_SCALAR(suspension_damping_n_s_per_m)
	READ_MODEL_SCALAR(tire_stiffness_n_per_m)
	READ_MODEL_SCALAR(tire_damping_n_s_per_m)
	READ_MODEL_SCALAR(tire_slip_relaxation_s)
	READ_MODEL_SCALAR(travel_droop_m)
	READ_MODEL_SCALAR(travel_bump_m)
	READ_MODEL_SCALAR(bump_stop_stiffness_n_per_m)
	READ_MODEL_SCALAR(bump_stop_damping_n_s_per_m)
	READ_MODEL_SCALAR(droop_stop_stiffness_n_per_m)
	READ_MODEL_SCALAR(droop_stop_damping_n_s_per_m)
	READ_MODEL_SCALAR(drive_torque_per_wheel_nm)
	READ_MODEL_SCALAR(brake_torque_per_wheel_nm)
	if (dictionary.has("brake_front_fraction")) {
		READ_MODEL_SCALAR(brake_front_fraction)
	}
	READ_MODEL_SCALAR(reverse_torque_fraction)
	READ_MODEL_SCALAR(drive_torque_fade_rad_s)
	READ_MODEL_SCALAR(rolling_resistance_coefficient)
	READ_MODEL_SCALAR(tire_friction_scale)
	READ_MODEL_SCALAR(max_steer_angle_rad)
	READ_MODEL_SCALAR(steer_servo_natural_frequency_rad_s)
	READ_MODEL_SCALAR(steer_servo_damping_ratio)
	READ_MODEL_SCALAR(hull_contact_stiffness_n_per_m)
	READ_MODEL_SCALAR(hull_contact_damping_n_s_per_m)
	READ_MODEL_SCALAR(hull_contact_friction_scale)
#undef READ_MODEL_SCALAR

	godot::PackedFloat64Array packed;
	if (!read_float64_array(dictionary, "sprung_inertia_kg_m2", packed, error) || packed.size() != 6) {
		if (error.empty()) error = "sprung_inertia_kg_m2 must contain 6 values";
		return false;
	}
	for (int64_t i = 0; i < 6; ++i) model.sprung_inertia_kg_m2[static_cast<std::size_t>(i)] = packed[i];
	if (!read_float64_array(dictionary, "corner_x_m", packed, error) || packed.size() != 4) {
		if (error.empty()) error = "corner_x_m must contain 4 values";
		return false;
	}
	for (int64_t i = 0; i < 4; ++i) model.corner_x_m[static_cast<std::size_t>(i)] = packed[i];
	if (!read_float64_array(dictionary, "corner_y_m", packed, error) || packed.size() != 4) {
		if (error.empty()) error = "corner_y_m must contain 4 values";
		return false;
	}
	for (int64_t i = 0; i < 4; ++i) model.corner_y_m[static_cast<std::size_t>(i)] = packed[i];
	if (!read_float64_array(dictionary, "hull_probe_centers_frd_m", packed, error)) return false;
	if (packed.size() == 0 || packed.size() % 3 != 0 || packed.size() / 3 > kMaximumHullProbes) {
		error = "hull_probe_centers_frd_m must contain 1 to 64 triplets";
		return false;
	}
	model.hull_probe_centers_frd_m.reserve(static_cast<std::size_t>(packed.size() / 3));
	for (int64_t i = 0; i < packed.size(); i += 3) {
		model.hull_probe_centers_frd_m.push_back({packed[i], packed[i + 1], packed[i + 2]});
	}
	if (!read_float64_array(dictionary, "hull_probe_radii_m", packed, error)) return false;
	if (packed.size() != static_cast<int64_t>(model.hull_probe_centers_frd_m.size())) {
		error = "hull_probe_radii_m count must match the hull centers";
		return false;
	}
	model.hull_probe_radii_m.reserve(static_cast<std::size_t>(packed.size()));
	for (int64_t i = 0; i < packed.size(); ++i) model.hull_probe_radii_m.push_back(packed[i]);
	return openrc::ground_vehicle::valid_model(model, error);
}

bool read_controls(const godot::Dictionary &dictionary, Controls &controls,
		openrc::ground_vehicle::Vec14 &external_generalized_force,
		bool &has_external_generalized_force, std::string &error) {
	if (!read_number(dictionary, "throttle", controls.throttle) ||
			!read_number(dictionary, "steering", controls.steering) ||
			!read_number(dictionary, "brake", controls.brake) ||
			!read_bool(dictionary, "reverse", controls.reverse)) {
		error = "Controls must provide finite throttle, steering, brake, and bool reverse";
		return false;
	}
	has_external_generalized_force = dictionary.has("external_generalized_force");
	if (has_external_generalized_force) {
		const godot::Variant value = lookup(dictionary, "external_generalized_force");
		if (value.get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) {
			error = "external_generalized_force must be a PackedFloat64Array";
			return false;
		}
		const godot::PackedFloat64Array packed = static_cast<godot::PackedFloat64Array>(value);
		if (packed.size() != static_cast<int64_t>(openrc::ground_vehicle::kGeneralizedSize)) {
			error = "external_generalized_force must contain exactly 14 float64 values";
			return false;
		}
		for (int64_t i = 0; i < packed.size(); ++i) {
			if (!std::isfinite(packed[i])) {
				error = "external_generalized_force contains a non-finite value";
				return false;
			}
			external_generalized_force[static_cast<std::size_t>(i)] = packed[i];
		}
	}
	return openrc::ground_vehicle::valid_controls(controls, error);
}

godot::Dictionary failure(const std::string &message) {
	godot::Dictionary result;
	result["ok"] = false;
	result["error"] = message.c_str();
	return result;
}

template <std::size_t N>
godot::PackedFloat64Array packed_array(const std::array<double, N> &source) {
	godot::PackedFloat64Array result;
	result.resize(static_cast<int64_t>(N));
	for (std::size_t i = 0; i < N; ++i) result[static_cast<int64_t>(i)] = source[i];
	return result;
}

godot::Dictionary to_dictionary(const EvalResult &value) {
	godot::Dictionary result;
	result["ok"] = value.ok;
	result["error"] = value.error.c_str();
	if (!value.ok) return result;
	result["generalized_acceleration"] = packed_array(value.generalized_acceleration);
	result["steering_acceleration_rad_per_s2"] = value.steering_acceleration_rad_per_s2;
	result["suspension_force_n"] = packed_array(value.suspension_force_n);
	result["wheel_load_n"] = packed_array(value.wheel_load_n);
	result["wheel_longitudinal_force_n"] = packed_array(value.wheel_longitudinal_force_n);
	result["wheel_lateral_force_n"] = packed_array(value.wheel_lateral_force_n);
	result["wheel_brake_torque_n_m"] = packed_array(value.wheel_brake_torque_n_m);
	result["wheel_slip_ratio"] = packed_array(value.wheel_slip_ratio);
	result["wheel_slip_angle_rad"] = packed_array(value.wheel_slip_angle_rad);
	result["wheel_slip_speed_m_per_s"] = packed_array(value.wheel_slip_speed_m_per_s);
	godot::PackedByteArray wheel_contact;
	wheel_contact.resize(4);
	for (int64_t i = 0; i < 4; ++i) wheel_contact.set(i, value.wheel_in_contact[static_cast<std::size_t>(i)] ? 1 : 0);
	result["wheel_in_contact"] = wheel_contact;
	godot::PackedByteArray hull_contact;
	hull_contact.resize(static_cast<int64_t>(value.hull_in_contact.size()));
	for (std::size_t i = 0; i < value.hull_in_contact.size(); ++i) hull_contact.set(static_cast<int64_t>(i), value.hull_in_contact[i] ? 1 : 0);
	result["hull_in_contact"] = hull_contact;
	result["airborne"] = value.airborne;
	result["friction_sweeps_used"] = static_cast<int64_t>(value.friction_sweeps_used);
	result["energy_j"] = value.energy_j;
	return result;
}

bool parse_state(const godot::PackedFloat64Array &packed, std::array<double, kStateSize> &state, std::string &error) {
	if (packed.size() != kStateSize) {
		error = "State must contain exactly 31 float64 values";
		return false;
	}
	for (int64_t i = 0; i < kStateSize; ++i) {
		state[static_cast<std::size_t>(i)] = packed[i];
		if (!std::isfinite(packed[i])) {
			error = "State contains a non-finite value";
			return false;
		}
	}
	const auto q = openrc::ground_vehicle::quaternion(state);
	const double q_length = std::sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
	if (!std::isfinite(q_length) || q_length <= 1.0e-10) {
		error = "Invalid vehicle attitude";
		return false;
	}
	return true;
}

bool read_road_batch(const godot::Callable &road_batch, const std::vector<Vec3> &query_points,
		std::vector<Surface> &surfaces, std::string &error) {
	if (!road_batch.is_valid()) {
		error = "Road batch Callable is invalid";
		return false;
	}
	godot::PackedFloat64Array coords;
	coords.resize(static_cast<int64_t>(query_points.size() * 2));
	for (std::size_t i = 0; i < query_points.size(); ++i) {
		if (!std::isfinite(query_points[i][0]) || !std::isfinite(query_points[i][1])) {
			error = "Road query contains a non-finite coordinate";
			return false;
		}
		coords[static_cast<int64_t>(i * 2)] = query_points[i][0];
		coords[static_cast<int64_t>(i * 2 + 1)] = query_points[i][1];
	}
	godot::Array args;
	args.push_back(coords);
	const godot::Variant response_variant = road_batch.callv(args);
	if (response_variant.get_type() != godot::Variant::DICTIONARY) {
		error = "Road batch Callable must return a Dictionary";
		return false;
	}
	const godot::Dictionary response = static_cast<godot::Dictionary>(response_variant);
	const godot::Variant ok_variant = lookup(response, "ok");
	if (ok_variant.get_type() != godot::Variant::BOOL || !static_cast<bool>(ok_variant)) {
		const godot::Variant error_variant = lookup(response, "error");
		error = error_variant.get_type() == godot::Variant::STRING
			? static_cast<godot::String>(error_variant).utf8().get_data()
			: "Road batch Callable rejected the query";
		return false;
	}
	const godot::Variant samples_variant = lookup(response, "samples");
	if (samples_variant.get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) {
		error = "Road batch samples must be PackedFloat64Array";
		return false;
	}
	const godot::PackedFloat64Array samples = static_cast<godot::PackedFloat64Array>(samples_variant);
	if (samples.size() != static_cast<int64_t>(query_points.size() * 6)) {
		error = "Road batch samples must contain six float64 values per query";
		return false;
	}
	surfaces.reserve(query_points.size());
	for (std::size_t i = 0; i < query_points.size(); ++i) {
		const int64_t offset = static_cast<int64_t>(i * 6);
		Surface sample;
		sample.height_m = samples[offset];
		sample.normal_ned = {samples[offset + 1], samples[offset + 2], samples[offset + 3]};
		sample.mu = samples[offset + 4];
		sample.rolling = samples[offset + 5];
		surfaces.push_back(sample);
	}
	return true;
}

constexpr double kLakeSampleEpsilon = 0.025;
constexpr double kLakeEdgeEpsilon = 0.00000001;
constexpr double kLakeContactEpsilon = 0.0000001;

struct LakeTerrainInput {
	godot::PackedFloat64Array shoreline;
	godot::PackedFloat64Array bank;
	godot::Array bed_profile;
	double water_level_down_m = 0.0;
	double bank_north_min = 0.0;
	double bank_north_max = 0.0;
	double bank_east_min = 0.0;
	double bank_east_max = 0.0;
};

struct LakeTerrainPoint {
	double shore_signed = 0.0;
	double bank_signed = 0.0;
	double blend = 0.0;
	double depth = 0.0;
	double ground_down = 0.0;
	bool inside_water = false;
	bool inside_bank = false;
};

bool nonempty_string(const godot::Dictionary &dictionary, const char *key) {
	const godot::Variant value = lookup(dictionary, key);
	return value.get_type() == godot::Variant::STRING &&
		!static_cast<godot::String>(value).is_empty();
}

bool read_lake_terrain_input(const godot::Dictionary &lake, LakeTerrainInput &input) {
	if (!matches_text(lake, "format", "openrc-lake v1") ||
			!nonempty_string(lake, "id") || !nonempty_string(lake, "identity") ||
			!read_number(lake, "water_level_down_m", input.water_level_down_m) ||
			input.water_level_down_m < 0.05 || input.water_level_down_m > 2.0) {
		return false;
	}
	const godot::Variant shoreline_value = lookup(lake, "shoreline_ne_m");
	const godot::Variant bank_value = lookup(lake, "bank_ne_m");
	const godot::Variant profile_value = lookup(lake, "bed_profile");
	const godot::Variant bounds_value = lookup(lake, "wave_bounds");
	const godot::Variant waves_value = lookup(lake, "waves");
	if (shoreline_value.get_type() != godot::Variant::PACKED_FLOAT64_ARRAY ||
			bank_value.get_type() != godot::Variant::PACKED_FLOAT64_ARRAY ||
			profile_value.get_type() != godot::Variant::ARRAY ||
			bounds_value.get_type() != godot::Variant::DICTIONARY ||
			waves_value.get_type() != godot::Variant::ARRAY) {
		return false;
	}
	input.shoreline = static_cast<godot::PackedFloat64Array>(shoreline_value);
	input.bank = static_cast<godot::PackedFloat64Array>(bank_value);
	input.bed_profile = static_cast<godot::Array>(profile_value);
	const int64_t max_polygon_values = 128;
	if (input.shoreline.size() < 16 || input.shoreline.size() > max_polygon_values ||
			input.shoreline.size() % 2 != 0 || input.bank.size() < 16 ||
			input.bank.size() > max_polygon_values || input.bank.size() % 2 != 0 ||
			input.bed_profile.size() < 2 || input.bed_profile.size() > 8) {
		return false;
	}
	for (int64_t index = 0; index < input.shoreline.size(); ++index) {
		if (!std::isfinite(input.shoreline[index])) return false;
	}
	input.bank_north_min = std::numeric_limits<double>::infinity();
	input.bank_north_max = -std::numeric_limits<double>::infinity();
	input.bank_east_min = std::numeric_limits<double>::infinity();
	input.bank_east_max = -std::numeric_limits<double>::infinity();
	for (int64_t index = 0; index < input.bank.size(); index += 2) {
		const double north = input.bank[index];
		const double east = input.bank[index + 1];
		if (!std::isfinite(north) || !std::isfinite(east)) return false;
		input.bank_north_min = std::min(input.bank_north_min, north);
		input.bank_north_max = std::max(input.bank_north_max, north);
		input.bank_east_min = std::min(input.bank_east_min, east);
		input.bank_east_max = std::max(input.bank_east_max, east);
	}
	double previous_inset = 0.0;
	double previous_depth = 0.0;
	for (int64_t index = 0; index < input.bed_profile.size(); ++index) {
		const godot::Variant row_value = input.bed_profile[index];
		if (row_value.get_type() != godot::Variant::DICTIONARY) return false;
		const godot::Dictionary row = static_cast<godot::Dictionary>(row_value);
		double inset = 0.0;
		double depth = 0.0;
		if (!read_number(row, "inset_m", inset) || !read_number(row, "depth_m", depth)) return false;
		if (index == 0) {
			if (std::fabs(inset) > kLakeContactEpsilon || std::fabs(depth) > kLakeContactEpsilon) return false;
		} else if (inset <= previous_inset || depth <= previous_depth) {
			return false;
		}
		previous_inset = inset;
		previous_depth = depth;
	}
	const godot::Dictionary bounds = static_cast<godot::Dictionary>(bounds_value);
	double max_amplitude = 0.0;
	double min_wavelength = 0.0;
	double max_wavelength = 0.0;
	double min_period = 0.0;
	double max_period = 0.0;
	double shore_fade = 0.0;
	if (!read_number(bounds, "max_amplitude_m", max_amplitude) ||
			!read_number(bounds, "min_wavelength_m", min_wavelength) ||
			!read_number(bounds, "max_wavelength_m", max_wavelength) ||
			!read_number(bounds, "min_period_s", min_period) ||
			!read_number(bounds, "max_period_s", max_period) ||
			!read_number(bounds, "shore_fade_m", shore_fade) ||
			max_amplitude < 0.0 || min_wavelength <= 0.0 || max_wavelength < min_wavelength ||
			min_period <= 0.0 || max_period < min_period || shore_fade <= 0.0) {
		return false;
	}
	const godot::Array waves = static_cast<godot::Array>(waves_value);
	if (waves.size() > 2) return false;
	for (int64_t index = 0; index < waves.size(); ++index) {
		const godot::Variant wave_value = waves[index];
		if (wave_value.get_type() != godot::Variant::DICTIONARY) return false;
		const godot::Dictionary wave = static_cast<godot::Dictionary>(wave_value);
		for (const char *key : {"amplitude_m", "wavelength_m", "period_s", "heading_rad", "phase_rad"}) {
		double value = 0.0;
			if (!read_number(wave, key, value)) return false;
		}
	}
	return true;
}

double lake_distance_sq(double north, double east, double other_north, double other_east) {
	const double delta_north = north - other_north;
	const double delta_east = east - other_east;
	return delta_north * delta_north + delta_east * delta_east;
}

double lake_point_segment_distance_sq(double north, double east,
		double north_a, double east_a, double north_b, double east_b) {
	const double delta_north = north_b - north_a;
	const double delta_east = east_b - east_a;
	const double length_sq = delta_north * delta_north + delta_east * delta_east;
	if (length_sq <= 0.0) return lake_distance_sq(north, east, north_a, east_a);
	const double t = openrc::ground_vehicle::clampf(
		((north - north_a) * delta_north + (east - east_a) * delta_east) / length_sq, 0.0, 1.0);
	return lake_distance_sq(north, east,
		north_a + t * delta_north, east_a + t * delta_east);
}

double lake_polygon_state(const godot::PackedFloat64Array &polygon, double north, double east) {
	bool inside = false;
	bool on_boundary = false;
	double minimum_sq = std::numeric_limits<double>::infinity();
	const int64_t count = polygon.size() / 2;
	for (int64_t index = 0; index < count; ++index) {
		const int64_t next = (index + 1) % count;
		const double north_a = polygon[index * 2];
		const double east_a = polygon[index * 2 + 1];
		const double north_b = polygon[next * 2];
		const double east_b = polygon[next * 2 + 1];
		const double distance_sq = lake_point_segment_distance_sq(
			north, east, north_a, east_a, north_b, east_b);
		minimum_sq = std::min(minimum_sq, distance_sq);
		if (distance_sq <= kLakeEdgeEpsilon * kLakeEdgeEpsilon) on_boundary = true;
		if ((north_a > north) != (north_b > north)) {
			const double crossing_east = (east_b - east_a) * (north - north_a) / (north_b - north_a) + east_a;
			if (east < crossing_east) inside = !inside;
		}
	}
	const double distance = std::sqrt(minimum_sq);
	return on_boundary || inside ? distance : -distance;
}

double lake_smoothstep(double value) {
	const double t = openrc::ground_vehicle::clampf(value, 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

double lake_bed_depth(const godot::Array &profile, double inset) {
	for (int64_t index = 0; index < profile.size() - 1; ++index) {
		const godot::Dictionary first = static_cast<godot::Dictionary>(profile[index]);
		const godot::Dictionary second = static_cast<godot::Dictionary>(profile[index + 1]);
		const double first_inset = static_cast<double>(lookup(first, "inset_m"));
		const double second_inset = static_cast<double>(lookup(second, "inset_m"));
		if (inset <= second_inset) {
			const double t = openrc::ground_vehicle::clampf(
				(inset - first_inset) / (second_inset - first_inset), 0.0, 1.0);
			const double first_depth = static_cast<double>(lookup(first, "depth_m"));
			const double second_depth = static_cast<double>(lookup(second, "depth_m"));
			return first_depth + (second_depth - first_depth) * lake_smoothstep(t);
		}
	}
	const godot::Dictionary last = static_cast<godot::Dictionary>(profile[profile.size() - 1]);
	return static_cast<double>(lookup(last, "depth_m"));
}

LakeTerrainPoint lake_terrain_point_state(const LakeTerrainInput &lake, double north, double east) {
	LakeTerrainPoint point;
	point.shore_signed = lake_polygon_state(lake.shoreline, north, east);
	point.bank_signed = lake_polygon_state(lake.bank, north, east);
	const double shore_distance = std::fabs(point.shore_signed);
	const double bank_distance = std::fabs(point.bank_signed);
	const bool inside_shoreline = point.shore_signed >= 0.0;
	point.inside_bank = point.bank_signed >= 0.0;
	point.inside_water = point.inside_bank && inside_shoreline;
	point.blend = 1.0;
	if (!inside_shoreline) {
		if (!point.inside_bank) {
			point.blend = 0.0;
		} else {
			const double span = shore_distance + bank_distance;
			point.blend = span <= 0.0 ? 1.0 : lake_smoothstep(bank_distance / span);
		}
	}
	point.depth = inside_shoreline ? lake_bed_depth(lake.bed_profile, shore_distance) : 0.0;
	point.ground_down = inside_shoreline
		? lake.water_level_down_m + point.depth
		: lake.water_level_down_m * point.blend;
	return point;
}

godot::PackedFloat64Array compose_lake_terrain(
		const godot::Dictionary &lake_dictionary, double north, double east,
		const godot::PackedFloat64Array &base) {
	if (!std::isfinite(north) || !std::isfinite(east) || base.size() != 3) return {};
	for (int64_t index = 0; index < base.size(); ++index) {
		if (!std::isfinite(base[index])) return {};
	}
	LakeTerrainInput lake;
	if (!read_lake_terrain_input(lake_dictionary, lake)) return {};
	const double shore_signed = lake_polygon_state(lake.shoreline, north, east);
	if (!std::isfinite(shore_signed)) return {};
	const bool outside_bank_aabb = north < lake.bank_north_min - kLakeSampleEpsilon ||
		north > lake.bank_north_max + kLakeSampleEpsilon ||
		east < lake.bank_east_min - kLakeSampleEpsilon ||
		east > lake.bank_east_max + kLakeSampleEpsilon;
	if (outside_bank_aabb) {
		return {base[0], base[1], base[2], shore_signed};
	}
	LakeTerrainPoint center = lake_terrain_point_state(lake, north, east);
	if (!center.inside_bank) return {base[0], base[1], base[2], shore_signed};
	const LakeTerrainPoint north_plus = lake_terrain_point_state(lake, north + kLakeSampleEpsilon, east);
	const LakeTerrainPoint north_minus = lake_terrain_point_state(lake, north - kLakeSampleEpsilon, east);
	const LakeTerrainPoint east_plus = lake_terrain_point_state(lake, north, east + kLakeSampleEpsilon);
	const LakeTerrainPoint east_minus = lake_terrain_point_state(lake, north, east - kLakeSampleEpsilon);
	const double blend_north = (north_plus.blend - north_minus.blend) / (2.0 * kLakeSampleEpsilon);
	const double blend_east = (east_plus.blend - east_minus.blend) / (2.0 * kLakeSampleEpsilon);
	const double depth_north = (north_plus.depth - north_minus.depth) / (2.0 * kLakeSampleEpsilon);
	const double depth_east = (east_plus.depth - east_minus.depth) / (2.0 * kLakeSampleEpsilon);
	const double height_north = (north_plus.ground_down - north_minus.ground_down) / (2.0 * kLakeSampleEpsilon);
	const double height_east = (east_plus.ground_down - east_minus.ground_down) / (2.0 * kLakeSampleEpsilon);
	const double height_up = base[0] * (1.0 - center.blend) - center.ground_down;
	const double slope_north = base[1] * (1.0 - center.blend) - base[0] * blend_north - height_north;
	const double slope_east = base[2] * (1.0 - center.blend) - base[0] * blend_east - height_east;
	if (!std::isfinite(height_up) || !std::isfinite(slope_north) ||
			!std::isfinite(slope_east) || !std::isfinite(shore_signed)) return {};
	return {height_up, slope_north, slope_east, shore_signed};
}

} // namespace

class OpenRCGroundVehicleNative final : public godot::RefCounted {
	GDCLASS(OpenRCGroundVehicleNative, godot::RefCounted)

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("abi_info"), &OpenRCGroundVehicleNative::abi_info);
		godot::ClassDB::bind_method(godot::D_METHOD("backend_identity"), &OpenRCGroundVehicleNative::backend_identity);
		godot::ClassDB::bind_method(godot::D_METHOD("echo_float64", "values"), &OpenRCGroundVehicleNative::echo_float64);
		godot::ClassDB::bind_method(godot::D_METHOD("sample_lake_terrain", "lake", "north", "east", "base"), &OpenRCGroundVehicleNative::sample_lake_terrain);
		godot::ClassDB::bind_method(godot::D_METHOD("evaluate", "state", "model", "controls", "road_batch", "calculate_energy", "adaptive_friction"), &OpenRCGroundVehicleNative::evaluate);
	}

public:
	godot::Dictionary abi_info() const {
		godot::Dictionary result;
		result["float_bytes"] = static_cast<int64_t>(sizeof(double));
		result["ieee754"] = std::numeric_limits<double>::is_iec559;
		result["solver"] = kBackendVersion;
		result["abi_version"] = kAbiVersion;
		result["solver_version"] = kSolverVersion;
		return result;
	}

	godot::Dictionary backend_identity() const {
		godot::Dictionary result;
		result["backend"] = "native";
		result["backend_version"] = kBackendVersion;
		result["abi_version"] = kAbiVersion;
		result["solver_version"] = kSolverVersion;
		result["source_sha256"] = "";
		result["toolchain_sha256"] = "";
		result["binary_sha256"] = "";
		godot::Ref<godot::FileAccess> receipt_file = godot::FileAccess::open(
				"res://native/ground_vehicle/build-receipt.json", godot::FileAccess::READ);
		if (receipt_file.is_null() || !receipt_file->is_open()) return result;
		const godot::Variant parsed = godot::JSON::parse_string(receipt_file->get_as_text());
		if (parsed.get_type() != godot::Variant::DICTIONARY) return result;
		const godot::Dictionary receipt = static_cast<godot::Dictionary>(parsed);
		if (!matches_text(receipt, "backend", "native") || !matches_text(receipt, "backend_version", kBackendVersion) ||
				!matches_number(receipt, "abi_version", kAbiVersion) || !matches_text(receipt, "solver_version", kSolverVersion)) return result;
		const godot::String os_name = godot::OS::get_singleton()->get_name();
		const char *platform_key = os_name == "Windows" ? "windows" : (os_name == "Linux" ? "linux" : "");
		if (platform_key[0] == '\0') return result;
		const godot::Variant platforms_variant = lookup(receipt, "platforms");
		if (platforms_variant.get_type() != godot::Variant::DICTIONARY) return result;
		const godot::Variant platform_variant = lookup(static_cast<godot::Dictionary>(platforms_variant), platform_key);
		if (platform_variant.get_type() != godot::Variant::DICTIONARY) return result;
		const godot::Dictionary platform = static_cast<godot::Dictionary>(platform_variant);
		if (!matches_text(platform, "backend", "native") ||
				!matches_text(platform, "backend_version", kBackendVersion) ||
				!matches_number(platform, "abi_version", kAbiVersion) ||
				!matches_text(platform, "solver_version", kSolverVersion)) return result;
		for (const char *key : {"source_sha256", "toolchain_sha256", "binary_sha256"}) {
			const godot::Variant value = lookup(platform, key);
			if (is_sha256(value)) result[key] = value;
		}
		return result;
	}

	godot::PackedFloat64Array echo_float64(const godot::PackedFloat64Array &values) const {
		return values;
	}

	godot::PackedFloat64Array sample_lake_terrain(const godot::Dictionary &lake,
			double north, double east, const godot::PackedFloat64Array &base) const {
		return compose_lake_terrain(lake, north, east, base);
	}

	godot::Dictionary evaluate(const godot::Variant &state_value,
			const godot::Variant &model_value, const godot::Variant &controls_value,
			const godot::Variant &road_value, const godot::Variant &energy_value,
			const godot::Variant &adaptive_value) const {
	try {
		if (state_value.get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) {
			return failure("State must be a PackedFloat64Array");
		}
		if (model_value.get_type() != godot::Variant::DICTIONARY || controls_value.get_type() != godot::Variant::DICTIONARY) {
			return failure("Model and controls must be Dictionaries");
		}
		if (road_value.get_type() != godot::Variant::CALLABLE) return failure("Road batch must be a Callable");
		if (energy_value.get_type() != godot::Variant::BOOL || adaptive_value.get_type() != godot::Variant::BOOL) {
			return failure("Evaluation flags must be bool values");
		}
		const godot::PackedFloat64Array packed_state = static_cast<godot::PackedFloat64Array>(state_value);
		const godot::Dictionary model_dictionary = static_cast<godot::Dictionary>(model_value);
		const godot::Dictionary controls_dictionary = static_cast<godot::Dictionary>(controls_value);
		const godot::Callable road_batch = static_cast<godot::Callable>(road_value);
		const bool calculate_energy = static_cast<bool>(energy_value);
		const bool adaptive_friction = static_cast<bool>(adaptive_value);
		Model model;
		Controls controls;
		openrc::ground_vehicle::Vec14 external_generalized_force{};
		bool has_external_generalized_force = false;
		std::array<double, openrc::ground_vehicle::kStateSize> state{};
		std::string error;
		if (!read_model(model_dictionary, model, error)) return failure(error);
		if (!read_controls(controls_dictionary, controls, external_generalized_force,
				has_external_generalized_force, error)) return failure(error);
		if (!parse_state(packed_state, state, error)) return failure(error);

		const double servo_target = controls.steering * model.max_steer_angle_rad;
		const double servo_acceleration = model.steer_servo_natural_frequency_rad_s * model.steer_servo_natural_frequency_rad_s
			* (servo_target - state[29]) - 2.0 * model.steer_servo_damping_ratio
			* model.steer_servo_natural_frequency_rad_s * state[30];
		if (!std::isfinite(servo_acceleration)) return failure("Steering servo acceleration is non-finite");
		openrc::ground_vehicle::CornerGeometry geometry;
		if (!openrc::ground_vehicle::corner_geometry(state, model, state[29], state[30], servo_acceleration, geometry, error)) {
			return failure(error);
		}
		const std::vector<Vec3> query_points = openrc::ground_vehicle::query_positions(state, model, geometry);
		std::vector<Surface> surfaces;
		if (!read_road_batch(road_batch, query_points, surfaces, error)) return failure(error);
		EvalResult result;
		const openrc::ground_vehicle::Vec14 *external_force = has_external_generalized_force
			? &external_generalized_force : nullptr;
		if (!openrc::ground_vehicle::evaluate(state, model, controls, surfaces,
				calculate_energy, adaptive_friction, external_force, result)) {
			return failure(result.error);
		}
		return to_dictionary(result);
	} catch (const std::exception &exception) {
		return failure(std::string("Native evaluation failed safely: ") + exception.what());
	} catch (...) {
		return failure("Native evaluation failed safely with an unknown error");
	}
	}
};

void initialize_openrc_ground_vehicle(godot::ModuleInitializationLevel level) {
	if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		godot::ClassDB::register_class<OpenRCGroundVehicleNative>();
	}
}

void uninitialize_openrc_ground_vehicle(godot::ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT openrc_ground_vehicle_library_init(
		GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	godot::GDExtensionBinding::InitObject init_object(get_proc_address, library, initialization);
	init_object.register_initializer(initialize_openrc_ground_vehicle);
	init_object.register_terminator(uninitialize_openrc_ground_vehicle);
	init_object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
