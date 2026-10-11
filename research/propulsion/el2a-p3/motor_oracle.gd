# EL2a-P3 motor compact-path differential oracle. Fixtures cover arithmetic and guards, not calibration.
extends SceneTree

const Candidate: Script = preload("res://physics/electric_motor.gd")
const Frozen: Script = preload("res://../research/propulsion/el2a-p1/frozen_electric_motor.gd")
const SAMPLE_COUNT: int = 10000
const MOTOR_KEYS: Array[String] = ["kv_rpm_per_volt", "resistance_ohm", "no_load_current_a"]

var _rng_state: int = 0x6D2B79F5
var _comparisons: int = 0
var _failures: int = 0
var _first_failure: String = ""


func _initialize() -> void:
	_run_seeded_valid_cases()
	_run_invalid_scalar_cases()
	_run_invalid_motor_cases()
	_run_extreme_overflow_cases()
	_run_mutable_motor_cases()
	_run_mutation_controls()
	print("EL2a-P3 motor oracle: %d byte comparisons, %d failures, samples=%d" % [
		_comparisons, _failures, SAMPLE_COUNT,
	])
	if _failures > 0:
		print("first mismatch: " + _first_failure)
	quit(1 if _failures > 0 else 0)


func _run_seeded_valid_cases() -> void:
	for sample: int in SAMPLE_COUNT:
		var motor: Dictionary = _motor_fixture(
			0.25 + 2499.75 * _unit(),
			0.000001 + 20.0 * _unit(),
			20.0 * _unit(),
		)
		var bus_voltage_v: float = 0.01 + 100.0 * _unit()
		var rpm: float = 1.4 * _unit() * bus_voltage_v * float(motor.kv_rpm_per_volt)
		var duty: float = _unit()
		if sample % 29 == 0:
			rpm = 0.0
		elif sample % 31 == 0:
			rpm = 1.4 * bus_voltage_v * float(motor.kv_rpm_per_volt)
		if sample % 31 == 0:
			duty = 0.0
		elif sample % 37 == 0:
			duty = 1.0
		_compare_motor_case(
			"seed %05d" % sample, rpm, duty, bus_voltage_v, motor, sample % 7 != 0,
		)


func _run_invalid_scalar_cases() -> void:
	var motor: Dictionary = _motor_fixture()
	var cases: Array[Dictionary] = [
		{"name": "negative rpm", "rpm": -1.0, "duty": 0.55, "bus": 12.0},
		{"name": "nonfinite rpm", "rpm": NAN, "duty": 0.55, "bus": 12.0},
		{"name": "infinite rpm", "rpm": INF, "duty": 0.55, "bus": 12.0},
		{"name": "negative duty", "rpm": 1800.0, "duty": -0.01, "bus": 12.0},
		{"name": "duty over one", "rpm": 1800.0, "duty": 1.01, "bus": 12.0},
		{"name": "nonfinite duty", "rpm": 1800.0, "duty": NAN, "bus": 12.0},
		{"name": "negative bus voltage", "rpm": 1800.0, "duty": 0.55, "bus": -0.01},
		{"name": "nonfinite bus voltage", "rpm": 1800.0, "duty": 0.55, "bus": INF},
	]
	for test_case: Dictionary in cases:
		_compare_motor_case(
			"invalid " + str(test_case.name), test_case.rpm, test_case.duty,
			test_case.bus, motor, true,
		)


func _run_invalid_motor_cases() -> void:
	var base: Dictionary = _motor_fixture()
	var cases: Array[Dictionary] = []
	var motor: Dictionary

	motor = base.duplicate(true)
	motor.erase("kv_rpm_per_volt")
	cases.append({"name": "missing Kv", "motor": motor})
	motor = base.duplicate(true)
	motor["kv_rpm_per_volt"] = NAN
	cases.append({"name": "nonfinite Kv", "motor": motor})
	motor = base.duplicate(true)
	motor["resistance_ohm"] = 0.0
	cases.append({"name": "zero resistance", "motor": motor})
	motor = base.duplicate(true)
	motor["no_load_current_a"] = -0.01
	cases.append({"name": "negative idle current", "motor": motor})
	motor = base.duplicate(true)
	motor["future_state"] = 1.0
	cases.append({"name": "unsupported mutable field", "motor": motor})

	for test_case: Dictionary in cases:
		_compare_motor_case(
			"invalid motor " + str(test_case.name), 1800.0, 0.55, 12.0, test_case.motor, true,
		)


func _run_extreme_overflow_cases() -> void:
	var bus_power_case: Dictionary = _bus_power_overflow_case()
	var cases: Array[Dictionary] = [
		{
			"name": "motor constants overflow",
			"rpm": 0.0,
			"duty": 0.0,
			"bus": 12.0,
			"motor": _motor_fixture(1e-308, 0.2, 1.0),
			"message": "motor constants overflow or underflow",
		},
		{
			"name": "motor voltage overflow",
			"rpm": 1e308,
			"duty": 0.0,
			"bus": 12.0,
			"motor": _motor_fixture(1e-100, 0.2, 0.0),
			"message": "motor evaluation overflow: motor_voltage_v",
		},
		{
			"name": "shaft torque overflow",
			"rpm": 0.0,
			"duty": 1.0,
			"bus": 1e308,
			"motor": _motor_fixture(1e-100, 1e8, 0.0),
			"message": "motor evaluation overflow: shaft_torque_nm",
		},
		{
			"name": "shaft power overflow",
			"rpm": 1e308,
			"duty": 1.0,
			"bus": 1e308,
			"motor": _motor_fixture(2.0, 1e307, 0.0),
			"message": "motor evaluation overflow: shaft_power_w",
		},
		{
			"name": "bus power overflow",
			"rpm": bus_power_case.rpm,
			"duty": 1.0,
			"bus": 1e308,
			"motor": bus_power_case.motor,
			"message": "motor evaluation overflow: bus_power_w",
		},
	]
	for test_case: Dictionary in cases:
		var result: Dictionary = _compare_motor_case(
			"overflow " + str(test_case.name), test_case.rpm, test_case.duty,
			test_case.bus, test_case.motor, true,
		)
		var actual_message: String = str(result.get("message", ""))
		_check(
			"overflow diagnostic: %s (expected %s; got %s)" % [
				str(test_case.name), str(test_case.message), actual_message,
			],
			actual_message == str(test_case.message),
		)


func _run_mutable_motor_cases() -> void:
	var motor: Dictionary = _motor_fixture()
	_compare_motor_case("mutable definition baseline", 1800.0, 0.55, 12.0, motor, true)
	motor["kv_rpm_per_volt"] = 430.0
	_compare_motor_case("mutable Kv revalidated", 1800.0, 0.55, 12.0, motor, true)
	motor["resistance_ohm"] = 0.31
	_compare_motor_case("mutable resistance revalidated", 1800.0, 0.55, 12.0, motor, true)
	motor["no_load_current_a"] = 2.25
	_compare_motor_case("mutable idle current revalidated", 1800.0, 0.55, 12.0, motor, true)
	motor["unknown"] = 1.0
	_compare_motor_case("mutated unknown field rejected", 1800.0, 0.55, 12.0, motor, true)
	motor.erase("unknown")
	motor["resistance_ohm"] = 0.0
	_compare_motor_case("mutated domain error rechecked", 1800.0, 0.55, 12.0, motor, true)


func _run_mutation_controls() -> void:
	var motor: Dictionary = _motor_fixture()
	var full: Dictionary = Frozen.evaluate(1800.0, 0.55, 12.0, motor, true)
	if not full.get("ok", false):
		_record_failure("mutation controls need a valid frozen result")
		return
	var compact: Dictionary = _compact_fields(full)
	var changed_torque: Dictionary = compact.duplicate(true)
	changed_torque["shaft_torque_nm"] = float(changed_torque.shaft_torque_nm) + 1.0
	_check_mutation("synthetic torque mutation detected", compact, changed_torque)
	var changed_current: Dictionary = compact.duplicate(true)
	changed_current["motor_current_a"] = float(changed_current.motor_current_a) + 1.0
	_check_mutation("synthetic current mutation detected", compact, changed_current)


func _compare_motor_case(label: String, rpm: float, duty: float, bus_voltage_v: float,
		motor: Dictionary, enabled: bool) -> Dictionary:
	var expected: Dictionary = Frozen.evaluate(rpm, duty, bus_voltage_v, motor, enabled)
	var actual: Dictionary = Candidate.evaluate(rpm, duty, bus_voltage_v, motor, enabled)
	_compare(label + " full", expected, actual)
	if _motor_is_valid(motor):
		var compact_expected: Dictionary = expected if not expected.get("ok", false) \
			else _compact_fields(expected)
		var compact_actual: Dictionary = Candidate._evaluate_validated(
			rpm, duty, bus_voltage_v, float(motor.kv_rpm_per_volt),
			float(motor.resistance_ohm), float(motor.no_load_current_a), enabled, true,
		)
		_compare(label + " compact source", compact_expected, compact_actual)
	return actual


func _compact_fields(result: Dictionary) -> Dictionary:
	return {
		ok = true,
		mode = result.mode,
		shaft_torque_nm = result.shaft_torque_nm,
		motor_current_a = result.motor_current_a,
		battery_current_a = result.battery_current_a,
	}


func _motor_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var motor: Dictionary = value
	for key: String in MOTOR_KEYS:
		if not motor.has(key) or typeof(motor.get(key)) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(motor.get(key))):
			return false
	for key: Variant in motor:
		if key not in MOTOR_KEYS:
			return false
	return float(motor.kv_rpm_per_volt) > 0.0 \
		and float(motor.resistance_ohm) > 0.0 \
		and float(motor.no_load_current_a) >= 0.0


func _motor_fixture(kv: float = 600.0, resistance: float = 0.2,
		no_load: float = 1.0) -> Dictionary:
	return {
		"kv_rpm_per_volt": kv,
		"resistance_ohm": resistance,
		"no_load_current_a": no_load,
	}


func _bus_power_overflow_case() -> Dictionary:
	# Keep torque, shaft power, copper loss and rotational loss finite so this isolates bus power.
	var bus_voltage_v: float = 1e308
	var kv: float = 1e-300
	var rpm: float = (bus_voltage_v - 2e292) * kv
	var represented_back_emf: float = rpm / kv
	var resistance: float = (bus_voltage_v - represented_back_emf) / 2.0
	return {"rpm": rpm, "motor": _motor_fixture(kv, resistance, 1.0)}


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


func _check_mutation(label: String, expected: Dictionary, changed: Dictionary) -> void:
	_comparisons += 1
	if var_to_bytes(expected) == var_to_bytes(changed):
		_record_failure(label)


func _check(label: String, condition: bool) -> void:
	if not condition:
		_record_failure(label)


func _record_failure(label: String) -> void:
	_failures += 1
	if _first_failure.is_empty():
		_first_failure = label
	if _failures <= 5:
		print("FAIL: " + label)
