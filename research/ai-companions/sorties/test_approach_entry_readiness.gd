## AFC-09 unit checks for the measured entry-envelope classifier; no simulation is run.
extends SceneTree

var readiness_script: Script
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	var script_dir: String = get_script().resource_path.get_base_dir()
	readiness_script = load(script_dir.path_join("approach_entry_readiness.gd"))
	if readiness_script == null:
		printerr("Approach-entry readiness classifier is unavailable.")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var nominal := _nominal_metrics()
	_assert(bool(readiness_script.classify(nominal).ready), "nominal measured gate is ready")

	var upper_bound := nominal.duplicate(true)
	upper_bound.altitude_m = 6.5
	upper_bound.airspeed_mps = 12.5
	upper_bound.north_m = 16.0
	upper_bound.east_m = 10.25
	upper_bound.yaw_rad = deg_to_rad(8.0)
	upper_bound.bank_rad = deg_to_rad(5.0)
	upper_bound.sink_mps = 1.0
	_assert(bool(readiness_script.classify(upper_bound).ready), "all existing upper gate bounds are inclusive")

	var lower_bound := nominal.duplicate(true)
	lower_bound.altitude_m = 5.5
	lower_bound.airspeed_mps = 11.5
	lower_bound.north_m = 14.0
	lower_bound.east_m = 9.75
	lower_bound.yaw_rad = -deg_to_rad(8.0)
	lower_bound.bank_rad = -deg_to_rad(5.0)
	lower_bound.sink_mps = -1.0
	_assert(bool(readiness_script.classify(lower_bound).ready), "all existing lower gate bounds are inclusive")

	_assert_rejected(nominal, "altitude_m", 6.5001, "altitude")
	_assert_rejected(nominal, "altitude_m", 5.4999, "altitude")
	_assert_rejected(nominal, "airspeed_mps", 12.5001, "airspeed")
	_assert_rejected(nominal, "airspeed_mps", 11.4999, "airspeed")
	_assert_rejected(nominal, "north_m", 16.0001, "cross_track")
	_assert_rejected(nominal, "north_m", 13.9999, "cross_track")
	_assert_rejected(nominal, "east_m", 10.2501, "gate_position")
	_assert_rejected(nominal, "east_m", 9.7499, "gate_position")
	_assert_rejected(nominal, "yaw_rad", deg_to_rad(8.001), "heading")
	_assert_rejected(nominal, "yaw_rad", -deg_to_rad(8.001), "heading")
	_assert_rejected(nominal, "bank_rad", deg_to_rad(5.001), "bank")
	_assert_rejected(nominal, "bank_rad", -deg_to_rad(5.001), "bank")
	_assert_rejected(nominal, "sink_mps", 1.0001, "sink")
	_assert_rejected(nominal, "sink_mps", -1.0001, "sink")

	var numeric_fields := [
		["altitude_m", "altitude"], ["airspeed_mps", "airspeed"],
		["north_m", "cross_track"], ["runway_center_north_m", "cross_track"],
		["east_m", "gate_position"], ["expected_east_m", "gate_position"],
		["yaw_rad", "heading"], ["expected_heading_rad", "heading"],
		["bank_rad", "bank"], ["sink_mps", "sink"], ["ground_speed_mps", "ground_speed"],
	]
	for field: Array in numeric_fields:
		_assert_invalid_measured_field(nominal, str(field[0]), str(field[1]))

	var wrapped_heading := nominal.duplicate(true)
	wrapped_heading.expected_heading_rad = -PI + 0.01
	wrapped_heading.yaw_rad = PI - 0.01
	_assert(bool(readiness_script.classify(wrapped_heading).ready), "heading error wraps across ±π")
	var wrapped_heading_reverse := nominal.duplicate(true)
	wrapped_heading_reverse.expected_heading_rad = PI - 0.01
	wrapped_heading_reverse.yaw_rad = -PI + 0.01
	_assert(bool(readiness_script.classify(wrapped_heading_reverse).ready), "heading error wraps across ±π in the reverse direction")

	var invalid_prediction := nominal.duplicate(true)
	invalid_prediction.gate_prediction_valid = false
	_assert_rejected_result(invalid_prediction, "gate_prediction", "invalid wind/gate prediction is refused")
	var missing_prediction := nominal.duplicate(true)
	missing_prediction.erase("gate_prediction_valid")
	_assert_rejected_result(missing_prediction, "gate_prediction", "missing gate prediction is refused")
	for malformed_prediction: Variant in [1, 0, NAN, INF, -INF, "true", "false", null]:
		var malformed := nominal.duplicate(true)
		malformed.gate_prediction_valid = malformed_prediction
		_assert_rejected_result(malformed, "gate_prediction", "non-boolean gate prediction is refused")
	var missing_position := nominal.duplicate(true)
	missing_position.erase("east_m")
	_assert_rejected_result(missing_position, "gate_position", "missing gate position is refused")
	var nonnumeric_speed := nominal.duplicate(true)
	nonnumeric_speed.ground_speed_mps = "unknown"
	_assert_rejected_result(nonnumeric_speed, "ground_speed", "nonnumeric ground speed is refused")

	print("AFC-09 approach-entry readiness: %d checks, %d failed" % [checks, failures.size()])
	for failure: String in failures:
		printerr("FAIL " + failure)
	quit(1 if not failures.is_empty() else 0)


func _nominal_metrics() -> Dictionary:
	return {
		altitude_m = 6.0,
		airspeed_mps = 12.0,
		north_m = 15.0,
		runway_center_north_m = 15.0,
		east_m = 10.0,
		expected_east_m = 10.0,
		yaw_rad = 0.0,
		expected_heading_rad = 0.0,
		bank_rad = 0.0,
		sink_mps = 0.0,
		ground_speed_mps = 10.0,
		gate_prediction_valid = true,
	}


func _assert_rejected(metrics: Dictionary, key: String, value: Variant, reason: String) -> void:
	var changed: Dictionary = metrics.duplicate(true)
	changed[key] = value
	_assert_rejected_result(changed, reason, "%s outside existing envelope is refused" % key)


func _assert_invalid_measured_field(metrics: Dictionary, key: String, reason: String) -> void:
	var missing: Dictionary = metrics.duplicate(true)
	missing.erase(key)
	_assert_rejected_result(missing, reason, "%s missing value is refused" % key)
	for invalid: Variant in [NAN, INF, -INF, true, "not-a-number"]:
		var changed: Dictionary = metrics.duplicate(true)
		changed[key] = invalid
		_assert_rejected_result(changed, reason, "%s malformed value %s is refused" % [key, str(invalid)])


func _assert_rejected_result(metrics: Dictionary, reason: String, label: String) -> void:
	var result: Dictionary = readiness_script.classify(metrics)
	var reasons: Array = result.get("reasons", [])
	_assert(not bool(result.get("ready", true)) and reasons.has(reason), label, str(reasons))


func _assert(condition: bool, label: String, detail: String = "") -> void:
	checks += 1
	if condition:
		return
	failures.append(label + (": " + detail if not detail.is_empty() else ""))
