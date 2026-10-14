# HELI-15: four-stick mapping, yaw-rate/heading hold and optional trainer aid.
# Controller outputs use the aircraft's declared swash and tail angles.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const Swash = preload("res://physics/rotorcraft/swash.gd")
const STATE_SIZE: int = 19
const HEADING_REF: int = 17
const YAW_INTEGRATOR: int = 18
const TRAINER_LAW: String = "openrc-four-stick-electronics-v1"
const BODY_RATE_LAW: String = "openrc-fbl-body-rate-electronics-v1"
const PARAMETER_KEYS: Array = [
	"curves_by_mode", "linkage", "tail_collective_trim_rad", "tail_collective_min_rad",
	"tail_collective_max_rad", "yaw_control_sign", "yaw_deadzone", "yaw_max_rate_rad_s",
	"yaw_heading_gain_per_s", "yaw_rate_kp_rad_per_rad_s", "yaw_rate_ki_rad_per_rad",
	"yaw_integrator_limit_rad", "trainer_max_tilt_rad", "trainer_roll_attitude_gain_per_s",
	"trainer_pitch_attitude_gain_per_s", "trainer_roll_rate_limit_rad_s",
	"trainer_pitch_rate_limit_rad_s", "trainer_roll_cyclic_gain_rad_per_rad_s",
	"trainer_pitch_cyclic_gain_rad_per_rad_s",
]
const BODY_RATE_PARAMETER_KEYS: Array = [
	"curves_by_mode", "linkage", "controller_law", "tail_collective_trim_rad",
	"tail_collective_min_rad", "tail_collective_max_rad", "yaw_control_sign",
	"yaw_deadzone", "yaw_rate_kp_rad_per_rad_s", "yaw_rate_ki_rad_per_rad",
	"yaw_integrator_limit_rad", "body_rate_max_rad_s",
	"body_rate_roll_cyclic_gain_rad_per_rad_s",
	"body_rate_pitch_cyclic_gain_rad_per_rad_s",
]
const BODY_RATE_MODEL_KEYS: Array = [
	"curves_by_mode", "linkage", "tail_collective_trim_rad", "tail_collective_min_rad",
	"tail_collective_max_rad", "yaw_control_sign", "yaw_deadzone",
	"yaw_rate_kp_rad_per_rad_s", "yaw_rate_ki_rad_per_rad", "yaw_integrator_limit_rad",
	"body_rate_max_rad_s", "body_rate_roll_cyclic_gain_rad_per_rad_s",
	"body_rate_pitch_cyclic_gain_rad_per_rad_s",
]


## Validate all electronics values from the aircraft authoring source. No
## simulator-wide cyclic, pitch, yaw or trainer gains are embedded here.
static func prepare(parameters: Dictionary) -> Dictionary:
	var law: String = str(parameters.get("controller_law", TRAINER_LAW))
	var parameter_keys: Array
	if law == TRAINER_LAW:
		parameter_keys = PARAMETER_KEYS
	elif law == BODY_RATE_LAW:
		parameter_keys = BODY_RATE_PARAMETER_KEYS
	else:
		return {"ok": false, "message": "unsupported rotorcraft controller law"}
	if parameters.size() != parameter_keys.size() or not parameters.has_all(parameter_keys):
		return {"ok": false, "message": "electronics parameters are missing or contain unknown fields"}
	if not parameters.curves_by_mode is Dictionary or not parameters.linkage is Dictionary:
		return {"ok": false, "message": "electronics curves and linkage must be dictionaries"}
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
	for key: String in parameter_keys:
		if key in ["curves_by_mode", "linkage", "controller_law"]:
			continue
		if key == "body_rate_max_rad_s":
			if not _positive_vector3(parameters[key]):
				return {"ok": false, "message": "body-rate limits must be three positive finite values"}
			model[key] = _as_f64(parameters[key])
			continue
		if not _number(parameters[key]):
			return {"ok": false, "message": "electronics parameter " + key + " must be finite"}
		model[key] = float(parameters[key])
	if absf(model.yaw_control_sign) != 1.0 or model.yaw_deadzone < 0.0 or model.yaw_deadzone >= 1.0 \
			or model.yaw_rate_kp_rad_per_rad_s <= 0.0 or model.yaw_rate_ki_rad_per_rad <= 0.0 \
			or model.yaw_integrator_limit_rad <= 0.0:
		return {"ok": false, "message": "electronics gains, signs, rates or limits are invalid"}
	if law == TRAINER_LAW and (model.yaw_max_rate_rad_s <= 0.0 or model.yaw_heading_gain_per_s <= 0.0 \
			or model.trainer_max_tilt_rad <= 0.0 or model.trainer_max_tilt_rad >= PI / 2.0 \
			or model.trainer_roll_attitude_gain_per_s <= 0.0 or model.trainer_pitch_attitude_gain_per_s <= 0.0 \
			or model.trainer_roll_rate_limit_rad_s <= 0.0 or model.trainer_pitch_rate_limit_rad_s <= 0.0 \
			or model.trainer_roll_cyclic_gain_rad_per_rad_s <= 0.0 \
			or model.trainer_pitch_cyclic_gain_rad_per_rad_s <= 0.0):
		return {"ok": false, "message": "trainer gains, signs, rates or limits are invalid"}
	if law == BODY_RATE_LAW and (model.body_rate_roll_cyclic_gain_rad_per_rad_s <= 0.0 \
			or model.body_rate_pitch_cyclic_gain_rad_per_rad_s <= 0.0):
		return {"ok": false, "message": "body-rate cyclic gains must be positive"}
	if model.tail_collective_min_rad >= model.tail_collective_max_rad \
			or model.tail_collective_trim_rad < model.tail_collective_min_rad \
			or model.tail_collective_trim_rad > model.tail_collective_max_rad:
		return {"ok": false, "message": "tail collective trim must lie inside its declared limits"}
	model["curves_by_mode"] = _freeze_curves(curves)
	model["linkage"] = linkage.duplicate(true)
	model.linkage.make_read_only()
	model["law"] = law
	model.make_read_only()
	return {"ok": true, "model": model}


## `sticks`: [longitudinal, lateral, yaw, collective], each in [-1, 1].
## State is the 19-value body/rotor/controller state. Continuous PI memory is
## returned as derivatives so it can be integrated at every RK stage.
static func evaluate(model: Dictionary, state: PackedFloat64Array, sticks: PackedFloat64Array,
		flight_mode: String, trainer_enabled: bool, trim: Dictionary = {}) -> Dictionary:
	return _evaluate(model, state, sticks, flight_mode, trainer_enabled, trim, false)


## Internal flight/render path for the immutable model returned by prepare().
## Public evaluate() remains the configuration-revalidating reference path.
static func fast_evaluate(model: Dictionary, state: PackedFloat64Array, sticks: PackedFloat64Array,
		flight_mode: String, trainer_enabled: bool, trim: Dictionary = {}) -> Dictionary:
	return _evaluate(model, state, sticks, flight_mode, trainer_enabled, trim, true)


static func _evaluate(model: Dictionary, state: PackedFloat64Array, sticks: PackedFloat64Array,
		flight_mode: String, trainer_enabled: bool, trim: Dictionary, prepared: bool) -> Dictionary:
	var body_rate_law: bool = model.get("law") == BODY_RATE_LAW
	if not _prepared(model) or state.size() != STATE_SIZE or sticks.size() != 4 \
			or flight_mode.is_empty() or typeof(trainer_enabled) != TYPE_BOOL or not _trim_is_valid(trim, model):
		return {"ok": false, "message": "invalid electronics context, state, mode or stick layout"}
	if body_rate_law and trainer_enabled:
		return {"ok": false, "message": "FBL body-rate mode cannot enable the trainer attitude controller"}
	for value: float in state:
		if not is_finite(value):
			return {"ok": false, "message": "electronics state is nonfinite"}
	for value: float in sticks:
		if not is_finite(value) or value < -1.0 or value > 1.0:
			return {"ok": false, "message": "pilot sticks must be finite and in [-1, 1]"}
	if absf(state[HEADING_REF]) > 1.0e12 or absf(state[YAW_INTEGRATOR]) > 1.0e12:
		return {"ok": false, "message": "controller state is outside its finite operating range"}
	var collective_input: float = sticks[3]
	var pitch_value: float
	var throttle_value: float
	if prepared:
		var curves: Dictionary = model.curves_by_mode
		if not curves.is_read_only() or not curves.has(flight_mode):
			return {"ok": false, "message": "requested flight mode has no usable collective/throttle curve"}
		if not curves[flight_mode] is Dictionary:
			return {"ok": false, "message": "prepared mode curves must be dictionaries"}
		var mode: Dictionary = curves[flight_mode]
		if not mode.is_read_only() or mode.size() != 2 or not mode.has_all(["pitch", "throttle"]) \
				or not _immutable_curve_shape(mode.pitch) or not _immutable_curve_shape(mode.throttle):
			return {"ok": false, "message": "prepared mode curves must be immutable"}
		pitch_value = Swash._sample_validated_curve(mode.pitch, collective_input)
		throttle_value = Swash._sample_validated_curve(mode.throttle, collective_input)
		if not is_finite(pitch_value) or pitch_value < -1.0 or pitch_value > 1.0 \
				or not is_finite(throttle_value) or throttle_value < 0.0 or throttle_value > 1.0:
			return {"ok": false, "message": "prepared curve output is outside its finite domain"}
	else:
		var pitch_curve: Dictionary = Swash.sample_mode_curve(model.curves_by_mode, flight_mode, "pitch", collective_input)
		var throttle_curve: Dictionary = Swash.sample_mode_curve(model.curves_by_mode, flight_mode, "throttle", collective_input)
		if not pitch_curve.ok or not throttle_curve.ok:
			return {"ok": false, "message": "requested flight mode has no usable collective/throttle curve"}
		pitch_value = float(pitch_curve.value)
		throttle_value = float(throttle_curve.value)
	var cyclic_longitudinal: float = sticks[0]
	var cyclic_lateral: float = sticks[1]
	var euler: PackedFloat64Array = PackedFloat64Array()
	if not body_rate_law:
		euler = M.q_to_euler(PackedFloat64Array([state[6], state[7], state[8], state[9]]))
	if body_rate_law:
		var rates: PackedFloat64Array = model.body_rate_max_rad_s
		var desired_roll_rate: float = sticks[1] * rates[0]
		var desired_pitch_rate: float = -sticks[0] * rates[1]
		var lateral_command_rad: float = model.body_rate_roll_cyclic_gain_rad_per_rad_s \
			* (desired_roll_rate - state[10])
		var longitudinal_command_rad: float = -model.body_rate_pitch_cyclic_gain_rad_per_rad_s \
			* (desired_pitch_rate - state[11])
		cyclic_lateral = clampf(lateral_command_rad / model.linkage.lateral_rad_per_unit, -1.0, 1.0)
		cyclic_longitudinal = clampf(longitudinal_command_rad / model.linkage.longitudinal_rad_per_unit, -1.0, 1.0)
	elif trainer_enabled:
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
	var mixed: Dictionary = Swash.mix_120(pitch_value, cyclic_longitudinal, cyclic_lateral)
	if not mixed.ok:
		return {"ok": false, "message": "swash mix refused the physical stick commands"}
	var servo_positions: PackedFloat64Array = mixed.servo_targets.duplicate()
	var servo_travel_limited: bool = false
	for index: int in range(servo_positions.size()):
		var clamped: float = clampf(servo_positions[index], -1.0, 1.0)
		servo_travel_limited = servo_travel_limited or clamped != servo_positions[index]
		servo_positions[index] = clamped
	var swash: Dictionary = Swash._linkage_output_prepared(servo_positions, model.linkage) if prepared else Swash.linkage_output(servo_positions, model.linkage)
	if not swash.ok:
		return {"ok": false, "message": "swash linkage refused the mixed commands"}
	var cyclic_forward: float = clampf(float(swash.longitudinal_rad)
		+ float(trim.get("cyclic_forward_bias_rad", 0.0)),
		-model.linkage.cyclic_max_rad, model.linkage.cyclic_max_rad)
	var cyclic_right: float = clampf(float(swash.lateral_rad)
		+ float(trim.get("cyclic_right_bias_rad", 0.0)),
		-model.linkage.cyclic_max_rad, model.linkage.cyclic_max_rad)
	var yaw_stick: float = sticks[2]
	var manual_yaw_rate: float
	var heading_error: float = 0.0
	var target_yaw_rate: float
	if body_rate_law:
		manual_yaw_rate = yaw_stick * model.body_rate_max_rad_s[2] \
			if absf(yaw_stick) > model.yaw_deadzone else 0.0
		target_yaw_rate = manual_yaw_rate
	else:
		manual_yaw_rate = yaw_stick * model.yaw_max_rate_rad_s \
			if absf(yaw_stick) > model.yaw_deadzone else 0.0
		heading_error = _wrap(state[HEADING_REF] - euler[0])
		target_yaw_rate = clampf(manual_yaw_rate + model.yaw_heading_gain_per_s * heading_error,
			-model.yaw_max_rate_rad_s, model.yaw_max_rate_rad_s)
	var yaw_rate_error: float = target_yaw_rate - state[12]
	var integrator: float = clampf(state[YAW_INTEGRATOR], -model.yaw_integrator_limit_rad, model.yaw_integrator_limit_rad)
var ground_yaw_precomp: float = 0.0
if trim.has("ground_yaw_precomp_tail_bias_rad"):
	var reference_collective: float = float(trim.ground_yaw_precomp_collective_rad)
	ground_yaw_precomp = float(trim.ground_yaw_precomp_tail_bias_rad) \
		* clampf(float(swash.theta0_rad) / reference_collective, 0.0, 1.0)
	var tail_unsaturated: float = model.tail_collective_trim_rad \
		+ float(trim.get("tail_collective_bias_rad", 0.0)) + ground_yaw_precomp + model.yaw_control_sign * (
		model.yaw_rate_kp_rad_per_rad_s * yaw_rate_error + model.yaw_rate_ki_rad_per_rad * integrator)
	var tail_collective: float = clampf(tail_unsaturated, model.tail_collective_min_rad, model.tail_collective_max_rad)
	var integral_rate: float = yaw_rate_error
	var integral_output_rate: float = model.yaw_control_sign * model.yaw_rate_ki_rad_per_rad * integral_rate
	if (tail_unsaturated > model.tail_collective_max_rad and integral_output_rate > 0.0) \
			or (tail_unsaturated < model.tail_collective_min_rad and integral_output_rate < 0.0) \
			or (integrator >= model.yaw_integrator_limit_rad and integral_rate > 0.0) \
			or (integrator <= -model.yaw_integrator_limit_rad and integral_rate < 0.0):
		integral_rate = 0.0
	var heading_rate: float = manual_yaw_rate if not body_rate_law and absf(yaw_stick) > model.yaw_deadzone else 0.0
	var result: Dictionary = {"ok": true, "collective_75_rad": float(swash.theta0_rad),
		"cyclic_forward_rad": cyclic_forward, "cyclic_right_rad": cyclic_right,
		"tail_collective_rad": tail_collective, "drive_fraction": throttle_value,
		"controller_derivative": PackedFloat64Array([heading_rate, integral_rate]),
		"target_yaw_rate_rad_s": target_yaw_rate, "measured_yaw_rate_rad_s": state[12]}
	if not body_rate_law:
		result["heading_error_rad"] = heading_error
	result["yaw_rate_error_rad_s"] = yaw_rate_error
	if trim.has("ground_yaw_precomp_tail_bias_rad"):
		result["ground_yaw_precomp_rad"] = ground_yaw_precomp
	result["tail_saturated"] = tail_collective != tail_unsaturated
	result["trainer_active"] = trainer_enabled
	result["trim"] = trim.duplicate(true)
	result["servo_travel_limited"] = servo_travel_limited
	result["swash_servo_targets"] = servo_positions
	result["swash_servo_commands"] = mixed.servo_targets
	if body_rate_law:
		result["controller_law"] = BODY_RATE_LAW
		result["desired_body_rates_rad_s"] = PackedFloat64Array([
			sticks[1] * model.body_rate_max_rad_s[0],
			-sticks[0] * model.body_rate_max_rad_s[1],
			manual_yaw_rate,
		])
		result["measured_body_rates_rad_s"] = PackedFloat64Array([state[10], state[11], state[12]])
		result["body_rate_feedback"] = true
		result["heading_hold_active"] = false
	else:
		result["heading_error_rad"] = heading_error
	return result


static func _prepared(model: Dictionary) -> bool:
	if not model.is_read_only():
		return false
	var law: String = str(model.get("law", ""))
	if law == TRAINER_LAW:
		if model.size() != PARAMETER_KEYS.size() + 1 or not model.has_all(PARAMETER_KEYS):
			return false
	elif law == BODY_RATE_LAW:
		if model.size() != BODY_RATE_MODEL_KEYS.size() + 1 or not model.has_all(BODY_RATE_MODEL_KEYS) \
				or not _positive_vector3(model.get("body_rate_max_rad_s", PackedFloat64Array())):
			return false
	else:
		return false
	return model.curves_by_mode is Dictionary and model.linkage is Dictionary \
		and model.curves_by_mode.is_read_only() and model.linkage.is_read_only()


static func _immutable_curve_shape(points: Variant) -> bool:
	# Packed arrays use copy-on-write value semantics. Ordinary arrays must be
	# frozen too, otherwise their elements can mutate through a read-only mode.
	return (points is PackedFloat64Array and points.size() == 5) \
		or (points is Array and points.size() == 5 and points.is_read_only())


static func _freeze_curves(source: Dictionary) -> Dictionary:
	var curves: Dictionary = source.duplicate(true)
	for mode_name: String in curves.keys():
		for channel: String in ["pitch", "throttle"]:
			if curves[mode_name][channel] is Array:
				curves[mode_name][channel].make_read_only()
		curves[mode_name].make_read_only()
	curves.make_read_only()
	return curves


static func _wrap(angle: float) -> float:
	return M.atan2_(M.sin_(angle), M.cos_(angle))


static func _trim_is_valid(trim: Dictionary, model: Dictionary) -> bool:
	var keys: Array = ["roll_reference_rad", "pitch_reference_rad", "cyclic_forward_bias_rad",
		"cyclic_right_bias_rad", "tail_collective_bias_rad",
		"ground_yaw_precomp_tail_bias_rad", "ground_yaw_precomp_collective_rad"]
	for key: Variant in trim.keys():
		if typeof(key) != TYPE_STRING or not keys.has(key):
			return false
	for key: String in keys:
		if trim.has(key) and not _number(trim[key]):
			return false
	var has_ground_precomp_bias: bool = trim.has("ground_yaw_precomp_tail_bias_rad")
	var has_ground_precomp_collective: bool = trim.has("ground_yaw_precomp_collective_rad")
	if has_ground_precomp_bias != has_ground_precomp_collective:
		return false
	if model.get("law") == BODY_RATE_LAW and (trim.has("roll_reference_rad") or trim.has("pitch_reference_rad")):
		return false
	if has_ground_precomp_bias:
		if model.get("law") != TRAINER_LAW:
			return false
		var reference_collective: float = float(trim.ground_yaw_precomp_collective_rad)
		if reference_collective <= 0.0 or reference_collective > model.linkage.collective_max_rad:
			return false
		var baseline_tail: float = model.tail_collective_trim_rad \
			+ float(trim.get("tail_collective_bias_rad", 0.0))
		var reference_tail: float = baseline_tail + float(trim.ground_yaw_precomp_tail_bias_rad)
		if baseline_tail < model.tail_collective_min_rad or baseline_tail > model.tail_collective_max_rad \
				or reference_tail < model.tail_collective_min_rad or reference_tail > model.tail_collective_max_rad:
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


static func _positive_vector3(value: Variant) -> bool:
	if (not value is Array and not value is PackedFloat64Array) or value.size() != 3:
		return false
	for item: Variant in value:
		if not _number(item) or float(item) <= 0.0:
			return false
	return true


static func _as_f64(value: Variant) -> PackedFloat64Array:
	var output := PackedFloat64Array()
	for item: Variant in value:
		output.append(float(item))
	return output
