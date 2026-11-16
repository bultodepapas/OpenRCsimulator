# Loaded four-motor hover admission. This is a frozen-SOC operating point, not sustained flight, a battery
# endurance estimate, or a controller/stability guarantee. The caller independently solves the static wrench
# balance and passes its four required rotor thrusts; this helper does not trust cached derived values.
#
# The electrical shaft friction law is shared with controlled_plant.gd: the plant should alias its existing
# FRICTION_SPEED constant to this constant so the admission calculation and the running law cannot drift.
#
# A polarization resistance represents steady-state voltage loss here: Rp = R0 + R1. The polarization time
# constant is irrelevant to a settled operating point and is validated separately by the data boundary. A missing
# R1 means zero, preserving older prepared documents. This helper neither mutates its inputs nor changes the
# separately defined open-circuit single-motor diagnostics.
extends RefCounted

const BatteryPack := preload("res://physics/multirotor/battery_pack.gd")

const FRICTION_SPEED := 30.0
const LAW_ELECTRIC := "el-one-quadrant-bus-v1"
## Relative residual bound on voltage, current and shaft torque. A tiny floor avoids division by zero; failure to
## resolve a very small current in the bus equation refuses the point instead of claiming a false equilibrium.
const RESIDUAL_TOLERANCE := 1.0e-9
const RESIDUAL_FLOOR := 1.0e-12


## Solve {rotor_law, powertrain, battery}, four hover thrusts [N], and pack open-circuit voltage [V].
##
## Required normalized rotor_law keys: thrust_coefficient_n_s2, torque_coefficient_n_m_s2, max_speed_rad_s.
## Powertrain keys: law, braking, kv_rad_s_per_v, resistance_ohm, no_load_current_a, idle_command, max_command.
## Battery keys: resistance_ohm (R0), auxiliary_current_a, optionally polarization_resistance_ohm (R1).
##
## At positive hover speed every motor has positive current, so the one-quadrant and damped bridge laws agree.
## For each motor, I = Kv*kQ*w² + I0*clamp(w/FRICTION_SPEED, 0, 1), and U = w/Kv + Rm*I. Pack balance gives
## V² - (Voc - Rp*Iaux)*V + Rp*sum(U*I) = 0. We select the high-voltage root and require positive discriminant:
## equality is an algebraic solution with zero power margin and is deliberately refused for admission.
##
## Both success and failure return {ok, message, v_bus, i_pack, duty, speeds, currents}. On failure, voltage and
## current are NAN and the three packed arrays are empty; never consume them when ok is false.
static func solve(data: Dictionary, hover_thrusts: PackedFloat64Array, voc: float) -> Dictionary:
	var rotor_value: Variant = data.get("rotor_law")
	var motor_value: Variant = data.get("powertrain")
	var battery_value: Variant = data.get("battery")
	if typeof(rotor_value) != TYPE_DICTIONARY or typeof(motor_value) != TYPE_DICTIONARY \
			or typeof(battery_value) != TYPE_DICTIONARY:
		return _failure("hover: normalized rotor_law, powertrain and battery blocks are required")
	var rotor: Dictionary = rotor_value
	var motor: Dictionary = motor_value
	var battery: Dictionary = battery_value
	if motor.get("law") != LAW_ELECTRIC or motor.get("braking") not in ["none", "damped_nonregenerative"]:
		return _failure("hover: supported electrical law and braking setting required")
	if not is_finite(voc) or voc <= 0.0:
		return _failure("hover: open-circuit voltage must be finite and positive")
	if hover_thrusts.size() != 4:
		return _failure("hover: four required rotor thrusts are required")
	for key: String in ["thrust_coefficient_n_s2", "torque_coefficient_n_m_s2", "max_speed_rad_s"]:
		if not _positive(rotor.get(key)):
			return _failure("hover: rotor_law.%s must be finite and positive" % key)
	for key: String in ["kv_rad_s_per_v", "resistance_ohm"]:
		if not _positive(motor.get(key)):
			return _failure("hover: powertrain.%s must be finite and positive" % key)
	if not _nonnegative(motor.get("no_load_current_a")):
		return _failure("hover: powertrain.no_load_current_a must be finite and nonnegative")
	if not _number(motor.get("idle_command")) or not _number(motor.get("max_command")):
		return _failure("hover: powertrain command bounds must be finite")
	var idle := float(motor.idle_command)
	var top := float(motor.max_command)
	if idle < 0.0 or idle >= top or top > 1.0:
		return _failure("hover: command bounds must satisfy 0 <= idle < max <= 1")
	if not _nonnegative(battery.get("resistance_ohm")) or not _nonnegative(battery.get("auxiliary_current_a")):
		return _failure("hover: battery resistance and auxiliary current must be finite and nonnegative")
	if battery.has("polarization_resistance_ohm") and not _nonnegative(battery.polarization_resistance_ohm):
		return _failure("hover: battery.polarization_resistance_ohm must be finite and nonnegative")

	var integration_error: String = BatteryPack.integration_error(battery, motor)
	if not integration_error.is_empty():
		return _failure(integration_error)

	var k_t := float(rotor.thrust_coefficient_n_s2)
	var k_q := float(rotor.torque_coefficient_n_m_s2)
	var speed_limit := float(rotor.max_speed_rad_s)
	var kv := float(motor.kv_rad_s_per_v)
	var motor_resistance := float(motor.resistance_ohm)
	var no_load := float(motor.no_load_current_a)
	var pack_resistance := float(battery.resistance_ohm) + float(battery.get("polarization_resistance_ohm", 0.0))
	var auxiliary := float(battery.auxiliary_current_a)
	if not is_finite(pack_resistance):
		return _failure("hover: total battery resistance is not finite")

	var speeds := PackedFloat64Array()
	var currents := PackedFloat64Array()
	var emf := PackedFloat64Array()
	var motor_voltage := PackedFloat64Array()
	var required_power := 0.0
	for i in 4:
		var thrust: float = hover_thrusts[i]
		if not is_finite(thrust) or thrust <= 0.0:
			return _failure("hover: rotor %d requires finite positive thrust" % (i + 1))
		var speed_squared: float = thrust / k_t
		if not is_finite(speed_squared) or speed_squared <= 0.0:
			return _failure("hover: rotor %d speed is not finite and positive" % (i + 1))
		var speed := sqrt(speed_squared)
		if speed > speed_limit:
			return _failure("hover: rotor %d speed %s rad/s exceeds limit %s rad/s" % [i + 1, speed, speed_limit])
		var current: float = (k_q * speed_squared) * kv + no_load * clampf(speed / FRICTION_SPEED, 0.0, 1.0)
		var back_emf: float = speed / kv
		var voltage: float = back_emf + motor_resistance * current
		if not is_finite(current) or current <= 0.0 or not is_finite(back_emf) or back_emf <= 0.0 \
				or not is_finite(voltage) or voltage <= 0.0:
			return _failure("hover: rotor %d motor current or voltage is not finite and positive" % (i + 1))
		var power: float = voltage * current
		required_power += power
		if not is_finite(power) or power <= 0.0 or not is_finite(required_power):
			return _failure("hover: required motor power is not finite and positive")
		speeds.append(speed)
		currents.append(current)
		emf.append(back_emf)
		motor_voltage.append(voltage)

	var available := voc - pack_resistance * auxiliary
	if not is_finite(available) or available <= 0.0:
		return _failure("hover: auxiliary load leaves no positive unloaded bus voltage")
	var discriminant := available * available - 4.0 * pack_resistance * required_power
	if not is_finite(discriminant):
		return _failure("hover: loaded bus discriminant is not finite")
	if discriminant < 0.0:
		return _failure("hover: pack cannot supply the required motor power")
	if discriminant == 0.0:
		return _failure("hover: pack operates at the zero-margin power limit")
	var voltage_bus := 0.5 * (available + sqrt(discriminant))
	if not is_finite(voltage_bus) or voltage_bus <= 0.0:
		return _failure("hover: high-voltage bus root is not finite and positive")

	var duty := PackedFloat64Array()
	for i in 4:
		var command: float = motor_voltage[i] / voltage_bus
		if not is_finite(command) or command <= idle or command >= top:
			return _failure("hover: rotor %d duty %s must lie strictly between idle %s and max %s" % [i + 1, command, idle, top])
		duty.append(command)

	# Reconstruct the running plant's four-positive-current bus, rather than accepting the power bound alone.
	# It is the same closed-form bus used by the damped bridge and by the all-active one-quadrant branch.
	var numerator := available
	var denominator := 1.0
	for i in 4:
		numerator += pack_resistance * duty[i] * emf[i] / motor_resistance
		denominator += pack_resistance * duty[i] * duty[i] / motor_resistance
	if not is_finite(numerator) or not is_finite(denominator) or denominator <= 0.0:
		return _failure("hover: reconstructed bus coefficients are not finite")
	var bus_check := numerator / denominator
	if not is_finite(bus_check) or not _close(bus_check, voltage_bus):
		return _failure("hover: high-voltage branch fails the bus voltage residual")
	var pack_current := auxiliary
	for i in 4:
		var resolved_current: float = (duty[i] * bus_check - emf[i]) / motor_resistance
		if not is_finite(resolved_current) or resolved_current <= 0.0 or not _close(resolved_current, currents[i]):
			return _failure("hover: rotor %d is not on the positive-current branch or fails the motor residual" % (i + 1))
		var motor_torque: float = resolved_current / kv
		var friction: float = (no_load / kv) * clampf(speeds[i] / FRICTION_SPEED, 0.0, 1.0)
		var aero_torque: float = k_q * speeds[i] * speeds[i]
		if not is_finite(motor_torque) or not is_finite(friction) or not is_finite(aero_torque) \
				or not _close(motor_torque, friction + aero_torque):
			return _failure("hover: rotor %d fails the shaft-torque residual" % (i + 1))
		pack_current += duty[i] * resolved_current
	if not is_finite(pack_current) or not _close(voltage_bus, voc - pack_resistance * pack_current):
		return _failure("hover: pack fails the voltage/current residual")
	return {ok = true, message = "", v_bus = voltage_bus, i_pack = pack_current,
		duty = duty, speeds = speeds, currents = currents}


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0


static func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0


static func _close(value: float, expected: float) -> bool:
	return is_finite(value) and is_finite(expected) \
		and absf(value - expected) <= RESIDUAL_TOLERANCE * maxf(absf(expected), RESIDUAL_FLOOR)


static func _failure(message: String) -> Dictionary:
	return {ok = false, message = message, v_bus = NAN, i_pack = NAN, duty = PackedFloat64Array(),
		speeds = PackedFloat64Array(), currents = PackedFloat64Array()}
