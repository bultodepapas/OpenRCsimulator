// Electric motor/ideal motoring ESC stage law. Mirrors app/physics/electric_motor.gd;
// this header advances no state and owns no event or endpoint policy.
#pragma once

#include "nk_prop.hpp"

namespace nk {

struct ElectricMotorModel {
	R kv_rpm_per_volt = 0.0;
	R resistance_ohm = 0.0;
	R no_load_current_a = 0.0;
};

enum class ElectricMotorMode { Stopped, Coast, Drive };

struct ElectricMotorPoint {
	bool ok = false;
	ElectricMotorMode mode = ElectricMotorMode::Stopped;
	R duty = 0.0;
	R command_voltage_v = 0.0;
	R motor_voltage_v = 0.0;
	R back_emf_v = 0.0;
	R motor_current_a = 0.0;
	R battery_current_a = 0.0;
	R shaft_torque_nm = 0.0;
	R shaft_power_w = 0.0;
	R bus_power_w = 0.0;
	R copper_loss_w = 0.0;
	R rotational_loss_w = 0.0;
};

inline bool electric_motor_model_valid(const ElectricMotorModel &motor) {
	return is_finite(motor.kv_rpm_per_volt) && motor.kv_rpm_per_volt.v > 0.0 &&
			is_finite(motor.resistance_ohm) && motor.resistance_ohm.v > 0.0 &&
			is_finite(motor.no_load_current_a) && motor.no_load_current_a.v >= 0.0;
}

// ElectricMotor._evaluate_validated. Checks all source results even when a caller uses only
// torque/current: GDScript's compact stage path has the same overflow checks.
inline ElectricMotorPoint electric_motor_evaluate(R rpm, R duty, R bus_voltage_v,
		const ElectricMotorModel &motor, bool enabled) {
	ElectricMotorPoint out;
	if (!electric_motor_model_valid(motor) || !is_finite(rpm) || rpm.v < 0.0 || !is_finite(duty) ||
			duty.v < 0.0 || duty.v > 1.0 || !is_finite(bus_voltage_v) || bus_voltage_v.v < 0.0) {
		return out;
	}
	const R kt = R(60.0) / kTauConstant / motor.kv_rpm_per_volt;
	const R omega = rpm * (R(kTauConstant) / 60.0);
	const R back_emf = rpm / motor.kv_rpm_per_volt;
	const R effective_duty = enabled ? duty : R(0.0);
	const R command_voltage = effective_duty * bus_voltage_v;
	const R current = effective_duty.v > 0.0
			? maxf(0.0, (command_voltage - back_emf) / motor.resistance_ohm) : R(0.0);
	const R electromagnetic_torque = kt * current;
	R loss_torque = kt * motor.no_load_current_a;
	if (!is_finite(kt) || kt.v <= 0.0 || !is_finite(loss_torque)) {
		return out;
	}
	if (rpm.v == 0.0) {
		loss_torque = minf(loss_torque, electromagnetic_torque);
	}
	const R torque = electromagnetic_torque - loss_torque;
	const R battery_current = effective_duty * current;
	const R motor_voltage = current.v > 0.0 ? command_voltage : back_emf;
	const R shaft_power = torque * omega;
	const R bus_power = bus_voltage_v * battery_current;
	const R copper_loss = (current * motor.resistance_ohm) * current;
	const R rotational_loss = loss_torque * omega;
	if (!is_finite(command_voltage) || !is_finite(motor_voltage) || !is_finite(back_emf) ||
			!is_finite(current) || !is_finite(battery_current) || !is_finite(torque) ||
			!is_finite(shaft_power) || !is_finite(bus_power) || !is_finite(copper_loss) ||
			!is_finite(rotational_loss)) {
		return out;
	}
	out.ok = true;
	out.mode = current.v > 0.0 ? ElectricMotorMode::Drive :
			(rpm.v > 0.0 ? ElectricMotorMode::Coast : ElectricMotorMode::Stopped);
	out.duty = effective_duty;
	out.command_voltage_v = command_voltage;
	out.motor_voltage_v = motor_voltage;
	out.back_emf_v = back_emf;
	out.motor_current_a = current;
	out.battery_current_a = battery_current;
	out.shaft_torque_nm = torque;
	out.shaft_power_w = shaft_power;
	out.bus_power_w = bus_power;
	out.copper_loss_w = copper_loss;
	out.rotational_loss_w = rotational_loss;
	return out;
}

} // namespace nk
