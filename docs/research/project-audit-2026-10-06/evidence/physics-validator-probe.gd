extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")

func _initialize() -> void:
	var stik: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	var contacts: Array = stik["landing_gear"]["contacts"]
	var bad_triangle := [[0.0, -0.18], [1.0, 0.18], [1.0, 0.0]]
	for i in contacts.size():
		var old: Array = contacts[i]["position"]["value"]
		contacts[i]["position"]["value"] = [bad_triangle[i][0], bad_triangle[i][1], old[2]]
	var footprint_result := AD.validate_and_derive(stik)
	print("outside_support_polygon_accepted=", footprint_result.ok, " errors=", footprint_result.errors)

	var p51: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/p51d_mustang_120.json"))
	var table: Dictionary = p51["propulsion"]["engine"]["shaft"]["power_curve"]
	table["value"][0][0] = "1000"
	table.erase("kind")
	table.erase("source")
	var shaft_result := AD.validate_and_derive(p51)
	print("shaft_string_rpm_missing_provenance_accepted=", shaft_result.ok, " errors=", shaft_result.errors)

	var p51_nan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/p51d_mustang_120.json"))
	p51_nan["propulsion"]["engine"]["shaft"]["power_curve"]["value"][0][0] = "nan"
	var nan_result := AD.validate_and_derive(p51_nan)
	print("shaft_nan_string_accepted=", nan_result.ok, " errors=", nan_result.errors)
	quit(0)
