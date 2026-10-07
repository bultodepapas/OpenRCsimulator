# D1-R2: a shaft curve obeys the same typed/provenanced quantity contract as other tables.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const P51 := "res://data/aircraft/p51d_mustang_120.json"
const CURVE_PATH := "propulsion.engine.shaft.power_curve"

var _raw: Dictionary
var _checks: int = 0
var _failures: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s: %s" % [label, detail])


func _reject(label: String, table: Variant) -> void:
	var data: Dictionary = _raw.duplicate(true)
	data.propulsion.engine.shaft.power_curve = table
	var result: Dictionary = AD.validate_and_derive(data)
	_check(label, not result.ok and result.model.is_empty()
		and str(result.errors).contains(CURVE_PATH), str(result.errors))


func _initialize() -> void:
	_raw = JSON.parse_string(FileAccess.get_file_as_string(P51))
	var original: Dictionary = _raw.propulsion.engine.shaft.power_curve
	for entry in Catalog.ENTRIES:
		var result: Dictionary = AD.load_file(entry.data)
		_check("current aircraft loads: " + entry.id, result.ok, str(result.errors))

	var expected: PackedFloat64Array = PackedFloat64Array()
	for row in original.value:
		expected.append_array(PackedFloat64Array(row))
	_check("valid curve values and order preserved", AD.load_file(P51).model.propulsion.shaft.power_curve == expected)
	for kind in AD.KINDS:
		var valid: Dictionary = _raw.duplicate(true)
		valid.propulsion.engine.shaft.power_curve.kind = kind
		valid.propulsion.engine.shaft.power_curve.value = [[1000, 820.6], [1500.0, 1268]]
		_check("integer/float pairs and kind " + kind, AD.validate_and_derive(valid).ok)

	for field in ["value", "unit", "kind", "source"]:
		var missing: Dictionary = original.duplicate(true)
		missing.erase(field)
		_reject("missing " + field, missing)
	for kind in [null, "", "guess", 1, true, [], {}]:
		var bad: Dictionary = original.duplicate(true)
		bad.kind = kind
		_reject("invalid kind " + str(kind), bad)
	for source in [null, "", " \t\n", 123, true, [], {}]:
		var bad: Dictionary = original.duplicate(true)
		bad.source = source
		_reject("invalid source " + str(source), bad)
	for unit in [null, "", "W", "rpm,W", 123, []]:
		var bad: Dictionary = original.duplicate(true)
		bad.unit = unit
		_reject("invalid unit " + str(unit), bad)
	for table in [null, [], "curve", 123, true, {}]:
		_reject("invalid table shape " + str(table), table)
	for rows in [null, {}, "rows", [], [[1000, 100]], [null, [2000, 200]],
		[[1000], [2000, 200]], [[1000, 100, 1], [2000, 200]], [[1000, 100], {}]]:
		var bad: Dictionary = original.duplicate(true)
		bad.value = rows
		_reject("invalid rows " + str(rows), bad)

	# Both columns, both ends and an interior row. In-memory NaN/Inf must be
	# refused before derivation/hash serialization; JSON files also use this API.
	for row_index in [0, original.value.size() / 2, original.value.size() - 1]:
		for column in 2:
			for value in ["1000", true, false, null, [], {}, NAN, INF, -INF]:
				var bad: Dictionary = original.duplicate(true)
				bad.value[row_index][column] = value
				_reject("invalid cell [%d][%d] = %s" % [row_index, column, value], bad)
	for rows in [[[0, 100], [2000, 200]], [[-1, 100], [2000, 200]],
		[[1000, 0], [2000, 200]], [[1000, 100], [2000, -1]],
		[[1000, 100], [1000, 200]], [[2000, 100], [1000, 200]]]:
		var bad: Dictionary = original.duplicate(true)
		bad.value = rows
		_reject("invalid positive/order constraint " + str(rows), bad)

	_test_file_and_session_guards()
	print("D1-R2: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_file_and_session_guards() -> void:
	var invalid: Dictionary = _raw.duplicate(true)
	invalid.propulsion.engine.shaft.power_curve.value[0][0] = "1000"
	invalid.propulsion.engine.shaft.power_curve.erase("source")
	var path: String = "user://d1-r2-invalid-aircraft.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check("temporary fixture opens", file != null)
	if file == null:
		return
	file.store_string(JSON.stringify(invalid))
	file.close()
	var loaded: Dictionary = AD.load_file(path)
	_check("invalid JSON file refused with field path", not loaded.ok and str(loaded.errors).contains(CURVE_PATH))
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(P51)
	root.add_child(session)
	for _i in 10:
		session.sim.step()
	var aircraft: Dictionary = session.aircraft.duplicate(true)
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var previous: PackedFloat64Array = session.sim.previous.duplicate()
	var aux: PackedFloat64Array = session.sim.aux.duplicate()
	var start: Dictionary = session.start.duplicate(true)
	var trims: Dictionary = session.trims.duplicate(true)
	var tick: int = session.sim.tick
	session.aircraft_path = path
	var message: String = session.reload()
	_check("bad reload identifies curve", message.begins_with("reload failed") and message.contains(CURVE_PATH), message)
	_check("bad reload preserves model/trim", session.aircraft == aircraft and session.start == start and session.trims == trims)
	_check("bad reload preserves full flight state", session.sim.state == state and session.sim.previous == previous and session.sim.aux == aux
		and session.sim.tick == tick and not session.sim.paused and session.engine_running)
	session.sim.step()
	_check("previous aircraft keeps flying", session.sim.tick == tick + 1 and session.sim.fault_reason.is_empty())
	session.free()

	var initial: Node = Session.new()
	initial.input_enabled = false
	initial.setup(path)
	root.add_child(initial)
	_check("invalid initial aircraft cannot fly", not initial.is_flyable() and initial.sim.paused and initial.pause_reason.contains(CURVE_PATH))
	initial.resume()
	initial.sim.step()
	_check("resume cannot bypass invalid data", initial.sim.paused and initial.sim.tick == 0)
	initial.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
