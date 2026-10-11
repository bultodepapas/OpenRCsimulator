# EL2a-P1 differential oracle. All fixtures are synthetic and are coverage, not calibration.
extends SceneTree

const Candidate: Script = preload("res://physics/electric_supply.gd")
const Frozen: Script = preload("res://../research/propulsion/el2a-p1/frozen_electric_supply.gd")
const SAMPLE_COUNT: int = 10000

var _rng_state: int = 0x6D2B79F5
var _comparisons: int = 0
var _failures: int = 0
var _first_failure: String = ""


func _initialize() -> void:
	_run_seeded_valid_cases()
	_run_invalid_cases()
	_run_mutation_controls()
	print("EL2a-P1 electric source oracle: %d byte comparisons, %d failures" % [_comparisons, _failures])
	if _failures > 0:
		print("first mismatch: " + _first_failure)
	quit(1 if _failures > 0 else 0)


func _run_seeded_valid_cases() -> void:
	for sample: int in SAMPLE_COUNT:
		var args: Array = _valid_arguments(sample)
		_compare_public_case("seed %05d evaluate" % sample, args, false)
		_compare_public_case("seed %05d evaluate_available" % sample, args, true)


func _run_invalid_cases() -> void:
	var base: Array = [1800.0, 0.55, 0.63, _pack_fixture(), _motor_fixture(), true]
	var cases: Array[Dictionary] = []
	var args: Array
	var invalid_pack: Dictionary
	var invalid_motor: Dictionary

	args = _copy_args(base)
	args[0] = true
	cases.append({"name": "boolean rpm", "args": args})
	args = _copy_args(base)
	args[0] = NAN
	cases.append({"name": "nonfinite rpm", "args": args})
	args = _copy_args(base)
	args[1] = "0.5"
	cases.append({"name": "string duty", "args": args})
	args = _copy_args(base)
	args[1] = INF
	cases.append({"name": "infinite duty", "args": args})
	args = _copy_args(base)
	args[2] = 1.01
	cases.append({"name": "out-of-range SOC", "args": args})
	args = _copy_args(base)
	args[5] = 1
	cases.append({"name": "nonboolean enabled", "args": args})
	args = _copy_args(base)
	args[3] = null
	cases.append({"name": "non-dictionary pack", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack.erase("capacity_ah")
	cases.append({"name": "missing pack field", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["future_state"] = 0.1
	cases.append({"name": "unknown pack key", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["ocv_points"] = [0.0, 10.0, 1.0, 14.0]
	cases.append({"name": "wrong OCV array type", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["ocv_points"] = PackedFloat64Array([0.0, 10.0, 0.5])
	cases.append({"name": "odd OCV point count", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["ocv_points"][2] = NAN
	cases.append({"name": "nonfinite OCV knot", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["ocv_points"] = PackedFloat64Array([0.0, 10.0, 0.5, 12.0, 0.5, 13.0, 1.0, 14.0])
	cases.append({"name": "duplicate OCV knot", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["capacity_ah"] = "2"
	cases.append({"name": "string capacity", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["capacity_ah"] = 1e308
	cases.append({"name": "capacity coulomb overflow", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	# Normal finite inputs and power isolate only the derived SOC-rate overflow.
	invalid_pack["ocv_points"] = PackedFloat64Array([0.0, 1e-200, 1.0, 1e-200])
	invalid_pack["capacity_ah"] = 1e-100
	invalid_pack["resistance_ohm"] = 0.0
	invalid_pack["auxiliary_current_a"] = 1e280
	args[0] = 0.0
	args[1] = 0.0
	cases.append({"name": "SOC-rate overflow", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["resistance_ohm"] = -0.1
	cases.append({"name": "negative pack resistance", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["auxiliary_current_a"] = INF
	cases.append({"name": "nonfinite auxiliary current", "args": args})
	args = _copy_args(base)
	invalid_pack = args[3]
	invalid_pack["resistance_ohm"] = 1e308
	cases.append({"name": "auxiliary sag overflow", "args": args})
	args = _copy_args(base)
	args[4] = null
	cases.append({"name": "non-dictionary motor", "args": args})
	args = _copy_args(base)
	invalid_motor = args[4]
	invalid_motor["phase_current_a"] = 4.0
	cases.append({"name": "unknown motor key", "args": args})
	args = _copy_args(base)
	invalid_motor = args[4]
	invalid_motor["kv_rpm_per_volt"] = NAN
	cases.append({"name": "nonfinite motor Kv", "args": args})
	args = _copy_args(base)
	invalid_motor = args[4]
	invalid_motor["resistance_ohm"] = 0.0
	cases.append({"name": "zero motor resistance", "args": args})
	args = _copy_args(base)
	args[0] = 1e308
	invalid_motor = args[4]
	invalid_motor["kv_rpm_per_volt"] = 1e-308
	cases.append({"name": "back-EMF overflow", "args": args})
	args = _copy_args(base)
	args[0] = 0.0
	invalid_motor = args[4]
	invalid_motor["kv_rpm_per_volt"] = 1e-308
	cases.append({"name": "motor constant overflow", "args": args})
	args = _copy_args(base)
	args[0] = 0.0
	args[1] = 0.0
	var huge_pack: Dictionary = {
		"ocv_points": PackedFloat64Array([0.0, 1e308, 1.0, 1e308]),
		"capacity_ah": 1.0,
		"resistance_ohm": 0.0,
		"auxiliary_current_a": 1e308,
	}
	args[3] = huge_pack
	cases.append({"name": "pack power overflow", "args": args})

	for test_case: Dictionary in cases:
		var label: String = str(test_case.name)
		var test_args: Array = test_case.args
		_compare_public_case("invalid " + label + " evaluate", test_args, false)
		_compare_public_case("invalid " + label + " evaluate_available", test_args, true)


func _compare_public_case(label: String, args: Array, available_at_zero: bool) -> void:
	var rpm: Variant = args[0]
	var duty: Variant = args[1]
	var soc: Variant = args[2]
	var pack: Variant = args[3]
	var motor: Variant = args[4]
	var enabled: Variant = args[5]
	var expected: Dictionary = Frozen.evaluate_available(rpm, duty, soc, pack, motor, enabled) \
		if available_at_zero else Frozen.evaluate(rpm, duty, soc, pack, motor, enabled)
	var actual: Dictionary = Candidate.evaluate_available(rpm, duty, soc, pack, motor, enabled) \
		if available_at_zero else Candidate.evaluate(rpm, duty, soc, pack, motor, enabled)
	_compare(label + " public result", expected, actual)
	var compact_expected: Dictionary = expected if not expected.get("ok", false) else _consumed_fields(expected)
	var compact_actual: Dictionary = Candidate.evaluate_dynamics(
		rpm, duty, soc, pack, motor, enabled, available_at_zero)
	_compare(label + " dynamics result", compact_expected, compact_actual)


func _consumed_fields(result: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"shaft_torque_nm": result.shaft_torque_nm,
		"motor_current_a": result.motor_current_a,
		"pack_current_a": result.pack_current_a,
		"pack_terminal_power_w": result.pack_terminal_power_w,
		"pack_loss_w": result.pack_loss_w,
	}


func _run_mutation_controls() -> void:
	var args: Array = [1800.0, 0.55, 0.63, _pack_fixture(), _motor_fixture(), true]
	var full: Dictionary = Frozen.evaluate(args[0], args[1], args[2], args[3], args[4], args[5])
	var compact: Dictionary = _consumed_fields(full)
	var changed_torque: Dictionary = compact.duplicate(true)
	changed_torque["shaft_torque_nm"] = float(changed_torque.shaft_torque_nm) + 1.0
	_check_mutation("synthetic torque mutation detected", compact, changed_torque)
	var changed_charge: Dictionary = compact.duplicate(true)
	changed_charge["pack_current_a"] = float(changed_charge.pack_current_a) + 1.0
	_check_mutation("synthetic charge mutation detected", compact, changed_charge)


func _check_mutation(label: String, expected: Dictionary, changed: Dictionary) -> void:
	_comparisons += 1
	if var_to_bytes(expected) == var_to_bytes(changed):
		_record_failure(label)


func _valid_arguments(sample: int) -> Array:
	var knot_count: int = 2 + int(_next_u32() % 5)
	var points: PackedFloat64Array = PackedFloat64Array()
	var voltage: float = 5.0 + 50.0 * _unit()
	points.append(0.0)
	points.append(voltage)
	for knot: int in range(1, knot_count):
		voltage += 0.1 + 20.0 * _unit()
		points.append(float(knot) / float(knot_count - 1))
		points.append(voltage)
	var top_voltage: float = points[points.size() - 1]
	var kv: float = 20.0 + 2480.0 * _unit()
	var motor_resistance: float = 0.003 + 2.0 * _unit()
	var no_load_current: float = 6.0 * _unit()
	var pack_resistance: float = 0.25 * _unit()
	var auxiliary_current: float = 3.0 * _unit()
	var capacity: float = 0.02 + 80.0 * _unit()
	if sample % 211 == 0:
		kv = 0.01
	if sample % 223 == 0:
		kv = 100000.0
	if sample % 227 == 0:
		motor_resistance = 1e-8
	if sample % 229 == 0:
		no_load_current = 100.0
	if sample % 233 == 0:
		pack_resistance = 0.0
	if sample % 239 == 0:
		capacity = 1e-6
	var motor: Dictionary = _motor_fixture(kv, motor_resistance, no_load_current)
	var pack: Dictionary = _pack_fixture(pack_resistance, auxiliary_current, capacity, points)
	var rpm: float = (1.4 * _unit()) * top_voltage * kv
	var duty: float = _unit()
	var soc: float = _unit()
	if sample % 29 == 0:
		rpm = 0.0
	elif sample % 31 == 0:
		rpm = 1.4 * top_voltage * kv
	if sample % 31 == 0:
		duty = 0.0
	elif sample % 37 == 0:
		duty = 1.0
	if sample % 19 == 0:
		soc = 0.0
	elif sample % 23 == 0:
		soc = 1.0
	return [rpm, duty, soc, pack, motor, sample % 7 != 0]


func _pack_fixture(resistance: float = 0.08, auxiliary: float = 0.4,
		capacity: float = 3.0, points: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	var ocv_points: PackedFloat64Array = points
	if ocv_points.is_empty():
		ocv_points = PackedFloat64Array([0.0, 10.0, 0.5, 12.0, 1.0, 14.0])
	return {
		"ocv_points": ocv_points,
		"capacity_ah": capacity,
		"resistance_ohm": resistance,
		"auxiliary_current_a": auxiliary,
	}


func _motor_fixture(kv: float = 600.0, resistance: float = 0.2,
		no_load: float = 1.0) -> Dictionary:
	return {
		"kv_rpm_per_volt": kv,
		"resistance_ohm": resistance,
		"no_load_current_a": no_load,
	}


func _copy_args(source: Array) -> Array:
	var copied: Array = source.duplicate()
	if typeof(source[3]) == TYPE_DICTIONARY:
		copied[3] = source[3].duplicate(true)
	if typeof(source[4]) == TYPE_DICTIONARY:
		copied[4] = source[4].duplicate(true)
	return copied


func _next_u32() -> int:
	var value: int = _rng_state & 0xFFFFFFFF
	value = (value ^ (value << 13)) & 0xFFFFFFFF
	value = (value ^ (value >> 17)) & 0xFFFFFFFF
	value = (value ^ (value << 5)) & 0xFFFFFFFF
	_rng_state = value
	return value


func _unit() -> float:
	return float(_next_u32() & 0x00FFFFFF) / 16777216.0


func _compare(label: String, expected: Dictionary, actual: Dictionary) -> void:
	_comparisons += 1
	if var_to_bytes(expected) == var_to_bytes(actual):
		return
	_record_failure(label)


func _record_failure(label: String) -> void:
	_failures += 1
	if _first_failure.is_empty():
		_first_failure = label
	if _failures <= 5:
		print("FAIL: " + label)
