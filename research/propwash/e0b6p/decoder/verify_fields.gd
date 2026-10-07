# E0b6p: bounded native model-decoder field contract probe.
# Run in a disposable app copy with tests/e0b6p_native/adapter.gd installed.
extends SceneTree

const Adapter = preload("res://tests/e0b6p_native/adapter.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Fixture = preload("res://tests/test_wash_profile.gd")
const Propulsion = preload("res://physics/propulsion.gd")

const RHO: float = 1.225
const HELD_CL: float = 0.3

var _state: PackedFloat64Array = PackedFloat64Array()
var _velocity: PackedFloat64Array = PackedFloat64Array()
var _thrust_torque: PackedFloat64Array = PackedFloat64Array()
var _fade: float = 1.0
var _model: Dictionary = {}
var _controls: Dictionary = {}
var _native_calls: int = 0
var _passed: int = 0
var _failed: int = 0
var _cases: Array[Dictionary] = []


func _initialize() -> void:
	if not Adapter.available():
		_record("native adapter loads the GDExtension", false, "expected an available backend")
		_finish()
		return

	var validated: Dictionary = AircraftData.validate_and_derive(Fixture.combined_raw())
	if not bool(validated.get("ok", false)):
		_record("combined_raw fixture passes AircraftData validation", false,
			str(validated.get("errors", [])))
		_finish()
		return
	_model = validated.model
	_prepare_call()

	var baseline: Variant = _call_native(_model, _controls)
	var baseline_ok: bool = _is_finite_loads(baseline) and _has_nonzero_load(baseline)
	_record("schema-validated heldCL=0.3 native call is finite and nonzero", baseline_ok,
		_result_summary(baseline))
	if not baseline_ok:
		_finish()
		return

	_check_required_fields()
	_check_finite_integer_number()
	_check_conditional_free_slope()
	_check_optional_numbers()
	_finish()


func _prepare_call() -> void:
	_velocity = PackedFloat64Array([14.0, 0.0, 0.0])
	_state = PackedFloat64Array([
		0.0, 0.0, -100.0, _velocity[0], _velocity[1], _velocity[2],
		1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	])
	_controls = {
		"elevator": 0.08,
		"rudder": -0.04,
		"aileron_left": 0.0,
		"aileron_right": 0.0,
	}
	var propulsion: Dictionary = _model["propulsion"]
	var full_thrust_torque: PackedFloat64Array = Propulsion.thrust_torque(
		_velocity, propulsion["max_rpm"], propulsion, RHO)
	_thrust_torque = PackedFloat64Array([full_thrust_torque[0], full_thrust_torque[1]])
	_fade = 1.0


func _call_native(model: Dictionary, controls: Dictionary) -> Variant:
	_native_calls += 1
	# Keep this call signature aligned with native/verify.gd's direct backend probe.
	return Adapter.backend.call("loads", _state, _velocity, controls, model, _thrust_torque,
		RHO, _fade, HELD_CL, PackedFloat64Array())


func _check_required_fields() -> void:
	for field: Dictionary in _required_fields():
		var root_name: String = str(field["root"])
		var path: Array = field["path"]
		var kind: String = str(field["kind"])
		var shape: int = int(field.get("shape", 0))
		var operations: Array[String] = ["absent", "null", "wrongtype", "nonfinite"]
		if kind.begins_with("packed"):
			operations.append("wrongshape")
		for operation: String in operations:
			var case_model: Dictionary = _model.duplicate(true)
			var case_controls: Dictionary = _controls.duplicate(true)
			var source: Dictionary = case_model if root_name == "model" else case_controls
			var mutated: Dictionary = _mutated_root(source, path, kind, shape, operation)
			if root_name == "model":
				case_model = mutated
			else:
				case_controls = mutated
			var result: Variant = _call_native(case_model, case_controls)
			var label: String = "%s.%s rejects %s" % [root_name, _path_text(path), operation]
			_record(label, _is_refusal(result), _result_summary(result))


func _required_fields() -> Array[Dictionary]:
	var fields: Array[Dictionary] = [
		{"root": "model", "path": ["propulsion", "diameter"], "kind": "number"},
		{"root": "model", "path": ["propulsion", "slipstream", "hub"], "kind": "packed", "shape": 3},
		{"root": "model", "path": ["propulsion", "slipstream", "wash_factor"], "kind": "packed", "shape": 2},
		{"root": "model", "path": ["propulsion", "slipstream", "swirl_factor"], "kind": "number"},
		{"root": "model", "path": ["propulsion", "slipstream", "vertical_drift"], "kind": "number"},
		{"root": "model", "path": ["propulsion", "slipstream", "edge_fraction"], "kind": "number"},
		{"root": "model", "path": ["cg_le"], "kind": "packed", "shape": 3},
		{"root": "model", "path": ["surfaces", "tail_local_limit"], "kind": "number"},
		{"root": "model", "path": ["surfaces", "tail_stall_end"], "kind": "number"},
		{"root": "model", "path": ["surfaces", "tail_CD0"], "kind": "number"},
		{"root": "model", "path": ["surfaces", "tail_k"], "kind": "number"},
		{"root": "model", "path": ["surfaces", "tail_CD90"], "kind": "number"},
		{"root": "controls", "path": ["elevator"], "kind": "number"},
		{"root": "controls", "path": ["rudder"], "kind": "number"},
	]
	for tail_name: String in ["horizontal", "vertical"]:
		fields.append({"root": "model", "path": ["surfaces", tail_name, "position"],
			"kind": "packed", "shape": 3})
		for key: String in ["lift_slope", "control_effectiveness", "incidence"]:
			fields.append({"root": "model", "path": ["surfaces", tail_name, key], "kind": "number"})
	var slipstream: Dictionary = _model["propulsion"]["slipstream"]
	var pieces: Array = slipstream["pieces"]
	for piece_index: int in pieces.size():
		for key: String in ["area", "span"]:
			fields.append({"root": "model", "path": ["propulsion", "slipstream", "pieces", piece_index, key],
				"kind": "number"})
		for key: String in ["root", "span_dir"]:
			fields.append({"root": "model", "path": ["propulsion", "slipstream", "pieces", piece_index, key],
				"kind": "packed", "shape": 3})
	return fields


func _check_finite_integer_number() -> void:
	var integer_model: Dictionary = _set_root(_model, ["propulsion", "slipstream", "swirl_factor"], 0)
	var result: Variant = _call_native(integer_model, _controls)
	_record("finite integer accepted by read_number", _is_finite_loads(result)
		and _has_nonzero_load(result), _result_summary(result))


func _check_conditional_free_slope() -> void:
	var path: Array = ["surfaces", "horizontal", "free_slope"]
	var surfaces: Dictionary = _model["surfaces"]
	var horizontal: Dictionary = surfaces["horizontal"]
	if not horizontal.has("free_slope"):
		_record("combined_raw fixture enables the conditional free_slope branch", false,
			"horizontal.free_slope is absent")
		return
	var classic_model: Dictionary = _without_path(_model, path)
	var absent_result: Variant = _call_native(classic_model, _controls)
	_record("conditional free_slope absence selects the accepted classic-tail branch",
		_is_finite_loads(absent_result), _result_summary(absent_result))
	for operation: String in ["null", "wrongtype", "nonfinite"]:
		var malformed: Dictionary = _mutated_root(_model, path, "number", 0, operation)
		var result: Variant = _call_native(malformed, _controls)
		_record("model.%s rejects %s when present" % [_path_text(path), operation],
			_is_refusal(result), _result_summary(result))


func _check_optional_numbers() -> void:
	var optional_paths: Array[Array] = [
		["surfaces", "horizontal", "downwash_per_cl"],
		["surfaces", "horizontal", "elevator_tau"],
		["surfaces", "horizontal", "free_incidence"],
		["surfaces", "vertical", "downwash_per_cl"],
		["surfaces", "vertical", "elevator_tau"],
		["surfaces", "vertical", "free_incidence"],
	]
	for path: Array in optional_paths:
		var absent_model: Dictionary = _without_path(_model, path)
		var zero_model: Dictionary = _set_root(_model, path, 0.0)
		var absent_result: Variant = _call_native(absent_model, _controls)
		var zero_result: Variant = _call_native(zero_model, _controls)
		var equivalent: bool = _is_finite_loads(absent_result) and _is_finite_loads(zero_result)
		if equivalent:
			var absent_values: PackedFloat64Array = absent_result
			var zero_values: PackedFloat64Array = zero_result
			equivalent = absent_values.to_byte_array() == zero_values.to_byte_array()
		_record("optional_number %s absence equals explicit zero" % _path_text(path), equivalent,
			"absent=%s; zero=%s" % [_result_summary(absent_result), _result_summary(zero_result)])
		var nil_model: Dictionary = _set_root(_model, path, null)
		var nil_result: Variant = _call_native(nil_model, _controls)
		_record("optional_number %s rejects explicit nil" % _path_text(path), _is_refusal(nil_result),
			_result_summary(nil_result))


func _mutated_root(source: Dictionary, path: Array, kind: String, shape: int,
		operation: String) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	if operation == "absent":
		_erase_path(result, path)
	else:
		var replacement: Variant = _invalid_value(kind, shape, operation)
		_set_path(result, path, replacement)
	return result


func _invalid_value(kind: String, shape: int, operation: String) -> Variant:
	if operation == "null":
		return null
	if operation == "wrongtype":
		return "wrong native field type"
	if operation == "nonfinite":
		if kind == "number":
			return NAN
		var nonfinite: PackedFloat64Array = PackedFloat64Array()
		nonfinite.resize(shape)
		nonfinite.fill(0.0)
		nonfinite[0] = NAN
		return nonfinite
	if operation == "wrongshape":
		return PackedFloat64Array([0.0])
	return null


func _set_root(source: Dictionary, path: Array, value: Variant) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	_set_path(result, path, value)
	return result


func _without_path(source: Dictionary, path: Array) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	_erase_path(result, path)
	return result


func _set_path(root: Dictionary, path: Array, value: Variant) -> void:
	var parent: Variant = root
	for index: int in range(path.size() - 1):
		var segment: Variant = path[index]
		if parent is Dictionary:
			var dictionary_parent: Dictionary = parent
			parent = dictionary_parent[segment]
		elif parent is Array:
			var array_parent: Array = parent
			parent = array_parent[int(segment)]
		else:
			return
	var leaf: Variant = path[path.size() - 1]
	if parent is Dictionary:
		var dictionary_parent: Dictionary = parent
		dictionary_parent[leaf] = value
	elif parent is Array:
		var array_parent: Array = parent
		array_parent[int(leaf)] = value


func _erase_path(root: Dictionary, path: Array) -> void:
	var parent: Variant = root
	for index: int in range(path.size() - 1):
		var segment: Variant = path[index]
		if parent is Dictionary:
			var dictionary_parent: Dictionary = parent
			parent = dictionary_parent[segment]
		elif parent is Array:
			var array_parent: Array = parent
			parent = array_parent[int(segment)]
		else:
			return
	var leaf: Variant = path[path.size() - 1]
	if parent is Dictionary:
		var dictionary_parent: Dictionary = parent
		dictionary_parent.erase(leaf)
	elif parent is Array:
		var array_parent: Array = parent
		array_parent.remove_at(int(leaf))


func _is_finite_loads(result: Variant) -> bool:
	if not (result is PackedFloat64Array):
		return false
	var values: PackedFloat64Array = result
	if values.size() != 6:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _has_nonzero_load(result: Variant) -> bool:
	if not _is_finite_loads(result):
		return false
	var values: PackedFloat64Array = result
	for value: float in values:
		if value != 0.0:
			return true
	return false


func _is_refusal(result: Variant) -> bool:
	if not (result is PackedFloat64Array):
		return false
	var values: PackedFloat64Array = result
	return values.is_empty()


func _result_summary(result: Variant) -> String:
	if not (result is PackedFloat64Array):
		return "type=%s" % type_string(typeof(result))
	var values: PackedFloat64Array = result
	return "size=%d finite=%s nonzero=%s" % [values.size(), _all_finite(values), _has_nonzero_load(values)]


func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _path_text(path: Array) -> String:
	var result: String = ""
	for segment: Variant in path:
		if segment is int:
			result += "[%d]" % int(segment)
		else:
			if not result.is_empty():
				result += "."
			result += str(segment)
	return result


func _record(label: String, passed: bool, observed: String) -> void:
	if passed:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL %s: %s" % [label, observed])
	_cases.append({"label": label, "passed": passed, "observed": observed})


func _finish() -> void:
	var required_field_count: int = 0
	if not _model.is_empty():
		required_field_count = _required_fields().size()
	var report: Dictionary = {
		"format": "openrc-e0b6p-native-field-verification v1",
		"required_field_count": required_field_count,
		"native_calls": _native_calls,
		"cases": _cases.size(),
		"passed": _passed,
		"failed": _failed,
		"results": _cases,
		"godot": Engine.get_version_info().string,
	}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_record("report path supplied", false, "expected one JSON output path")
	else:
		var output: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
		if output == null:
			_record("report path writable", false, "could not open %s" % args[0])
		else:
			report["cases"] = _cases.size()
			report["passed"] = _passed
			report["failed"] = _failed
			report["results"] = _cases
			output.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	print("E0b6p native field decoder: %d cases, %d passed, %d failed; %d native calls" % [
		_cases.size(), _passed, _failed, _native_calls])
	quit(1 if _failed > 0 else 0)
