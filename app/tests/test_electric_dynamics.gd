# EL2a-P1 compact source checks; all values are synthetic fixtures, not calibration.
extends SceneTree

const Supply: Script = preload("res://physics/electric_supply.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_stage_matches_public_boundaries()
	_mutable_inputs_are_revalidated()
	_compact_path_preserves_fail_closed_validation()
	print("EL2a-P1 electric dynamics: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _stage_matches_public_boundaries() -> void:
	var pack: Dictionary = _pack_fixture()
	var motor: Dictionary = _motor_fixture()
	var args: Array = [1800.0, 0.55, 0.63, pack, motor, true]
	var ordinary: Dictionary = _stage_matches_public("ordinary point", args, false)
	_check("ordinary compact point accepted", ordinary.get("ok", false))
	var overrun_args: Array = args.duplicate()
	overrun_args[0] = 9000.0
	var overrun: Dictionary = _stage_matches_public("overrun point", overrun_args, false)
	_check("overrun compact point accepted", overrun.get("ok", false))
	var exhausted_args: Array = args.duplicate()
	exhausted_args[2] = 0.0
	var exhausted: Dictionary = _stage_matches_public("exhausted boundary", exhausted_args, false)
	_check("exhausted compact point accepted", exhausted.get("ok", false))
	var available: Dictionary = _stage_matches_public("available at zero boundary", exhausted_args, true)
	_check("available-at-zero compact point accepted", available.get("ok", false))
	_check("empty boundary and left-limit remain distinct",
		var_to_bytes(exhausted) != var_to_bytes(available))
	var stopped_args: Array = args.duplicate()
	stopped_args[0] = 0.0
	var stopped: Dictionary = _stage_matches_public("rest point", stopped_args, false)
	_check("rest compact point accepted", stopped.get("ok", false))
	var disabled_args: Array = args.duplicate()
	disabled_args[5] = false
	var disabled: Dictionary = _stage_matches_public("disabled source", disabled_args, false)
	_check("disabled compact point accepted", disabled.get("ok", false))


func _mutable_inputs_are_revalidated() -> void:
	var pack: Dictionary = _pack_fixture()
	var motor: Dictionary = _motor_fixture()
	var args: Array = [1800.0, 0.55, 0.63, pack, motor, true]
	var baseline: Dictionary = _stage_matches_public("mutable baseline", args, false)
	pack["resistance_ohm"] = 0.3
	var changed_pack: Dictionary = _stage_matches_public("mutated pack resistance", args, false)
	_check("pack mutation changes compact output",
		var_to_bytes(baseline) != var_to_bytes(changed_pack))
	pack["auxiliary_current_a"] = 0.9
	var changed_auxiliary: Dictionary = _stage_matches_public("mutated pack auxiliary", args, false)
	_check("auxiliary mutation changes compact output",
		var_to_bytes(changed_pack) != var_to_bytes(changed_auxiliary))
	motor["resistance_ohm"] = 0.5
	var changed_motor_resistance: Dictionary = _stage_matches_public("mutated motor resistance", args, false)
	_check("motor resistance mutation changes compact output",
		var_to_bytes(changed_auxiliary) != var_to_bytes(changed_motor_resistance))
	motor["kv_rpm_per_volt"] = 350.0
	var changed_motor_kv: Dictionary = _stage_matches_public("mutated motor Kv", args, false)
	_check("motor Kv mutation changes compact output",
		var_to_bytes(changed_motor_resistance) != var_to_bytes(changed_motor_kv))


func _compact_path_preserves_fail_closed_validation() -> void:
	var base: Array = [1800.0, 0.55, 0.63, _pack_fixture(), _motor_fixture(), true]
	var cases: Array[Dictionary] = []
	var args: Array
	var invalid_pack: Dictionary
	var invalid_motor: Dictionary

	args = _copy_args(base)
	args[0] = "1800"
	cases.append({"name": "wrong rpm type", "args": args})
	args = _copy_args(base)
	args[1] = NAN
	cases.append({"name": "nonfinite duty", "args": args})
	args = _copy_args(base)
	args[5] = 1
	cases.append({"name": "wrong enabled type", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["ocv_points"] = [0.0, 10.0, 1.0, 14.0]
	cases.append({"name": "wrong OCV representation", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["ocv_points"][2] = INF
	cases.append({"name": "nonfinite OCV knot", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["future_state"] = 0.2
	cases.append({"name": "unknown pack key", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["capacity_ah"] = 1e308
	cases.append({"name": "capacity conversion overflow", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	# Keep input values and power finite; only the SOC-rate quotient overflows.
	invalid_pack["ocv_points"] = PackedFloat64Array([0.0, 1e-200, 1.0, 1e-200])
	invalid_pack["capacity_ah"] = 1e-100
	invalid_pack["resistance_ohm"] = 0.0
	invalid_pack["auxiliary_current_a"] = 1e280
	args[0] = 0.0
	args[1] = 0.0
	cases.append({"name": "derived SOC rate overflow", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["resistance_ohm"] = 1e308
	cases.append({"name": "auxiliary sag overflow", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["ocv_points"] = PackedFloat64Array([0.0, 1e308, 1.0, 1e308])
	invalid_pack["resistance_ohm"] = 0.0
	invalid_pack["auxiliary_current_a"] = 1e308
	args[0] = 0.0
	args[1] = 0.0
	cases.append({"name": "pack power overflow", "args": args})
	args = _copy_args(base)
	invalid_motor = args[4]
	invalid_motor["unsupported"] = 1.0
	cases.append({"name": "unknown motor key", "args": args})
	args = _copy_args(base)
	invalid_motor = args[4]
	invalid_motor["kv_rpm_per_volt"] = NAN
	cases.append({"name": "nonfinite motor constant", "args": args})
	args = _copy_args(base)
	args[0] = 1e308
	invalid_motor = args[4]
	invalid_motor["kv_rpm_per_volt"] = 1e-308
	cases.append({"name": "back-EMF overflow", "args": args})

	for test_case: Dictionary in cases:
		var failed: Dictionary = _stage_matches_public(
			str(test_case.name), test_case.args, false)
		_check(str(test_case.name) + " rejected by compact path", not failed.get("ok", true))
		var available_failed: Dictionary = _stage_matches_public(
			str(test_case.name) + " available", test_case.args, true)
		_check(str(test_case.name) + " rejected by available compact path",
			not available_failed.get("ok", true))


func _stage_matches_public(label: String, args: Array, available_at_zero: bool) -> Dictionary:
	var expected: Dictionary = Supply.evaluate_available(
		args[0], args[1], args[2], args[3], args[4], args[5]) if available_at_zero else Supply.evaluate(
		args[0], args[1], args[2], args[3], args[4], args[5])
	var actual: Dictionary = Supply.evaluate_dynamics(
		args[0], args[1], args[2], args[3], args[4], args[5], available_at_zero)
	if expected.get("ok", false):
		var expected_subset: Dictionary = {
			"ok": true,
			"shaft_torque_nm": expected.shaft_torque_nm,
			"motor_current_a": expected.motor_current_a,
			"pack_current_a": expected.pack_current_a,
			"pack_terminal_power_w": expected.pack_terminal_power_w,
			"pack_loss_w": expected.pack_loss_w,
		}
		_check(label + " stage subset matches public native bytes",
			var_to_bytes(expected_subset) == var_to_bytes(actual))
	else:
		_check(label + " stage failure matches public native bytes",
			var_to_bytes(expected) == var_to_bytes(actual))
	return actual


func _copy_args(source: Array) -> Array:
	var copied: Array = source.duplicate()
	if typeof(source[3]) == TYPE_DICTIONARY:
		copied[3] = source[3].duplicate(true)
	if typeof(source[4]) == TYPE_DICTIONARY:
		copied[4] = source[4].duplicate(true)
	return copied


func _pack_fixture() -> Dictionary:
	return {
		"ocv_points": PackedFloat64Array([0.0, 10.0, 0.5, 12.0, 1.0, 14.0]),
		"capacity_ah": 3.0,
		"resistance_ohm": 0.08,
		"auxiliary_current_a": 0.4,
	}


func _motor_fixture() -> Dictionary:
	return {"kv_rpm_per_volt": 600.0, "resistance_ohm": 0.2, "no_load_current_a": 1.0}


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)
