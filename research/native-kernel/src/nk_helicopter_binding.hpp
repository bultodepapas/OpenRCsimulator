// Experimental X-Cell prepared stage bridge. The Godot snapshots are decoded
// once into pure nk::R models; helicopter stage calls retain no Godot object.
// This component remains unqualified for flight admission until joint stage,
// stop-event, replay and actual Simulation/VehicleModel gates all pass.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <array>
#include <string>
#include <vector>

#include "nk_helicopter_stage.hpp"
#include "nk_weather_binding.hpp" // prepare-time dictionary/array validation utilities

namespace nk {

struct HeliField { const char *name; R *value; };

inline bool heli_decode_fields(WeatherSnapshotDecoder &dec, const godot::Dictionary &dictionary,
		std::initializer_list<HeliField> fields) {
	for (const auto &field : fields) if (!dec.number(dictionary, field.name, *field.value)) return false;
	return true;
}

inline bool heli_float_model(WeatherSnapshotDecoder &dec, const godot::Dictionary &model, const char *law,
		int expected_size, const char *where, std::initializer_list<const char *> keys) {
	if (!model.is_read_only() || model.size() != expected_size || !dec.keys(model, where, keys)) {
		return dec.fail(std::string("invalid or mutable ") + where);
	}
	godot::String identity;
	if (!dec.string(model, "law", identity) || identity != godot::String(law)) return dec.fail(std::string("unsupported ") + where + " law");
	const godot::Array names = model.keys();
	for (int64_t i = 0; i < names.size(); ++i) {
		const godot::String key = names[i];
		if (key == godot::String("law")) continue;
		const godot::Variant value = model[key];
		if (value.get_type() != godot::Variant::FLOAT || !std::isfinite(static_cast<double>(value))) {
			return dec.fail(std::string("invalid prepared numeric field in ") + where);
		}
	}
	return true;
}

inline bool heli_curve_decode(WeatherSnapshotDecoder &dec, const godot::Dictionary &mode,
		const char *channel, std::array<R, 5> &out, R minimum, R maximum) {
	if (!mode.has(channel)) return dec.fail("missing helicopter curve");
	const godot::Variant value = mode[channel];
	if (value.get_type() == godot::Variant::PACKED_FLOAT64_ARRAY) {
		const godot::PackedFloat64Array points = value;
		if (points.size() != 5) return dec.fail("invalid helicopter curve size");
		for (int i = 0; i < 5; ++i) out[i] = points[i];
	} else if (value.get_type() == godot::Variant::ARRAY) {
		const godot::Array points = value;
		if (!points.is_read_only() || points.size() != 5) return dec.fail("invalid or mutable helicopter curve");
		for (int i = 0; i < 5; ++i) {
			if (points[i].get_type() == godot::Variant::FLOAT) out[i] = static_cast<double>(points[i]);
			else if (points[i].get_type() == godot::Variant::INT) out[i] = static_cast<double>(static_cast<int64_t>(points[i]));
			else return dec.fail("nonnumeric helicopter curve");
		}
	} else return dec.fail("invalid helicopter curve type");
	for (const R point : out) if (!is_finite(point) || point < minimum || point > maximum) return dec.fail("helicopter curve out of range");
	return true;
}

inline bool heli_decode_main(WeatherSnapshotDecoder &dec, const godot::Dictionary &src, HeliMainRotorModel &m) {
	if (!heli_float_model(dec, src, "openrc-xcell-main-rotor-v1", 22, "main rotor", {"law", "rho_kg_m3",
		"rotor_radius_m", "blade_chord_m", "rotor_blade_count", "blade_lift_curve_slope_per_rad", "blade_section_cd0",
		"thrust_coefficient_max", "blade_flapping_inertia_kg_m2", "gamma_flybar", "flapback_k_mu", "omega_nominal_rad_s",
		"cyclic_longitudinal_gain_nominal_rad_per_rad", "cyclic_lateral_gain_nominal_rad_per_rad",
		"hub_spring_stiffness_nm_per_rad", "rotation_sense", "hub_x_m", "hub_y_m", "hub_z_m", "solidity",
		"lock_number", "bare_flap_time_constant_nominal_s"})) return false;
#define H_MAIN(FIELD) {#FIELD, &m.FIELD}
	if (!heli_decode_fields(dec, src, {H_MAIN(rho_kg_m3), H_MAIN(rotor_radius_m), H_MAIN(blade_lift_curve_slope_per_rad),
		H_MAIN(blade_section_cd0), H_MAIN(thrust_coefficient_max), H_MAIN(solidity), H_MAIN(gamma_flybar), H_MAIN(flapback_k_mu),
		H_MAIN(omega_nominal_rad_s), H_MAIN(cyclic_longitudinal_gain_nominal_rad_per_rad), H_MAIN(cyclic_lateral_gain_nominal_rad_per_rad),
		H_MAIN(hub_spring_stiffness_nm_per_rad), H_MAIN(rotation_sense), H_MAIN(hub_x_m), H_MAIN(hub_y_m), H_MAIN(hub_z_m)})) return false;
#undef H_MAIN
	return (m.rho_kg_m3 > 0.0 && m.rotor_radius_m > 0.0 && m.gamma_flybar > 0.0 && m.omega_nominal_rad_s > 0.0 &&
		m.blade_lift_curve_slope_per_rad > 0.0 && m.thrust_coefficient_max > 0.0 && m.solidity > 0.0 && m.solidity < 1.0 &&
		static_cast<double>(src["rotor_blade_count"]) == 2.0 && absf(m.rotation_sense) == 1.0) || dec.fail("invalid main rotor parameters");
}

inline bool heli_decode_tail(WeatherSnapshotDecoder &dec, const godot::Dictionary &src, HeliTailRotorModel &m) {
	if (!heli_float_model(dec, src, "openrc-xcell-linearized-tail-v1", 20, "tail rotor", {"law", "rho_kg_m3",
		"main_rotor_radius_m", "tail_rotor_radius_m", "blade_chord_m", "rotor_blade_count", "blade_lift_curve_slope_per_rad",
		"blade_section_cd0", "thrust_coefficient_max", "tail_to_main_speed_ratio", "hub_distance_aft_m", "hub_height_above_cg_m",
		"vertical_fin_area_m2", "trim_collective_rad", "wake_efficiency", "rotation_sense", "solidity", "blockage_factor",
		"wake_gi", "wake_gf"})) return false;
#define H_TAIL(FIELD) {#FIELD, &m.FIELD}
	if (!heli_decode_fields(dec, src, {H_TAIL(rho_kg_m3), H_TAIL(tail_rotor_radius_m), H_TAIL(blade_lift_curve_slope_per_rad),
		H_TAIL(blade_section_cd0), H_TAIL(thrust_coefficient_max), H_TAIL(tail_to_main_speed_ratio), H_TAIL(hub_distance_aft_m),
		H_TAIL(hub_height_above_cg_m), H_TAIL(trim_collective_rad), H_TAIL(wake_efficiency), H_TAIL(rotation_sense),
		H_TAIL(solidity), H_TAIL(blockage_factor), H_TAIL(wake_gi), H_TAIL(wake_gf)})) return false;
#undef H_TAIL
	return (m.rho_kg_m3 > 0.0 && m.tail_rotor_radius_m > 0.0 && m.blade_lift_curve_slope_per_rad > 0.0 &&
		m.blade_section_cd0 >= 0.0 && m.thrust_coefficient_max > 0.0 && m.tail_to_main_speed_ratio > 0.0 &&
		m.hub_distance_aft_m > 0.0 && m.hub_height_above_cg_m > 0.0 && m.trim_collective_rad > 0.0 &&
		m.trim_collective_rad <= kPi / 2.0 && m.wake_efficiency > 0.0 && m.wake_efficiency <= 1.0 &&
		absf(m.rotation_sense) == 1.0 && m.solidity > 0.0 && m.solidity < 1.0 && m.blockage_factor > 0.0 &&
		m.blockage_factor <= 1.0 && m.wake_gf > m.wake_gi && static_cast<double>(src["rotor_blade_count"]) == 2.0 &&
		static_cast<double>(src["main_rotor_radius_m"]) > 0.0 && static_cast<double>(src["blade_chord_m"]) > 0.0 &&
		static_cast<double>(src["vertical_fin_area_m2"]) >= 0.0) || dec.fail("invalid tail rotor parameters");
}

inline bool heli_decode_airframe(WeatherSnapshotDecoder &dec, const godot::Dictionary &src, HeliAirframeModel &m) {
	if (!heli_float_model(dec, src, "openrc-passive-rotorcraft-airframe-v1", 18, "airframe", {"law", "rho_kg_m3",
		"fuselage_area_x_m2", "fuselage_area_y_m2", "fuselage_area_z_m2", "fuselage_x_m", "fuselage_y_m", "fuselage_z_m",
		"vertical_fin_area_m2", "vertical_fin_lift_curve_slope_per_rad", "vertical_fin_x_m", "vertical_fin_y_m", "vertical_fin_z_m",
		"horizontal_tail_area_m2", "horizontal_tail_lift_curve_slope_per_rad", "horizontal_tail_x_m", "horizontal_tail_y_m", "horizontal_tail_z_m"})) return false;
	if (!heli_decode_fields(dec, src, {{"rho_kg_m3", &m.rho_kg_m3}, {"fuselage_area_x_m2", &m.fuselage_area[0]},
		{"fuselage_area_y_m2", &m.fuselage_area[1]}, {"fuselage_area_z_m2", &m.fuselage_area[2]},
		{"fuselage_x_m", &m.fuselage_arm[0]}, {"fuselage_y_m", &m.fuselage_arm[1]}, {"fuselage_z_m", &m.fuselage_arm[2]},
		{"vertical_fin_area_m2", &m.vertical_fin_area}, {"vertical_fin_lift_curve_slope_per_rad", &m.vertical_fin_lift_slope},
		{"vertical_fin_x_m", &m.vertical_fin_arm[0]}, {"vertical_fin_y_m", &m.vertical_fin_arm[1]}, {"vertical_fin_z_m", &m.vertical_fin_arm[2]},
		{"horizontal_tail_area_m2", &m.horizontal_tail_area}, {"horizontal_tail_lift_curve_slope_per_rad", &m.horizontal_tail_lift_slope},
		{"horizontal_tail_x_m", &m.horizontal_tail_arm[0]}, {"horizontal_tail_y_m", &m.horizontal_tail_arm[1]}, {"horizontal_tail_z_m", &m.horizontal_tail_arm[2]}})) return false;
	return (m.rho_kg_m3 > 0.0 && m.fuselage_area[0] >= 0.0 && m.fuselage_area[1] >= 0.0 && m.fuselage_area[2] >= 0.0 &&
		m.vertical_fin_area >= 0.0 && m.vertical_fin_lift_slope >= 0.0 && m.horizontal_tail_area >= 0.0 && m.horizontal_tail_lift_slope >= 0.0)
		|| dec.fail("invalid helicopter airframe parameters");
}

inline bool heli_decode_drive(WeatherSnapshotDecoder &dec, const godot::Dictionary &src, HeliDriveModel &m) {
	if (!heli_float_model(dec, src, "openrc-one-speed-drive-proxy-v1", 9, "drive", {"law", "engine_torque_max_nm",
		"engine_power_max_w", "engine_speed_ratio_to_main", "gear_efficiency", "governor_target_main_rad_s",
		"governor_gain_nm_per_rad_s", "shaft_loss_torque_nm", "shaft_viscous_loss_nm_per_rad_s"})) return false;
#define H_DRIVE(FIELD) {#FIELD, &m.FIELD}
	if (!heli_decode_fields(dec, src, {H_DRIVE(engine_torque_max_nm), H_DRIVE(engine_power_max_w), H_DRIVE(engine_speed_ratio_to_main),
		H_DRIVE(gear_efficiency), H_DRIVE(governor_target_main_rad_s), H_DRIVE(governor_gain_nm_per_rad_s),
		H_DRIVE(shaft_loss_torque_nm), H_DRIVE(shaft_viscous_loss_nm_per_rad_s)})) return false;
#undef H_DRIVE
	return (m.engine_torque_max_nm > 0.0 && m.engine_power_max_w > 0.0 && m.engine_speed_ratio_to_main > 0.0 &&
		m.gear_efficiency > 0.0 && m.gear_efficiency <= 1.0 && m.governor_target_main_rad_s > 0.0 &&
		m.governor_gain_nm_per_rad_s >= 0.0 && m.shaft_loss_torque_nm >= 0.0 && m.shaft_viscous_loss_nm_per_rad_s >= 0.0)
		|| dec.fail("invalid helicopter drive parameters");
}

inline bool heli_decode_controls(WeatherSnapshotDecoder &dec, const godot::Dictionary &src, HeliTrainerModel &m) {
	if (!src.is_read_only() || src.size() != 20 || !dec.keys(src, "electronics", {"law", "curves_by_mode", "linkage",
		"tail_collective_trim_rad", "tail_collective_min_rad", "tail_collective_max_rad", "yaw_control_sign", "yaw_deadzone",
		"yaw_max_rate_rad_s", "yaw_heading_gain_per_s", "yaw_rate_kp_rad_per_rad_s", "yaw_rate_ki_rad_per_rad",
		"yaw_integrator_limit_rad", "trainer_max_tilt_rad", "trainer_roll_attitude_gain_per_s", "trainer_pitch_attitude_gain_per_s",
		"trainer_roll_rate_limit_rad_s", "trainer_pitch_rate_limit_rad_s", "trainer_roll_cyclic_gain_rad_per_rad_s",
		"trainer_pitch_cyclic_gain_rad_per_rad_s"})) return dec.fail("invalid or mutable helicopter electronics");
	godot::String law;
	if (!dec.string(src, "law", law) || law != godot::String("openrc-four-stick-electronics-v1")) return dec.fail("unsupported helicopter electronics law");
	godot::Dictionary curves, linkage, normal, idle;
	if (!dec.dictionary(src, "curves_by_mode", curves) || !dec.dictionary(src, "linkage", linkage) ||
		!curves.is_read_only() || curves.size() != 2 || !dec.keys(curves, "curves", {"normal", "idle_up"}) ||
		!dec.dictionary(curves, "normal", normal) || !dec.dictionary(curves, "idle_up", idle) ||
		!normal.is_read_only() || !idle.is_read_only() || normal.size() != 2 || idle.size() != 2 ||
		!dec.keys(normal, "normal curve", {"pitch", "throttle"}) || !dec.keys(idle, "idle curve", {"pitch", "throttle"}) ||
		!heli_curve_decode(dec, normal, "pitch", m.normal_pitch, -1.0, 1.0) ||
		!heli_curve_decode(dec, normal, "throttle", m.normal_throttle, 0.0, 1.0) ||
		!heli_curve_decode(dec, idle, "pitch", m.idle_pitch, -1.0, 1.0) ||
		!heli_curve_decode(dec, idle, "throttle", m.idle_throttle, 0.0, 1.0)) return dec.fail("invalid prepared helicopter curves");
	if (!linkage.is_read_only() || linkage.size() != 6 || !dec.keys(linkage, "linkage", {"collective_rad_per_unit",
		"longitudinal_rad_per_unit", "lateral_rad_per_unit", "collective_min_rad", "collective_max_rad", "cyclic_max_rad"})) return dec.fail("invalid helicopter linkage");
#define H_CONTROL(FIELD) {#FIELD, &m.FIELD}
	if (!heli_decode_fields(dec, linkage, {H_CONTROL(collective_rad_per_unit), H_CONTROL(longitudinal_rad_per_unit),
		H_CONTROL(lateral_rad_per_unit), H_CONTROL(collective_min_rad), H_CONTROL(collective_max_rad), H_CONTROL(cyclic_max_rad)}) ||
		!heli_decode_fields(dec, src, {H_CONTROL(tail_collective_trim_rad), H_CONTROL(tail_collective_min_rad), H_CONTROL(tail_collective_max_rad),
		H_CONTROL(yaw_control_sign), H_CONTROL(yaw_deadzone), H_CONTROL(yaw_max_rate_rad_s), H_CONTROL(yaw_heading_gain_per_s),
		H_CONTROL(yaw_rate_kp_rad_per_rad_s), H_CONTROL(yaw_rate_ki_rad_per_rad), H_CONTROL(yaw_integrator_limit_rad),
		H_CONTROL(trainer_max_tilt_rad), H_CONTROL(trainer_roll_attitude_gain_per_s), H_CONTROL(trainer_pitch_attitude_gain_per_s),
		H_CONTROL(trainer_roll_rate_limit_rad_s), H_CONTROL(trainer_pitch_rate_limit_rad_s),
		H_CONTROL(trainer_roll_cyclic_gain_rad_per_rad_s), H_CONTROL(trainer_pitch_cyclic_gain_rad_per_rad_s)})) return false;
#undef H_CONTROL
	return (m.collective_rad_per_unit > 0.0 && m.longitudinal_rad_per_unit > 0.0 && m.lateral_rad_per_unit > 0.0 &&
		m.collective_min_rad < m.collective_max_rad && m.cyclic_max_rad >= 0.0 &&
		m.tail_collective_min_rad < m.tail_collective_max_rad && m.tail_collective_trim_rad >= m.tail_collective_min_rad &&
		m.tail_collective_trim_rad <= m.tail_collective_max_rad && absf(m.yaw_control_sign) == 1.0 &&
		m.yaw_deadzone >= 0.0 && m.yaw_deadzone < 1.0 && m.yaw_max_rate_rad_s > 0.0 && m.yaw_heading_gain_per_s > 0.0 &&
		m.yaw_rate_kp_rad_per_rad_s > 0.0 && m.yaw_rate_ki_rad_per_rad > 0.0 && m.yaw_integrator_limit_rad > 0.0 &&
		m.trainer_max_tilt_rad > 0.0 && m.trainer_max_tilt_rad < kPi / 2.0 &&
		m.trainer_roll_attitude_gain_per_s > 0.0 && m.trainer_pitch_attitude_gain_per_s > 0.0 &&
		m.trainer_roll_rate_limit_rad_s > 0.0 && m.trainer_pitch_rate_limit_rad_s > 0.0 &&
		m.trainer_roll_cyclic_gain_rad_per_rad_s > 0.0 && m.trainer_pitch_cyclic_gain_rad_per_rad_s > 0.0)
		|| dec.fail("invalid helicopter control parameters");
}

} // namespace nk
