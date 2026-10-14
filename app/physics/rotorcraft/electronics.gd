# HELI-15: four-stick mapping, yaw-rate/heading hold and optional trainer aid.
# Controller outputs use the aircraft's declared swash and tail angles.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const Swash = preload("res://physics/rotorcraft/swash.gd")
const STATE_SIZE: int = 19
const HEADING_REF: int = 17
const YAW_INTEGRATOR: int = 18
const PARAMETER_KEYS: Array = [
	"curves_by_mode", "linkage", "tail_collective_trim_rad", "tail_collective_min_rad",
	"tail_collective_max_rad", "yaw_control_sign", "yaw_deadzone", "yaw_max_rate_rad_s",
	"yaw_heading_gain_per_s", "yaw_rate_kp_rad_per_rad_s", "yaw_rate_ki_rad_per_rad",
	"yaw_integrator_limit_rad", "trainer_max_tilt_rad", "trainer_roll_attitude_gain_per_s",
	"trainer_pitch_attitude_gain_per_s", "trainer_roll_rate_limit_rad_s",
	"trainer_pitch_rate_limit_rad_s", "trainer_roll_cyclic_gain_rad_per_rad_s",
	"trainer_pitch_cyclic_gain_rad_per_rad_s",
]


## Validate all electronics values from the aircraft authoring source. No
## simulator-wide cyclic, pitch, yaw or trainer gains are embedded here.
static func prepare(parameters: Dictionary) -> Dictionary:
	if parameters.size() != PARAMETER_KEYS.size() or not parameters.has_all(PARAMETER_KEYS):
		return {"ok": false, "message": "electronics parameters are missing or contain unknown fields"}
	var curves: Dictionary = parameters.curves_by_mode
	var curve_check: Dictionary = Swash.validate_curves(curves)
	if not curve_check.ok:
		return {"ok": false, "message": "invalid flight curves: " + str(curve_check.get("error", "unknown"))}
	var linkage: Dictionary = parameters.linkage
	# Reuse the authored linkage validator without inventing a servo or pitch value.
	var linkage_check: Dictionary = Swash.linkage_output(PackedFloat64Array([0.0, 0.0, 0.0]), linkage)
	if not linkage_check.ok:
		return {"ok": false, "message": "invalid swash linkage: " + str(linkage_check.get("error", "unknown"))}
	var model: Dictionary = {}
	for key: String in PARAMETER_KEYS:
		if key == "curves_by_mode" or key == "linkage":
			continue
		if not _number(parameters[key]):
			return {"ok": false, "message": "electronics parameter " + key + " must be finite"}
		model[key] = float(parameters[key])
	if absf(model.yaw_control_sign) != 1.0 or model.yaw_deadzone < 0.0 or model.yaw_deadzone >= 1.0 \
			or model.yaw_max_rate_rad_s <= 0.0 or model.yaw_heading_gain_per_s <= 0.0 \
			or model.yaw_rate_kp_rad_per_rad_s <= 0.0 or model.yaw_rate_ki_rad_per_rad <= 0.0 \
			or model.yaw_integrator_limit_rad <= 0.0 or model.trainer_max_tilt_rad <= 0.0 \
			or model.trainer_max_tilt_rad >= PI / 2.0 or model.trainer_roll_attitude_gain_per_s <= 0.0 \
			or model.trainer_pitch_attitude_gain_per_s <= 0.0 \
			or model.trainer_roll_rate_limit_rad_s <= 0.0 or model.trainer_pitch_rate_limit_rad_s <= 0.0 \
			or model.trainer_roll_cyclic_gain_rad_per_rad_s <= 0.0 \
			or model.trainer_pitch_cyclic_gain_rad_per_rad_s <= 0.0:
		return {"ok": false, "message": "electronics gains, signs, rates or limits are invalid"}
	if model.tail_collective_min_rad >= model.tail_collective_max_rad \
			or model.tail_collective_trim_rad < model.tail_collective_min_rad \
			or model.tail_collective_trim_rad > model.tail_collective_max_rad:
		return {"ok": false, "message": "tail collective trim must lie inside its declared limits"}
	model["curves_by_mode"] = _freeze_curves(curves)
	model["linkage"] = linkage.duplicate(true)
	model.linkage.make_read_only()
	model["law"] = "openrc-four-stick-electronics-v1"
	model.make_read_only()
	return {"ok": true, "model": model}


## `sticks`: [longitudinal, lateral, yaw, collective], each in [-1, 1].
## State is the 19-value body/rotor/controller state. Continuous PI memory is
## returned as derivatives so it can be integrated at every RK stage.
static func evaluate(model: Dictionary, state: PackedFloat64Array, sticks: PackedFloat64Array,
		flight_mode: String, trainer_enabled: bool, trim: Dictionary = {}) -> Dictionary:
	if not _prepared(model) or state.size() != STATE_SIZE or sticks.size() != 4 \
			or flight_mode.is_empty() or typeof(trainer_enabled) != TYPE_BOOL or not _trim_is_valid(trim, model):
		return {"ok": false, "message": "invalid electronics context, state, mode or stick layout"}
	for value: float in state:
		if not is_finite(value):
			return {"ok": false, "message": "electronics state is nonfinite"}
	for value: float in sticks:
		if not is_finite(value) or value < -1.0 or value > 1.0:
			return {"ok": false, "message": "pilot sticks must be finite and in [-1, 1]"}
	if absf(state[HEADING_REF]) > 1.0e12 or absf(state[YAW_INTEGRATOR]) > 1.0e12:
		return {"ok": false, "message": "controller state is outside its finite operating range"}
	var collective_input: float = sticks[3]
	var pitch_curve: Dictionary = Swash.sample_mode_curve(model.curves_by_mode, flight_mode, "pitch", collective_input)
	var throttle_curve: Dictionary = Swash.sample_mode_curve(model.curves_by_mode, flight_mode, "throttle", collective_input)
	if not pitch_curve.ok or not throttle_curve.ok:
		return {"ok": false, "message": "requested flight mode has no usable collective/throttle curve"}
	var cyclic_longitudinal: float = sticks[0]
	var cyclic_lateral: float = sticks[1]
	var euler: PackedFloat64Array = M.q_to_euler(PackedFloat64Array([state[6], state[7], state[8], state[9]]))
	if trainer_enabled:
		var desired_roll: float = clampf(float(trim.get("roll_reference_rad", 0.0))
			+ cyclic_lateral * model.trainer_max_tilt_rad,
			-model.trainer_max_tilt_rad, model.trainer_max_tilt_rad)
		var desired_pitch: float = clampf(float(trim.get("pitch_reference_rad", 0.0))
			- cyclic_longitudinal * model.trainer_max_tilt_rad,
			-model.trainer_max_tilt_rad, model.trainer_max_tilt_rad)
		var desired_roll_rate: float = clampf(model.trainer_roll_attitude_gain_per_s * (desired_roll - euler[2]),
			-model.trainer_roll_rate_limit_rad_s, model.trainer_roll_rate_limit_rad_s)
		var desired_pitch_rate: float = clampf(model.trainer_pitch_attitude_gain_per_s * (desired_pitch - euler[1]),
			-model.trainer_pitch_rate_limit_rad_s, model.trainer_pitch_rate_limit_rad_s)
		var lateral_command_rad: float = model.trainer_roll_cyclic_gain_rad_per_rad_s * (desired_roll_rate - state[10])
		var longitudinal_command_rad: float = -model.trainer_pitch_cyclic_gain_rad_per_rad_s * (desired_pitch_rate - state[11])
		cyclic_lateral = clampf(lateral_command_rad / model.linkage.lateral_rad_per_unit, -1.0, 1.0)
		cyclic_longitudinal = clampf(longitudinal_command_rad / model.linkage.longitudinal_rad_per_unit, -1.0, 1.0)
	var mixed: Dictionary = Swash.mix_120(float(pitch_curve.value), cyclic_longitudinal, cyclic_lateral)
	if not mixed.ok:
		return {"ok": false, "message": "swash mix refused the physical stick commands"}
	var servo_positions: PackedFloat64Array = mixed.servo_targets.duplicate()
	var servo_travel_limited: bool = false
	for index: int in range(servo_positions.size()):
		var clamped: float = clampf(servo_positions[index], -1.0, 1.0)
		servo_travel_limited = servo_travel_limited or clamped != servo_positions[index]
		servo_positions[index] = clamped
	var swash: Dictionary = Swash.linkage_output(servo_positions, model.linkage)
	if not swash.ok:
		return {"ok": false, "message": "swash linkage refused the mixed commands"}
	var cyclic_forward: float = clampf(float(swash.longitudinal_rad)
		+ float(trim.get("cyclic_forward_bias_rad", 0.0)),
		-model.linkage.cyclic_max_rad, model.linkage.cyclic_max_rad)
	var cyclic_right: float = clampf(float(swash.lateral_rad)
		+ float(trim.get("cyclic_right_bias_rad", 0.0)),
		-model.linkage.cyclic_max_rad, model.linkage.cyclic_max_rad)
	var yaw_stick: float = sticks[2]
	var manual_yaw_rate: float = yaw_stick * model.yaw_max_rate_rad_s if absf(yaw_stick) > model.yaw_deadzone else 0.0
	var heading_error: float = _wrap(state[HEADING_REF] - euler[0])
	var target_yaw_rate: float = clampf(manual_yaw_rate + model.yaw_heading_gain_per_s * heading_error,
		-model.yaw_max_rate_rad_s, model.yaw_max_rate_rad_s)
	var yaw_rate_error: float = target_yaw_rate - state[12]
	var integrator: float = clampf(state[YAW_INTEGRATOR], -model.yaw_integrator_limit_rad, model.yaw_integrator_limit_rad)
	var tail_unsaturated: float = model.tail_collective_trim_rad \
		+ float(trim.get("tail_collective_bias_rad", 0.0)) + model.yaw_control_sign * (
		model.yaw_rate_kp_rad_per_rad_s * yaw_rate_error + model.yaw_rate_ki_rad_per_rad * integrator)
	var tail_collective: float = clampf(tail_unsaturated, model.tail_collective_min_rad, model.tail_collective_max_rad)
	var integral_rate: float = yaw_rate_error
	var integral_output_rate: float = model.yaw_control_sign * model.yaw_rate_ki_rad_per_rad * integral_rate
	if (tail_unsaturated > model.tail_collective_max_rad and integral_output_rate > 0.0) \
			or (tail_unsaturated < model.tail_collective_min_rad and integral_output_rate < 0.0) \
			or (integrator >= model.yaw_integrator_limit_rad and integral_rate > 0.0) \
			or (integrator <= -model.yaw_integrator_limit_rad and integral_rate < 0.0):
		integral_rate = 0.0
	var heading_rate: float = manual_yaw_rate if absf(yaw_stick) > model.yaw_deadzone else 0.0
	return {"ok": true, "collective_75_rad": float(swash.theta0_rad),
		"cyclic_forward_rad": cyclic_forward, "cyclic_right_rad": cyclic_right,
		"tail_collective_rad": tail_collective, "drive_fraction": float(throttle_curve.value),
		"controller_derivative": PackedFloat64Array([heading_rate, integral_rate]),
		"target_yaw_rate_rad_s": target_yaw_rate, "measured_yaw_rate_rad_s": state[12],
		"heading_error_rad": heading_error, "yaw_rate_error_rad_s": yaw_rate_error,
		"tail_saturated": tail_collective != tail_unsaturated,
		"trainer_active": trainer_enabled, "trim": trim.duplicate(true),
		"servo_travel_limited": servo_travel_limited,
		"swash_servo_targets": servo_positions, "swash_servo_commands": mixed.servo_targets}


static func _prepared(model: Dictionary) -> bool:
	if not model.is_read_only() or model.get("law") != "openrc-four-stick-electronics-v1" \
			or model.size() != PARAMETER_KEYS.size() + 1:
		return false
	return model.has("curves_by_mode") and model.has("linkage")


static func _freeze_curves(source: Dictionary) -> Dictionary:
	var curves: Dictionary = source.duplicate(true)
	for mode_name: String in curves.keys():
		curves[mode_name].make_read_only()
	curves.make_read_only()
	return curves


static func _wrap(angle: float) -> float:
	return M.atan2_(M.sin_(angle), M.cos_(angle))


static func _trim_is_valid(trim: Dictionary, model: Dictionary) -> bool:
	var keys: Array = ["roll_reference_rad", "pitch_reference_rad", "cyclic_forward_bias_rad",
		"cyclic_right_bias_rad", "tail_collective_bias_rad"]
	for key: Variant in trim.keys():
		if typeof(key) != TYPE_STRING or not keys.has(key):
			return false
	for key: String in keys:
		if trim.has(key) and not _number(trim[key]):
			return false
	if absf(float(trim.get("roll_reference_rad", 0.0))) >= PI / 2.0 \
			or absf(float(trim.get("pitch_reference_rad", 0.0))) >= PI / 2.0:
		return false
	if absf(float(trim.get("cyclic_forward_bias_rad", 0.0))) > model.linkage.cyclic_max_rad \
			or absf(float(trim.get("cyclic_right_bias_rad", 0.0))) > model.linkage.cyclic_max_rad:
		return false
	return absf(float(trim.get("tail_collective_bias_rad", 0.0))) \
		<= model.tail_collective_max_rad - model.tail_collective_min_rad


static func _number(value: Variant) -> bool:
	var kind: int = typeof(value)
	return (kind == TYPE_FLOAT or kind == TYPE_INT) and is_finite(float(value))
