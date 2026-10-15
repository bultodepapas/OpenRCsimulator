extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Fixture := preload("res://tests/wing_polar_fixture.gd")
const SOURCE_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: parse_precision_probe.gd <candidate-json-path>")
		quit(2)
		return
	var source_text := FileAccess.get_file_as_string(SOURCE_PATH)
	var source_static: Variant = JSON.parse_string(source_text)
	var source_parser := JSON.new()
	var source_parse_error := source_parser.parse(source_text)
	if not source_static is Dictionary or source_parse_error != OK or not source_parser.data is Dictionary:
		printerr("catalog JSON parse failed")
		quit(1)
		return
	var source_before: Dictionary = source_static
	var source_json_parser: Dictionary = source_parser.data
	var before_value: Variant = source_before.aero.coefficients.Cldr.value
	var before_value_json_parser: Variant = source_json_parser.aero.coefficients.Cldr.value
	var validation := AD.validate_and_derive(source_before)
	var after_validation_value: Variant = source_before.aero.coefficients.Cldr.value
	var fixture_raw: Dictionary = Fixture.raw(0.7)
	var fixture_value: Variant = fixture_raw.aero.coefficients.Cldr.value
	var serialized := JSON.stringify(fixture_raw, "  ", true, true) + "\n"
	var serialized_raw: Variant = JSON.parse_string(serialized)
	if not serialized_raw is Dictionary:
		printerr("fixture serialization parse failed")
		quit(1)
		return
	var candidate_path := args[0]
	var candidate_text := FileAccess.get_file_as_string(candidate_path)
	var candidate_parser := JSON.new()
	var candidate_parse_error := candidate_parser.parse(candidate_text)
	if candidate_parse_error != OK or not candidate_parser.data is Dictionary:
		printerr("candidate JSON parse failed: ", candidate_path)
		quit(1)
		return
	var candidate: Dictionary = candidate_parser.data
	var source_without_polar := source_json_parser.duplicate(true)
	var candidate_without_polar := candidate.duplicate(true)
	source_without_polar.aero.erase("wing_polar")
	candidate_without_polar.aero.erase("wing_polar")
	var report := {
		format = "d8b-r2-godot-cldr-parse-probe-v1",
		candidate_path = candidate_path,
		godot = Engine.get_version_info(),
		catalog_json_new_parse_error = source_parse_error,
		candidate_json_new_parse_error = candidate_parse_error,
		catalog_static_parse_cldr_value = before_value,
		catalog_json_new_parse_cldr_value = before_value_json_parser,
		catalog_value_after_validate_and_derive = after_validation_value,
		validate_ok = bool(validation.get("ok", false)),
		fixture_raw_cldr_value = fixture_value,
		fixture_serialized_roundtrip_cldr_value = serialized_raw.aero.coefficients.Cldr.value,
		candidate_json_new_parse_cldr_value = candidate.aero.coefficients.Cldr.value,
		catalog_and_candidate_nonpolar_dictionary_equal = source_without_polar == candidate_without_polar,
		serialized_fixture_nonpolar_dictionary_equal = source_without_polar == _without_polar(serialized_raw),
		catalog_cldr_value_stringified_full_precision = JSON.stringify(before_value, "", true, true),
		fixture_cldr_value_stringified_full_precision = JSON.stringify(fixture_value, "", true, true),
	}
	print(JSON.stringify(report, "\t", true, true))
	quit(0)


func _without_polar(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	if result.get("aero") is Dictionary:
		result.aero.erase("wing_polar")
	return result
