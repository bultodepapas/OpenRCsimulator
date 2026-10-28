// OCV/resistance battery stage law. Mirrors electric_supply.gd and the three-slot
// FlightSession._battery_point path; event location and boundary projection stay with the session.
#pragma once

#include <array>
#include <vector>

#include "nk_electric.hpp"

namespace nk {

struct OcvBatteryModel {
	R capacity_ah = 0.0;
	R resistance_ohm = 0.0;
	R auxiliary_current_a = 0.0;
	R initial_soc = 0.0;
	std::vector<double> ocv_points; // [SOC, voltage, ...]
};

struct OcvBatteryPoint {
	bool ok = false;
	bool exhausted = false;
	ElectricMotorPoint motor;
	R motor_current_a = 0.0;
	R pack_current_a = 0.0;
	R bus_voltage_v = 0.0;
	R pack_terminal_power_w = 0.0;
	R pack_loss_w = 0.0;
	std::array<R, 3> rates{}; // charge C, terminal energy J, pack loss J
};

// electric_supply.gd _validate_pack. Type and unknown-key checks belong to the decoder.
inline bool ocv_battery_model_valid(const OcvBatteryModel &battery) {
	const size_t size = battery.ocv_points.size();
	if (size < 4 || size % 2 != 0) {
		return false;
	}
	for (size_t i = 0; i < size; i += 2) {
		const R soc = battery.ocv_points[i];
		const R voltage = battery.ocv_points[i + 1];
		if (!is_finite(soc) || !is_finite(voltage) || voltage.v <= 0.0 || soc.v < 0.0 || soc.v > 1.0) {
			return false;
		}
		if (i > 0 && (soc.v <= battery.ocv_points[i - 2] || voltage.v < battery.ocv_points[i - 1])) {
			return false;
		}
	}
	if (battery.ocv_points[0] != 0.0 || battery.ocv_points[size - 2] != 1.0 ||
			!is_finite(battery.capacity_ah) || battery.capacity_ah.v <= 0.0) {
		return false;
	}
	const R capacity_c = 3600.0 * battery.capacity_ah;
	return is_finite(capacity_c) && capacity_c.v > 0.0 && is_finite(battery.resistance_ohm) &&
			battery.resistance_ohm.v >= 0.0 && is_finite(battery.auxiliary_current_a) &&
			battery.auxiliary_current_a.v >= 0.0;
}

inline R ocv_battery_initial_charge(const OcvBatteryModel &battery) {
	return 3600.0 * battery.capacity_ah * battery.initial_soc;
}

// Session-level trial validation, before evaluating the source. The caller checks total
// continuous layout and passes its exact three battery slots here.
inline bool ocv_battery_block_valid(const R *block, int size, const OcvBatteryModel &battery, bool trial) {
	if (block == nullptr || size != 3) {
		return false;
	}
	for (int i = 0; i < size; ++i) {
		if (!is_finite(block[i])) {
			return false;
		}
	}
	return (trial || block[0].v >= 0.0) && block[0].v <= ocv_battery_initial_charge(battery).v &&
			block[1].v >= 0.0 && block[2].v >= 0.0;
}

inline R ocv_battery_interpolate(const std::vector<double> &points, R soc) {
	if (soc.v <= 0.0) {
		return points[1];
	}
	if (soc.v >= 1.0) {
		return points[points.size() - 1];
	}
	for (size_t i = 0; i + 2 < points.size(); i += 2) {
		const R left = points[i];
		const R right = points[i + 2];
		if (soc.v <= right.v) {
			const R fraction = (soc - left) / (right - left);
			return R(points[i + 1]) + fraction * (R(points[i + 3]) - points[i + 1]);
		}
	}
	return kNan;
}

// electric_supply.gd _assemble_result's stage subset, including diagnostic overflow checks.
inline OcvBatteryPoint ocv_battery_assemble(bool exhausted, const ElectricMotorPoint &source,
		R motor_current, R motor_bus_current, R auxiliary_current, R bus_voltage, R ocv,
		const OcvBatteryModel &battery) {
	OcvBatteryPoint out;
	const R pack_current = motor_bus_current + auxiliary_current;
	const R soc_rate = -pack_current / (3600.0 * battery.capacity_ah);
	const R terminal_power = bus_voltage * pack_current;
	const R loss = battery.resistance_ohm.v > 0.0 ?
			(battery.resistance_ohm * pack_current) * pack_current : R(0.0);
	const R open_circuit_power = ocv * pack_current;
	const R power_balance_residual = open_circuit_power - terminal_power - loss;
	if (!is_finite(pack_current) || !is_finite(soc_rate) || !is_finite(terminal_power) ||
			!is_finite(loss) || !is_finite(open_circuit_power) || !is_finite(power_balance_residual)) {
		return out;
	}
	out.ok = true;
	out.exhausted = exhausted;
	out.motor = source;
	out.motor_current_a = motor_current;
	out.pack_current_a = pack_current;
	out.bus_voltage_v = bus_voltage;
	out.pack_terminal_power_w = terminal_power;
	out.pack_loss_w = loss;
	out.rates = {-pack_current, terminal_power, loss};
	return out;
}

// electric_supply.gd evaluate_dynamics; SOC is the already-derived stage SOC.
inline OcvBatteryPoint ocv_battery_evaluate(R rpm, R duty, R soc, const OcvBatteryModel &battery,
		const ElectricMotorModel &motor, bool enabled, bool available_at_zero) {
	OcvBatteryPoint out;
	if (!is_finite(rpm) || rpm.v < 0.0 || !is_finite(duty) || duty.v < 0.0 || duty.v > 1.0 ||
			!is_finite(soc) || soc.v < 0.0 || soc.v > 1.0 || !ocv_battery_model_valid(battery) ||
			!electric_motor_model_valid(motor)) {
		return out;
	}
	const R ocv = ocv_battery_interpolate(battery.ocv_points, soc);
	if (!is_finite(ocv) || ocv.v <= 0.0) {
		return out;
	}
	if (soc.v == 0.0 && !available_at_zero) {
		const ElectricMotorPoint source = electric_motor_evaluate(rpm, duty, 0.0, motor, false);
		if (!source.ok) {
			return out;
		}
		return ocv_battery_assemble(true, source, 0.0, 0.0, 0.0, 0.0, ocv, battery);
	}
	const R effective_duty = enabled ? duty : R(0.0);
	const R back_emf = rpm / motor.kv_rpm_per_volt;
	if (!is_finite(back_emf)) {
		return out;
	}
	const R auxiliary_drop = battery.resistance_ohm * battery.auxiliary_current_a;
	const R bus_without_motor = ocv - auxiliary_drop;
	if (!is_finite(auxiliary_drop) || !is_finite(bus_without_motor) || bus_without_motor.v <= 0.0) {
		return out;
	}
	const R duty_squared = effective_duty * effective_duty;
	const R denominator = motor.resistance_ohm + duty_squared * battery.resistance_ohm;
	const R numerator = effective_duty * bus_without_motor - back_emf;
	if (!is_finite(denominator) || denominator.v <= 0.0 || !is_finite(numerator)) {
		return out;
	}
	const R solved_motor_current = effective_duty.v > 0.0 && numerator.v > 0.0 ? numerator / denominator : R(0.0);
	if (!is_finite(solved_motor_current) || solved_motor_current.v < 0.0) {
		return out;
	}
	const R solved_motor_bus_current = effective_duty * solved_motor_current;
	const R solved_pack_current = solved_motor_bus_current + battery.auxiliary_current_a;
	const R bus_voltage = ocv - battery.resistance_ohm * solved_pack_current;
	if (!is_finite(solved_motor_bus_current) || !is_finite(solved_pack_current) ||
			!is_finite(bus_voltage) || bus_voltage.v <= 0.0) {
		return out;
	}
	const ElectricMotorPoint source = electric_motor_evaluate(rpm, duty, bus_voltage, motor, enabled);
	if (!source.ok) {
		return out;
	}
	const R current_scale = maxf(1.0, maxf(absf(solved_motor_current), absf(source.motor_current_a)));
	const R tolerance = 1e-11 * current_scale;
	if (absf(source.motor_current_a - solved_motor_current).v > tolerance.v ||
			absf(source.battery_current_a - solved_motor_bus_current).v > tolerance.v) {
		return out;
	}
	return ocv_battery_assemble(false, source, source.motor_current_a, source.battery_current_a,
			battery.auxiliary_current_a, bus_voltage, ocv, battery);
}

// FlightSession._battery_point for the OCV branch. `charge < 0` selects the connected
// left limit during exhaustion localization; exactly zero remains disconnected.
inline OcvBatteryPoint ocv_battery_stage(R rpm, R duty, const R *block, int size,
		const OcvBatteryModel &battery, const ElectricMotorModel &motor, bool enabled) {
	if (!ocv_battery_block_valid(block, size, battery, true)) {
		return {};
	}
	const R charge = block[0];
	const R soc = maxf(0.0, charge / (3600.0 * battery.capacity_ah));
	return ocv_battery_evaluate(rpm, duty, soc, battery, motor, enabled, charge.v < 0.0);
}

} // namespace nk
