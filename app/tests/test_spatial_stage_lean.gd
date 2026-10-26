# M5-W05d-R4: full and lean stage-air receipts preserve physics and queries.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Flow := preload("res://physics/wind_aircraft_flow.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const RHO := Air.RHO_SEA_LEVEL


class TraceField extends "res://physics/wind_field.gd":
	var mode := "linear"
	var origin_ned := PackedFloat64Array([0.0, 0.0, 0.0])
	var uniform_wind := PackedFloat64Array([0.3, -0.2, 0.1])
	var fail_at := -1
	var calls := 0
	var positions: Array[PackedFloat64Array] = []
	var times: Array[float] = []

	func sample_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		var query_index := calls
		calls += 1
		positions.append(position_ned.duplicate())
		times.append(time_s)
		if query_index == fail_at:
			return PackedFloat64Array([0.0, NAN, 0.0])
		if mode == "uniform":
			return uniform_wind.duplicate()
		return wind_value(position_ned, time_s)

	func wind_value(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		var n := position_ned[0] - origin_ned[0]
		var e := position_ned[1] - origin_ned[1]
		var d := position_ned[2] - origin_ned[2]
		return PackedFloat64Array([
			0.25 + 0.035 * n + 0.045 * e - 0.012 * d + 0.015 * time_s,
			-0.10 + 0.018 * n - 0.021 * e + 0.010 * d - 0.008 * time_s,
			0.08 - 0.013 * n + 0.016 * e + 0.019 * d + 0.006 * time_s,
		])

	func reset_trace() -> void:
		calls = 0
		positions.clear()
		times.clear()


var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var configs := _catalog_models()
	_check("all catalog ideal/pack aircraft load", configs.size() >= 12, "loaded %d" % configs.size())
	var conventional: Dictionary = {}
	var tailless: Dictionary = {}
	for config: Dictionary in configs:
		var model: Dictionary = config.model
		if model.get("surfaces", {}).has("tailless") and tailless.is_empty():
			tailless = config
		elif not model.get("surfaces", {}).has("tailless") and conventional.is_empty():
			conventional = config
		_check_case(config)
	_check("catalog has conventional and tailless refusal fixtures",
		not conventional.is_empty() and not tailless.is_empty())
	if not conventional.is_empty():
		_check_rejection_parity(conventional.model)
		_check_provider_failure_parity(conventional.model, "%s/%s" % [conventional.id, conventional.mode], false)
		_check_sampler_context(conventional.model, "%s/%s" % [conventional.id, conventional.mode])
	if not tailless.is_empty():
		_check_provider_failure_parity(tailless.model, "%s/%s" % [tailless.id, tailless.mode], true)
		_check_sampler_context(tailless.model, "%s/%s" % [tailless.id, tailless.mode])
	print("Spatial stage lean: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _catalog_models() -> Array:
	var configs: Array = []
	for id: String in Catalog.airplane_flyable_ids():
		var modes: Array[String] = ["ideal"]
		if Catalog.has_battery_mode(id, "pack"):
			modes.append("pack")
		for mode: String in modes:
			var path: String = Catalog.data_for(id, mode)
			var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			_check("%s/%s source parses" % [id, mode], raw is Dictionary, path)
			if not raw is Dictionary:
				continue
			var loaded: Dictionary = AD.validate_and_derive(raw)
			_check("%s/%s normalizes" % [id, mode], loaded.get("ok", false), str(loaded.get("errors", [])))
			if loaded.get("ok", false):
				configs.append({"id": id, "mode": mode, "model": loaded.model})
	return configs


func _check_case(config: Dictionary) -> void:
	var model: Dictionary = config.model
	var label := "%s/%s" % [config.id, config.mode]
	var state := _state()
	var state_bytes: PackedByteArray = state.to_byte_array()
	var model_json := JSON.stringify(model)
	for field_mode: String in ["uniform", "linear"]:
		for law: String in ["", Aero.SPATIAL_CONTINUATION_LAW]:
			_compare_pair(model, label, state, field_mode, law)
	_check(label + " state and normalized model remain unchanged",
		state.to_byte_array() == state_bytes and JSON.stringify(model) == model_json)


func _compare_pair(model: Dictionary, label: String, state: PackedFloat64Array,
		field_mode: String, law: String) -> void:
	var context := "%s %s law=%s" % [label, field_mode, "narrow" if law.is_empty() else "full-angle"]
	var rho := 1.07
	var time_s := 2.375
	var full_field := _field(field_mode, state)
	var lean_field := _field(field_mode, state)
	var full_result: Dictionary = Flow.stage_air(state, model, _environment(full_field), time_s, rho, law)
	var lean_result: Dictionary = Flow.stage_air(state, model, _environment(lean_field), time_s, rho, law, false)
	_check(context + " both stage receipts succeed", full_result.get("ok", false) and lean_result.get("ok", false),
		"full=%s lean=%s" % [str(full_result.get("errors", [])), str(lean_result.get("errors", []))])
	if not full_result.get("ok", false) or not lean_result.get("ok", false):
		return
	var full_air: Dictionary = full_result.air.duplicate()
	var lean_air: Dictionary = lean_result.air.duplicate()
	var flow: Dictionary = full_result.flow
	var expected_keys: Array[String] = ["ok", "errors", "law", "position_ned", "time_s", "offsets_body",
		"positions_ned", "wind_ned", "relative_body", "delta_body", "reference_wind_ned",
		"reference_air_body", "uniform", "wing_count", "horizontal_index", "vertical_index", "propulsion_index", "indices"]
	var actual_keys: Array = flow.keys()
	actual_keys.sort()
	expected_keys.sort()
	var scalar_count: int = Flow.geometry(model).offsets_body.size()
	_check(context + " default flow diagnostic shape remains intact", actual_keys == expected_keys
		and flow.get("ok", false) and flow.offsets_body.size() == scalar_count
		and flow.positions_ned.size() == scalar_count and flow.wind_ned.size() == scalar_count
		and flow.relative_body.size() == scalar_count and flow.delta_body.size() == scalar_count)
	_check(context + " lean receipt omits only the diagnostic flow bundle", not lean_result.has("flow"))
	_check(context + " all numeric Air fields match exactly", _air_equal(full_air, lean_air))
	_check(context + " both stage receipts validate", Flow.matches_stage(full_air, state, rho)
		and Flow.matches_stage(lean_air, state, rho))
	_check(context + " stage query count and order match geometry",
		_same_trace(full_field, lean_field) and _trace_matches(full_field, state, model, time_s))
	var rpm: float = float(model.propulsion.get("max_rpm", 10000.0)) * 0.72
	full_field.reset_trace()
	lean_field.reset_trace()
	var full_loads: PackedFloat64Array = Dynamics.loads_from_air(state, model, _neutral(), rpm, rho, full_air)
	var lean_loads: PackedFloat64Array = Dynamics.loads_from_air(state, model, _neutral(), rpm, rho, lean_air)
	_check(context + " Dynamics force vector stays finite and byte-identical",
		_finite6(full_loads) and _finite6(lean_loads) and _same(full_loads, lean_loads),
		"full=%s lean=%s" % [str(full_loads), str(lean_loads)])
	_check(context + " force evaluation makes identical wash-point queries", _same_trace(full_field, lean_field))


func _check_sampler_context(model: Dictionary, label: String) -> void:
	var state_a := _state()
	var original_a: PackedFloat64Array = state_a.duplicate()
	var full_field := _field("linear", original_a)
	var lean_field := _field("linear", original_a)
	var time_a := 3.125
	var full_a: Dictionary = Flow.stage_air(state_a, model, _environment(full_field), time_a, RHO,
		Aero.SPATIAL_CONTINUATION_LAW)
	var lean_a: Dictionary = Flow.stage_air(state_a, model, _environment(lean_field), time_a, RHO,
		Aero.SPATIAL_CONTINUATION_LAW, false)
	_check(label + " sampler-context stage succeeds", full_a.get("ok", false) and lean_a.get("ok", false))
	if not full_a.get("ok", false) or not lean_a.get("ok", false):
		return
	var air_full_a: Dictionary = full_a.air.duplicate()
	var air_lean_a: Dictionary = lean_a.air.duplicate()
	var reference_a: PackedFloat64Array = full_a.flow.reference_wind_ned.duplicate()
	var arms_a := _probe_arms(model)
	full_a.clear()
	lean_a.clear()
	_check(label + " sampler target stays alive with retained Air only",
		air_full_a.ambient_delta_body_at.is_valid() and air_lean_a.ambient_delta_body_at.is_valid()
		and is_instance_valid(air_full_a.get("spatial_sampler"))
		and is_instance_valid(air_lean_a.get("spatial_sampler")))
	_check_sampler_pair(label + " first stage", air_full_a, air_lean_a, state_a, original_a,
		reference_a, arms_a, full_field, lean_field, time_a)
	state_a[RB.POS] += 70.0
	state_a[RB.ATT] *= 0.97
	state_a[RB.ATT + 1] *= 0.91
	var state_b := _state()
	state_b[RB.POS + 1] += 26.0
	state_b[RB.VEL + 1] -= 0.35
	var time_b := 8.75
	var full_b: Dictionary = Flow.stage_air(state_b, model, _environment(full_field), time_b, RHO,
		Aero.SPATIAL_CONTINUATION_LAW)
	var lean_b: Dictionary = Flow.stage_air(state_b, model, _environment(lean_field), time_b, RHO,
		Aero.SPATIAL_CONTINUATION_LAW, false)
	_check(label + " interleaved second stage succeeds", full_b.get("ok", false) and lean_b.get("ok", false))
	if not full_b.get("ok", false) or not lean_b.get("ok", false):
		return
	var original_b: PackedFloat64Array = state_b.duplicate()
	var air_full_b: Dictionary = full_b.air.duplicate()
	var air_lean_b: Dictionary = lean_b.air.duplicate()
	var reference_b: PackedFloat64Array = full_b.flow.reference_wind_ned.duplicate()
	full_b.clear()
	lean_b.clear()
	_check_sampler_pair(label + " original sampler after interleave", air_full_a, air_lean_a, state_a,
		original_a, reference_a, arms_a, full_field, lean_field, time_a)
	_check_sampler_pair(label + " second sampler time/state", air_full_b, air_lean_b, state_b,
		original_b, reference_b, arms_a, full_field, lean_field, time_b)
	_check_sampler_pair(label + " original sampler after second interleave", air_full_a, air_lean_a, state_a,
		original_a, reference_a, arms_a, full_field, lean_field, time_a)
	_check("%s original state storage is detached" % label,
		air_full_a.spatial_state.to_byte_array() == original_a.to_byte_array()
		and air_lean_a.spatial_state.to_byte_array() == original_a.to_byte_array())
	full_field.reset_trace()
	lean_field.reset_trace()
	var invalid_arm := PackedFloat64Array([0.0, NAN, 0.0])
	_check(label + " both callbacks reject malformed arms before querying",
		_all_nan(air_full_a.ambient_delta_body_at.call(invalid_arm))
		and _all_nan(air_lean_a.ambient_delta_body_at.call(invalid_arm))
		and full_field.calls == 0 and lean_field.calls == 0)
	full_field.fail_at = 0
	lean_field.fail_at = 0
	_check(label + " both callbacks reject failed field samples",
		_all_nan(air_full_a.ambient_delta_body_at.call(arms_a[0]))
		and _all_nan(air_lean_a.ambient_delta_body_at.call(arms_a[0]))
		and _same_trace(full_field, lean_field) and full_field.calls == 1)


func _check_sampler_pair(label: String, air_full: Dictionary, air_lean: Dictionary,
		mutated_state: PackedFloat64Array, captured_state: PackedFloat64Array, reference: PackedFloat64Array,
		arms: Array[PackedFloat64Array], full_field: TraceField, lean_field: TraceField, time_s: float) -> void:
	full_field.reset_trace()
	lean_field.reset_trace()
	var source_before: PackedByteArray = mutated_state.to_byte_array()
	var expected_positions: Array[PackedFloat64Array] = []
	var q: PackedFloat64Array = captured_state.slice(RB.ATT, RB.ATT + 4)
	var position: PackedFloat64Array = captured_state.slice(RB.POS, RB.POS + 3)
	for arm in arms:
		var before: PackedByteArray = arm.to_byte_array()
		var full_delta: PackedFloat64Array = air_full.ambient_delta_body_at.call(arm.duplicate())
		var lean_delta: PackedFloat64Array = air_lean.ambient_delta_body_at.call(arm.duplicate())
		var point: PackedFloat64Array = M.add(position, M.q_rotate(q, arm))
		expected_positions.append(point)
		var expected: PackedFloat64Array = _delta_at(full_field, captured_state, reference, arm, time_s)
		_check(label + " exact detached callback delta", _same(full_delta, lean_delta) and _same(full_delta, expected))
		_check(label + " callback leaves arm and source states unchanged",
			arm.to_byte_array() == before and mutated_state.to_byte_array() == source_before)
	_check(label + " callback query time and point trace match", _same_trace(full_field, lean_field)
		and _trace_matches_points(full_field, expected_positions, time_s))


func _check_rejection_parity(model: Dictionary) -> void:
	var state := _state()
	var bad_model: Dictionary = model.duplicate(true)
	bad_model.envelope.station_ys = PackedFloat64Array([0.0])
	var no_hub: Dictionary = model.duplicate(true)
	no_hub.propulsion.kind = "none"
	var extreme_rates := state.duplicate()
	for axis in 3: extreme_rates[RB.RATE + axis] = 1.7e308
	# Manufactured finite geometry/rates whose cross product overflows; not authored aircraft data.
	var overflow_model: Dictionary = model.duplicate(true)
	var distant_tail: PackedFloat64Array = model.surfaces.horizontal.position.duplicate()
	distant_tail[0] = 10.0
	overflow_model.surfaces.horizontal.position = distant_tail
	var cases: Array[Dictionary] = [
		{"name": "invalid rho", "model": model, "state": state, "time": 1.0, "rho": NAN, "law": ""},
		{"name": "unsupported law", "model": model, "state": state, "time": 1.0, "rho": RHO, "law": "unsupported"},
		{"name": "invalid geometry", "model": bad_model, "state": state, "time": 1.0, "rho": RHO, "law": ""},
		{"name": "invalid state", "model": model, "state": PackedFloat64Array([0.0, 1.0]), "time": 1.0, "rho": RHO, "law": ""},
		{"name": "invalid time", "model": model, "state": state, "time": -0.25, "rho": RHO, "law": ""},
		{"name": "invalid environment", "model": model, "state": state, "time": 1.0, "rho": RHO, "law": ""},
		{"name": "missing powered hub", "model": no_hub, "state": state, "time": 1.0, "rho": RHO, "law": "", "after_queries": true},
		{"name": "point-flow overflow", "model": overflow_model, "state": extreme_rates, "time": 1.0, "rho": RHO, "law": "", "after_queries": true},
		{"name": "qbar overflow", "model": model, "state": state, "time": 1.0, "rho": 1.7e308, "law": "", "after_queries": true},
	]
	for item: Dictionary in cases:
		var full_field := _field("linear", state)
		var lean_field := _field("linear", state)
		var candidate: Dictionary = item.model
		var candidate_state: PackedFloat64Array = item.state
		var full: Dictionary = Flow.stage_air(candidate_state, candidate, null if item.name == "invalid environment" else _environment(full_field),
			float(item.time), float(item.rho), str(item.law))
		var lean: Dictionary = Flow.stage_air(candidate_state, candidate, null if item.name == "invalid environment" else _environment(lean_field),
			float(item.time), float(item.rho), str(item.law), false)
		_check("%s rejects identically" % item.name, not full.get("ok", false) and not lean.get("ok", false)
			and full.get("errors", PackedStringArray()) == lean.get("errors", PackedStringArray())
			and full.get("air", {}).is_empty() and lean.get("air", {}).is_empty())
		_check("%s preserves rejection query boundary" % item.name, _same_trace(full_field, lean_field)
			and (full_field.calls > 0 if item.get("after_queries", false) else full_field.calls == 0))


func _check_provider_failure_parity(model: Dictionary, label: String, tailless: bool) -> void:
	var state := _state()
	var time_s := 1.75
	var expected: Array[PackedFloat64Array] = _expected_queries(state, model)
	var geometry: Dictionary = Flow.geometry(model)
	var station_count: int = geometry.offsets_body.size() / 3
	var expected_count: int = station_count + 1 - (1 if int(geometry.horizontal_index) < 0 else 0)
	_check(label + " provider failure fixture query count", expected.size() == expected_count
		and (not tailless or expected.size() == 9))
	for fail_at in expected.size():
		var full_field := _field("linear", state)
		var lean_field := _field("linear", state)
		full_field.fail_at = fail_at
		lean_field.fail_at = fail_at
		var full: Dictionary = Flow.stage_air(state, model, _environment(full_field), time_s, RHO)
		var lean: Dictionary = Flow.stage_air(state, model, _environment(lean_field), time_s, RHO, "", false)
		_check("%s fails closed at query %d" % [label, fail_at],
			not full.get("ok", false) and not lean.get("ok", false)
			and full.get("errors", PackedStringArray()) == lean.get("errors", PackedStringArray())
			and full.get("air", {}).is_empty() and lean.get("air", {}).is_empty())
		_check("%s preserves failing query prefix %d" % [label, fail_at],
			_same_trace(full_field, lean_field) and full_field.calls == fail_at + 1
			and _trace_matches_prefix(full_field, expected, fail_at + 1, time_s))


func _air_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: Variant in a.keys():
		if not b.has(key):
			return false
		if key in ["ambient_delta_body_at", "spatial_sampler"]:
			continue
		var left: Variant = a[key]
		var right: Variant = b[key]
		if typeof(left) != typeof(right):
			return false
		if typeof(left) == TYPE_PACKED_FLOAT64_ARRAY:
			var left_array: PackedFloat64Array = left
			var right_array: PackedFloat64Array = right
			if not _same(left_array, right_array):
				return false
		elif var_to_bytes(left) != var_to_bytes(right):
			return false
	return true


func _expected_queries(state: PackedFloat64Array, model: Dictionary) -> Array[PackedFloat64Array]:
	var result: Array[PackedFloat64Array] = [state.slice(RB.POS, RB.POS + 3)]
	var geometry: Dictionary = Flow.geometry(model)
	if not geometry.get("ok", false):
		return result
	var q: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var position: PackedFloat64Array = state.slice(RB.POS, RB.POS + 3)
	var station_count: int = int(geometry.offsets_body.size() / 3)
	for index in station_count:
		if index == int(geometry.wing_count) and int(geometry.horizontal_index) < 0:
			continue
		var arm: PackedFloat64Array = geometry.offsets_body.slice(index * 3, index * 3 + 3)
		result.append(M.add(position, M.q_rotate(q, arm)))
	return result


func _trace_matches(field: TraceField, state: PackedFloat64Array, model: Dictionary, time_s: float) -> bool:
	return _trace_matches_points(field, _expected_queries(state, model), time_s)


func _trace_matches_points(field: TraceField, expected: Array[PackedFloat64Array], time_s: float) -> bool:
	if field.positions.size() != expected.size() or field.times.size() != expected.size():
		return false
	for index in expected.size():
		if not _same(field.positions[index], expected[index]) or field.times[index] != time_s:
			return false
	return true


func _trace_matches_prefix(field: TraceField, expected: Array[PackedFloat64Array], count: int, time_s: float) -> bool:
	var prefix: Array[PackedFloat64Array] = []
	for index in count:
		prefix.append(expected[index])
	return _trace_matches_points(field, prefix, time_s)


func _same_trace(a: TraceField, b: TraceField) -> bool:
	if a.calls != b.calls or a.positions.size() != b.positions.size() or a.times.size() != b.times.size():
		return false
	for index in a.positions.size():
		if not _same(a.positions[index], b.positions[index]) or a.times[index] != b.times[index]:
			return false
	return true


func _probe_arms(model: Dictionary) -> Array[PackedFloat64Array]:
	var result: Array[PackedFloat64Array] = []
	var geometry: Dictionary = Flow.geometry(model)
	var station_count: int = int(geometry.offsets_body.size() / 3)
	for index in station_count:
		if index == int(geometry.wing_count) and int(geometry.horizontal_index) < 0:
			continue
		result.append(geometry.offsets_body.slice(index * 3, index * 3 + 3))
	result.append(PackedFloat64Array([0.41, -0.27, 0.19]))
	result.append(PackedFloat64Array([-0.63, 0.52, -0.31]))
	return result


func _delta_at(field: TraceField, state: PackedFloat64Array, reference: PackedFloat64Array,
		arm: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
	var q: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var position: PackedFloat64Array = M.add(state.slice(RB.POS, RB.POS + 3), M.q_rotate(q, arm))
	var wind: PackedFloat64Array = field.wind_value(position, time_s)
	if _same(reference, wind):
		return PackedFloat64Array([0.0, 0.0, 0.0])
	return M.q_rotate(M.q_conj(q), M.sub(reference, wind))


func _field(mode: String, state: PackedFloat64Array) -> TraceField:
	var field := TraceField.new()
	field.mode = mode
	field.origin_ned = state.slice(RB.POS, RB.POS + 3)
	return field


func _environment(field: TraceField) -> Object:
	var environment := SimEnvironment.new()
	environment.weather = field
	return environment


func _state() -> PackedFloat64Array:
	var state := RB.make_state(M.v3(120.0, -17.0, -22.0), M.v3(18.0, 0.2, -0.1),
		M.q_from_euler(0.31, -0.17, 0.12), M.v3(0.45, -0.25, 0.19))
	for index in 4:
		state[RB.ATT + index] *= 1.00001
	return state


func _neutral() -> Dictionary:
	return {"elevator": 0.0, "aileron_left": 0.0, "aileron_right": 0.0, "rudder": 0.0, "flap": 0.0}


func _finite6(values: PackedFloat64Array) -> bool:
	if values.size() != 6:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _same(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	return a.to_byte_array() == b.to_byte_array()


func _all_nan(values: PackedFloat64Array) -> bool:
	return values.size() == 3 and is_nan(values[0]) and is_nan(values[1]) and is_nan(values[2])


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s%s" % [label, " — " + detail if not detail.is_empty() else ""])
