extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
func _initialize() -> void:
	var results: Array = []
	for label in ["numeric_string", "missing_kind", "missing_source", "nan_power", "infinite_final_rpm"]:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/p51d_mustang_120.json"))
		var curve: Dictionary = raw.propulsion.engine.shaft.power_curve
		match label:
			"numeric_string": curve.value[0][0] = "1000"
			"missing_kind": curve.erase("kind")
			"missing_source": curve.erase("source")
			"nan_power": curve.value[0][1] = NAN
			"infinite_final_rpm": curve.value[-1][0] = INF
		var result: Dictionary = AD.validate_and_derive(raw)
		results.append({"case": label, "accepted": result.ok, "errors": Array(result.errors)})
	var file = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  ") + "\n")
	file.close()
	print(JSON.stringify(results))
	quit()
