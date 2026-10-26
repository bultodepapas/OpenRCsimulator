# EL2a: stateless OCV + pack-resistance supply algebra for the existing EL1a source.
# The normalized pack is {ocv_points: PackedFloat64Array([SOC0, V0, ...]),
# capacity_ah, resistance_ohm, auxiliary_current_a}. No RC, thermal, ESC cutoff,
# regeneration, or time/state advancement is modeled here.
# `motor_current_a` remains EL1a's equivalent DC-port current; it is not phase RMS current.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const Electric: Script = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/electric_motor.gd")
const PACK_KEYS: Array[String] = ["ocv_points", "capacity_ah", "resistance_ohm", "auxiliary_current_a"]
const MOTOR_KEYS: Array[String] = ["kv_rpm_per_volt", "resistance_ohm", "no_load_current_a"]


## Evaluate one algebraic supply point. Inputs and returned rates are SI, except SOC and Ah.
## `enabled=false` disconnects the motor while configured pack-side auxiliary current remains.
## At SOC=0 the ideal exhausted pack disconnects all loads; this is a boundary convention,
## not an ESC/BMS low-voltage-cutoff model. The caller owns SOC integration and event location.
static func evaluate(rpm: Variant, duty: Variant, soc: Variant, pack: Variant, motor: Variant,
		enabled: Variant = true) -> Dictionary:
	return _evaluate(rpm, duty, soc, pack, motor, enabled, false)


## Evaluate the connected motoring branch at SOC=0. This is the left-limit used only while
## locating exhaustion; the accepted Q=0 boundary still uses evaluate() and disconnects all loads.
static func evaluate_available(rpm: Variant, duty: Variant, soc: Variant, pack: Variant, motor: Variant,
		enabled: Variant = true) -> Dictionary:
	return _evaluate(rpm, duty, soc, pack, motor, enabled, true)


## Stage-local result: identical validation/arithmetic, without building endpoint telemetry.
## No validated data or evaluation survives this call; mutable definitions remain checked.
static func evaluate_dynamics(rpm: Variant, duty: Variant, soc: Variant, pack: Variant, motor: Variant,
		enabled: Variant = true, available_at_zero: bool = false) -> Dictionary:
	return _evaluate(rpm, duty, soc, pack, motor, enabled, available_at_zero, true)


static func _evaluate(rpm: Variant, duty: Variant, soc: Variant, pack: Variant, motor: Variant,
		enabled: Variant, available_at_zero: bool, dynamics_only: bool = false) -> Dictionary:
	if not _is_number(rpm) or not is_finite(float(rpm)) or float(rpm) < 0.0:
		return _failure("rpm must be a finite number >= 0")
	if not _is_number(duty) or not is_finite(float(duty)) or float(duty) < 0.0 or float(duty) > 1.0:
		return _failure("duty must be a finite number in [0,1]")
	if not _is_number(soc) or not is_finite(float(soc)) or float(soc) < 0.0 or float(soc) > 1.0:
		return _failure("soc must be a finite number in [0,1]")
	if typeof(enabled) != TYPE_BOOL:
		return _failure("enabled must be a boolean")

	var pack_validation: Dictionary = _validate_pack(pack)
	if not pack_validation.ok:
		return _failure(str(pack_validation.message))
	var motor_validation: Dictionary = _validate_motor(motor)
	if not motor_validation.ok:
		return _failure(str(motor_validation.message))

	var rpm_value: float = float(rpm)
	var requested_duty: float = float(duty)
	var soc_value: float = float(soc)
	var capacity_ah: float = float(pack_validation.capacity_ah)
	var pack_resistance_ohm: float = float(pack_validation.resistance_ohm)
	var auxiliary_demand_a: float = float(pack_validation.auxiliary_current_a)
	var ocv: float = _interpolate_ocv(pack_validation.ocv_points, soc_value)
	if not is_finite(ocv) or ocv <= 0.0:
		return _failure("OCV interpolation did not produce a finite positive voltage")

	if soc_value == 0.0 and not available_at_zero:
		var exhausted_source: Dictionary = Electric._evaluate_validated(rpm_value, requested_duty, 0.0,
			motor_validation.kv_rpm_per_volt, motor_validation.resistance_ohm,
			motor_validation.no_load_current_a, false, dynamics_only)
		if not exhausted_source.ok:
			return _failure("source evaluation failed: " + str(exhausted_source.message))
		return _assemble_result("exhausted", rpm_value, requested_duty, 0.0, soc_value, ocv,
			capacity_ah, pack_resistance_ohm, auxiliary_demand_a, 0.0, 0.0, 0.0, 0.0,
			exhausted_source, dynamics_only)

	var effective_duty: float = requested_duty if enabled else 0.0
	var back_emf_v: float = rpm_value / float(motor_validation.kv_rpm_per_volt)
	var motor_resistance_ohm: float = float(motor_validation.resistance_ohm)
	if not is_finite(back_emf_v):
		return _failure("back EMF overflowed")

	# Auxiliary current is pack-side. Its sag is included before solving motor current.
	var auxiliary_voltage_drop_v: float = pack_resistance_ohm * auxiliary_demand_a
	var bus_without_motor_v: float = ocv - auxiliary_voltage_drop_v
	if not is_finite(auxiliary_voltage_drop_v) or not is_finite(bus_without_motor_v) or bus_without_motor_v <= 0.0:
		return _failure("auxiliary load leaves no positive feasible bus voltage")

	# Solving Im = max((d*Vbus-E)/Rm, 0) and Vbus = OCV-Rpack*(d*Im+Iaux)
	# gives this closed form. The d^2 term follows from both ESC voltage and current conversion.
	var duty_squared: float = effective_duty * effective_duty
	var denominator: float = motor_resistance_ohm + duty_squared * pack_resistance_ohm
	var numerator: float = effective_duty * bus_without_motor_v - back_emf_v
	if not is_finite(denominator) or denominator <= 0.0 or not is_finite(numerator):
		return _failure("battery/motor current solve overflowed or became invalid")
	var solved_motor_current_a: float = numerator / denominator if effective_duty > 0.0 and numerator > 0.0 else 0.0
	if not is_finite(solved_motor_current_a) or solved_motor_current_a < 0.0:
		return _failure("solved motor current is invalid")
	var solved_motor_bus_current_a: float = effective_duty * solved_motor_current_a
	var solved_pack_current_a: float = solved_motor_bus_current_a + auxiliary_demand_a
	var bus_voltage_v: float = ocv - pack_resistance_ohm * solved_pack_current_a
	if not is_finite(solved_motor_bus_current_a) or not is_finite(solved_pack_current_a) \
			or not is_finite(bus_voltage_v) or bus_voltage_v <= 0.0:
		return _failure("battery sag leaves no positive feasible bus voltage")

	var source: Dictionary = Electric._evaluate_validated(rpm_value, requested_duty, bus_voltage_v,
		motor_validation.kv_rpm_per_volt, motor_validation.resistance_ohm,
		motor_validation.no_load_current_a, enabled, dynamics_only)
	if not source.ok:
		return _failure("source evaluation failed: " + str(source.message))
	var source_motor_current_a: float = float(source.motor_current_a)
	var source_bus_current_a: float = float(source.battery_current_a)
	var current_scale: float = maxf(1.0, maxf(absf(solved_motor_current_a), absf(source_motor_current_a)))
	var current_tolerance: float = 1e-11 * current_scale
	if absf(source_motor_current_a - solved_motor_current_a) > current_tolerance \
			or absf(source_bus_current_a - solved_motor_bus_current_a) > current_tolerance:
		return _failure("closed-form battery solution disagrees with source current")

	return _assemble_result(str(source.mode), rpm_value, requested_duty, effective_duty, soc_value, ocv,
		capacity_ah, pack_resistance_ohm, auxiliary_demand_a, source_motor_current_a,
		source_bus_current_a, auxiliary_demand_a, bus_voltage_v, source, dynamics_only)


static func _validate_pack(raw_pack: Variant) -> Dictionary:
	if typeof(raw_pack) != TYPE_DICTIONARY:
		return _failure("pack must be a dictionary")
	var pack: Dictionary = raw_pack
	for key: String in PACK_KEYS:
		if not pack.has(key):
			return _failure("pack is missing " + key)
	for key: Variant in pack:
		if key not in PACK_KEYS:
			return _failure("pack has unsupported field " + str(key))

	var raw_points: Variant = pack.get("ocv_points")
	if typeof(raw_points) != TYPE_PACKED_FLOAT64_ARRAY:
		return _failure("pack.ocv_points must be PackedFloat64Array([SOC, V, ...])")
	var points: PackedFloat64Array = PackedFloat64Array(raw_points)
	if points.size() < 4 or points.size() % 2 != 0:
		return _failure("pack.ocv_points needs at least two SOC/voltage pairs")
	for index: int in range(0, points.size(), 2):
		var knot_soc: float = points[index]
		var knot_voltage: float = points[index + 1]
		if not is_finite(knot_soc) or not is_finite(knot_voltage):
			return _failure("pack.ocv_points values must be finite")
		if knot_voltage <= 0.0:
			return _failure("pack OCV voltages must be positive")
		if knot_soc < 0.0 or knot_soc > 1.0:
			return _failure("pack OCV SOC knots must be in [0,1]")
		if index > 0:
			var previous_soc: float = points[index - 2]
			var previous_voltage: float = points[index - 1]
			if knot_soc <= previous_soc:
				return _failure("pack OCV SOC knots must be strictly increasing")
			if knot_voltage < previous_voltage:
				return _failure("pack OCV voltage must be nondecreasing with SOC")
	if points[0] != 0.0 or points[points.size() - 2] != 1.0:
		return _failure("pack OCV curve must cover SOC [0,1] exactly")

	if not _is_number(pack.get("capacity_ah")) or not is_finite(float(pack.capacity_ah)) \
			or float(pack.capacity_ah) <= 0.0:
		return _failure("pack.capacity_ah must be finite and > 0")
	var capacity_c: float = 3600.0 * float(pack.capacity_ah)
	if not is_finite(capacity_c) or capacity_c <= 0.0:
		return _failure("pack capacity in coulombs must be finite and > 0")
	if not _is_number(pack.get("resistance_ohm")) or not is_finite(float(pack.resistance_ohm)) \
			or float(pack.resistance_ohm) < 0.0:
		return _failure("pack.resistance_ohm must be finite and >= 0")
	if not _is_number(pack.get("auxiliary_current_a")) or not is_finite(float(pack.auxiliary_current_a)) \
			or float(pack.auxiliary_current_a) < 0.0:
		return _failure("pack.auxiliary_current_a must be finite and >= 0")

	return {
		"ok": true,
		"message": "",
		"ocv_points": points,
		"capacity_ah": float(pack.capacity_ah),
		"resistance_ohm": float(pack.resistance_ohm),
		"auxiliary_current_a": float(pack.auxiliary_current_a),
	}


static func _validate_motor(raw_motor: Variant) -> Dictionary:
	if typeof(raw_motor) != TYPE_DICTIONARY:
		return _failure("motor must be a dictionary")
	var motor: Dictionary = raw_motor
	for key: String in MOTOR_KEYS:
		if not motor.has(key) or not _is_number(motor.get(key)) or not is_finite(float(motor.get(key))):
			return _failure("motor needs finite numeric " + key)
	for key: Variant in motor:
		if key not in MOTOR_KEYS:
			return _failure("motor has unsupported field " + str(key))
	var kv: float = float(motor.kv_rpm_per_volt)
	var resistance: float = float(motor.resistance_ohm)
	var no_load_current: float = float(motor.no_load_current_a)
	if kv <= 0.0 or resistance <= 0.0 or no_load_current < 0.0:
		return _failure("motor requires Kv > 0, R > 0 and I0 >= 0")
	return {"ok": true, "message": "", "kv_rpm_per_volt": kv, "resistance_ohm": resistance,
		"no_load_current_a": no_load_current}


static func _interpolate_ocv(points: PackedFloat64Array, soc: float) -> float:
	if soc <= 0.0:
		return points[1]
	if soc >= 1.0:
		return points[points.size() - 1]
	for index: int in range(0, points.size() - 2, 2):
		var left_soc: float = points[index]
		var right_soc: float = points[index + 2]
		if soc <= right_soc:
			var fraction: float = (soc - left_soc) / (right_soc - left_soc)
			return points[index + 1] + fraction * (points[index + 3] - points[index + 1])
	return NAN


static func _assemble_result(mode: String, rpm: float, requested_duty: float, effective_duty: float,
		soc: float, ocv: float, capacity_ah: float, pack_resistance_ohm: float,
		auxiliary_demand_a: float, motor_current_a: float, motor_bus_current_a: float,
		auxiliary_current_a: float, bus_voltage_v: float, source: Dictionary,
		dynamics_only: bool = false) -> Dictionary:
	var pack_current_a: float = motor_bus_current_a + auxiliary_current_a
	var soc_rate_per_s: float = -pack_current_a / (3600.0 * capacity_ah)
	var pack_terminal_power_w: float = bus_voltage_v * pack_current_a
	var pack_loss_w: float = (pack_resistance_ohm * pack_current_a) * pack_current_a \
		if pack_resistance_ohm > 0.0 else 0.0
	var pack_open_circuit_power_w: float = ocv * pack_current_a
	var power_balance_residual_w: float = pack_open_circuit_power_w - pack_terminal_power_w - pack_loss_w
	# Every other result scalar was validated on entry or by the motor. Check all newly
	# computed diagnostics even on the compact path, so overflow still refuses the tick.
	var finite_result: bool = is_finite(pack_current_a) and is_finite(soc_rate_per_s) \
			and is_finite(pack_terminal_power_w) and is_finite(pack_loss_w) \
			and is_finite(pack_open_circuit_power_w) and is_finite(power_balance_residual_w)
	# Match the full result's insertion-order diagnostic when the compact motor omitted telemetry.
	# `energy_rate_j_per_s` is the first result field backed by pack_terminal_power_w.
	if dynamics_only and not finite_result:
		if not is_finite(pack_current_a):
			return _failure("battery evaluation overflow: pack_current_a")
		if not is_finite(soc_rate_per_s):
			return _failure("battery evaluation overflow: soc_rate_per_s")
		if not is_finite(pack_terminal_power_w):
			return _failure("battery evaluation overflow: energy_rate_j_per_s")
		if not is_finite(pack_open_circuit_power_w):
			return _failure("battery evaluation overflow: pack_open_circuit_power_w")
		if not is_finite(pack_loss_w):
			return _failure("battery evaluation overflow: pack_loss_w")
		if not is_finite(power_balance_residual_w):
			return _failure("battery evaluation overflow: pack_power_balance_residual_w")
	if dynamics_only and finite_result:
		return {"ok": true, "shaft_torque_nm": float(source.shaft_torque_nm),
			"motor_current_a": motor_current_a, "pack_current_a": pack_current_a,
			"pack_terminal_power_w": pack_terminal_power_w, "pack_loss_w": pack_loss_w}
	var result: Dictionary = {
		"ok": true,
		"mode": mode,
		"rpm": rpm,
		"soc": soc,
		"requested_duty": requested_duty,
		"effective_duty": effective_duty,
		"ocv_v": ocv,
		"bus_voltage_v": bus_voltage_v,
		"motor_current_a": motor_current_a,
		"motor_bus_current_a": motor_bus_current_a,
		"auxiliary_demand_a": auxiliary_demand_a,
		"auxiliary_current_a": auxiliary_current_a,
		"pack_current_a": pack_current_a,
		"soc_rate_per_s": soc_rate_per_s,
		"charge_rate_coulombs_per_s": pack_current_a,
		"energy_rate_j_per_s": pack_terminal_power_w,
		"motor_bus_power_w": float(source.bus_power_w),
		"shaft_torque_nm": float(source.shaft_torque_nm),
		"shaft_power_w": float(source.shaft_power_w),
		"motor_copper_loss_w": float(source.copper_loss_w),
		"motor_rotational_loss_w": float(source.rotational_loss_w),
		"pack_terminal_power_w": pack_terminal_power_w,
		"pack_open_circuit_power_w": pack_open_circuit_power_w,
		"pack_loss_w": pack_loss_w,
		"pack_power_balance_residual_w": power_balance_residual_w,
		"source": source,
	}
	if finite_result:
		return result
	for key: Variant in result:
		if typeof(result[key]) == TYPE_FLOAT and not is_finite(float(result[key])):
			return _failure("battery evaluation overflow: " + str(key))
	return result


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
