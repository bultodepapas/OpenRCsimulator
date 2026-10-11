# EL2a: provenance-complete OCV/resistance battery data without changing fixed-voltage normalization.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const BATTERY_4S := "res://data/aircraft/synthetic_stik_electric_4s_battery.json"
const BATTERY_6S := "res://data/aircraft/synthetic_stik_electric_6s_battery.json"
const FIXED_4S := "res://data/aircraft/synthetic_stik_electric_4s.json"
const FIXED_6S := "res://data/aircraft/synthetic_stik_electric_6s.json"

var _failures: int = 0
var _count: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _raw(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _rejects(label: String, path: String, mutate: Callable, needle: String) -> void:
	var raw: Dictionary = _raw(path)
	mutate.call(raw)
	var result: Dictionary = AD.validate_and_derive(raw)
	_check("rejects: " + label, not result.ok and _contains(result.errors, needle), str(result.errors))


func _contains(messages: PackedStringArray, needle: String) -> bool:
	for message: String in messages:
		if needle in message:
			return true
	return false


func _has_synthetic_provenance(quantity: Dictionary) -> bool:
	return quantity.get("kind") == "estimated" and typeof(quantity.get("source")) == TYPE_STRING \
		and "EL2a synthetic authored fixture" in str(quantity.get("source")) \
		and "not Timber data" in str(quantity.get("source")) \
		and "measured LiPo fit" in str(quantity.get("source"))


func _check_synthetic_provenance(raw: Dictionary, label: String) -> void:
	var battery: Dictionary = raw.propulsion.battery
	for key: String in ["capacity_ah", "resistance_ohm", "auxiliary_current_a", "initial_soc"]:
		_check(label + " provenance: " + key, _has_synthetic_provenance(battery[key]), str(battery[key]))
	for index: int in battery.ocv_points.size():
		for key: String in ["soc", "voltage"]:
			_check(label + " provenance: point %d %s" % [index, key],
				_has_synthetic_provenance(battery.ocv_points[index][key]), str(battery.ocv_points[index][key]))


func _check_fixture(path: String, label: String, expected_kv: float, expected_capacity: float,
		expected_resistance: float, expected_auxiliary: float, expected_min_ocv: float,
		expected_max_ocv: float) -> void:
	var raw: Dictionary = _raw(path)
	_check(label + " fixture identity is distinct", raw.get("id") == label)
	_check_synthetic_provenance(raw, label)
	var result: Dictionary = AD.load_file(path)
	_check(label + " loads", result.ok, str(result.errors))
	if not result.ok:
		return
	var propulsion: Dictionary = result.model.propulsion
	var battery: Dictionary = propulsion.battery
	_check(label + " battery kind normalized", battery.get("kind") == "ocv_resistance", str(battery))
	_check(label + " capacity and initial SOC normalized",
			battery.get("capacity_ah") == expected_capacity and battery.get("initial_soc") == 0.95,
			str(battery))
	_check(label + " pack resistance and auxiliary current normalized",
			battery.get("resistance_ohm") == expected_resistance
			and battery.get("auxiliary_current_a") == expected_auxiliary, str(battery))
	_check(label + " OCV knots normalize to float64 SOC/voltage pairs",
			battery.get("ocv_points") == PackedFloat64Array([0.0, expected_min_ocv, 1.0, expected_max_ocv]),
			str(battery.get("ocv_points")))
	_check(label + " maximum Kv × OCV is only the reference RPM",
			propulsion.get("max_rpm") == expected_kv * expected_max_ocv, str(propulsion.get("max_rpm")))
	_check(label + " minimum-SOC auxiliary bus is feasible",
			expected_resistance * expected_auxiliary < expected_min_ocv)


func _check_fixed_voltage(path: String, expected_voltage: float, expected_rpm: float) -> void:
	var result: Dictionary = AD.load_file(path)
	_check("legacy fixed-voltage fixture still loads: " + path.get_file(), result.ok, str(result.errors))
	if not result.ok:
		return
	var propulsion: Dictionary = result.model.propulsion
	var battery: Dictionary = propulsion.battery
	_check("fixed-voltage normalized dictionary is unchanged: " + path.get_file(),
		battery.size() == 2 and battery.get("kind") == "fixed_voltage"
		and battery.get("voltage_v") == expected_voltage)
	_check("fixed-voltage Kv reference is unchanged: " + path.get_file(), propulsion.get("max_rpm") == expected_rpm)
	_check("fixed-voltage native encoding is unchanged: " + path.get_file(),
		var_to_bytes(battery) == var_to_bytes({kind = "fixed_voltage", voltage_v = expected_voltage}))


func _initialize() -> void:
	_check_fixture(BATTERY_4S, "synthetic_stik_electric_4s_battery", 800.0, 3.2, 0.03, 0.2, 12.0, 16.8)
	_check_fixture(BATTERY_6S, "synthetic_stik_electric_6s_battery", 400.0, 2.2, 0.045, 0.15, 18.0, 25.2)
	_check_fixed_voltage(FIXED_4S, 14.8, 800.0 * 14.8)
	_check_fixed_voltage(FIXED_6S, 22.2, 400.0 * 22.2)

	_rejects("unknown battery field", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.cell_count = 4, "unsupported field")
	_rejects("mixed fixed-voltage field", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.voltage_v = {value = 14.8, unit = "V", kind = "estimated", source = "EL2a mixed-field test"}, "unsupported field")
	_rejects("unknown OCV point field", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.ocv_points[0].temperature_c = 25.0, "unsupported field")
	_rejects("zero capacity", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.capacity_ah.value = 0.0, "capacity_ah")
	_rejects("negative pack resistance", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.resistance_ohm.value = -0.01, "resistance_ohm")
	_rejects("negative auxiliary current", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.auxiliary_current_a.value = -0.1, "auxiliary_current_a")
	_rejects("zero initial SOC", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.initial_soc.value = 0.0, "initial_soc")
	_rejects("initial SOC above one", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.initial_soc.value = 1.01, "initial_soc")
	_rejects("zero OCV voltage", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.ocv_points[0].voltage.value = 0.0, "voltage")
	_rejects("wrong OCV voltage unit", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.ocv_points[0].voltage.unit = "mV", "ocv_points[0].voltage")
	_rejects("wrong SOC unit", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.ocv_points[0].soc.unit = "percent", "ocv_points[0].soc")
	_rejects("empty OCV provenance", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.ocv_points[1].voltage.source = " \t", "ocv_points[1].voltage")
	_rejects("missing OCV endpoint", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.ocv_points[1].soc.value = 0.9, "last SOC knot")
	_rejects("first OCV endpoint is not zero", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.ocv_points[0].soc.value = 0.1, "first SOC knot")
	_rejects("decreasing SOC knots", BATTERY_4S,
		func(data: Dictionary) -> void: _set_three_points(data, [0.0, 12.0, 1.0, 16.0, 0.5, 16.8]), "strictly increasing")
	_rejects("decreasing OCV curve", BATTERY_4S,
		func(data: Dictionary) -> void: _set_three_points(data, [0.0, 12.0, 0.5, 16.0, 1.0, 15.0]), "nondecreasing")
	_rejects("too few OCV points", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.ocv_points.resize(1), "at least two")
	_rejects("minimum-OCV auxiliary load is infeasible", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.resistance_ohm.value = 60.0, "feasible bus")
	_rejects("finite inputs whose auxiliary sag overflows", BATTERY_4S,
		func(data: Dictionary) -> void: _set_battery_pair(data, 1e308, 1e308), "nonfinite")
	_rejects("capacity-to-coulomb conversion overflow", BATTERY_4S,
		func(data: Dictionary) -> void: data.propulsion.battery.capacity_ah.value = 1e308, "3600 × capacity")
	_rejects("initial charge underflow", BATTERY_4S,
		func(data: Dictionary) -> void: _set_capacity_and_soc(data, 3e-308, 1e-21), "initial charge")
	_rejects("OCV segment slope overflow", BATTERY_4S,
		func(data: Dictionary) -> void: _set_three_points(data, [0.0, 12.0, 3e-308, 24.0, 1.0, 25.0]), "slope")

	var nonfinite: Dictionary = _raw(BATTERY_4S)
	nonfinite.propulsion.battery.ocv_points[0].voltage.value = INF
	var inf_result: Dictionary = AD.validate_and_derive(nonfinite)
	_check("in-memory OCV INF rejected", not inf_result.ok and _contains(inf_result.errors, "ocv_points[0].voltage"), str(inf_result.errors))
	nonfinite = _raw(BATTERY_4S)
	nonfinite.propulsion.battery.resistance_ohm.value = NAN
	var nan_result: Dictionary = AD.validate_and_derive(nonfinite)
	_check("in-memory resistance NAN rejected", not nan_result.ok and _contains(nan_result.errors, "resistance_ohm"), str(nan_result.errors))
	_check_serialized_overflow()

	if _failures > 0:
		printerr("EL2a electric battery data: %d/%d checks failed" % [_failures, _count])
		quit(1)
	else:
		print("EL2a electric battery data: %d checks passed" % _count)
		quit(0)


func _set_three_points(data: Dictionary, flat: Array) -> void:
	var source: String = "EL2a synthetic authored fixture for a loader test; not Timber data or a measured LiPo fit"
	var points: Array = []
	for index: int in range(0, flat.size(), 2):
		points.append({
			"soc": {"value": flat[index], "unit": "1", "kind": "estimated", "source": source},
			"voltage": {"value": flat[index + 1], "unit": "V", "kind": "estimated", "source": source},
		})
	data.propulsion.battery.ocv_points = points


func _set_battery_pair(data: Dictionary, resistance: float, auxiliary: float) -> void:
	data.propulsion.battery.resistance_ohm.value = resistance
	data.propulsion.battery.auxiliary_current_a.value = auxiliary


func _set_capacity_and_soc(data: Dictionary, capacity: float, initial_soc: float) -> void:
	data.propulsion.battery.capacity_ah.value = capacity
	data.propulsion.battery.initial_soc.value = initial_soc


func _check_serialized_overflow() -> void:
	var path: String = "user://electric-battery-overflow-%d.json" % OS.get_process_id()
	var text: String = FileAccess.get_file_as_string(BATTERY_4S)
	var points_at: int = text.find("\"ocv_points\"")
	var tail: String = text.substr(points_at)
	var token: String = "\"value\": 12.0"
	_check("find OCV serialized overflow target", points_at >= 0 and tail.contains(token))
	if points_at < 0 or not tail.contains(token):
		return
	var token_at: int = tail.find(token)
	text = text.substr(0, points_at) + tail.substr(0, token_at) \
		+ "\"value\": 1e999" + tail.substr(token_at + token.length())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("create OCV overflow fixture", false, str(FileAccess.get_open_error()))
		return
	file.store_string(text)
	file.close()
	var result: Dictionary = AD.load_file(path)
	_check("serialized OCV numeric overflow refused", not result.ok and _contains(result.errors, "ocv_points"), str(result.errors))
	_check("remove OCV overflow fixture", DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
