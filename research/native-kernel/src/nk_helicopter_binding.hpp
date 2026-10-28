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

inline bool heli_decode_context(WeatherSnapshotDecoder &dec, const godot::Dictionary &src, HeliStageModel &m) {
	if (!src.is_read_only() || src.size() != 19 || !dec.keys(src, "flight context", {"law", "mass_kg", "gravity_m_s2",
		"inertia_kg_m2", "inertia_body_kg_m2", "inertia_inverse_kg_m2", "main_model", "tail_model", "airframe_model",
		"aero_context", "drive_model", "electronics_model", "spin_inertia_kg_m2", "b_body_frd_kg_m2", "flow_floor_m_s",
		"fin_tail_wake_fraction", "height_over_radius", "inflow_loss", "inflow_instability"})) return dec.fail("invalid or mutable helicopter flight context");
	godot::String law;
	if (!dec.string(src, "law", law) || law != godot::String("openrc-helicopter-flight-dynamics-v1")) return dec.fail("unsupported helicopter flight law");
	godot::Dictionary main, tail, airframe, aero, drive, electronics;
	if (!dec.dictionary(src, "main_model", main) || !dec.dictionary(src, "tail_model", tail) ||
		!dec.dictionary(src, "airframe_model", airframe) || !dec.dictionary(src, "aero_context", aero) ||
		!dec.dictionary(src, "drive_model", drive) || !dec.dictionary(src, "electronics_model", electronics) ||
		!heli_decode_main(dec, main, m.aero.main) || !heli_decode_tail(dec, tail, m.aero.tail) ||
		!heli_decode_airframe(dec, airframe, m.aero.airframe) || !heli_decode_drive(dec, drive, m.drive) ||
		!heli_decode_controls(dec, electronics, m.controls)) return false;
	if (!aero.is_read_only() || aero.size() != 9 || !dec.keys(aero, "aerodynamic context", {"law", "main_model", "tail_model",
		"airframe_model", "flow_floor_m_s", "fin_tail_wake_fraction", "height_over_radius", "loss", "instability"})) {
		return dec.fail("invalid or mutable helicopter aerodynamic context");
	}
	godot::String aero_law;
	godot::Dictionary aero_main, aero_tail, aero_airframe;
	if (!dec.string(aero, "law", aero_law) || aero_law != godot::String("openrc-helicopter-aero-performance-context-v1") ||
		!dec.dictionary(aero, "main_model", aero_main) || !dec.dictionary(aero, "tail_model", aero_tail) ||
		!dec.dictionary(aero, "airframe_model", aero_airframe) || aero_main != main || aero_tail != tail || aero_airframe != airframe) {
		return dec.fail("helicopter aerodynamic context disagrees with flight models");
	}
	R ae_flow, ae_fraction, ae_height, ae_loss, ae_instability;
	if (!heli_decode_fields(dec, src, {{"mass_kg", &m.mass_kg}, {"gravity_m_s2", &m.gravity_m_s2},
		{"spin_inertia_kg_m2", &m.spin_inertia}, {"flow_floor_m_s", &m.aero.flow_floor_m_s},
		{"fin_tail_wake_fraction", &m.aero.fin_tail_wake_fraction}, {"height_over_radius", &m.aero.height_over_radius},
		{"inflow_loss", &m.aero.inflow_loss}, {"inflow_instability", &m.aero.inflow_instability}}) ||
		!heli_decode_fields(dec, aero, {{"flow_floor_m_s", &ae_flow}, {"fin_tail_wake_fraction", &ae_fraction},
		{"height_over_radius", &ae_height}, {"loss", &ae_loss}, {"instability", &ae_instability}})) return false;
	if (ae_flow != m.aero.flow_floor_m_s || ae_fraction != m.aero.fin_tail_wake_fraction || ae_height != m.aero.height_over_radius ||
		ae_loss != m.aero.inflow_loss || ae_instability != m.aero.inflow_instability ||
		m.mass_kg <= 0.0 || m.gravity_m_s2 < 0.0 || m.spin_inertia <= 0.0 || m.aero.flow_floor_m_s <= 0.0 ||
		m.aero.fin_tail_wake_fraction < 0.0 || m.aero.fin_tail_wake_fraction > 1.0 ||
		(m.aero.height_over_radius < 0.0 && m.aero.height_over_radius != -1.0) || m.aero.inflow_loss < 1.0 ||
		m.aero.inflow_instability < 0.0 || m.aero.inflow_instability > 1.0 ||
		m.aero.main.rho_kg_m3 != m.aero.tail.rho_kg_m3 || m.aero.main.rho_kg_m3 != m.aero.airframe.rho_kg_m3 ||
		m.aero.main.rotor_radius_m != static_cast<double>(tail["main_rotor_radius_m"]) ||
		m.aero.airframe.vertical_fin_area != static_cast<double>(tail["vertical_fin_area_m2"])) {
		return dec.fail("inconsistent helicopter flight and aerodynamic parameters");
	}
	std::vector<R> inertia, duplicate, inverse, b;
	if (!dec.packed(src, "inertia_kg_m2", inertia, 6) || !dec.packed(src, "inertia_body_kg_m2", duplicate, 6) ||
		!dec.packed(src, "inertia_inverse_kg_m2", inverse, 6) || !dec.packed(src, "b_body_frd_kg_m2", b, 3)) return false;
	for (int i = 0; i < 6; ++i) {
		if (bits(inertia[i].v) != bits(duplicate[i].v)) return dec.fail("inconsistent helicopter inertia tensors");
		m.inertia[i] = inertia[i]; m.inertia_inverse[i] = inverse[i];
	}
	for (int i = 0; i < 3; ++i) m.coupling_b[i] = b[i];
	const R a = inertia[0], j = inertia[1], c = inertia[2], d = inertia[3], e = inertia[4], f = inertia[5];
	const R c00 = j * c - f * f, c11 = a * c - e * e, c22 = a * j - d * d;
	const R c01 = e * f - d * c, c02 = d * f - j * e, c12 = d * e - a * f;
	const R det = a * c00 + d * c01 + e * c02;
	if (a <= 0.0 || c22 <= 0.0 || !is_finite(det) || det <= 0.0) return dec.fail("helicopter inertia is not positive definite");
	const R expected_inverse[6] = {c00 / det, c11 / det, c22 / det, c01 / det, c02 / det, c12 / det};
	for (int i = 0; i < 6; ++i) if (bits(expected_inverse[i].v) != bits(inverse[i].v)) return dec.fail("helicopter inverse inertia disagrees");
	const Vec3 inverse_b = heli_inertia_mul(m.inertia_inverse, m.coupling_b);
	const R denominator = 1.0 - heli_dot3(m.coupling_b, inverse_b) / m.spin_inertia;
	if (!is_finite(denominator) || denominator <= 0.0) return dec.fail("invalid helicopter effective carrier inertia");
	return true;
}

inline bool heli_decode_skids(WeatherSnapshotDecoder &dec, const godot::Dictionary &src, HeliSkidModel &m) {
	if (!src.is_read_only() || src.size() != 6 || !dec.keys(src, "skids", {"points_body_frd_m", "spring_n_m",
		"damping_n_s_m", "friction", "slip_m_s", "reach_m"})) return dec.fail("invalid or mutable helicopter skids");
	std::vector<R> points;
	if (!dec.packed(src, "points_body_frd_m", points, 12) ||
		!heli_decode_fields(dec, src, {{"spring_n_m", &m.spring_n_m}, {"damping_n_s_m", &m.damping_n_s_m},
		{"friction", &m.friction}, {"slip_m_s", &m.slip_m_s}, {"reach_m", &m.reach_m}})) return false;
	R reach = 0.0;
	for (int i = 0; i < 12; ++i) m.points_body_frd_m[i] = points[i];
	for (int i = 0; i < 12; i += 3) reach = maxf(reach, sqrt_(points[i] * points[i] + points[i + 1] * points[i + 1] + points[i + 2] * points[i + 2]));
	return (m.spring_n_m > 0.0 && m.damping_n_s_m > 0.0 && m.friction > 0.0 && m.slip_m_s > 0.0 &&
		m.reach_m > 0.0 && bits(m.reach_m.v) == bits(reach.v)) || dec.fail("invalid helicopter skid parameters");
}

inline bool heli_decode_tick(WeatherSnapshotDecoder &dec, const godot::Dictionary &src, HeliTickContext &tick) {
	if (!dec.keys(src, "helicopter tick", {"inputs", "mode", "trainer", "hold", "armed", "ground_start", "spool_start_s", "trim"}) ||
		src.size() != 8) return dec.fail("invalid helicopter tick context");
	std::vector<R> inputs;
	bool trainer, hold, armed, ground_start;
	R spool_start;
	godot::String mode;
	godot::Dictionary trim;
	if (!dec.packed(src, "inputs", inputs, 4) || !dec.string(src, "mode", mode) || !dec.boolean(src, "trainer", trainer) ||
		!dec.boolean(src, "hold", hold) || !dec.boolean(src, "armed", armed) || !dec.boolean(src, "ground_start", ground_start) ||
		!dec.number(src, "spool_start_s", spool_start) || !dec.dictionary(src, "trim", trim)) return false;
	if (mode != godot::String("normal") && mode != godot::String("idle_up")) return dec.fail("unsupported helicopter mode");
	if (!dec.keys(trim, "trim", {"roll_reference_rad", "pitch_reference_rad", "cyclic_forward_bias_rad", "cyclic_right_bias_rad",
		"tail_collective_bias_rad", "ground_yaw_precomp_tail_bias_rad", "ground_yaw_precomp_collective_rad"})) return false;
	for (int i = 0; i < 4; ++i) tick.inputs[i] = inputs[i];
	tick.idle_up = mode == godot::String("idle_up"); tick.trainer = trainer; tick.hold = hold;
	tick.armed = armed; tick.ground_start = ground_start; tick.spool_start_s = spool_start;
	const HeliField optional[] = {{"roll_reference_rad", &tick.trim.roll_reference_rad}, {"pitch_reference_rad", &tick.trim.pitch_reference_rad},
		{"cyclic_forward_bias_rad", &tick.trim.cyclic_forward_bias_rad}, {"cyclic_right_bias_rad", &tick.trim.cyclic_right_bias_rad},
		{"tail_collective_bias_rad", &tick.trim.tail_collective_bias_rad}, {"ground_yaw_precomp_tail_bias_rad", &tick.trim.ground_yaw_precomp_tail_bias_rad},
		{"ground_yaw_precomp_collective_rad", &tick.trim.ground_yaw_precomp_collective_rad}};
	for (const HeliField &field : optional) if (trim.has(field.name) && !dec.number(trim, field.name, *field.value)) return false;
	const bool has_bias = trim.has("ground_yaw_precomp_tail_bias_rad"), has_collective = trim.has("ground_yaw_precomp_collective_rad");
	if (has_bias != has_collective) return dec.fail("incomplete helicopter ground yaw precompensation");
	tick.trim.ground_precomp = has_bias;
	return true;
}

class HelicopterBinding {
	bool ready_ = false;
	HeliStageModel model_;

public:
	bool ready() const { return ready_; }
	const HeliStageModel &model() const { return model_; }

	godot::Dictionary prepare_helicopter(const godot::Dictionary &snapshot) {
		ready_ = false;
		WeatherSnapshotDecoder dec;
		godot::String format;
		godot::Dictionary context, skids;
		if (!dec.keys(snapshot, "helicopter snapshot", {"format", "context", "skids", "surfaces"}) || snapshot.size() != 4 ||
			!dec.string(snapshot, "format", format) || format != godot::String("openrc-nk3-helicopter-snapshot-v1") ||
			!dec.dictionary(snapshot, "context", context) || !dec.dictionary(snapshot, "skids", skids)) return failure(dec.error.empty() ? "invalid helicopter snapshot" : dec.error);
		if (!snapshot.has("surfaces") || snapshot["surfaces"].get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) return failure("missing helicopter surface table");
		const godot::PackedFloat64Array surfaces = snapshot["surfaces"];
		HeliStageModel candidate;
		if (surfaces.size() > 6000) return failure("helicopter surface table too large");
		candidate.surfaces.values.assign(surfaces.ptr(), surfaces.ptr() + surfaces.size());
		candidate.surfaces.valid = surface_table_is_valid(candidate.surfaces.values);
		if (!candidate.surfaces.valid || !heli_decode_context(dec, context, candidate) || !heli_decode_skids(dec, skids, candidate.skids)) {
			return failure(dec.error.empty() ? "invalid helicopter surface table" : dec.error);
		}
		model_ = std::move(candidate);
		ready_ = true;
		godot::Dictionary out;
		out["ok"] = true; out["error"] = "";
		return out;
	}

	godot::Dictionary heli_component(const godot::PackedFloat64Array &body, const godot::PackedFloat64Array &continuous,
			double time, const godot::Dictionary &raw_tick, const godot::PackedFloat64Array &wind) const {
		if (!ready_ || body.size() != 13 || (continuous.size() != 6 && continuous.size() != 14) || wind.size() != 3) {
			return failure("invalid helicopter component argument shape or unprepared model");
		}
		WeatherSnapshotDecoder dec;
		HeliTickContext tick;
		if (!heli_decode_tick(dec, raw_tick, tick)) return failure(dec.error);
		R state[13], values[14];
		Vec3 wind_ned;
		for (int i = 0; i < 13; ++i) state[i] = body[i];
		for (int64_t i = 0; i < continuous.size(); ++i) values[i] = continuous[i];
		for (int i = 0; i < 3; ++i) wind_ned[i] = wind[i];
		const HeliStageResult result = heli_stage(state, values, static_cast<int>(continuous.size()), time, model_, tick, wind_ned);
		if (!result.ok) return failure(result.message);
		godot::Dictionary out;
		out["ok"] = true;
		out["error"] = "";
		out["loads"] = pack(result.loads.data(), 6);
		out["body_derivative"] = pack(result.body_derivative.data(), 13);
		out["derivative"] = pack(result.derivative.data(), result.derivative_size);
		out["rotor_momentum"] = pack(result.rotor_momentum.data(), 3);
		return out;
	}

private:
	static godot::Dictionary failure(const std::string &message) {
		godot::Dictionary out;
		out["ok"] = false; out["error"] = godot::String(message.c_str());
		return out;
	}
	static godot::PackedFloat64Array pack(const R *values, int size) {
		godot::PackedFloat64Array out;
		out.resize(size);
		for (int i = 0; i < size; ++i) out[i] = values[i].v;
		return out;
	}
};

} // namespace nk
