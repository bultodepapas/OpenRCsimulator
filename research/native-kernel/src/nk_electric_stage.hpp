// Godot-independent prepared electric source for repeated flight stages.
// Numeric model fields are detached during preparation; endpoint events and
// the ESC supervisor remain owned by the session.
#pragma once

#include <array>
#include <utility>
#include <vector>

#include "nk_battery.hpp"
#include "nk_pack_ecm.hpp"

namespace nk {

enum class ElectricBatteryKind { FixedVoltage, OcvResistance, PackEcm };

struct ElectricStagePoint {
	bool ok = false;
	// Torque, motor current, pack/bus current, bus voltage.
	std::array<R, 4> values{};
	std::vector<R> rates;
};

struct ElectricPreparedSource {
	bool ready = false;
	ElectricBatteryKind kind = ElectricBatteryKind::FixedVoltage;
	ElectricMotorModel motor;
	R fixed_voltage = 0.0;
	OcvBatteryModel ocv;
	PackEcmModel pack;

	// block contains only the battery sub-block. The session owns and validates
	// the complete layout, tick-held throttle, and discrete source state.
	ElectricStagePoint evaluate(R rpm, R duty, const R *block, int size, bool enabled,
			R ambient_k, R cooling_mps) const {
		ElectricStagePoint out;
		if (!ready) return out;
		if (kind == ElectricBatteryKind::FixedVoltage) {
			if (size != 0) return out;
			const ElectricMotorPoint point = electric_motor_evaluate(rpm, duty, fixed_voltage, motor, enabled);
			if (!point.ok) return out;
			out.values = {point.shaft_torque_nm, point.motor_current_a, point.battery_current_a, fixed_voltage};
		} else if (kind == ElectricBatteryKind::OcvResistance) {
			const OcvBatteryPoint point = ocv_battery_stage(rpm, duty, block, size, ocv, motor, enabled);
			if (!point.ok) return out;
			out.values = {point.motor.shaft_torque_nm, point.motor_current_a, point.pack_current_a, point.bus_voltage_v};
			out.rates.assign(point.rates.begin(), point.rates.end());
		} else if (kind == ElectricBatteryKind::PackEcm) {
			PackEcmPoint point = pack_ecm_stage(rpm, duty, block, size, pack, motor, enabled, ambient_k, cooling_mps);
			if (!point.ok) return out;
			out.values = {point.motor.shaft_torque_nm, point.motor_current_a, point.pack_current_a, point.bus_voltage_v};
			out.rates = std::move(point.rates);
		} else {
			return out;
		}
		out.ok = true;
		return out;
	}
};

} // namespace nk
