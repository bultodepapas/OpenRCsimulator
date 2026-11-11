# DR-07/14/15: the simulator-owned multirotor flight controller as ONE pure sampled law.
# sample(config, frame, input, clock, supply_voltage) reads the accepted frame of a tick and returns the
# candidate sampled block and discrete modes; it holds no memory of its own. Every integrator, filter, held motor
# command and arming latch lives in the kernel's checkpointed aux/modes arrays (DR-16a framed protocol), so a
# refused tick, a reset and a restore carry or discard them together with the body.
#
# Order per sample (FPV engineering contracts §3): source/arm/mode boundary, throttle policy, one rates mapping,
# ideal gyro sample and digital filters, torque request, bounded allocation and held motor commands, then the next
# integrator with back-calculation anti-windup. tau_req,k uses I_k; the returned block stores I_(k+1) with u_k.
#
# Declared idealizations and limits: the gyro and attitude are the accepted body state (no sensor noise, bias or
# delay); filters are first-order with alpha = 1 − exp(−2·pi·f_c·T_s); the derivative acts on the filtered
# measurement; an optional first-order setpoint low-pass and acceleration feed-forward on the smoothed setpoint
# (its memory is the previous-setpoint slots; both default to off); Airmode is always active while armed
# (moments keep priority through the allocator weights, so collective may rise above a low throttle); the
# integrator freezes while the collective is at or below the arming threshold. This is a simulator controller,
# not Betaflight: familiar names do not establish firmware equivalence. 64-bit floats only.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const Allocator := preload("res://physics/multirotor/allocator.gd")
const ActuatorMap := preload("res://physics/multirotor/actuator_map.gd")

const LAW := "openrc-fc-acro-angle-v1"
const SAMPLE_HZ := 240

## Pilot frame, flattened: the kernel's input array. Sticks are calibrated and PRE-expo; the rates law is the only
## shaping. Pitch > 0 is stick back (nose up, positive q); roll > 0 right; yaw > 0 right.
const INPUT_SIZE := 9
const IN_ROLL := 0
const IN_PITCH := 1
const IN_YAW := 2
const IN_THROTTLE := 3 # absolute policy: [0, 1]; rate policy: [-1, 1]
const IN_ARM := 4 # 0 or 1 (level of the arm switch)
const IN_MODE := 5 # requested flight mode
const IN_SOURCE_GENERATION := 6 # integer >= 0; a new connection is a new generation
const IN_SOURCE_READY := 7 # 0 or 1
const IN_ACTIONS := 8 # bit field of ACTION_*
const ACTION_THROTTLE_RESET := 1 # rate policy: zero the virtual throttle before this sample
const ACTION_RECOVERY := 2 # the session attests OFF then ON at low throttle in the new source generation

## Sampled block (FPV engineering contracts §4, 31 values).
const AUX_SIZE := 31
const AUX_INTEGRAL := 0 # N·m
const AUX_GYRO := 3 # rad/s, filtered measurement memory
const AUX_DTERM := 6 # rad/s², filtered measurement derivative memory
const AUX_PREVIOUS_SETPOINT := 9 # rad/s, reserved for feed-forward
const AUX_COMMAND := 12 # four held actuator commands of the accepted sample
const AUX_TAU_REQUEST := 16 # N·m
const AUX_TAU_ALLOCATED := 19 # N·m, static command prediction
const AUX_SETPOINT := 22 # rad/s
const AUX_COLLECTIVE := 25 # [0, 1] after the throttle policy
const AUX_THRUST_TARGET := 26 # four allocated thrust targets, N
const AUX_VIRTUAL_THROTTLE := 30 # [0, 1], rate policy accumulator

const MODES_SIZE := 8
const MODE_MOTOR := 0
const MODE_FLIGHT := 1
const MODE_PREVIOUS_ARM := 2
const MODE_OFF_OBSERVED := 3
const MODE_SOURCE_GENERATION := 4
const MODE_FILTER_READY := 5
const MODE_ARM_BLOCK := 6
const MODE_SAMPLES := 7 # accepted sample count since reset (the committed command cursor)

const MOTOR_DISARMED := 0
const MOTOR_ARMED := 1
const MOTOR_CRASHED := 2
const MOTOR_DEPLETED := 3
const FLIGHT_ACRO := 0
const FLIGHT_ANGLE := 1
const BLOCK_NONE := 0
const BLOCK_THROTTLE := 1 # throttle was not low at the ON edge
const BLOCK_SWITCH := 2 # no OFF observed in this source generation, or the switch was held ON
const BLOCK_SOURCE := 3 # the input source is not ready
const BLOCK_TERMINAL := 4 # crashed or depleted: only a pad reset clears it
const THROTTLE_ABSOLUTE := 0
const THROTTLE_RATE := 1


## Build the immutable-by-convention controller configuration.
## controller: the `controller` block of a prepared multirotor document (SI gains).
## rates: Rates.prepare(...).prepared; allocator: Allocator.prepare(...); actuator: ActuatorMap.prepare(...).map.
## research_sample_hz > 0 is the DR-09a qualification seam: the same law prepared for a kernel stepped at another
## rate (960 or 1920 Hz reference runs, every sample with fresh feedback). It changes the identity and is never a
## product schedule; data admits 240 Hz only.
static func prepare(controller: Dictionary, rates: Dictionary, allocator: Dictionary, actuator: Dictionary,
		throttle_policy: int, research_sample_hz: int = 0, throttle_limit: float = 1.0) -> Dictionary:
	var errors := PackedStringArray()
	var sample_hz: int = research_sample_hz if research_sample_hz > 0 else SAMPLE_HZ
	if int(controller.get("sample_hz", 0)) != SAMPLE_HZ:
		errors.append("controller: only the %d Hz sample schedule is admitted" % SAMPLE_HZ)
	for key: String in ["kp", "ki", "kd", "i_max", "kaw", "tau_limit"]:
		var values: Variant = controller.get(key)
		if typeof(values) != TYPE_PACKED_FLOAT64_ARRAY or values.size() != 3:
			errors.append("controller.%s: three values required" % key)
			continue
		for value: float in values:
			if not is_finite(value) or value < 0.0:
				errors.append("controller.%s: values must be finite and nonnegative" % key)
	var nyquist: float = 0.5 * float(sample_hz)
	for key: String in ["gyro_lpf_hz", "dterm_lpf_hz"]:
		var cutoff: float = float(controller.get(key, NAN))
		if not is_finite(cutoff) or cutoff <= 0.0 or cutoff >= nyquist:
			errors.append("controller.%s: cutoff must lie strictly between 0 and the %.0f Hz Nyquist frequency" % [key, nyquist])
	for key: String in ["angle_max_tilt_rad", "angle_gain_per_s", "angle_rate_limit_rad_s", "arm_low_throttle", "throttle_rate_per_s"]:
		var value: float = float(controller.get(key, NAN))
		if not is_finite(value) or value <= 0.0:
			errors.append("controller.%s: must be finite and positive" % key)
	# Optional stick-response shaping: a first-order setpoint low-pass and an acceleration feed-forward on the
	# smoothed setpoint (N·m per rad/s² of commanded angular acceleration). Absent keys mean no smoothing, no FF.
	var kff: Variant = controller.get("kff", PackedFloat64Array([0.0, 0.0, 0.0]))
	if typeof(kff) != TYPE_PACKED_FLOAT64_ARRAY or kff.size() != 3:
		errors.append("controller.kff: three values required")
		kff = PackedFloat64Array([0.0, 0.0, 0.0])
	for value: float in kff:
		if not is_finite(value) or value < 0.0:
			errors.append("controller.kff: values must be finite and nonnegative")
	var setpoint_cutoff: float = float(controller.get("setpoint_lpf_hz", 0.0))
	if not is_finite(setpoint_cutoff) or setpoint_cutoff < 0.0 or setpoint_cutoff >= nyquist:
		errors.append("controller.setpoint_lpf_hz: cutoff must be 0 (off) or lie below the %.0f Hz Nyquist frequency" % nyquist)
	# Pilot preference: the fraction of the command range a full throttle stick reaches (a training aid for
	# keyboard and gamepad; a radio flies the full range). It scales the collective only, never the arming check.
	if not is_finite(throttle_limit) or throttle_limit < 0.2 or throttle_limit > 1.0:
		errors.append("controller: throttle limit must lie in 0.2..1")
	if throttle_policy not in [THROTTLE_ABSOLUTE, THROTTLE_RATE]:
		errors.append("controller: unknown throttle policy")
	if not allocator.get("ok", false):
		errors.append("controller: the allocator is not prepared")
	if not rates.has("identity"):
		errors.append("controller: the rates profile is not prepared")
	if not errors.is_empty():
		return {ok = false, errors = errors, config = {}}
	var period: float = 1.0 / float(sample_hz)
	var config := {
		law = LAW, period_s = period, sample_hz = sample_hz,
		kp = controller.kp.duplicate(), ki = controller.ki.duplicate(), kd = controller.kd.duplicate(),
		i_max = controller.i_max.duplicate(), kaw = controller.kaw.duplicate(), tau_limit = controller.tau_limit.duplicate(),
		gyro_alpha = 1.0 - exp(-TAU * float(controller.gyro_lpf_hz) * period),
		dterm_alpha = 1.0 - exp(-TAU * float(controller.dterm_lpf_hz) * period),
		kff = kff.duplicate(), setpoint_alpha = 1.0 if setpoint_cutoff == 0.0 else 1.0 - exp(-TAU * setpoint_cutoff * period),
		angle_max_tilt = float(controller.angle_max_tilt_rad), angle_gain = float(controller.angle_gain_per_s),
		angle_rate_limit = float(controller.angle_rate_limit_rad_s),
		arm_low_throttle = float(controller.arm_low_throttle), throttle_rate = float(controller.throttle_rate_per_s),
		throttle_policy = throttle_policy, throttle_limit = throttle_limit, rates = rates, allocator = allocator, actuator = actuator,
	}
	config.identity = var_to_bytes([LAW, sample_hz, config.kp, config.ki, config.kd, config.i_max, config.kaw,
		config.tau_limit, float(controller.gyro_lpf_hz), float(controller.dterm_lpf_hz), config.angle_max_tilt,
		config.angle_gain, config.angle_rate_limit, config.arm_low_throttle, config.throttle_rate, throttle_policy,
		config.kff, setpoint_cutoff, throttle_limit,
		str(rates.identity), str(allocator.get("law", "")), allocator.weights, allocator.scales,
		var_to_bytes(actuator)]).hex_encode().sha256_text()
	return {ok = true, errors = errors, config = config}


## Sampled block for a prepared start: gyro memory equals the prepared body rate, everything else zero.
static func initial_aux(body: PackedFloat64Array) -> PackedFloat64Array:
	var aux := PackedFloat64Array()
	aux.resize(AUX_SIZE)
	for axis in 3:
		aux[AUX_GYRO + axis] = body[RB.RATE + axis]
	return aux


## Discrete state for a prepared start: disarmed, Acro, no arm evidence, filters initialized from the start.
static func initial_modes(source_generation: int = 0, flight_mode: int = FLIGHT_ACRO) -> PackedInt64Array:
	var modes := PackedInt64Array()
	modes.resize(MODES_SIZE)
	modes[MODE_FLIGHT] = flight_mode
	modes[MODE_SOURCE_GENERATION] = source_generation
	modes[MODE_FILTER_READY] = 1
	modes[MODE_ARM_BLOCK] = BLOCK_SWITCH
	return modes


## A neutral, disarmed pilot frame for the given source generation.
static func neutral_input(source_generation: int = 0, ready: bool = true) -> PackedFloat64Array:
	var input := PackedFloat64Array()
	input.resize(INPUT_SIZE)
	input[IN_SOURCE_GENERATION] = float(source_generation)
	input[IN_SOURCE_READY] = 1.0 if ready else 0.0
	return input


## Domain of the flattened pilot frame under this configuration.
static func input_is_valid(config: Dictionary, input: Variant) -> bool:
	if typeof(input) != TYPE_PACKED_FLOAT64_ARRAY or input.size() != INPUT_SIZE:
		return false
	for value: float in input:
		if not is_finite(value):
			return false
	for index: int in [IN_ROLL, IN_PITCH, IN_YAW]:
		if absf(input[index]) > 1.0:
			return false
	var throttle_floor: float = -1.0 if int(config.throttle_policy) == THROTTLE_RATE else 0.0
	if input[IN_THROTTLE] < throttle_floor or input[IN_THROTTLE] > 1.0:
		return false
	return input[IN_ARM] in [0.0, 1.0] and input[IN_MODE] in [0.0, 1.0] and input[IN_SOURCE_READY] in [0.0, 1.0] \
		and input[IN_SOURCE_GENERATION] >= 0.0 and input[IN_SOURCE_GENERATION] == floorf(input[IN_SOURCE_GENERATION]) \
		and input[IN_SOURCE_GENERATION] < 9.0e15 and input[IN_ACTIONS] in [0.0, 1.0, 2.0, 3.0]


## Domain of the discrete block (the state validator's enum check).
static func modes_are_valid(modes: Variant) -> bool:
	return typeof(modes) == TYPE_PACKED_INT64_ARRAY and modes.size() == MODES_SIZE \
		and modes[MODE_MOTOR] >= MOTOR_DISARMED and modes[MODE_MOTOR] <= MOTOR_DEPLETED \
		and modes[MODE_FLIGHT] in [FLIGHT_ACRO, FLIGHT_ANGLE] and modes[MODE_PREVIOUS_ARM] in [0, 1] \
		and modes[MODE_OFF_OBSERVED] in [0, 1] and modes[MODE_SOURCE_GENERATION] >= 0 \
		and modes[MODE_FILTER_READY] in [0, 1] and modes[MODE_ARM_BLOCK] >= BLOCK_NONE and modes[MODE_ARM_BLOCK] <= BLOCK_TERMINAL \
		and modes[MODE_SAMPLES] >= 0


## The pure sample transition. Returns {aux, modes}; a pilot frame outside its domain returns a nonfinite block,
## which the kernel refuses (the session validates frames first, so this is the last line of defence).
static func sample(config: Dictionary, frame: Dictionary, input: PackedFloat64Array, clock: Dictionary,
		supply_voltage: float) -> Dictionary:
	var previous: PackedFloat64Array = frame.aux
	var aux: PackedFloat64Array = previous.duplicate()
	var modes: PackedInt64Array = frame.modes.duplicate()
	if not input_is_valid(config, input) or not is_finite(supply_voltage):
		aux[0] = NAN
		return {aux = aux, modes = modes}
	var period: float = float(clock.dt)
	var body: PackedFloat64Array = frame.body
	var actions: int = int(input[IN_ACTIONS])
	var ready: bool = input[IN_SOURCE_READY] == 1.0
	var arm_level: int = int(input[IN_ARM])
	var motor: int = modes[MODE_MOTOR]

	# a. Source generation: a new connection invalidates every earlier arm edge.
	var generation: int = int(input[IN_SOURCE_GENERATION])
	var new_generation: bool = generation != modes[MODE_SOURCE_GENERATION]
	if new_generation:
		modes[MODE_SOURCE_GENERATION] = generation
		modes[MODE_OFF_OBSERVED] = 0
		modes[MODE_PREVIOUS_ARM] = 0

	# b. Throttle policy (fixed tick, checkpointed accumulator). Disarmed, the virtual throttle rests at zero.
	var collective: float = input[IN_THROTTLE]
	if int(config.throttle_policy) == THROTTLE_RATE:
		var virtual: float = previous[AUX_VIRTUAL_THROTTLE]
		if actions & ACTION_THROTTLE_RESET != 0 or motor != MOTOR_ARMED:
			virtual = 0.0
		if motor == MOTOR_ARMED:
			virtual = clampf(virtual + float(config.throttle_rate) * input[IN_THROTTLE] * period, 0.0, 1.0)
		aux[AUX_VIRTUAL_THROTTLE] = virtual
		collective = virtual
	var throttle_low: bool = collective <= float(config.arm_low_throttle)

	# c. Motor lifecycle at the sampled boundary. Terminal states persist until a prepared pad reset.
	if motor == MOTOR_CRASHED or motor == MOTOR_DEPLETED:
		modes[MODE_ARM_BLOCK] = BLOCK_TERMINAL
		if arm_level == 0:
			modes[MODE_OFF_OBSERVED] = 1
	elif arm_level == 0:
		modes[MODE_OFF_OBSERVED] = 1
		motor = MOTOR_DISARMED
		modes[MODE_ARM_BLOCK] = BLOCK_SWITCH # the next request needs a fresh ON edge
	elif motor == MOTOR_ARMED:
		if not ready:
			motor = MOTOR_DISARMED
			modes[MODE_ARM_BLOCK] = BLOCK_SOURCE
			modes[MODE_OFF_OBSERVED] = 0
		elif new_generation:
			# Recovery: only an attested OFF then ON at low throttle keeps motor authority across a reconnect.
			if actions & ACTION_RECOVERY != 0 and throttle_low:
				modes[MODE_OFF_OBSERVED] = 1
			else:
				motor = MOTOR_DISARMED
				modes[MODE_ARM_BLOCK] = BLOCK_SWITCH
	else:
		var fresh_edge: bool = modes[MODE_PREVIOUS_ARM] == 0 and modes[MODE_OFF_OBSERVED] == 1
		if not ready:
			modes[MODE_ARM_BLOCK] = BLOCK_SOURCE
		elif not fresh_edge:
			# A switch still held after a high-throttle refusal keeps that reason until it is cycled.
			if not (modes[MODE_ARM_BLOCK] == BLOCK_THROTTLE and modes[MODE_PREVIOUS_ARM] == 1):
				modes[MODE_ARM_BLOCK] = BLOCK_SWITCH
		elif not throttle_low:
			modes[MODE_ARM_BLOCK] = BLOCK_THROTTLE
			modes[MODE_OFF_OBSERVED] = 0 # a refused edge is spent: cycle the switch again
		else:
			motor = MOTOR_ARMED
			modes[MODE_ARM_BLOCK] = BLOCK_NONE
	modes[MODE_PREVIOUS_ARM] = arm_level
	modes[MODE_MOTOR] = motor
	modes[MODE_FLIGHT] = int(input[IN_MODE]) # the rate loop and its memory are shared; a switch resets nothing
	modes[MODE_SAMPLES] = modes[MODE_SAMPLES] + 1
	var armed: bool = motor == MOTOR_ARMED
	if int(config.throttle_policy) == THROTTLE_RATE and not armed:
		aux[AUX_VIRTUAL_THROTTLE] = 0.0
		collective = 0.0

	# d. One rates mapping (Acro), or the bounded attitude loop on roll and pitch (Angle). Yaw is always a rate.
	var setpoint: PackedFloat64Array = Rates.setpoints_rad_s(config.rates,
		PackedFloat64Array([input[IN_ROLL], input[IN_PITCH], input[IN_YAW]]))
	if modes[MODE_FLIGHT] == FLIGHT_ANGLE:
		var level: PackedFloat64Array = _angle_rate_target(config, body, input[IN_ROLL], input[IN_PITCH])
		setpoint[0] = level[0]
		setpoint[1] = level[1]
	# Setpoint smoothing and its rate for the feed-forward path; the memory is the previous smoothed setpoint.
	var setpoint_rate := PackedFloat64Array([0.0, 0.0, 0.0])
	for axis in 3:
		var held: float = previous[AUX_PREVIOUS_SETPOINT + axis]
		setpoint[axis] = held + float(config.setpoint_alpha) * (setpoint[axis] - held)
		setpoint_rate[axis] = (setpoint[axis] - held) / period

	# e. Ideal gyro sample and the declared digital filters.
	var gyro := PackedFloat64Array([0.0, 0.0, 0.0])
	var dterm := PackedFloat64Array([0.0, 0.0, 0.0])
	for axis in 3:
		var measured: float = body[RB.RATE + axis]
		if modes[MODE_FILTER_READY] == 0:
			gyro[axis] = measured
			dterm[axis] = 0.0
		else:
			gyro[axis] = previous[AUX_GYRO + axis] + float(config.gyro_alpha) * (measured - previous[AUX_GYRO + axis])
			var raw_derivative: float = (gyro[axis] - previous[AUX_GYRO + axis]) / period
			dterm[axis] = previous[AUX_DTERM + axis] + float(config.dterm_alpha) * (raw_derivative - previous[AUX_DTERM + axis])
	modes[MODE_FILTER_READY] = 1

	# f. Torque request with I_k, bounded allocation, held commands, then I_(k+1).
	var error := PackedFloat64Array([0.0, 0.0, 0.0])
	var tau_request := PackedFloat64Array([0.0, 0.0, 0.0])
	var tau_allocated := PackedFloat64Array([0.0, 0.0, 0.0])
	var commands := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var targets := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var integral := PackedFloat64Array([0.0, 0.0, 0.0])
	if armed:
		for axis in 3:
			error[axis] = setpoint[axis] - gyro[axis]
			var limit: float = config.tau_limit[axis]
			tau_request[axis] = clampf(float(config.kp[axis]) * error[axis] + previous[AUX_INTEGRAL + axis]
				- float(config.kd[axis]) * dterm[axis] + float(config.kff[axis]) * setpoint_rate[axis], -limit, limit)
		var actuator: Dictionary = config.actuator
		var idle: float = actuator.idle
		var top: float = actuator.top
		var floor_thrust: float = ActuatorMap.static_thrust(actuator, idle, supply_voltage)
		var ceiling_thrust: float = maxf(ActuatorMap.static_thrust(actuator, top, supply_voltage), floor_thrust)
		var collective_thrust: float = 4.0 * ActuatorMap.static_thrust(actuator,
			idle + collective * float(config.throttle_limit) * (top - idle), supply_voltage)
		var allocation: Dictionary = Allocator.allocate(config.allocator,
			PackedFloat64Array([collective_thrust, tau_request[0], tau_request[1], tau_request[2]]),
			PackedFloat64Array([floor_thrust, floor_thrust, floor_thrust, floor_thrust]),
			PackedFloat64Array([ceiling_thrust, ceiling_thrust, ceiling_thrust, ceiling_thrust]))
		if not allocation.get("ok", false):
			aux[0] = NAN
			return {aux = aux, modes = modes}
		for rotor in 4:
			targets[rotor] = allocation.thrusts[rotor]
			commands[rotor] = clampf(ActuatorMap.command_for_thrust(actuator, targets[rotor], supply_voltage), idle, top)
		for axis in 3:
			tau_allocated[axis] = allocation.wrench[axis + 1]
			var next: float = previous[AUX_INTEGRAL + axis]
			if not throttle_low:
				next += period * (float(config.ki[axis]) * error[axis]
					+ float(config.kaw[axis]) * (tau_allocated[axis] - tau_request[axis]))
			integral[axis] = clampf(next, -float(config.i_max[axis]), float(config.i_max[axis]))
	for axis in 3:
		aux[AUX_INTEGRAL + axis] = integral[axis]
		aux[AUX_GYRO + axis] = gyro[axis]
		aux[AUX_DTERM + axis] = dterm[axis]
		aux[AUX_PREVIOUS_SETPOINT + axis] = setpoint[axis]
		aux[AUX_TAU_REQUEST + axis] = tau_request[axis]
		aux[AUX_TAU_ALLOCATED + axis] = tau_allocated[axis]
		aux[AUX_SETPOINT + axis] = setpoint[axis]
	for rotor in 4:
		aux[AUX_COMMAND + rotor] = commands[rotor]
		aux[AUX_THRUST_TARGET + rotor] = targets[rotor]
	aux[AUX_COLLECTIVE] = collective
	return {aux = aux, modes = modes}


## Angle mode outer loop: [p, q] rate targets (rad/s) toward a bounded-tilt attitude at the current heading.
## The error is the shortest body-frame rotation from the current to the desired attitude, so it is defined at
## every attitude (inverted and near vertical included); only its roll and pitch components are used.
static func _angle_rate_target(config: Dictionary, body: PackedFloat64Array, roll_stick: float, pitch_stick: float) -> PackedFloat64Array:
	var attitude: PackedFloat64Array = M.quat(body[RB.ATT], body[RB.ATT + 1], body[RB.ATT + 2], body[RB.ATT + 3])
	var desired: PackedFloat64Array = M.q_from_euler(heading(attitude), pitch_stick * float(config.angle_max_tilt),
		roll_stick * float(config.angle_max_tilt))
	var delta: PackedFloat64Array = M.q_mul(M.q_conj(attitude), desired)
	var flip: float = -1.0 if delta[0] < 0.0 else 1.0
	var vector_norm: float = sqrt(delta[1] * delta[1] + delta[2] * delta[2] + delta[3] * delta[3])
	var scale: float = 2.0 * flip
	if vector_norm > 1.0e-9:
		scale = flip * 2.0 * atan2(vector_norm, flip * delta[0]) / vector_norm
	var limit: float = config.angle_rate_limit
	return PackedFloat64Array([
		clampf(float(config.angle_gain) * scale * delta[1], -limit, limit),
		clampf(float(config.angle_gain) * scale * delta[2], -limit, limit)])


## Heading (rad) of a body-to-NED attitude, defined at every attitude: the nose's horizontal direction, or near a
## vertical nose the direction the airframe's top side implies.
static func heading(attitude: PackedFloat64Array) -> float:
	var nose: PackedFloat64Array = M.q_rotate(attitude, M.v3(1.0, 0.0, 0.0))
	if sqrt(nose[0] * nose[0] + nose[1] * nose[1]) > 0.2:
		return atan2(nose[1], nose[0])
	var top: PackedFloat64Array = M.q_rotate(attitude, M.v3(0.0, 0.0, -1.0))
	if nose[2] < 0.0: # nose up: the top side points backward
		return atan2(-top[1], -top[0])
	return atan2(top[1], top[0])
