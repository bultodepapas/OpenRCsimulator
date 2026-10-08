# E0b6p explicit-adapter protocol checks; run only in the disposable prepared-model app.
extends SceneTree

const Prepared: Script = preload("res://tests/e0b6p_prepared/adapter.gd")
const Raw: Script = preload("res://tests/e0b6p_native/adapter.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Fixture = preload("res://tests/test_wash_profile.gd")
const Air = preload("res://physics/air_data.gd")
const Oracle = preload("res://physics/slipstream.gd")
const RHO: float = 1.225
const EXPECTED_CASES: int = 35

var _rows: Array[Dictionary] = []
var _failed: int = 0


func _initialize() -> void:
	var output_path: String = _output_path()
	_record("output path supplied", not output_path.is_empty(), output_path)
	if output_path.is_empty():
		_finish("")
		return
	_record("prepared adapter available", Prepared.available(), "")
	_record("stateless native adapter available", Raw.available(), "")
	if not Prepared.available() or not Raw.available():
		_finish(output_path)
		return
	Prepared.reset_route_counts()
	Raw.reset_route_counts()
	var raw: Dictionary = Fixture.combined_raw()
	raw.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	var loaded: Dictionary = AircraftData.validate_and_derive(raw)
	_record("combined fixture validates", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		_finish(output_path)
		return
	var model: Dictionary = loaded.model
	var input: Dictionary = _inputs(model)
	_record("smooth prepare succeeds", Prepared.prepare(model), "")
	_compare("prepared loads equal stateless native bytes", model, input)
	_record("prepared route was used", int(Prepared.prepared_calls) > 0 and int(Prepared.setup_calls) == 0,
		str(_protocol()))

	Prepared.backend.call("invalidate_model")
	var setup_before: int = int(Prepared.setup_calls)
	_refusal("direct backend invalidation refuses active smooth load", model, input)
	_record("backend invalidation did not fall back to setup", int(Prepared.setup_calls) == setup_before,
		str(_protocol()))
	_record("prepare restores invalidated backend", Prepared.prepare(model), "")
	_compare("reprepared loads are exact", model, input)

	var replacement: Dictionary = model.duplicate(true)
	var refused_before: int = int(Prepared.route_counts.refused)
	_refusal("replacement dictionary identity is rejected", replacement, input)
	_record("replacement rejection avoids setup fallback",
		int(Prepared.route_counts.refused) == refused_before + 1, str(_protocol()))
	_compare("original dictionary remains prepared", model, input)

	var malformed: Dictionary = model.duplicate(true)
	malformed.propulsion.slipstream.pieces[0].root = PackedFloat64Array([0.0, 0.0])
	var attempts_before: int = int(Prepared.prepared_calls)
	_record("malformed prepare fails", not Prepared.prepare(malformed), "")
	var setup_after_failure: int = int(Prepared.setup_calls)
	_refusal("failed prepare refuses without raw fallback", malformed, input)
	_record("failed prepare did not call setup or prepared kernel",
		int(Prepared.setup_calls) == setup_after_failure and int(Prepared.prepared_calls) == attempts_before,
		str(_protocol()))

	Prepared.begin_setup()
	_record("begin_setup enables explicit raw setup", bool(Prepared.setup_mode), str(_protocol()))
	var setup_count: int = int(Prepared.setup_calls)
	_compare("begin_setup uses stateless native loads", model, input)
	_record("begin_setup increments only setup route", int(Prepared.setup_calls) == setup_count + 1,
		str(_protocol()))

	_record("nested-edit fixture prepares", Prepared.prepare(model), "")
	var before: PackedFloat64Array = _compare("nested-edit baseline", model, input)
	var slipstream: Dictionary = model.propulsion.slipstream
	var wash: PackedFloat64Array = slipstream.wash_factor
	wash.fill(0.0)
	slipstream.wash_factor = wash
	slipstream.swirl_factor = 0.0
	model.propulsion.slipstream = slipstream
	var held: PackedFloat64Array = _prepared_loads(model, input)
	var edited_raw: PackedFloat64Array = _raw_loads(model, input)
	_record("nested edits retain old snapshot until reprepare", _same(before, held), str(held))
	_record("stateless loads observe nested edit", _different(held, edited_raw), str(edited_raw))
	_record("reprepare after nested edit succeeds", Prepared.prepare(model), "")
	var updated: PackedFloat64Array = _compare("reprepared loads equal edited stateless bytes", model, input)
	_record("reprepare updates loads", _different(before, updated), str(updated))

	_record("prepare smooth model before mode-change check", Prepared.prepare(model), "")
	slipstream = model.propulsion.slipstream
	slipstream.erase("edge_fraction")
	model.propulsion.slipstream = slipstream
	_refusal("removing edge_fraction after prepare is rejected", model, input)
	var no_wake: Dictionary = model.propulsion
	no_wake.slipstream = {}
	model.propulsion = no_wake
	_record("explicit legacy reprepare succeeds", Prepared.prepare(model), "")
	_compare_oracle("legacy reprepare returns normal oracle", model, input)

	var legacy_result: Dictionary = AircraftData.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	_record("real legacy aircraft loads", bool(legacy_result.get("ok", false)),
		str(legacy_result.get("errors", [])))
	if bool(legacy_result.get("ok", false)):
		var legacy: Dictionary = legacy_result.model
		var legacy_input: Dictionary = _inputs(legacy)
		_record("legacy aircraft prepare succeeds", Prepared.prepare(legacy), "")
		_compare_oracle("legacy aircraft uses normal oracle", legacy, legacy_input)
	_record("legacy oracle route was used", int(Prepared.route_counts.legacy) > 0,
		str(Prepared.route_counts))
	_finish(output_path)


func _inputs(model: Dictionary) -> Dictionary:
	var state: PackedFloat64Array = PackedFloat64Array([
		0.0, 0.0, -100.0, 14.0, 0.6, -0.35, 1.0, 0.0, 0.0, 0.0, 0.08, -0.05, 0.03,
	])
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
	return {"state": state, "air": air,
		"controls": {"elevator": 0.12, "rudder": -0.1, "aileron_left": 0.0, "aileron_right": 0.0},
		"rpm": float(model.propulsion.max_rpm), "rho": RHO, "cl": 0.34,
		"transport": PackedFloat64Array()}


func _compare(label: String, model: Dictionary, input: Dictionary) -> PackedFloat64Array:
	return _compare_values(label, Prepared.loads(input.state, input.air, input.controls, model,
		input.rpm, input.rho, input.cl, input.transport),
		Raw.loads(input.state, input.air, input.controls, model, input.rpm, input.rho, input.cl, input.transport))


func _compare_oracle(label: String, model: Dictionary, input: Dictionary) -> void:
	var expected: PackedFloat64Array = Oracle.loads(input.state, input.air, input.controls, model,
		input.rpm, input.rho, input.cl, input.transport)
	_compare_values(label, Prepared.loads(input.state, input.air, input.controls, model, input.rpm,
		input.rho, input.cl, input.transport), expected)


func _compare_values(label: String, actual: PackedFloat64Array, expected: PackedFloat64Array) -> PackedFloat64Array:
	var finite: bool = _finite6(actual) and _finite6(expected)
	var exact: bool = finite and actual.to_byte_array() == expected.to_byte_array()
	_record_row({"label": label, "passed": finite and exact, "finite6": finite,
		"exact_bytes": exact, "actual": _json_loads(actual), "expected": _json_loads(expected)})
	return actual


func _prepared_loads(model: Dictionary, input: Dictionary) -> PackedFloat64Array:
	return Prepared.loads(input.state, input.air, input.controls, model, input.rpm, input.rho,
		input.cl, input.transport)


func _raw_loads(model: Dictionary, input: Dictionary) -> PackedFloat64Array:
	return Raw.loads(input.state, input.air, input.controls, model, input.rpm, input.rho,
		input.cl, input.transport)


func _refusal(label: String, model: Dictionary, input: Dictionary) -> void:
	var result: PackedFloat64Array = _prepared_loads(model, input)
	var refused: bool = result.size() == 6 and not _all_finite(result)
	_record_row({"label": label, "passed": refused, "refused_nonfinite6": refused,
		"actual_size": result.size(), "all_finite": _all_finite(result)})


func _protocol() -> Dictionary:
	return {"attempts": Prepared.preparation_attempts, "prepared_calls": Prepared.prepared_calls,
		"setup_calls": Prepared.setup_calls, "setup_mode": Prepared.setup_mode,
		"routes": Prepared.route_counts}


func _finite6(values: PackedFloat64Array) -> bool:
	return values.size() == 6 and _all_finite(values)


func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _same(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	return _finite6(left) and _finite6(right) and left.to_byte_array() == right.to_byte_array()


func _different(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	return _finite6(left) and _finite6(right) and left.to_byte_array() != right.to_byte_array()


func _json_loads(values: PackedFloat64Array) -> Array[float]:
	var result: Array[float] = []
	if _finite6(values):
		for value: float in values:
			result.append(value)
	return result


func _output_path() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--output="):
			return arg.trim_prefix("--output=")
		if not arg.begins_with("--"):
			return arg
	return ""


func _record(label: String, passed: bool, detail: String) -> void:
	_record_row({"label": label, "passed": passed, "detail": detail})


func _record_row(row: Dictionary) -> void:
	if not bool(row.get("passed", false)):
		_failed += 1
		printerr("FAIL %s: %s" % [row.get("label", "unknown"), str(row)])
	_rows.append(row)


func _finish(path: String) -> void:
	if _rows.size() != EXPECTED_CASES:
		_record("expected case count", false, "expected=%d actual=%d" % [EXPECTED_CASES, _rows.size()])
	var report: Dictionary = {"format": "openrc-e0b6p-prepared-adapter v1",
		"case_count": _rows.size(), "expected_cases": EXPECTED_CASES,
		"passed": _rows.size() - _failed, "failed": _failed, "failures": _failed,
		"results": _rows, "protocol": _protocol(), "godot": Engine.get_version_info().string}
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_failed += 1
			printerr("could not open adapter verification report: ", path)
		else:
			report["failed"] = _failed
			report["failures"] = _failed
			file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	print("E0b6p prepared adapter: %d cases, %d passed, %d failed" % [
		_rows.size(), _rows.size() - _failed, _failed])
	quit(1 if _failed > 0 else 0)
