# E0b6p prepared-model lifecycle probe; run in a disposable app copy with the prepared backend installed.
extends SceneTree

const Adapter = preload("res://tests/e0b6p_native/adapter.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Fixture = preload("res://tests/test_wash_profile.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const RHO: float = 1.17

var _backend: Object = null
var _rows: Array[Dictionary] = []
var _calls: int = 0
var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_record("output JSON path supplied", false, "expected one path argument")
		_finish("")
		return
	if not Adapter.available() or Adapter.backend == null:
		_record("prepared native backend is available", false, "Adapter.available() returned false")
		_finish(args[0])
		return
	_backend = Adapter.backend
	var combined: Dictionary = _build_model(false, 0.4)
	var classic: Dictionary = _build_model(true, 0.4)
	var replacement: Dictionary = _build_model(false, 0.7)
	if combined.is_empty() or classic.is_empty() or replacement.is_empty():
		_finish(args[0])
		return
	_backend.call("invalidate_model")
	_refusal("before prepare", _backend, 1, _inputs(combined))
	_record("classic-tail fixture omits free-slope branch",
		not classic.surfaces.horizontal.has("free_slope"), str(classic.surfaces.horizontal.keys()))
	_exercise("combined_raw", combined)
	_exercise("classic_tail", classic)
	_check_replacement(combined, replacement)
	_check_source_snapshot(combined)
	_check_invalid_prepare(combined)
	_check_dynamic_refusals(combined)
	_check_clear(combined)
	_check_instances(combined, replacement)
	_finish(args[0])


func _build_model(classic_tail: bool, swirl: float) -> Dictionary:
	var raw: Dictionary = Fixture.combined_raw()
	if classic_tail:
		raw.aero.surfaces.horizontal.erase("downwash_gradient")
	var slipstream: Dictionary = raw.propulsion.propeller.slipstream
	slipstream.swirl_factor.value = swirl
	if swirl > 0.5:
		slipstream.wash_factor.value = [0.6, 1.8]
	var result: Dictionary = AircraftData.validate_and_derive(raw)
	_record("%s fixture validates" % ("classic-tail" if classic_tail else "combined_raw"),
		bool(result.get("ok", false)), str(result.get("errors", [])))
	return result.get("model", {}) if bool(result.get("ok", false)) else {}


func _exercise(label: String, model: Dictionary) -> void:
	var token: int = _prepare(_backend, model)
	_record("%s prepare returns positive generation" % label, token > 0, str(token))
	if token <= 0:
		return
	var inputs: Dictionary = _inputs(model)
	var loads: PackedFloat64Array = _compare("%s baseline" % label, model, token, inputs)
	_refusal("%s wrong token" % label, _backend, token + 1, inputs)
	_record("%s finite nonzero elevator/rudder" % label,
		inputs.controls.elevator != 0.0 and inputs.controls.rudder != 0.0,
		"elevator=%s rudder=%s" % [inputs.controls.elevator, inputs.controls.rudder])
	_record("%s baseline loads nonzero" % label, _nonzero(loads), str(loads))
	_check_dynamic_inputs(label, model, token, inputs)


func _check_dynamic_inputs(label: String, model: Dictionary, token: int, base: Dictionary) -> void:
	var cases: Array[Dictionary] = [
		{"label": "state", "field": "state"}, {"label": "velocity", "field": "velocity"},
		{"label": "elevator", "field": "elevator"}, {"label": "rudder", "field": "rudder"},
		{"label": "thrust/torque", "field": "torque"}, {"label": "density", "field": "rho"},
		{"label": "fade", "field": "fade"}, {"label": "held CL", "field": "downwash_cl"},
		{"label": "transported wash", "field": "transport"},
	]
	for case: Dictionary in cases:
		var changed: Dictionary = base.duplicate(true)
		match str(case.field):
			"state": changed.state[10] = 0.31
			"velocity": changed.velocity[1] += 1.1
			"elevator": changed.controls.elevator = 0.17
			"rudder": changed.controls.rudder = 0.13
			"torque":
				changed.torque[0] *= 1.23
				changed.torque[1] *= 0.77
			"rho": changed.rho = 1.09
			"fade": changed.fade = 0.61
			"downwash_cl": changed.downwash_cl = -0.26
			"transport":
				for index: int in changed.transport.size():
					changed.transport[index] += 0.21
		_compare("%s changed %s" % [label, case.label], model, token, changed)


func _check_replacement(first: Dictionary, next: Dictionary) -> void:
	var inputs: Dictionary = _inputs(first)
	var old_token: int = _prepare(_backend, first)
	var old_loads: PackedFloat64Array = _compare("old replacement baseline", first, old_token, inputs)
	var new_token: int = _prepare(_backend, next)
	_record("valid replacement advances generation", new_token > 0 and new_token != old_token,
		"%d -> %d" % [old_token, new_token])
	_refusal("replacement invalidates old token", _backend, old_token, inputs)
	var new_inputs: Dictionary = _inputs(next)
	var new_loads: PackedFloat64Array = _compare("replacement equals new stateless loads", next,
		new_token, new_inputs)
	_record("valid replacement changes loads", _different(old_loads, new_loads),
		"old=%s new=%s" % [old_loads, new_loads])


func _check_source_snapshot(model: Dictionary) -> void:
	var source: Dictionary = model.duplicate(true)
	var original: Dictionary = source.duplicate(true)
	var inputs: Dictionary = _inputs(original)
	var token: int = _prepare(_backend, source)
	_mutate_source(source)
	var retained: PackedFloat64Array = _compare("post-prepare edits leave snapshot unchanged",
		original, token, inputs)
	var mutated_raw: PackedFloat64Array = _raw(_backend, source, inputs)
	_record("source edits affect stateless loads", _different(retained, mutated_raw),
		"prepared=%s mutated_raw=%s" % [retained, mutated_raw])
	var next_token: int = _prepare(_backend, source)
	_record("explicit reprepare advances generation", next_token > 0 and next_token != token,
		"%d -> %d" % [token, next_token])
	_refusal("reprepare invalidates old token", _backend, token, inputs)
	var updated: PackedFloat64Array = _compare("reprepare reflects source edits", source,
		next_token, _inputs(source))
	_record("reprepared loads change", _different(retained, updated), str(updated))


func _mutate_source(source: Dictionary) -> void:
	var propulsion: Dictionary = source["propulsion"]
	var slipstream: Dictionary = propulsion["slipstream"]
	slipstream["swirl_factor"] = 0.0
	var wash: PackedFloat64Array = slipstream["wash_factor"]
	wash.fill(0.0)
	slipstream["wash_factor"] = wash
	var hub: PackedFloat64Array = slipstream["hub"]
	hub[1] += 0.08
	slipstream["hub"] = hub
	propulsion["slipstream"] = slipstream
	source["propulsion"] = propulsion


func _check_invalid_prepare(model: Dictionary) -> void:
	var token: int = _prepare(_backend, model)
	var malformed: Dictionary = model.duplicate(true)
	malformed.propulsion.slipstream.pieces[0].root = PackedFloat64Array([0.0, 0.0])
	var rejected: int = _prepare(_backend, malformed)
	_record("malformed model prepare returns zero", rejected == 0, str(rejected))
	_refusal("invalid prepare clears previous snapshot", _backend, token, _inputs(model))


func _check_dynamic_refusals(model: Dictionary) -> void:
	var token: int = _prepare(_backend, model)
	var base: Dictionary = _inputs(model)
	_compare("refusal probes start from valid finite6 call", model, token, base)
	var cases: Array[Dictionary] = [
		{"label": "state wrong length", "field": "state_short"}, {"label": "state nonfinite", "field": "state_nan"},
		{"label": "velocity wrong length", "field": "velocity_short"}, {"label": "velocity nonfinite", "field": "velocity_inf"},
		{"label": "elevator nonfinite", "field": "elevator_nan"}, {"label": "rudder nonfinite", "field": "rudder_inf"},
		{"label": "thrust/torque wrong length", "field": "torque_short"}, {"label": "thrust/torque nonfinite", "field": "torque_nan"},
		{"label": "density nonfinite", "field": "rho_nan"}, {"label": "density nonpositive", "field": "rho_zero"},
		{"label": "fade nonfinite", "field": "fade_nan"}, {"label": "fade above one", "field": "fade_high"},
		{"label": "held CL nonfinite", "field": "cl_inf"}, {"label": "transport wrong size", "field": "transport_short"},
		{"label": "transport nonfinite", "field": "transport_nan"},
	]
	for case: Dictionary in cases:
		var bad: Dictionary = base.duplicate(true)
		match str(case.field):
			"state_short": bad.state.resize(12)
			"state_nan": bad.state[3] = NAN
			"velocity_short": bad.velocity.resize(2)
			"velocity_inf": bad.velocity[1] = INF
			"elevator_nan": bad.controls.elevator = NAN
			"rudder_inf": bad.controls.rudder = INF
			"torque_short": bad.torque.resize(1)
			"torque_nan": bad.torque[0] = NAN
			"rho_nan": bad.rho = NAN
			"rho_zero": bad.rho = 0.0
			"fade_nan": bad.fade = NAN
			"fade_high": bad.fade = 1.01
			"cl_inf": bad.downwash_cl = INF
			"transport_short": bad.transport.resize(bad.transport.size() - 1)
			"transport_nan": bad.transport[0] = NAN
		_refusal(str(case.label), _backend, token, bad)


func _check_clear(model: Dictionary) -> void:
	var token: int = _prepare(_backend, model)
	_backend.call("invalidate_model")
	_refusal("explicit clear invalidates token", _backend, token, _inputs(model))


func _check_instances(first: Dictionary, second: Dictionary) -> void:
	var peer: Object = ClassDB.instantiate(_backend.get_class()) as Object
	_record("second backend object instantiates", peer != null, str(_backend.get_class()))
	if peer == null:
		return
	_backend.call("invalidate_model")
	peer.call("invalidate_model")
	var first_token: int = _prepare(_backend, first)
	var second_token: int = _prepare(peer, second)
	_compare("first object keeps its own model", first, first_token, _inputs(first))
	_compare_backend("second object keeps its own model", peer, second, second_token, _inputs(second))
	peer.call("invalidate_model")
	_refusal("peer clear invalidates peer token", peer, second_token, _inputs(second))
	_compare("peer clear leaves first object prepared", first, first_token, _inputs(first))


func _inputs(model: Dictionary) -> Dictionary:
	var velocity: PackedFloat64Array = PackedFloat64Array([14.0, 0.7, -0.4])
	var transport: PackedFloat64Array = PackedFloat64Array()
	transport.resize(model.propulsion.slipstream.pieces.size())
	for index: int in transport.size():
		transport[index] = 0.15 + 0.04 * float(index)
	return {"state": PackedFloat64Array([0.0, 0.0, -100.0, 14.0, 0.7, -0.4,
		1.0, 0.0, 0.0, 0.0, 0.08, -0.06, 0.04]), "velocity": velocity,
		"controls": {"elevator": 0.11, "rudder": -0.09, "aileron_left": 0.02, "aileron_right": -0.02},
		"torque": _torque(velocity, model), "rho": RHO, "fade": 0.83,
		"downwash_cl": 0.42, "transport": transport}


func _torque(velocity: PackedFloat64Array, model: Dictionary) -> PackedFloat64Array:
	var prop: Dictionary = model.propulsion
	var full: PackedFloat64Array = Propulsion.thrust_torque(velocity, prop.max_rpm, prop, RHO)
	return PackedFloat64Array([full[0], full[1]])


func _compare(label: String, model: Dictionary, token: int, inputs: Dictionary) -> PackedFloat64Array:
	return _compare_backend(label, _backend, model, token, inputs)


func _compare_backend(label: String, backend: Object, model: Dictionary, token: int,
		inputs: Dictionary) -> PackedFloat64Array:
	var expected: Variant = _raw(backend, model, inputs)
	var actual: Variant = _prepared(backend, token, inputs)
	var finite: bool = _finite6(expected) and _finite6(actual)
	var exact: bool = false
	if finite:
		var expected_values: PackedFloat64Array = expected
		var actual_values: PackedFloat64Array = actual
		exact = expected_values.to_byte_array() == actual_values.to_byte_array()
	_record_row({"label": label, "kind": "finite6", "passed": finite and exact,
		"finite6": finite, "exact_bytes": exact, "expected": _json_loads(expected),
		"actual": _json_loads(actual)})
	return actual if actual is PackedFloat64Array else PackedFloat64Array()


func _refusal(label: String, backend: Object, token: int, inputs: Dictionary) -> void:
	var result: Variant = _prepared(backend, token, inputs)
	var empty: bool = result is PackedFloat64Array and (result as PackedFloat64Array).is_empty()
	_record_row({"label": label, "kind": "refusal", "passed": empty, "empty_array": empty,
		"actual": _json_loads(result), "actual_type": type_string(typeof(result))})


func _raw(backend: Object, model: Dictionary, inputs: Dictionary) -> Variant:
	_calls += 1
	return backend.call("loads", inputs.state, inputs.velocity, inputs.controls, model, inputs.torque,
		inputs.rho, inputs.fade, inputs.downwash_cl, inputs.transport)


func _prepared(backend: Object, token: int, inputs: Dictionary) -> Variant:
	_calls += 1
	return backend.call("loads_prepared", inputs.state, inputs.velocity, inputs.controls, token,
		inputs.torque, inputs.rho, inputs.fade, inputs.downwash_cl, inputs.transport)


func _finite6(value: Variant) -> bool:
	if not (value is PackedFloat64Array):
		return false
	var loads: PackedFloat64Array = value
	if loads.size() != 6:
		return false
	for component: float in loads:
		if not is_finite(component):
			return false
	return true


func _json_loads(value: Variant) -> Array[float]:
	var result: Array[float] = []
	if _finite6(value):
		var loads: PackedFloat64Array = value
		for component: float in loads:
			result.append(component)
	return result


func _nonzero(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if value != 0.0:
			return true
	return false


func _different(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	return _finite6(left) and _finite6(right) and left.to_byte_array() != right.to_byte_array()


func _prepare(backend: Object, model: Dictionary) -> int:
	return int(backend.call("prepare_model", model))


func _record(label: String, passed: bool, detail: String) -> void:
	_record_row({"label": label, "kind": "check", "passed": passed, "detail": detail})


func _record_row(row: Dictionary) -> void:
	if bool(row.get("passed", false)):
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL %s: %s" % [row.get("label", "unknown"), str(row)])
	_rows.append(row)


func _finish(path: String) -> void:
	var report: Dictionary = {"format": "openrc-e0b6p-prepared-model-lifecycle v1",
		"checks": _rows.size(), "case_count": _rows.size(), "passed": _passed,
		"failed": _failed, "failures": _failed, "native_calls": _calls,
		"results": _rows, "fixture_note": "Validated research fixtures; not aircraft calibration.",
		"godot": Engine.get_version_info().string}
	if not path.is_empty():
		var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if output == null:
			_failed += 1
			printerr("could not open verification report: ", path)
		else:
			report["failed"] = _failed
			report["failures"] = _failed
			output.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	print("E0b6p prepared lifecycle: %d cases, %d passed, %d failed; %d native calls" % [
		_rows.size(), _passed, _failed, _calls])
	quit(1 if _failed > 0 else 0)
