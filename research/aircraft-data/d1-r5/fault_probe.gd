# D1-R5: isolated solver-fault injection driver (verify.py supplies the loader).
extends SceneTree
func _initialize() -> void:
	var path := OS.get_environment("OPENRC_INDUCED_LOADER")
	if not FileAccess.file_exists(path):
		printerr("missing OPENRC_INDUCED_LOADER")
		quit(2)
		return
	var loader: Script = load(path)
	var failures := 0
	var wrong_map_control: bool = OS.get_environment("OPENRC_INDUCED_WRONG_MAP") == "1"
	for file: String in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var result: Dictionary = loader.load_file("res://data/aircraft/%s.json" % file)
		var refused: bool = not result.ok and result.model.is_empty() and str(result.errors).contains("induced wing calibration")
		if wrong_map_control:
			var escaped: bool = result.ok and result.errors.is_empty() and not result.model.is_empty()
			if escaped:
				var values: PackedFloat64Array = result.model.envelope.induced_map
				var count: int = result.model.envelope.station_ys.size()
				escaped = values.size() == count * count
				for value: float in values:
					escaped = escaped and value == 1.0
			print(file, " refused=", refused, " escaped=", escaped)
		else:
			print(file, " refused=", refused)
		if not refused:
			failures += 1
	quit(1 if failures else 0)
