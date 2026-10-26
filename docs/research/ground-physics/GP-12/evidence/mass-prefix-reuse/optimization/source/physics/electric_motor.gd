# EL1a: pure direct-drive DC-equivalent motor + ideal motoring ESC at prescribed bus voltage.
# All inputs/outputs are float64 SI except rpm and Kv (rpm/V). No aircraft-specific constants.
# See docs/research/propulsion/EL1a: no regeneration, active brake, current limit or battery state.
extends RefCounted


## motor contains normalized kv_rpm_per_volt, resistance_ohm, no_load_current_a.
## duty is the effective ESC command, not a transmitter pulse or a governed RPM demand.
## Invalid inputs return only {ok=false, message}; callers must reject the evaluation.
static func evaluate(rpm: float, duty: float, bus_voltage_v: float, motor: Dictionary,
		enabled: bool = true) -> Dictionary:
	for key: String in ["kv_rpm_per_volt", "resistance_ohm", "no_load_current_a"]:
		if not motor.has(key) or typeof(motor[key]) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("motor needs numeric " + key)
		if not is_finite(float(motor[key])):
			return _failure("motor needs finite " + key)
	var kv: float = motor.kv_rpm_per_volt
	var resistance: float = motor.resistance_ohm
	var idle_current: float = motor.no_load_current_a
	if kv <= 0.0 or resistance <= 0.0 or idle_current < 0.0:
		return _failure("motor requires Kv > 0, R > 0 and I0 >= 0")
	return _evaluate_validated(rpm, duty, bus_voltage_v, kv, resistance, idle_current, enabled)


## Internal scalar kernel. Callers must have checked the finite Kv/R/I0 domains in this call.
## Supply shares its stricter motor validation; no cache or unchecked public entry is used.
static func _evaluate_validated(rpm: float, duty: float, bus_voltage_v: float, kv: float,
		resistance: float, idle_current: float, enabled: bool, compact: bool = false) -> Dictionary:
	if not is_finite(rpm) or rpm < 0.0 or not is_finite(duty) or duty < 0.0 or duty > 1.0 \
			or not is_finite(bus_voltage_v) or bus_voltage_v < 0.0:
		return _failure("motor requires finite rpm >= 0, duty in [0,1] and bus voltage >= 0")

	# kt is N*m/A, reciprocal of Kv converted to rad/s/V (Drela K_Q = K_V).
	var kt: float = 60.0 / TAU / kv
	var omega: float = rpm * (TAU / 60.0)
	var back_emf: float = rpm / kv
	var effective_duty: float = duty if enabled else 0.0
	var command_voltage: float = effective_duty * bus_voltage_v
	# Explicit one-quadrant approximation: disconnected when commanded off or overrun.
	var current: float = maxf(0.0, (command_voltage - back_emf) / resistance) if effective_duty > 0.0 else 0.0
	var electromagnetic_torque: float = kt * current
	var loss_torque: float = kt * idle_current
	if not is_finite(kt) or kt <= 0.0 or not is_finite(loss_torque):
		return _failure("motor constants overflow or underflow")
	if rpm == 0.0:
		# Coulomb-loss extension at rest: friction cannot start the shaft backwards.
		loss_torque = minf(loss_torque, electromagnetic_torque)
	var torque: float = electromagnetic_torque - loss_torque
	var battery_current: float = effective_duty * current
	var motor_voltage: float = command_voltage if current > 0.0 else back_emf
	var shaft_power: float = torque * omega
	var bus_power: float = bus_voltage_v * battery_current
	var copper_loss: float = (current * resistance) * current
	var rotational_loss: float = loss_torque * omega
	var mode: String = "drive" if current > 0.0 else ("coast" if rpm > 0.0 else "stopped")
	# Scalar success guard avoids reflective Dictionary iteration in every RK stage.
	# Compact callers need only these values; invalid arithmetic still takes the full diagnostic path.
	var finite_outputs: bool = is_finite(command_voltage) and is_finite(motor_voltage) and is_finite(back_emf) \
			and is_finite(current) and is_finite(battery_current) and is_finite(torque) \
			and is_finite(shaft_power) and is_finite(bus_power) and is_finite(copper_loss) \
			and is_finite(rotational_loss)
	if compact and finite_outputs:
		return {ok = true, mode = mode, shaft_torque_nm = torque,
			motor_current_a = current, battery_current_a = battery_current}
	var result: Dictionary = {
		ok = true,
		mode = mode,
		duty = effective_duty,
		command_voltage_v = command_voltage,
		motor_voltage_v = motor_voltage,
		back_emf_v = back_emf,
		motor_current_a = current,
		battery_current_a = battery_current,
		shaft_torque_nm = torque,
		shaft_power_w = shaft_power,
		bus_power_w = bus_power,
		copper_loss_w = copper_loss,
		rotational_loss_w = rotational_loss,
	}
	# Keep the diagnostic slow path below to preserve the first offending field/message.
	if finite_outputs:
		return result
	# Finite inputs can overflow, including in the zero-speed torque path. Never return a valid NaN/Inf.
	for key: String in result:
		if typeof(result[key]) == TYPE_FLOAT and not is_finite(float(result[key])):
			return _failure("motor evaluation overflow: " + key)
	return result


static func _failure(message: String) -> Dictionary:
	return {ok = false, message = message}
