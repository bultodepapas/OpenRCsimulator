// Strict prepared adapter for the electric source/pack component. The snapshot owns
// decoded values; no Godot data or callback is retained for stage evaluations.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <array>
#include <cstdint>
#include <initializer_list>
#include <string>
#include <utility>
#include <vector>

#include "nk_battery.hpp"
#include "nk_pack_ecm.hpp"

namespace nk {

// openrc-nk3-electric-snapshot-v1: {format, motor, battery, esc}.
// motor = {kv_rpm_per_volt, resistance_ohm, no_load_current_a};
// esc = {kind: ideal_motoring, command_mapping: identity};
// battery.kind fixed_voltage: {kind, voltage_v}; ocv_resistance: {kind, capacity_ah,
// resistance_ohm, auxiliary_current_a, initial_soc, ocv_points: float64[]}; pack_ecm:
// {kind, series, branches, group_capacity_c, initial_soc, weak_capacity_factor,
// weak_resistance_factor, weak_soc_offset, interconnect_ohm, auxiliary_current_a,
// cooling_airflow_fraction, thermal_capacity_j_per_k, h_still_w_per_k,
// h_forced_w_per_k_sqrt_mps, lvc_filter_s, soc_knots, temperature_knots_k, ocv,
// r0, rc_r, rc_tau}. Tables are packed float64 arrays; rc_r/rc_tau are Arrays of
// packed float64 arrays. Source metadata and the endpoint supervisor are not evaluated here.
struct ElectricSnapshotDecoder {
	std::string error;

	bool fail(const std::string &why) {
		if (error.empty()) error = why;
		return false;
	}

	bool keys(const godot::Dictionary &dict, const char *where, std::initializer_list<const char *> allowed) {
		const godot::Array names = dict.keys();
		for (int64_t i = 0; i < names.size(); ++i) {
			const godot::Variant value = names[i];
			if (value.get_type() != godot::Variant::STRING && value.get_type() != godot::Variant::STRING_NAME) {
				return fail(std::string(where) + " has a non-string key");
			}
			const godot::String name = value;
			bool known = false;
			for (const char *candidate : allowed) if (name == godot::String(candidate)) { known = true; break; }
			if (!known) return fail(std::string("unsupported ") + where + "." + name.utf8().get_data());
		}
		return true;
	}

	bool dictionary(const godot::Dictionary &dict, const char *key, godot::Dictionary &out) {
		if (!dict.has(key) || dict[key].get_type() != godot::Variant::DICTIONARY) return fail(std::string("missing dictionary ") + key);
		out = dict[key];
		return true;
	}

	bool string(const godot::Dictionary &dict, const char *key, godot::String &out) {
		if (!dict.has(key) || dict[key].get_type() != godot::Variant::STRING) return fail(std::string("missing string ") + key);
		out = dict[key];
		return true;
	}

	bool number(const godot::Dictionary &dict, const char *key, R &out) {
		if (!dict.has(key)) return fail(std::string("missing number ") + key);
		const godot::Variant value = dict[key];
		if (value.get_type() == godot::Variant::FLOAT) out = static_cast<double>(value);
		else if (value.get_type() == godot::Variant::INT) out = static_cast<double>(static_cast<int64_t>(value));
		else return fail(std::string("non-numeric ") + key);
		return is_finite(out) || fail(std::string("nonfinite ") + key);
	}

	bool integer(const godot::Dictionary &dict, const char *key, int &out, int min, int max) {
		if (!dict.has(key) || dict[key].get_type() != godot::Variant::INT) return fail(std::string("missing integer ") + key);
		const int64_t value = dict[key];
		if (value < min || value > max) return fail(std::string("integer outside range ") + key);
		out = static_cast<int>(value);
		return true;
	}

	bool packed(const godot::Dictionary &dict, const char *key, std::vector<double> &out) {
		if (!dict.has(key) || dict[key].get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) {
			return fail(std::string("missing float64 array ") + key);
		}
		const godot::PackedFloat64Array values = dict[key];
		out.clear();
		out.reserve(static_cast<std::size_t>(values.size()));
		for (int64_t i = 0; i < values.size(); ++i) {
			const double value = values[i];
			if (!std::isfinite(value)) return fail(std::string("nonfinite array value ") + key);
			out.push_back(value);
		}
		return true;
	}

	bool packed_rows(const godot::Dictionary &dict, const char *key, int branches,
			std::vector<std::vector<double>> &out) {
		if (!dict.has(key) || dict[key].get_type() != godot::Variant::ARRAY) return fail(std::string("missing array ") + key);
		const godot::Array rows = dict[key];
		if (rows.size() != branches) return fail(std::string("invalid branch count ") + key);
		out.clear();
		out.reserve(static_cast<std::size_t>(branches));
		for (int i = 0; i < branches; ++i) {
			if (rows[i].get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) return fail(std::string("invalid branch table ") + key);
			const godot::PackedFloat64Array values = rows[i];
			std::vector<double> table;
			table.reserve(static_cast<std::size_t>(values.size()));
			for (int64_t j = 0; j < values.size(); ++j) {
				const double value = values[j];
				if (!std::isfinite(value)) return fail(std::string("nonfinite branch table ") + key);
				table.push_back(value);
			}
			out.push_back(std::move(table));
		}
		return true;
	}
};

enum class ElectricBatteryKind { FixedVoltage, OcvResistance, PackEcm };

struct ElectricStagePoint {
	bool ok = false;
	// Torque, motor current, pack/bus current, bus voltage.
	std::array<R, 4> values{};
	std::vector<R> rates;
};

class ElectricBinding {
	bool ready_ = false;
	ElectricBatteryKind kind_ = ElectricBatteryKind::FixedVoltage;
	ElectricMotorModel motor_;
	R fixed_voltage_ = 0.0;
	OcvBatteryModel ocv_;
	PackEcmModel pack_;

public:
	bool ready() const { return ready_; }
	ElectricBatteryKind kind() const { return kind_; }
	const ElectricMotorModel &motor() const { return motor_; }
	const OcvBatteryModel &ocv() const { return ocv_; }
	const PackEcmModel &pack() const { return pack_; }

	godot::Dictionary prepare_electric(const godot::Dictionary &snapshot) {
		ready_ = false;
		ElectricSnapshotDecoder dec;
		godot::String format, battery_kind, esc_kind, mapping;
		godot::Dictionary motor, battery, esc;
		if (!dec.keys(snapshot, "electric", {"format", "motor", "battery", "esc"}) ||
				!dec.string(snapshot, "format", format) || !dec.dictionary(snapshot, "motor", motor) ||
				!dec.dictionary(snapshot, "battery", battery) || !dec.dictionary(snapshot, "esc", esc)) return failure(dec.error);
		if (format != godot::String("openrc-nk3-electric-snapshot-v1")) return failure("unknown electric snapshot format");
		ElectricMotorModel decoded_motor;
		if (!dec.keys(motor, "motor", {"kv_rpm_per_volt", "resistance_ohm", "no_load_current_a"}) ||
				!dec.number(motor, "kv_rpm_per_volt", decoded_motor.kv_rpm_per_volt) ||
				!dec.number(motor, "resistance_ohm", decoded_motor.resistance_ohm) ||
				!dec.number(motor, "no_load_current_a", decoded_motor.no_load_current_a) ||
				!dec.keys(esc, "esc", {"kind", "command_mapping"}) || !dec.string(esc, "kind", esc_kind) ||
				!dec.string(esc, "command_mapping", mapping) || !dec.string(battery, "kind", battery_kind)) return failure(dec.error);
		if (!electric_motor_model_valid(decoded_motor) || esc_kind != godot::String("ideal_motoring") ||
				mapping != godot::String("identity")) return failure("invalid motor or unsupported ESC");
		ElectricBatteryKind decoded_kind;
		R voltage = 0.0;
		OcvBatteryModel ocv;
		PackEcmModel pack;
		if (battery_kind == godot::String("fixed_voltage")) {
			decoded_kind = ElectricBatteryKind::FixedVoltage;
			if (!dec.keys(battery, "battery", {"kind", "voltage_v"}) || !dec.number(battery, "voltage_v", voltage)) return failure(dec.error);
			if (voltage.v <= 0.0) return failure("fixed voltage must be positive");
		} else if (battery_kind == godot::String("ocv_resistance")) {
			decoded_kind = ElectricBatteryKind::OcvResistance;
			if (!dec.keys(battery, "battery", {"kind", "capacity_ah", "resistance_ohm", "auxiliary_current_a",
					"initial_soc", "ocv_points"}) || !dec.number(battery, "capacity_ah", ocv.capacity_ah) ||
					!dec.number(battery, "resistance_ohm", ocv.resistance_ohm) ||
					!dec.number(battery, "auxiliary_current_a", ocv.auxiliary_current_a) ||
					!dec.number(battery, "initial_soc", ocv.initial_soc) || !dec.packed(battery, "ocv_points", ocv.ocv_points)) return failure(dec.error);
			if (!ocv_battery_model_valid(ocv) || ocv.initial_soc.v <= 0.0 || ocv.initial_soc.v > 1.0 ||
					!is_finite(ocv_battery_initial_charge(ocv)) || ocv_battery_initial_charge(ocv).v <= 0.0) return failure("invalid OCV battery");
		} else if (battery_kind == godot::String("pack_ecm")) {
			decoded_kind = ElectricBatteryKind::PackEcm;
			if (!dec.keys(battery, "battery", {"kind", "series", "branches", "group_capacity_c", "initial_soc",
					"weak_capacity_factor", "weak_resistance_factor", "weak_soc_offset", "interconnect_ohm",
					"auxiliary_current_a", "cooling_airflow_fraction", "thermal_capacity_j_per_k", "h_still_w_per_k",
					"h_forced_w_per_k_sqrt_mps", "lvc_filter_s", "soc_knots", "temperature_knots_k", "ocv", "r0",
					"rc_r", "rc_tau"}) || !dec.integer(battery, "series", pack.series, 1, 24) ||
					!dec.integer(battery, "branches", pack.branches, 0, kPackMaxBranches) ||
					!dec.number(battery, "group_capacity_c", pack.group_capacity_c) ||
					!dec.number(battery, "initial_soc", pack.initial_soc) ||
					!dec.number(battery, "weak_capacity_factor", pack.weak_capacity_factor) ||
					!dec.number(battery, "weak_resistance_factor", pack.weak_resistance_factor) ||
					!dec.number(battery, "weak_soc_offset", pack.weak_soc_offset) ||
					!dec.number(battery, "interconnect_ohm", pack.interconnect_ohm) ||
					!dec.number(battery, "auxiliary_current_a", pack.auxiliary_current_a) ||
					!dec.number(battery, "cooling_airflow_fraction", pack.cooling_airflow_fraction) ||
					!dec.number(battery, "thermal_capacity_j_per_k", pack.thermal_capacity_j_per_k) ||
					!dec.number(battery, "h_still_w_per_k", pack.h_still_w_per_k) ||
					!dec.number(battery, "h_forced_w_per_k_sqrt_mps", pack.h_forced_w_per_k_sqrt_mps) ||
					!dec.number(battery, "lvc_filter_s", pack.lvc_filter_s) ||
					!dec.packed(battery, "soc_knots", pack.soc_knots) ||
					!dec.packed(battery, "temperature_knots_k", pack.temperature_knots_k) ||
					!dec.packed(battery, "ocv", pack.ocv) || !dec.packed(battery, "r0", pack.r0) ||
					!dec.packed_rows(battery, "rc_r", pack.branches, pack.rc_r) ||
					!dec.packed_rows(battery, "rc_tau", pack.branches, pack.rc_tau)) return failure(dec.error);
			if (!pack_ecm_model_valid(pack)) return failure("invalid pack ECM battery");
		} else {
			return failure("unsupported electric battery kind");
		}
		motor_ = decoded_motor;
		kind_ = decoded_kind;
		fixed_voltage_ = voltage;
		ocv_ = std::move(ocv);
		pack_ = std::move(pack);
		ready_ = true;
		godot::Dictionary out;
		out["ok"] = true;
		out["error"] = "";
		return out;
	}

	// Pure typed entry for future stage composition. The block is only the battery
	// sub-block; the owning session must validate the complete continuous layout.
	ElectricStagePoint evaluate(R rpm, R duty, const R *block, int size, bool enabled,
			R ambient_k, R cooling_mps) const {
		ElectricStagePoint out;
		if (!ready_) return out;
		if (kind_ == ElectricBatteryKind::FixedVoltage) {
			if (size != 0) return out;
			const ElectricMotorPoint point = electric_motor_evaluate(rpm, duty, fixed_voltage_, motor_, enabled);
			if (!point.ok) return out;
			out.values = {point.shaft_torque_nm, point.motor_current_a, point.battery_current_a, fixed_voltage_};
		} else if (kind_ == ElectricBatteryKind::OcvResistance) {
			const OcvBatteryPoint point = ocv_battery_stage(rpm, duty, block, size, ocv_, motor_, enabled);
			if (!point.ok) return out;
			out.values = {point.motor.shaft_torque_nm, point.motor_current_a, point.pack_current_a, point.bus_voltage_v};
			out.rates.assign(point.rates.begin(), point.rates.end());
		} else {
			PackEcmPoint point = pack_ecm_stage(rpm, duty, block, size, pack_, motor_, enabled, ambient_k, cooling_mps);
			if (!point.ok) return out;
			out.values = {point.motor.shaft_torque_nm, point.motor_current_a, point.pack_current_a, point.bus_voltage_v};
			out.rates = std::move(point.rates);
		}
		out.ok = true;
		return out;
	}

	godot::Dictionary electric_component(double rpm, double duty, const godot::PackedFloat64Array &block,
			bool enabled, double ambient_k, double cooling_mps) const {
		godot::Dictionary out;
		if (block.size() > 13) { out["ok"] = false; return out; }
		R values[13];
		for (int64_t i = 0; i < block.size(); ++i) values[i] = block[i];
		const ElectricStagePoint point = evaluate(rpm, duty, values, static_cast<int>(block.size()), enabled, ambient_k, cooling_mps);
		out["ok"] = point.ok;
		if (point.ok) {
			godot::PackedFloat64Array result, rates;
			result.resize(4);
			for (int i = 0; i < 4; ++i) result[i] = point.values[i].v;
			rates.resize(static_cast<int64_t>(point.rates.size()));
			for (size_t i = 0; i < point.rates.size(); ++i) rates[static_cast<int64_t>(i)] = point.rates[i].v;
			out["values"] = result;
			out["rates"] = rates;
		}
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
