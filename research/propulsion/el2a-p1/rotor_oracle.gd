# EL2a-P1 research oracle: frozen pre-optimization response plus seeded byte comparisons.
# The reference function is copied from app/physics/rotor_coupling.gd before EL2a-P1.
# Baseline SHA-256: 39C8269BA60B984978CBDD449CF2775CB0B73BB7A250B38459A6AB02851CF718
extends SceneTree

const Candidate: Script = preload("res://physics/rotor_coupling.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const SAMPLE_COUNT: int = 10000
const RNG_SEED: int = 0x6D2B79F5

var _rng_state: int = RNG_SEED
var _checks: int = 0
var _failures: int = 0
var _first_failure: String = ""


## Frozen source snapshot. Keep this function unchanged when the candidate evolves.
static func reference_response(body_rate: PackedFloat64Array, external_moment: PackedFloat64Array,
		inertia: PackedFloat64Array, inertia_inverse: PackedFloat64Array, axis: PackedFloat64Array,
		rotor_inertia: float, relative_speed: float, net_shaft_torque: float) -> Dictionary:
	for pair: Array in [[body_rate, 3], [external_moment, 3], [inertia, 6], [inertia_inverse, 6], [axis, 3]]:
		var values: PackedFloat64Array = pair[0]
		if values.size() != pair[1]:
			return {ok = false}
		for value: float in values:
			if not is_finite(value):
				return {ok = false}
	if absf(M.dot(axis, axis) - 1.0) > 1e-12:
		return {ok = false}
	var inverse_axis: PackedFloat64Array = RB.inertia_mul(inertia_inverse, axis)
	var denominator: float = 1.0 - rotor_inertia * M.dot(axis, inverse_axis)
	if not is_finite(denominator) or denominator <= 0.0 or not is_finite(rotor_inertia) or rotor_inertia <= 0.0 \
			or not is_finite(relative_speed) or relative_speed < 0.0 or not is_finite(net_shaft_torque):
		return {ok = false}
	var momentum: PackedFloat64Array = M.scale(axis, rotor_inertia * relative_speed)
	var total_h: PackedFloat64Array = M.add(RB.inertia_mul(inertia, body_rate), momentum)
	var unreacted: PackedFloat64Array = RB.inertia_mul(inertia_inverse,
		M.sub(external_moment, M.cross(body_rate, total_h)))
	var acceleration: float = (net_shaft_torque / rotor_inertia - M.dot(axis, unreacted)) / denominator
	var reaction: PackedFloat64Array = M.scale(axis, -rotor_inertia * acceleration)
	if not is_finite(acceleration):
		return {ok = false}
	for value: float in reaction:
		if not is_finite(value):
			return {ok = false}
	return {ok = true, spin_acceleration = acceleration, reaction = reaction, momentum = momentum}


func _initialize() -> void:
	_run_seeded_valid_cases()
	_run_invalid_cases()
	_run_mutation_control()
	print("EL2a-P1 rotor oracle: %d checks, %d failed, seed=%d, valid_samples=%d" % [
		_checks, _failures, RNG_SEED, SAMPLE_COUNT])
	if not _first_failure.is_empty():
		print("first failure: " + _first_failure)
	quit(1 if _failures > 0 else 0)


func _run_seeded_valid_cases() -> void:
	for sample: int in SAMPLE_COUNT:
		var args: Array = _valid_arguments()
		var expected: Dictionary = _reference_from_args(args)
		var actual: Dictionary = _candidate_from_args(args)
		_checks += 1
		if not expected.get("ok", false) or not actual.get("ok", false) or not _same_bytes(expected, actual):
			_record_failure("seeded valid sample %d" % sample)
			return


func _run_invalid_cases() -> void:
	var base: Array = _valid_arguments()
	var cases: Array[Dictionary] = []
	var args: Array

	args = _copy_arguments(base)
	args[0] = PackedFloat64Array([1.0, 2.0])
	cases.append({"name": "body rate wrong width", "args": args})

	args = _copy_arguments(base)
	args[0][1] = NAN
	cases.append({"name": "body rate nonfinite", "args": args})

	args = _copy_arguments(base)
	args[1] = PackedFloat64Array([1.0, 2.0])
	cases.append({"name": "external moment wrong width", "args": args})

	args = _copy_arguments(base)
	args[1][2] = INF
	cases.append({"name": "external moment nonfinite", "args": args})

	args = _copy_arguments(base)
	args[2] = PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0])
	cases.append({"name": "inertia wrong width", "args": args})

	args = _copy_arguments(base)
	args[2][5] = NAN
	cases.append({"name": "inertia nonfinite", "args": args})

	args = _copy_arguments(base)
	args[3] = PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0])
	cases.append({"name": "inverse wrong width", "args": args})

	args = _copy_arguments(base)
	args[3][0] = INF
	cases.append({"name": "inverse nonfinite", "args": args})

	args = _copy_arguments(base)
	args[4] = PackedFloat64Array([1.0, 0.0])
	cases.append({"name": "axis wrong width", "args": args})

	args = _copy_arguments(base)
	args[4][0] = NAN
	cases.append({"name": "axis nonfinite", "args": args})

	args = _copy_arguments(base)
	args[4][0] *= 2.0
	cases.append({"name": "axis not unit length", "args": args})

	args = _copy_arguments(base)
	args[5] = 0.0
	cases.append({"name": "zero rotor inertia", "args": args})

	args = _copy_arguments(base)
	args[5] = -0.2
	cases.append({"name": "negative rotor inertia", "args": args})

	args = _copy_arguments(base)
	args[5] = NAN
	cases.append({"name": "nonfinite rotor inertia", "args": args})

	args = _copy_arguments(base)
	args[5] = INF
	cases.append({"name": "infinite rotor inertia", "args": args})

	args = _copy_arguments(base)
	args[6] = -1.0
	cases.append({"name": "negative relative speed", "args": args})

	args = _copy_arguments(base)
	args[6] = NAN
	cases.append({"name": "nonfinite relative speed", "args": args})

	args = _copy_arguments(base)
	args[7] = NAN
	cases.append({"name": "nonfinite shaft torque", "args": args})

	args = _copy_arguments(base)
	var axis: PackedFloat64Array = args[4]
	var inverse: PackedFloat64Array = args[3]
	var compliance: float = M.dot(axis, RB.inertia_mul(inverse, axis))
	args[5] = 2.0 / compliance
	cases.append({"name": "nonpositive carrier denominator", "args": args})

	for test_case: Dictionary in cases:
		var expected: Dictionary = _reference_from_args(test_case.args)
		var actual: Dictionary = _candidate_from_args(test_case.args)
		_checks += 1
		if not _same_bytes(expected, actual) or expected.get("ok", true):
			_record_failure("invalid input: " + str(test_case.name))


func _run_mutation_control() -> void:
	var args: Array = _valid_arguments()
	var expected: Dictionary = _reference_from_args(args)
	var mutated: Dictionary = _candidate_from_args(args).duplicate(true)
	if expected.get("ok", false) and mutated.get("ok", false):
		mutated.spin_acceleration = float(mutated.spin_acceleration) + 1.0
		_checks += 1
		if _same_bytes(expected, mutated):
			_record_failure("byte comparator missed deliberate acceleration mutation")
	else:
		_checks += 1
		_record_failure("mutation control fixture did not produce a valid response")


func _valid_arguments() -> Array:
	var inertia: PackedFloat64Array = PackedFloat64Array([
		3.0 + 2.0 * _unit(), 3.5 + 2.5 * _unit(), 2.5 + 2.0 * _unit(),
		(0.10 + 0.25 * _unit()) * (1.0 if _next_u32() % 2 == 0 else -1.0),
		(0.08 + 0.22 * _unit()) * (1.0 if _next_u32() % 2 == 0 else -1.0),
		(0.07 + 0.20 * _unit()) * (1.0 if _next_u32() % 2 == 0 else -1.0),
	])
	var inertia_inverse: PackedFloat64Array = RB.inertia_inverse(inertia)
	var raw_axis: PackedFloat64Array = PackedFloat64Array([
		0.2 + _unit(), -0.7 + 0.5 * _unit(), 0.15 + 0.8 * _unit(),
	])
	var axis_norm: float = sqrt(M.dot(raw_axis, raw_axis))
	var axis: PackedFloat64Array = PackedFloat64Array([
		raw_axis[0] / axis_norm, raw_axis[1] / axis_norm, raw_axis[2] / axis_norm,
	])
	return [
		PackedFloat64Array([_signed(4.0), _signed(4.0), _signed(4.0)]),
		PackedFloat64Array([_signed(30.0), _signed(30.0), _signed(30.0)]),
		inertia,
		inertia_inverse,
		axis,
		0.02 + 0.55 * _unit(),
		9000.0 * _unit(),
		_signed(80.0),
	]


func _copy_arguments(source: Array) -> Array:
	var copied: Array = source.duplicate()
	for index: int in 5:
		copied[index] = source[index].duplicate()
	return copied


func _reference_from_args(args: Array) -> Dictionary:
	return reference_response(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7])


func _candidate_from_args(args: Array) -> Dictionary:
	return Candidate.response(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7])


func _same_bytes(left: Dictionary, right: Dictionary) -> bool:
	return var_to_bytes(left) == var_to_bytes(right)


func _next_u32() -> int:
	var value: int = _rng_state & 0xFFFFFFFF
	value = (value ^ (value << 13)) & 0xFFFFFFFF
	value = (value ^ (value >> 17)) & 0xFFFFFFFF
	value = (value ^ (value << 5)) & 0xFFFFFFFF
	_rng_state = value
	return value


func _unit() -> float:
	return float(_next_u32() & 0x00FFFFFF) / 16777216.0


func _signed(scale: float) -> float:
	return (2.0 * _unit() - 1.0) * scale


func _record_failure(label: String) -> void:
	_failures += 1
	if _first_failure.is_empty():
		_first_failure = label
