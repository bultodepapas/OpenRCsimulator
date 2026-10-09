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
	for file: String in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var result: Dictionary = loader.load_file("res://data/aircraft/%s.json" % file)
		var refused: bool = not result.ok and result.model.is_empty() and str(result.errors).contains("induced wing calibration")
		print(file, " refused=", refused)
		if not refused:
			failures += 1
	quit(1 if failures else 0)
