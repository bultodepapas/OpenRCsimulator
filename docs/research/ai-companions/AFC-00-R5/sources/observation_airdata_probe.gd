## AFC-00-R5: exact finite arithmetic comparison for the observation airspeed candidate.
extends SceneTree

const Air := preload("res://physics/air_data.gd")
const Candidate := preload("res://../research/ai-companions/performance/observation_airdata_candidate.gd")
const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--parse-only"):
		print("AFC OBSERVATION AIRDATA PROBE PARSED")
		quit(0)
		return
	call_deferred("_run")


func _run() -> void:
	var mismatches: Array[Dictionary] = []
	var finite_cases := 0
	for index in 512:
		var step: float = float(index)
		var attitude: PackedFloat64Array = Math3D.q_from_euler(
			sin(step * 0.071) * PI,
			sin(step * 0.037) * deg_to_rad(85.0),
			cos(step * 0.053) * PI)
		var velocity := PackedFloat64Array([
			cos(step * 0.109) * (3.0 + fmod(step, 44.0)),
			sin(step * 0.127) * (1.0 + fmod(step, 17.0)),
			cos(step * 0.163) * (0.25 + fmod(step, 5.0))])
		var state: PackedFloat64Array = RigidBody.make_state(
			PackedFloat64Array([step, -step * 0.25, -20.0 - fmod(step, 500.0)]),
			velocity, attitude, PackedFloat64Array([0.0, 0.0, 0.0]))
		var wind := PackedFloat64Array([
			sin(step * 0.193) * 18.0,
			cos(step * 0.211) * 12.0,
			sin(step * 0.239) * 4.0])
		var expected: float = float(Air.compute(state, wind, 1.225).V)
		var actual: float = Candidate.airspeed_m_s(state, wind)
		finite_cases += 1
		if not is_finite(expected) or not is_finite(actual) \
				or _float_bytes(expected) != _float_bytes(actual):
			mismatches.append({case = index, expected = expected, actual = actual})

	# Include zero and co-moving airflow edges, which the controller later rejects as nonpositive.
	for edge in 3:
		var q := Math3D.q_from_euler(0.31 * float(edge), -0.17 * float(edge), 0.23 * float(edge))
		var velocity := PackedFloat64Array([0.0, 0.0, 0.0]) if edge == 0 else PackedFloat64Array([4.0, -2.0, 1.5])
		var state: PackedFloat64Array = RigidBody.make_state(
			PackedFloat64Array([0.0, 0.0, -50.0]), velocity, q, PackedFloat64Array([0.0, 0.0, 0.0]))
		var wind := PackedFloat64Array([0.0, 0.0, 0.0])
		if edge > 0:
			wind = Math3D.q_rotate(q, velocity)
		var expected: float = float(Air.compute(state, wind, 1.225).V)
		var actual: float = Candidate.airspeed_m_s(state, wind)
		finite_cases += 1
		if not is_finite(expected) or not is_finite(actual) \
				or _float_bytes(expected) != _float_bytes(actual):
			mismatches.append({case = "edge-%d" % edge, expected = expected, actual = actual})

	# Exercise signed-zero input bits through nonidentity attitudes as well as ordinary magnitudes.
	var signed_zero_cases := 0
	var negative_zero_bytes := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128])
	var negative_zero_array: PackedFloat64Array = negative_zero_bytes.to_float64_array()
	var negative_zero: float = negative_zero_array[0]
	var positive_zero: float = 0.0
	var signed_zero_distinguishable: bool = _float_bytes(negative_zero) != _float_bytes(positive_zero)
	var signed_zero_variant_bytes_distinguishable: bool = var_to_bytes(PackedFloat64Array([negative_zero])) \
		!= var_to_bytes(PackedFloat64Array([positive_zero]))
	for edge in 6:
		var phase: float = float(edge + 1)
		var q: PackedFloat64Array = Math3D.q_from_euler(phase * 0.19, -phase * 0.11, phase * 0.07)
		var z0: float = negative_zero if edge % 2 == 0 else positive_zero
		var z1: float = positive_zero if edge % 2 == 0 else negative_zero
		var velocity := PackedFloat64Array([z0, 2.0 - phase * 0.1, z1])
		var state: PackedFloat64Array = RigidBody.make_state(
			PackedFloat64Array([phase, -phase, -30.0]), velocity, q,
			PackedFloat64Array([0.0, 0.0, 0.0]))
		var wind := PackedFloat64Array([z1, -0.75 * phase, z0])
		var expected: float = float(Air.compute(state, wind, 1.225).V)
		var actual: float = Candidate.airspeed_m_s(state, wind)
		finite_cases += 1
		signed_zero_cases += 1
		if not is_finite(expected) or not is_finite(actual) \
				or _float_bytes(expected) != _float_bytes(actual):
			mismatches.append({case = "signed-zero-%d" % edge, expected = expected, actual = actual,
				state_velocity_bytes = velocity.to_byte_array().hex_encode(), wind_bytes = wind.to_byte_array().hex_encode()})

	var report := {
		format = "openrc-afc-observation-airdata-arithmetic v2",
		complete = mismatches.is_empty() and finite_cases == 521 and signed_zero_distinguishable,
		status = "pass" if mismatches.is_empty() and finite_cases == 521 and signed_zero_distinguishable else "fail",
		cases = finite_cases,
		bitwise_equal_cases = finite_cases - mismatches.size(),
		mismatch_count = mismatches.size(),
		mismatches = mismatches,
		signed_zero_cases = signed_zero_cases,
		signed_zero_distinguishable_in_packed_float64 = signed_zero_distinguishable,
		signed_zero_distinguishable_in_var_to_bytes = signed_zero_variant_bytes_distinguishable,
		comparison = "Air.compute(state, wind, 1.225).V versus the research helper; PackedFloat64Array byte comparison per scalar.",
		limitation = "Arithmetic check only; gust/turbulence and observation/command parity are covered separately by the short paired flight probe. No timing or physical qualification."
	}
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			printerr("Cannot write report: " + output)
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print(JSON.stringify(report))
	print("AFC OBSERVATION AIRDATA ARITHMETIC COMPLETE")
	quit(0 if bool(report.complete) else 1)


func _float_bytes(value: float) -> PackedByteArray:
	return PackedFloat64Array([value]).to_byte_array()
