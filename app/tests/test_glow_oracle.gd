extends SceneTree

const TwoStroke := preload("res://physics/glow/two_stroke.gd")
const FourStroke := preload("res://physics/glow/four_stroke.gd")

const NUMERIC_FIELDS := [
	"indicated_torque_nm",
	"mechanical_torque_nm",
	"pumping_torque_nm",
	"valve_torque_nm",
	"shaft_torque_nm",
	"delivered_fuel_kg_s",
	"burned_fuel_kg_s",
	"unburned_fuel_kg_s",
	"fuel_input_power_w",
	"chemical_power_w",
	"indicated_power_w",
	"mechanical_loss_w",
	"pumping_loss_w",
	"valve_loss_w",
	"cycle_work_j",
	"air_charge_kg_cycle",
	"cycle_frequency_hz",
	"opportunity_frequency_hz",
	"firing_frequency_hz",
]

const TWO_STROKE_TABLES := [
	"mechanical_torque_nm",
	"combustion_efficiency",
	"indicated_efficiency",
	"delivery_ratio",
	"trapping_efficiency",
	"scavenge_pressure_pa",
]

const FOUR_STROKE_TABLES := [
	"mechanical_torque_nm",
	"combustion_efficiency",
	"indicated_efficiency",
	"volumetric_efficiency",
	"pumping_pressure_pa",
	"valve_torque_nm",
]

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var oracle_path := ProjectSettings.globalize_path("res://").path_join("..") \
			.simplify_path().path_join("research/glow-engines/reference/oracle.json")
	var file := FileAccess.open(oracle_path, FileAccess.READ)
	if file == null:
		_check("oracle JSON opens", false, "%s (error %d)" % [oracle_path, FileAccess.get_open_error()])
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_check("oracle JSON parses to an object", false)
		quit(1)
		return
	var document: Dictionary = parsed
	_check("oracle schema is recognized", document.get("schema") == "openrc-glow-kernel-oracle-v1")
	var raw_cases: Variant = document.get("cases")
	if typeof(raw_cases) != TYPE_ARRAY:
		_check("oracle contains a cases array", false)
		quit(1)
		return
	for raw_case in raw_cases:
		if typeof(raw_case) != TYPE_DICTIONARY:
			_check("oracle vector is an object", false)
			continue
		_compare_case(raw_case)
	print("%d checks, %d failed (%d oracle vectors)" % [_checks, _failures, raw_cases.size()])
	quit(1 if _failures > 0 else 0)


func _compare_case(case: Dictionary) -> void:
	var identifier: String = str(case.get("id", "unnamed"))
	var family: String = str(case.get("family", ""))
	var parameters_value: Variant = case.get("parameters")
	var expected_value: Variant = case.get("expected")
	if typeof(parameters_value) != TYPE_DICTIONARY or typeof(expected_value) != TYPE_DICTIONARY:
		_check("%s has parameter and expected objects" % identifier, false)
		return
	var parameters: Dictionary = (parameters_value as Dictionary).duplicate(true)
	var table_keys: Array = TWO_STROKE_TABLES if family == "two_stroke" else FOUR_STROKE_TABLES
	if family != "two_stroke" and family != "four_stroke":
		_check("%s names a known engine family" % identifier, false, family)
		return
	for key: String in table_keys:
		var raw_table: Variant = parameters.get(key)
		if typeof(raw_table) != TYPE_ARRAY:
			_check("%s.%s is a JSON array" % [identifier, key], false)
			return
		parameters[key] = PackedFloat64Array(raw_table)
	var result: Dictionary
	if family == "two_stroke":
		result = TwoStroke.evaluate(
			float(case["rpm"]), float(case["admission"]), float(case["mixture"]),
			float(case["dry_density_kg_m3"]), parameters, bool(case["running"]),
			float(case["firing_fraction"])
		)
	else:
		result = FourStroke.evaluate(
			float(case["rpm"]), float(case["admission"]), float(case["mixture"]),
			float(case["dry_density_kg_m3"]), parameters, bool(case["running"]),
			float(case["firing_fraction"])
		)
	var expected: Dictionary = expected_value
	_check("%s accepted/rejected status" % identifier, bool(result.get("ok", false)) == bool(expected.get("ok", false)),
		str(result.get("message", "")))
	if not bool(expected.get("ok", false)):
		_check("%s failure exposes a message" % identifier, not str(result.get("message", "")).is_empty())
	for key: String in NUMERIC_FIELDS:
		var actual_value := float(result.get(key, INF))
		var expected_number := float(expected.get(key, INF))
		var tolerance := maxf(1e-22, absf(expected_number) * 2e-11)
		_check("%s.%s matches independent reference" % [identifier, key],
			is_finite(actual_value) and is_finite(expected_number) \
			and absf(actual_value - expected_number) <= tolerance,
			"got %s, expected %s" % [String.num_scientific(actual_value), String.num_scientific(expected_number)])
