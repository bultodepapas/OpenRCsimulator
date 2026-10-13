extends RefCounted

## Pure, normalized swashplate kernels. This file has no session or input dependencies.
const MATH3D = preload("res://physics/math3d.gd")

const CURVE_POINT_COUNT: int = 5
const SERVO_COUNT: int = 3
const AXIS_LIMIT: float = 1.0
# Maximum absolute output of mix_120 over its three [-1, 1] axes is
# 1.5 + sqrt(3) / 2, reached at a rear servo.
const SERVO_COMMAND_LIMIT: float = 2.3660254037844386


## Each mode has exactly `pitch` and `throttle` five-point curves. Pitch is in [-1, 1],
## throttle is in [0, 1], and their shared input knots are [-1, -0.5, 0, 0.5, 1].
static func validate_curves(curves_by_mode: Variant) -> Dictionary:
	if typeof(curves_by_mode) != TYPE_DICTIONARY or curves_by_mode.is_empty():
		return _failure("curves must be a non-empty mode dictionary")
	for mode_name in curves_by_mode.keys():
		if typeof(mode_name) != TYPE_STRING or mode_name.strip_edges().is_empty():
			return _failure("mode names must be non-empty strings")
		var mode_curves: Variant = curves_by_mode[mode_name]
		if typeof(mode_curves) != TYPE_DICTIONARY or mode_curves.size() != 2:
			return _failure("each mode must contain exactly pitch and throttle curves")
		if not mode_curves.has("pitch") or not mode_curves.has("throttle"):
			return _failure("each mode must contain pitch and throttle curves")
		if not _curve_is_valid(mode_curves["pitch"], -1.0, 1.0):
			return _failure("pitch curve must have five finite values in [-1, 1]")
		if not _curve_is_valid(mode_curves["throttle"], 0.0, 1.0):
			return _failure("throttle curve must have five finite values in [0, 1]")
	return {"ok": true}


static func sample_mode_curve(curves_by_mode: Variant, mode_name: Variant, channel: Variant, normalized_input: Variant) -> Dictionary:
	var curve_validation := validate_curves(curves_by_mode)
	if not curve_validation["ok"]:
		return curve_validation
	if typeof(mode_name) != TYPE_STRING or not curves_by_mode.has(mode_name):
		return _failure("requested flight mode is absent")
	if typeof(channel) != TYPE_STRING or (channel != "pitch" and channel != "throttle"):
		return _failure("channel must be pitch or throttle")
	if not _number_in_range(normalized_input, -1.0, 1.0):
		return _failure("curve input must be finite and in [-1, 1]")

	var points: Variant = curves_by_mode[mode_name][channel]
	var position: float = (float(normalized_input) + 1.0) * 2.0
	if position >= 4.0:
		return {"ok": true, "value": float(points[4])}
	var lower_index: int = int(position)
	var fraction: float = position - float(lower_index)
	var lower_value: float = float(points[lower_index])
	var upper_value: float = float(points[lower_index + 1])
	return {"ok": true, "value": lower_value + fraction * (upper_value - lower_value)}


## Top view uses x-forward, y-right. Servo order is front (0 deg), rear-right (+120 deg),
## rear-left (-120 deg). Positive cyclic raises the corresponding swash side: front for
## longitudinal, right for lateral. Inputs and output commands are normalized units.
static func mix_120(collective: Variant, longitudinal: Variant, lateral: Variant) -> Dictionary:
	if not _number_in_range(collective, -AXIS_LIMIT, AXIS_LIMIT):
		return _failure("collective must be finite and in [-1, 1]")
	if not _number_in_range(longitudinal, -AXIS_LIMIT, AXIS_LIMIT):
		return _failure("longitudinal cyclic must be finite and in [-1, 1]")
	if not _number_in_range(lateral, -AXIS_LIMIT, AXIS_LIMIT):
		return _failure("lateral cyclic must be finite and in [-1, 1]")
	var root_three: float = MATH3D.sqrt_(3.0)
	var front: float = float(collective) + float(longitudinal)
	var rear_right: float = float(collective) - 0.5 * float(longitudinal) + 0.5 * root_three * float(lateral)
	var rear_left: float = float(collective) - 0.5 * float(longitudinal) - 0.5 * root_three * float(lateral)
	return {"ok": true, "servo_targets": PackedFloat64Array([front, rear_right, rear_left])}


## Decodes three normalized swash-rise servo positions in [-1, 1] using the same order
## and axis convention as mix_120. Positions outside configured normalized travel fail closed.
static func unmix_120(servo_positions: Variant) -> Dictionary:
	if not _sequence_has_size(servo_positions, SERVO_COUNT):
		return _failure("servo positions must contain exactly three numeric values")
	for index in SERVO_COUNT:
		if not _number_in_range(servo_positions[index], -1.0, 1.0):
			return _failure("servo positions must be finite and in [-1, 1]")
	var front: float = float(servo_positions[0])
	var rear_right: float = float(servo_positions[1])
	var rear_left: float = float(servo_positions[2])
	var collective: float = (front + rear_right + rear_left) / 3.0
	var longitudinal: float = (2.0 * front - rear_right - rear_left) / 3.0
	var lateral: float = (rear_right - rear_left) / MATH3D.sqrt_(3.0)
	return {
		"ok": true,
		"collective": collective,
		"longitudinal": longitudinal,
		"lateral": lateral,
	}


## Advances one per-servo response step. Servo positions and travel limits use normalized
## swash-rise units in [-1, 1]. The exact first-order lag step is rate-capped afterward.
## Required spec keys: travel_min, travel_max, rate_per_second; optional lag_seconds (zero by default).
static func step_servos(previous_positions: Variant, desired_positions: Variant, servo_spec: Variant, dt_seconds: Variant) -> Dictionary:
	if not _sequence_has_size(previous_positions, SERVO_COUNT):
		return _failure("previous positions must contain exactly three numeric values")
	if not _sequence_has_size(desired_positions, SERVO_COUNT):
		return _failure("desired positions must contain exactly three numeric values")
	if typeof(servo_spec) != TYPE_DICTIONARY:
		return _failure("servo spec must be a dictionary")
	if not _is_finite_number(dt_seconds) or float(dt_seconds) <= 0.0:
		return _failure("dt must be finite and positive")

	var allowed_keys: Array = ["travel_min", "travel_max", "rate_per_second", "lag_seconds"]
	for key in servo_spec.keys():
		if typeof(key) != TYPE_STRING or not allowed_keys.has(key):
			return _failure("servo spec contains an unknown key")
	if not servo_spec.has("travel_min") or not servo_spec.has("travel_max") or not servo_spec.has("rate_per_second"):
		return _failure("servo spec is missing a required field")
	var travel_min: Variant = servo_spec["travel_min"]
	var travel_max: Variant = servo_spec["travel_max"]
	var rates: Variant = servo_spec["rate_per_second"]
	var lags: Variant = servo_spec.get("lag_seconds", PackedFloat64Array([0.0, 0.0, 0.0]))
	if not _sequence_has_size(travel_min, SERVO_COUNT) or not _sequence_has_size(travel_max, SERVO_COUNT):
		return _failure("travel limits must each contain exactly three numeric values")
	if not _sequence_has_size(rates, SERVO_COUNT) or not _sequence_has_size(lags, SERVO_COUNT):
		return _failure("rate and lag arrays must each contain exactly three numeric values")

	for index in SERVO_COUNT:
		if not _number_in_range(travel_min[index], -1.0, 1.0) or not _number_in_range(travel_max[index], -1.0, 1.0):
			return _failure("travel limits must be finite and in [-1, 1]")
		if float(travel_min[index]) >= float(travel_max[index]):
			return _failure("each servo minimum must be less than its maximum")
		if not _is_finite_number(rates[index]) or float(rates[index]) < 0.0 or not _is_finite_number(lags[index]) or float(lags[index]) < 0.0:
			return _failure("servo rates and lags must be finite and non-negative")
		if not _number_in_range(previous_positions[index], float(travel_min[index]), float(travel_max[index])):
			return _failure("previous servo position is outside its declared travel")
		if not _number_in_range(desired_positions[index], -SERVO_COMMAND_LIMIT, SERVO_COMMAND_LIMIT):
			return _failure("desired servo command must be finite and within the mixer-reachable range")

	var positions := PackedFloat64Array()
	var clamped_flags: Array[bool] = []
	var rate_limited_flags: Array[bool] = []
	for index in SERVO_COUNT:
		var low: float = float(travel_min[index])
		var high: float = float(travel_max[index])
		var rate: float = float(rates[index])
		var lag: float = float(lags[index])
		var previous: float = float(previous_positions[index])
		var target: float = clampf(float(desired_positions[index]), low, high)
		var error: float = target - previous
		var lag_fraction: float = 1.0
		if lag > 0.0:
			var time_ratio: float = float(dt_seconds) / lag
			if not is_finite(time_ratio):
				return _failure("servo dt-to-lag ratio is outside the finite range")
			lag_fraction = 1.0 - MATH3D.exp_(-time_ratio)
		var lagged_delta: float = error * lag_fraction
		var maximum_delta: float = rate * float(dt_seconds)
		if not is_finite(lagged_delta) or not is_finite(maximum_delta):
			return _failure("servo step overflowed finite range")
		var delta: float = clampf(lagged_delta, -maximum_delta, maximum_delta)
		positions.append(previous + delta)
		clamped_flags.append(target != float(desired_positions[index]))
		rate_limited_flags.append(absf(delta) < absf(lagged_delta))
	return {
		"ok": true,
		"positions": positions,
		"travel_clamped": clamped_flags,
		"rate_limited": rate_limited_flags,
	}


## Converts achieved normalized servo positions to linear blade-pitch harmonics (radians).
## Linkage keys: collective_rad_per_unit, longitudinal_rad_per_unit, lateral_rad_per_unit,
## collective_min_rad, collective_max_rad, cyclic_max_rad. Limits and ratios are caller-declared.
static func linkage_output(servo_positions: Variant, linkage: Variant) -> Dictionary:
	var axes := unmix_120(servo_positions)
	if not axes["ok"]:
		return axes
	if typeof(linkage) != TYPE_DICTIONARY or linkage.size() != 6:
		return _failure("linkage must contain exactly six declared fields")
	var required_keys: Array = [
		"collective_rad_per_unit", "longitudinal_rad_per_unit", "lateral_rad_per_unit",
		"collective_min_rad", "collective_max_rad", "cyclic_max_rad",
	]
	for key in required_keys:
		if not linkage.has(key):
			return _failure("linkage is missing a required field")
	for key in linkage.keys():
		if typeof(key) != TYPE_STRING or not required_keys.has(key):
			return _failure("linkage contains an unknown field")
	for key in ["collective_rad_per_unit", "longitudinal_rad_per_unit", "lateral_rad_per_unit"]:
		if not _is_finite_number(linkage[key]) or float(linkage[key]) <= 0.0:
			return _failure("linkage ratios must be finite and positive")
	if not _is_finite_number(linkage["collective_min_rad"]):
		return _failure("collective minimum must be finite")
	if not _is_finite_number(linkage["collective_max_rad"]):
		return _failure("collective maximum must be finite")
	if float(linkage["collective_min_rad"]) >= float(linkage["collective_max_rad"]):
		return _failure("collective minimum must be less than maximum")
	if not _is_finite_number(linkage["cyclic_max_rad"]) or float(linkage["cyclic_max_rad"]) < 0.0:
		return _failure("cyclic limit must be finite and non-negative")

	var collective_raw: float = float(axes["collective"]) * float(linkage["collective_rad_per_unit"])
	var longitudinal_raw: float = float(axes["longitudinal"]) * float(linkage["longitudinal_rad_per_unit"])
	var lateral_raw: float = float(axes["lateral"]) * float(linkage["lateral_rad_per_unit"])
	if not is_finite(collective_raw) or not is_finite(longitudinal_raw) or not is_finite(lateral_raw):
		return _failure("linkage output overflowed finite range")
	var cyclic_limit: float = float(linkage["cyclic_max_rad"])
	return {
		"ok": true,
		"theta0_rad": clampf(collective_raw, float(linkage["collective_min_rad"]), float(linkage["collective_max_rad"])),
		"longitudinal_rad": clampf(longitudinal_raw, -cyclic_limit, cyclic_limit),
		"lateral_rad": clampf(lateral_raw, -cyclic_limit, cyclic_limit),
	}


static func _curve_is_valid(points: Variant, minimum: float, maximum: float) -> bool:
	if not _sequence_has_size(points, CURVE_POINT_COUNT):
		return false
	for index in CURVE_POINT_COUNT:
		if not _number_in_range(points[index], minimum, maximum):
			return false
	return true


static func _sequence_has_size(values: Variant, expected_size: int) -> bool:
	var kind: int = typeof(values)
	if kind != TYPE_ARRAY and kind != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	return values.size() == expected_size


static func _number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	if not _is_finite_number(value):
		return false
	var number: float = float(value)
	return number >= minimum and number <= maximum


static func _is_finite_number(value: Variant) -> bool:
	var kind: int = typeof(value)
	if kind != TYPE_FLOAT and kind != TYPE_INT:
		return false
	return is_finite(float(value))


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
